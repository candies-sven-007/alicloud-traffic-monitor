#!/bin/bash
# =============================================================================
# Alibaba Cloud ECS Outbound Traffic Monitor v2.0.0 - Complete Edition
# 阿里云ECS出站流量监控 - 完整单文件脚本
# Author  : Candies-Sven
# Repo    : https://github.com/candies-sven-007/alicloud-traffic-monitor
# License : MIT
# =============================================================================
# 
# 功能特性:
# - 自动检测网卡和系统类型
# - 原子性状态管理防止数据损坏
# - 完善的错误处理和日志记录
# - 日志自动轮转管理
# - Telegram 多级通知系统
# - 月初自动重置和恢复
# - OpenRC/Systemd 兼容
# - 交互式配置向导
# - 实时流量监控
# - 完整的诊断工具
# 
# 安装方式:
#   sudo bash alicloud-traffic-monitor-full.sh install
#
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────
# 彩色输出函数
# ─────────────────────────────────────────────────────────────────────────
info()    { echo -e "\033[1;34m[Candies-INFO]\033[0m $*"; }
success() { echo -e "\033[1;32m[✓]\033[0m $*"; }
warn()    { echo -e "\033[1;33m[Candies-WARN]\033[0m $*"; }
err()     { echo -e "\033[1;31m[Candies-ERR]\033[0m $*" >&2; }

# ─────────────────────────────────────────────────────────────────────────
# 全局配置常量
# ─────────────────────────────────────────────────────────────────────────
readonly APP_NAME="alicloud-traffic-monitor"
readonly APP_VERSION="2.0.0"
readonly APP_BIN="/usr/local/sbin/$APP_NAME"
readonly LINK="/usr/local/bin/alitm"
readonly CONF="/etc/$APP_NAME.conf"
readonly STATE_DIR="/var/lib/$APP_NAME"
readonly LOG_FILE="$STATE_DIR/traffic.log"
readonly STATE_FILE="$STATE_DIR/.state.env"
readonly PID_FILE="$STATE_DIR/monitor.pid"
readonly LOCK_FILE="$STATE_DIR/limit.lock"
readonly OPENRC_INIT="/etc/init.d/$APP_NAME"
readonly SYSTEMD_UNIT="/etc/systemd/system/${APP_NAME}.service"

# 流量常量
readonly BYTE_PER_GB=1000000000
readonly REPORT_STEP=$((10 * BYTE_PER_GB))
readonly LIMIT=$((200 * BYTE_PER_GB))

# 默认配置值
INTERFACE="${INTERFACE:-eth0}"
SINGBOX_SERVICE="${SINGBOX_SERVICE:-sing-box}"
INTERVAL="${INTERVAL:-1}"
TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
TG_CHAT_ID="${TG_CHAT_ID:-}"

# 状态变量
CURRENT_MONTH=""
MONTH_EGRESS=0
LAST_TX=0
REPORT_COUNT=0
NEXT_REPORT=0
LIMIT_REACHED=0

# ─────────────────────────────────────────────────────────────────────────
# 系统检测
# ─────────────────────────────────────────────────────────────────────────
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release 2>/dev/null || true
        OS="${ID:-unknown}"
    else
        OS="unknown"
    fi

    if echo "$OS" | grep -qi "alpine"; then
        INIT_SYS="openrc"
    elif echo "$OS" | grep -Ei "debian|ubuntu" >/dev/null 2>&1; then
        INIT_SYS="systemd"
    else
        INIT_SYS="unknown"
    fi
}

detect_system

# ─────────────────────────────────────────────────────────────────────────
# 权限检查
# ─────────────────────────────────────────────────────────────────────────
check_root() {
    if [ "$(id -u)" != "0" ]; then
        err "此脚本需要 root 权限"
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# 依赖安装
# ─────────────────────────────────────────────────────────────────────────
install_dependencies() {
    info "正在安装系统依赖..."

    case "$OS" in
        alpine*)
            apk update >/dev/null 2>&1 || true
            apk add --no-cache bash curl awk coreutils ca-certificates grep sed openrc >/dev/null 2>&1 || {
                err "Alpine 依赖安装失败"
                return 1
            }
            ;;
        debian|ubuntu*)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y >/dev/null 2>&1 || true
            apt-get install -y curl gawk coreutils ca-certificates grep sed >/dev/null 2>&1 || {
                err "Debian/Ubuntu 依赖安装失败"
                return 1
            }
            ;;
        centos|rhel|fedora*)
            yum install -y curl gawk coreutils ca-certificates grep sed >/dev/null 2>&1 || {
                err "CentOS/RHEL 依赖安装失败"
                return 1
            }
            ;;
        *)
            warn "系统 $OS 未经测试，尝试继续..."
            ;;
    esac

    success "依赖安装完成"
}

# ─────────────────────────────────────────────────────────────────────────
# 目录初始化
# ─────────────────────────────────────────────────────────────────────────
init_directories() {
    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
    touch "$LOG_FILE"
    chmod 644 "$LOG_FILE"
}

# ─────────────────────────────────────────────────────────────────────────
# 日志管理函数
# ─────────────────────────────────────────────────────────────────────────
log_msg() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    
    # 日志轮转 - 超过10MB则压缩
    if [ -f "$LOG_FILE" ]; then
        local size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt $((10 * 1024 * 1024)) ]; then
            local archive="${LOG_FILE}.$(date '+%Y%m%d_%H%M%S').gz"
            gzip -c "$LOG_FILE" > "$archive" 2>/dev/null || true
            > "$LOG_FILE"
            # 删除7天前的归档
            find "$(dirname "$LOG_FILE")" -name "${LOG_FILE}.*.gz" -mtime +7 -delete 2>/dev/null || true
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# 状态管理 - 原子性操作
# ─────────────────────────────────────────────────────────────────────────
save_state() {
    local tmp_file="${STATE_DIR}/.state.tmp.$$"
    
    {
        echo "CURRENT_MONTH='$CURRENT_MONTH'"
        echo "MONTH_EGRESS=$MONTH_EGRESS"
        echo "LAST_TX=$LAST_TX"
        echo "REPORT_COUNT=$REPORT_COUNT"
        echo "NEXT_REPORT=$NEXT_REPORT"
        echo "LIMIT_REACHED=$LIMIT_REACHED"
    } > "$tmp_file" || return 1

    mv "$tmp_file" "$STATE_FILE" 2>/dev/null || return 1
    chmod 600 "$STATE_FILE"
    return 0
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        . "$STATE_FILE" 2>/dev/null || {
            warn "状态文件损坏，使用默认值"
        }
    fi
    
    # 初始化未设置的变量
    CURRENT_MONTH="${CURRENT_MONTH:-$(date '+%Y-%m')}"
    MONTH_EGRESS="${MONTH_EGRESS:-0}"
    LAST_TX="${LAST_TX:-0}"
    REPORT_COUNT="${REPORT_COUNT:-0}"
    NEXT_REPORT="${NEXT_REPORT:-$REPORT_STEP}"
    LIMIT_REACHED="${LIMIT_REACHED:-0}"
}

# ─────────────────────────────────────────────────────────────────────────
# 配置管理
# ─────────────────────────────────────────────────────────────────────────
generate_config_template() {
    mkdir -p "$(dirname "$CONF")"
    
    cat > "$CONF.example" << 'EOF'
# ============================================================================
# Alibaba Cloud Traffic Monitor - Configuration File
# 阿里云流量监控 - 配置文件
# ============================================================================

# 监控网卡 (监控此网卡的出站流量)
# 默认值: eth0
# 可用网卡: ls /sys/class/net/
INTERFACE="eth0"

# 受控服务名称 (达到200GB后自动停止此服务)
# 默认值: sing-box
# 支持: systemd 或 OpenRC 服务
SINGBOX_SERVICE="sing-box"

# 检查间隔 (秒)
# 默认值: 1 (每秒检查一次)
# 取值范围: 1-60
INTERVAL="1"

# Telegram Bot Token (可选)
# 从 @BotFather 获取: https://t.me/BotFather
TG_BOT_TOKEN=""

# Telegram Chat ID (可选)
# 从 @userinfobot 获取: https://t.me/userinfobot
TG_CHAT_ID=""
EOF

    if [ ! -f "$CONF" ]; then
        cp "$CONF.example" "$CONF"
        chmod 600 "$CONF"
    fi
}

load_config() {
    if [ ! -f "$CONF" ]; then
        err "配置文件不存在: $CONF"
        err "请先运行: sudo $0 install"
        return 1
    fi

    . "$CONF" 2>/dev/null || {
        err "配置文件格式错误"
        return 1
    }

    INTERFACE="${INTERFACE:-eth0}"
    SINGBOX_SERVICE="${SINGBOX_SERVICE:-sing-box}"
    INTERVAL="${INTERVAL:-1}"
    
    return 0
}

validate_config() {
    # 验证网卡
    if [ ! -d "/sys/class/net/$INTERFACE" ]; then
        err "网卡不存在: $INTERFACE"
        err "可用网卡: $(ls /sys/class/net/ 2>/dev/null | tr '\n' ' ')"
        return 1
    fi

    if [ ! -f "/sys/class/net/$INTERFACE/statistics/tx_bytes" ]; then
        err "无法读取TX字节"
        return 1
    fi

    # 验证间隔
    if ! echo "$INTERVAL" | grep -qE '^[0-9]+$' || [ "$INTERVAL" -lt 1 ] || [ "$INTERVAL" -gt 60 ]; then
        err "INTERVAL 必须在 1-60 之间"
        return 1
    fi

    # 验证Telegram配置
    if [ -n "$TG_BOT_TOKEN" ] && [ -z "$TG_CHAT_ID" ]; then
        err "已设置 TG_BOT_TOKEN 但未设置 TG_CHAT_ID"
        return 1
    fi

    if [ -z "$TG_BOT_TOKEN" ] && [ -n "$TG_CHAT_ID" ]; then
        err "已设置 TG_CHAT_ID 但未设置 TG_BOT_TOKEN"
        return 1
    fi

    return 0
}

interactive_setup() {
    check_root

    clear
    cat << 'BANNER'

╔══════════════════════════════════════════════════════════════════╗
║   阿里云流量监控 - 交互式配置向导                              ║
║   Alibaba Cloud Traffic Monitor - Setup Wizard                   ║
╚══════════════════════════════════════════════════════════════════╝

BANNER
    echo ""

    # 网卡选择
    echo "🔹 第1步: 选择监控网卡"
    echo "   可用网卡: $(ls /sys/class/net/ 2>/dev/null | tr '\n' ' ')"
    read -p "   请输入网卡名称 [eth0]: " input_iface
    INTERFACE="${input_iface:-eth0}"
    echo ""

    # 服务名称
    echo "🔹 第2步: 选择受控服务"
    read -p "   请输入服务名 [sing-box]: " input_service
    SINGBOX_SERVICE="${input_service:-sing-box}"
    echo ""

    # 检查间隔
    echo "🔹 第3步: 设置检查间隔 (1-60秒)"
    read -p "   请输入间隔秒数 [1]: " input_interval
    INTERVAL="${input_interval:-1}"
    echo ""

    # Telegram配置
    echo "🔹 第4步: 配置 Telegram 通知 (可选)"
    read -p "   是否配置? (y/n) [n]: " enable_tg

    if [ "$enable_tg" = "y" ] || [ "$enable_tg" = "Y" ]; then
        read -p "   TG_BOT_TOKEN: " TG_BOT_TOKEN
        read -p "   TG_CHAT_ID: " TG_CHAT_ID
    else
        TG_BOT_TOKEN=""
        TG_CHAT_ID=""
    fi

    # 保存配置
    mkdir -p "$(dirname "$CONF")"
    cat > "$CONF" << CONFEOF
# 配置文件 - $(date '+%Y-%m-%d %H:%M:%S')
INTERFACE="$INTERFACE"
SINGBOX_SERVICE="$SINGBOX_SERVICE"
INTERVAL="$INTERVAL"
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_CHAT_ID="$TG_CHAT_ID"
CONFEOF

    chmod 600 "$CONF"

    echo ""
    success "配置已保存"
    echo "   文件: $CONF"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────
# 网络监控函数
# ─────────────────────────────────────────────────────────────────────────
get_tx_bytes() {
    cat "/sys/class/net/$INTERFACE/statistics/tx_bytes" 2>/dev/null || echo 0
}

bytes_to_gb() {
    local bytes=$1
    echo "$bytes" | awk '{ printf "%.2f", $1 / 1000000000 }'
}

calc_percentage() {
    local used=$1 total=$2
    echo "$used" | awk -v t="$total" '{ printf "%.1f", (t > 0) ? ($1 / t * 100) : 0 }'
}

calc_delta() {
    local current=$1 last=$2
    if [ "$current" -ge "$last" ]; then
        echo $((current - last))
    else
        # 计数器重置（系统重启）
        echo "$current"
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# Telegram 通知函数
# ─────────────────────────────────────────────────────────────────────────
send_telegram_msg() {
    local msg="$1"

    [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ] && return 0

    # 重试3次
    for attempt in 1 2 3; do
        if curl -fsS --max-time 15 -X POST \
            "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${TG_CHAT_ID}" \
            --data-urlencode "text=${msg}" \
            --data-urlencode "parse_mode=HTML" \
            >/dev/null 2>&1; then
            return 0
        fi
        [ "$attempt" -lt 3 ] && sleep 2
    done

    log_msg "WARN" "Telegram 发送失败"
    return 1
}

send_step_report() {
    local step=$1 used_gb=$2 percent=$3 remain_gb=$4

    local title warning
    case "$step" in
        17) title="⚠️ <b>流量预警</b>"; warning="🟡 进入最后 30GB\n" ;;
        18) title="⚠️ <b>流量预警</b>"; warning="🟠 进入最后 20GB\n" ;;
        19) title="🚨 <b>最后预警</b>"; warning="🔴 仅剩 10GB\n" ;;
        *) title="📊 <b>流量报告</b>"; warning="" ;;
    esac

    local msg="$title\n\n第 $step 次提示\n\n📤 月度流量: <b>${used_gb} GB / 200 GB</b>\n📈 使用率: <b>${percent}%</b>\n📉 剩余: <b>${remain_gb} GB</b>\n${warning}🕐 $(date '+%Y-%m-%d %H:%M:%S')"

    send_telegram_msg "$msg"
    log_msg "INFO" "报告 #$step: ${used_gb}GB / 200GB"
}

send_limit_reached_msg() {
    local used_gb=$1

    local msg="🛑 <b>已达200GB限额</b>\n\n📤 月度流量: <b>${used_gb} GB</b>\n🚫 sing-box 已停止\n🔒 熔断锁已锁定\n🔄 下月1日自动恢复\n\n🕐 $(date '+%Y-%m-%d %H:%M:%S')"

    send_telegram_msg "$msg"
    log_msg "EVENT" "达到200GB限额"
}

send_new_month_msg() {
    local msg="🔄 <b>新计费周期开始</b>\n\n📅 周期: $CURRENT_MONTH\n💾 配额: <b>200 GB</b>\n📤 已用: <b>0.00 GB</b>\n🟢 服务已恢复\n\n🕐 $(date '+%Y-%m-%d %H:%M:%S')"

    send_telegram_msg "$msg"
    log_msg "EVENT" "新月份开始"
}

# ─────────────────────────────────────────────────────────────────────────
# 服务控制函数
# ─────────────────────────────────────────────────────────────────────────
is_service_running() {
    if command -v rc-service >/dev/null 2>&1; then
        rc-service "$SINGBOX_SERVICE" status >/dev/null 2>&1
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl is-active "$SINGBOX_SERVICE" >/dev/null 2>&1
    else
        return 1
    fi
}

stop_service() {
    if command -v rc-service >/dev/null 2>&1; then
        rc-service "$SINGBOX_SERVICE" stop >/dev/null 2>&1 || true
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl stop "$SINGBOX_SERVICE" >/dev/null 2>&1 || true
    fi
    log_msg "INFO" "服务已停止"
}

start_service() {
    if command -v rc-service >/dev/null 2>&1; then
        rc-service "$SINGBOX_SERVICE" start >/dev/null 2>&1 || true
    elif command -v systemctl >/dev/null 2>&1; then
        systemctl start "$SINGBOX_SERVICE" >/dev/null 2>&1 || true
    fi
    log_msg "INFO" "服务已启动"
}

# ─────────────────────────────────────────────────────────────────────────
# 监控核心循环
# ─────────────────────────────────────────────────────────────────────────
run_monitor_loop() {
    load_config || return 1
    validate_config || return 1

    init_directories
    load_state

    log_msg "INFO" "监控启动: 网卡=$INTERFACE, 间隔=${INTERVAL}s"
    info "监控已启动"

    local error_count=0

    while true; do
        local real_month=$(date '+%Y-%m')

        # 检查月份变化
        if [ "$CURRENT_MONTH" != "$real_month" ]; then
            CURRENT_MONTH="$real_month"
            MONTH_EGRESS=0
            REPORT_COUNT=0
            NEXT_REPORT=$REPORT_STEP
            LIMIT_REACHED=0
            rm -f "$LOCK_FILE"

            log_msg "EVENT" "新月份: $CURRENT_MONTH"
            send_new_month_msg
            start_service
        fi

        # 读取当前TX
        local current_tx
        if ! current_tx=$(get_tx_bytes); then
            warn "无法读取TX"
            error_count=$((error_count + 1))

            if [ "$error_count" -gt 10 ]; then
                err "错误过多,退出"
                log_msg "ERROR" "连续错误超过10次"
                exit 1
            fi

            sleep "$INTERVAL"
            continue
        fi

        error_count=0

        # 计算增量
        local diff=$(calc_delta "$current_tx" "$LAST_TX")
        LAST_TX="$current_tx"
        MONTH_EGRESS=$((MONTH_EGRESS + diff))

        # 检查报告阈值
        while [ "$MONTH_EGRESS" -ge "$NEXT_REPORT" ] && [ "$NEXT_REPORT" -lt "$LIMIT" ]; do
            REPORT_COUNT=$((REPORT_COUNT + 1))

            local used_gb=$(bytes_to_gb "$MONTH_EGRESS")
            local remain=$((LIMIT - MONTH_EGRESS))
            local remain_gb=$(bytes_to_gb "$remain")
            local percent=$(calc_percentage "$MONTH_EGRESS" "$LIMIT")

            send_step_report "$REPORT_COUNT" "$used_gb" "$percent" "$remain_gb"
            NEXT_REPORT=$((NEXT_REPORT + REPORT_STEP))
        done

        # 检查限额
        if [ "$MONTH_EGRESS" -ge "$LIMIT" ] && [ "$LIMIT_REACHED" -eq 0 ]; then
            LIMIT_REACHED=1
            touch "$LOCK_FILE"
            stop_service

            local used_gb=$(bytes_to_gb "$MONTH_EGRESS")
            send_limit_reached_msg "$used_gb"
        fi

        # 熔断防御
        if [ "$LIMIT_REACHED" -eq 1 ] && is_service_running; then
            warn "熔断保护: 强制停止"
            stop_service
        fi

        save_state

        sleep "$INTERVAL"
    done
}

# ─────────────────────────────────────────────────────────────────────────
# 命令实现
# ─────────────────────────────────────────────────────────────────────────

cmd_status() {
    load_config >/dev/null 2>&1 || true
    load_state

    local used_gb=$(bytes_to_gb "$MONTH_EGRESS")
    local remain=$((LIMIT - MONTH_EGRESS))
    [ "$remain" -lt 0 ] && remain=0
    local remain_gb=$(bytes_to_gb "$remain")
    local percent=$(calc_percentage "$MONTH_EGRESS" "$LIMIT")

    local status_icon="🟢 正常"
    [ "$LIMIT_REACHED" -eq 1 ] && status_icon="🚨 熔断"

    cat << STATUS

╔════════════════════════════════════════════════════════════╗
║            阿里云流量监控 - 实时状态                      ║
╚════════════════════════════════════════════════════════════╝

📊 流量统计
  计费周期       : $CURRENT_MONTH
  出站流量       : $used_gb GB / 200 GB
  使用率         : $percent %
  剩余配额       : $remain_gb GB

🔔 通知统计
  提示次数       : $REPORT_COUNT / 20
  熔断状态       : $status_icon

⏰ 更新时间       : $(date '+%Y-%m-%d %H:%M:%S')

═══════════════════════════════════════════════════════════════

STATUS
}

cmd_test() {
    load_config || return 1

    if [ -z "$TG_BOT_TOKEN" ] || [ -z "$TG_CHAT_ID" ]; then
        err "未配置Telegram"
        return 1
    fi

    info "发送测试消息..."
    local msg="✅ <b>阿里云流量监控 - 测试消息</b>\n\n时间: $(date '+%Y-%m-%d %H:%M:%S')"

    if send_telegram_msg "$msg"; then
        success "测试消息已发送"
        return 0
    else
        err "发送失败"
        return 1
    fi
}

cmd_diagnose() {
    clear
    cat << 'DIAG'

╔════════════════════════════════════════════════════════════╗
║            阿里云流量监控 - 系统诊断                      ║
╚════════════════════════════════════════════════════════════╝

DIAG

    echo "1️⃣  网卡检查"
    if [ -d "/sys/class/net/eth0" ] && [ -f "/sys/class/net/eth0/statistics/tx_bytes" ]; then
        echo "   ✅ eth0 可用"
        local tx=$(cat /sys/class/net/eth0/statistics/tx_bytes 2>/dev/null)
        echo "   ✅ TX: $tx bytes"
    else
        echo "   ❌ eth0 不可用"
        echo "   可用: $(ls /sys/class/net/ 2>/dev/null)"
    fi
    echo ""

    echo "2️⃣  配置检查"
    if [ -f "$CONF" ]; then
        echo "   ✅ 配置存在: $CONF"
        grep "^INTERFACE\|^SINGBOX\|^INTERVAL" "$CONF" 2>/dev/null | sed 's/^/      /'
    else
        echo "   ⚠️  未配置"
    fi
    echo ""

    echo "3️⃣  依赖检查"
    for cmd in curl awk sed grep; do
        if command -v "$cmd" >/dev/null 2>&1; then
            echo "   ✅ $cmd"
        else
            echo "   ❌ $cmd"
        fi
    done
    echo ""

    echo "4️⃣  目录检查"
    echo "   状态: $STATE_DIR ($([ -d "$STATE_DIR" ] && echo "✅" || echo "❌"))"
    echo "   日志: $LOG_FILE ($([ -f "$LOG_FILE" ] && echo "✅" || echo "❌"))"
    echo "   锁: $LOCK_FILE ($([ -f "$LOCK_FILE" ] && echo "🔒" || echo "⭕"))"
    echo ""

    echo "5️⃣  进程检查"
    if pgrep -f "$APP_BIN run" >/dev/null 2>&1; then
        echo "   ✅ 监控进程运行中"
    else
        echo "   ❌ 监控进程已停止"
    fi
    echo ""

    echo "6️⃣  服务检查"
    load_config >/dev/null 2>&1 || SINGBOX_SERVICE="sing-box"
    if is_service_running; then
        echo "   ✅ $SINGBOX_SERVICE 运行中"
    else
        echo "   ❌ $SINGBOX_SERVICE 已停止"
    fi
    echo ""

    echo "7️⃣  最近日志"
    if [ -f "$LOG_FILE" ]; then
        tail -3 "$LOG_FILE" | sed 's/^/   /'
    fi
    echo ""
}

# OpenRC服务文件
generate_openrc_service() {
    cat > "$OPENRC_INIT" << SVCEOF
#!/sbin/openrc-run
name="Alibaba Cloud Traffic Monitor"
description="ECS egress traffic protection"

command="$APP_BIN"
command_args="run"
pidfile="$PID_FILE"
command_background="yes"

depend() {
    need localmount net
    after firewall
}

start_pre() {
    mkdir -p "$(dirname "$PID_FILE")"
}

stop() {
    ebegin "Stopping \$name"
    start-stop-daemon --stop --quiet --pidfile "\$pidfile"
    eend \$?
}
SVCEOF

    chmod +x "$OPENRC_INIT"
}

# Systemd服务文件
generate_systemd_service() {
    cat > "$SYSTEMD_UNIT" << SVCEOF
[Unit]
Description=Alibaba Cloud Traffic Monitor
After=network.target

[Service]
Type=simple
ExecStart=$APP_BIN run
Restart=on-failure
RestartSec=10s
User=root

[Install]
WantedBy=multi-user.target
SVCEOF

    chmod 644 "$SYSTEMD_UNIT"
}

cmd_install() {
    check_root

    clear
    cat << 'INSTALL'

╔═══════════════════════════════════════════════════════════════╗
║         阿里云流量监控 v2.0.0 - 安装向导                      ║
╚═══════════════════════════════════════════════════════════════╝

INSTALL
    echo ""

    # Step 1: 依赖
    info "第1步: 安装依赖"
    install_dependencies
    echo ""

    # Step 2: 目录
    info "第2步: 初始化目录"
    init_directories
    success "目录已创建"
    echo ""

    # Step 3: 配置
    info "第3步: 生成配置文件"
    generate_config_template
    echo ""

    # Step 4: 交互设置
    info "第4步: 配置向导"
    interactive_setup
    echo ""

    # Step 5: 程序
    info "第5步: 安装程序"
    cp "$0" "$APP_BIN"
    chmod 755 "$APP_BIN"
    ln -sf "$APP_BIN" "$LINK" 2>/dev/null || true
    success "程序已安装"
    echo ""

    # Step 6: 服务
    info "第6步: 安装服务"
    if [ "$INIT_SYS" = "openrc" ]; then
        generate_openrc_service
        rc-update add "$APP_NAME" default 2>/dev/null || true
        success "OpenRC 服务已注册"
    elif [ "$INIT_SYS" = "systemd" ]; then
        generate_systemd_service
        systemctl daemon-reload 2>/dev/null || true
        systemctl enable "$APP_NAME" 2>/dev/null || true
        success "Systemd 服务已注册"
    fi
    echo ""

    # Step 7: 启动
    info "第7步: 启动监控"
    nohup "$APP_BIN" run > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    sleep 1
    success "监控已启动"
    echo ""

    cat << DONE

╔═══════════════════════════════════════════════════════════════╗
║                    ✅ 安装完成                                ║
╚═══════════════════════════════════════════════════════════════╝

配置文件: $CONF
日志文件: $LOG_FILE
状态目录: $STATE_DIR

常用命令:
  查看状态    : $APP_NAME status          # 或 alitm status
  测试通知    : $APP_NAME test            # 或 alitm test
  系统诊断    : $APP_NAME diagnose        # 或 alitm diagnose
  查看日志    : tail -f $LOG_FILE
  编辑配置    : vi $CONF

═══════════════════════════════════════════════════════════════

DONE
}

cmd_uninstall() {
    check_root

    warn "即将卸载 $APP_NAME"
    read -p "确定卸载? (y/n): " confirm

    [ "$confirm" != "y" ] && return 0

    # 停止进程
    pkill -f "$APP_BIN run" 2>/dev/null || true
    rm -f "$PID_FILE"

    # 删除程序和链接
    rm -f "$APP_BIN" "$LINK" 2>/dev/null || true

    # 移除服务
    if [ -f "$OPENRC_INIT" ]; then
        rc-update del "$APP_NAME" 2>/dev/null || true
        rm -f "$OPENRC_INIT"
    fi

    if [ -f "$SYSTEMD_UNIT" ]; then
        systemctl disable "$APP_NAME" 2>/dev/null || true
        rm -f "$SYSTEMD_UNIT"
        systemctl daemon-reload 2>/dev/null || true
    fi

    # 询问数据
    read -p "删除配置和数据? (y/n) [n]: " delete_data

    if [ "$delete_data" = "y" ]; then
        rm -f "$CONF"
        rm -rf "$STATE_DIR"
        success "配置和数据已删除"
    else
        info "数据保留: $STATE_DIR"
    fi

    success "卸载完成"
}

# ─────────────────────────────────────────────────────────────────────────
# 主程序入口
# ─────────────────────────────────────────────────────────────────────────

print_banner() {
    cat << 'BANNER'

╔══════════════════════════════════════════════════════════════════╗
║     Alibaba Cloud ECS Outbound Traffic Monitor v2.0.0            ║
║     阿里云 ECS 出站流量监控脚本                                 ║
║                                                                  ║
║     功能: 自动监控并在达到200GB时停止服务                       ║
║     特性: 原子操作、错误恢复、通知系统、日志轮转               ║
╚══════════════════════════════════════════════════════════════════╝

BANNER
}

print_help() {
    cat << HELP
用法: $0 {install|run|status|test|diagnose|setup|uninstall}

命令说明:
  install   - 完整安装程序
  run       - 启动监控守护进程
  status    - 显示实时状态
  test      - 测试 Telegram 通知
  diagnose  - 系统诊断工具
  setup     - 重新配置
  uninstall - 卸载程序

示例:
  sudo $0 install      # 首次完整安装
  $0 status           # 查看流量状态
  $0 test             # 测试Telegram
  tail -f $LOG_FILE  # 查看日志

HELP
}

case "${1:-}" in
    install)
        cmd_install
        ;;
    run)
        check_root
        run_monitor_loop
        ;;
    status)
        cmd_status
        ;;
    test)
        cmd_test
        ;;
    diagnose)
        cmd_diagnose
        ;;
    setup)
        interactive_setup
        ;;
    uninstall)
        cmd_uninstall
        ;;
    *)
        print_banner
        print_help
        exit 1
        ;;
esac

# ─────────────────────────────────────────────────────────────────────────
# 扩展功能: 日志查看、配置编辑、重置状态、管理菜单等
# ─────────────────────────────────────────────────────────────────────────

# 查看日志
cmd_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        err "日志文件不存在"
        return 1
    fi

    info "日志文件: $LOG_FILE"
    info "最近50行:"
    echo ""
    tail -50 "$LOG_FILE"
}

# 清空日志
cmd_clear_logs() {
    check_root

    read -p "确定清空日志? (y/n): " confirm
    [ "$confirm" != "y" ] && return 0

    > "$LOG_FILE"
    success "日志已清空"
}

# 重置计数器
cmd_reset_state() {
    check_root

    warn "这将重置流量计数和通知次数"
    read -p "确定重置? (y/n): " confirm
    [ "$confirm" != "y" ] && return 0

    CURRENT_MONTH=$(date '+%Y-%m')
    MONTH_EGRESS=0
    LAST_TX=0
    REPORT_COUNT=0
    NEXT_REPORT=$REPORT_STEP
    LIMIT_REACHED=0
    rm -f "$LOCK_FILE"

    save_state
    success "状态已重置"
    
    # 尝试恢复服务
    load_config >/dev/null 2>&1 || true
    start_service
}

# 强制启动服务
cmd_force_start() {
    check_root
    
    load_config || return 1
    
    info "强制启动 $SINGBOX_SERVICE ..."
    start_service
    
    # 清除熔断锁
    rm -f "$LOCK_FILE"
    
    # 更新状态
    load_state
    LIMIT_REACHED=0
    save_state
    
    success "服务已启动，熔断已清除"
}

# 强制停止服务
cmd_force_stop() {
    check_root
    
    load_config || return 1
    
    warn "即将强制停止 $SINGBOX_SERVICE"
    read -p "确定? (y/n): " confirm
    [ "$confirm" != "y" ] && return 0
    
    stop_service
    success "服务已停止"
}

# 查看配置
cmd_show_config() {
    if [ ! -f "$CONF" ]; then
        err "配置文件不存在"
        return 1
    fi

    echo ""
    echo "════════════════════════════════════════"
    echo "  配置文件: $CONF"
    echo "════════════════════════════════════════"
    echo ""
    cat "$CONF" | grep -v "^#" | grep -v "^$"
    echo ""
}

# 版本信息
cmd_version() {
    cat << VERSION
$APP_NAME v$APP_VERSION

Author  : Candies-Sven
Repo    : https://github.com/candies-sven-007/alicloud-traffic-monitor
License : MIT

VERSION
}

# 交互式管理菜单
show_interactive_menu() {
    check_root
    
    while true; do
        load_config >/dev/null 2>&1 || true
        load_state
        
        local used_gb=$(bytes_to_gb "$MONTH_EGRESS")
        local percent=$(calc_percentage "$MONTH_EGRESS" "$LIMIT")

        clear
        cat << MENU

╔════════════════════════════════════════════════════════════╗
║          阿里云流量监控 - 管理面板                        ║
╚════════════════════════════════════════════════════════════╝

📊 实时状态:
   流量   : $used_gb GB / 200 GB ($percent%)
   周期   : $CURRENT_MONTH
   提示   : $REPORT_COUNT / 20

🎮 管理菜单:
  1) 查看状态
  2) 测试通知
  3) 显示配置
  4) 重新配置
  5) 查看日志
  6) 清空日志
  7) 强制启动服务
  8) 强制停止服务
  9) 重置流量计数
  10) 系统诊断
  11) 版本信息
  0) 退出

════════════════════════════════════════════════════════════

MENU
        read -p "请选择 [0-11]: " choice

        case "$choice" in
            1) cmd_status; read -p "按Enter继续..."; ;;
            2) cmd_test; read -p "按Enter继续..."; ;;
            3) cmd_show_config; read -p "按Enter继续..."; ;;
            4) interactive_setup; ;;
            5) cmd_logs; read -p "按Enter继续..."; ;;
            6) cmd_clear_logs; read -p "按Enter继续..."; ;;
            7) cmd_force_start; read -p "按Enter继续..."; ;;
            8) cmd_force_stop; read -p "按Enter继续..."; ;;
            9) cmd_reset_state; read -p "按Enter继续..."; ;;
            10) cmd_diagnose; read -p "按Enter继续..."; ;;
            11) cmd_version; read -p "按Enter继续..."; ;;
            0) info "退出"; exit 0; ;;
            *) warn "无效选择"; sleep 1; ;;
        esac
    done
}

# 如果没有参数或调用为 menu，启动交互菜单
if [ $# -eq 0 ] || [ "${1:-}" = "menu" ]; then
    show_interactive_menu
fi

# ─────────────────────────────────────────────────────────────────────────
# 完整使用指南
# ─────────────────────────────────────────────────────────────────────────

cmd_manual() {
    cat << 'MANUAL'

╔════════════════════════════════════════════════════════════════════╗
║     阿里云流量监控完整使用指南                                    ║
╚════════════════════════════════════════════════════════════════════╝

【快速开始】

1. 安装程序
   $ sudo bash alicloud-traffic-monitor-full.sh install

2. 查看状态
   $ alitm status

3. 测试通知
   $ alitm test

4. 查看日志
   $ tail -f /var/lib/alicloud-traffic-monitor/traffic.log

【配置说明】

配置文件: /etc/alicloud-traffic-monitor.conf

关键参数:
  INTERFACE        - 监控网卡 (默认: eth0)
  SINGBOX_SERVICE  - 受控服务 (默认: sing-box)
  INTERVAL         - 检查间隔 (1-60秒, 默认: 1)
  TG_BOT_TOKEN     - Telegram机器人token (可选)
  TG_CHAT_ID       - Telegram聊天ID (可选)

【流量限额说明】

- 200GB / 月 硬性限制
- 每10GB报告一次进度
- 170GB/180GB/190GB 时强制预警
- 达到200GB自动停止sing-box
- 月初自动恢复并重置计数

【通知等级】

🟢 0-100GB       - 无通知
🟡 100-170GB     - 第1-17次提示 (10GB间隔)
🟠 170-180GB     - 第18次提示 (最后30GB预警)
🟠 180-190GB     - 第19次提示 (最后20GB预警)
🔴 190-200GB     - 第19次提示 (最后10GB预警)
🚫 ≥200GB        - 第20次提示 (达到限额)

【常用命令】

# 安装
sudo $0 install

# 运行监控 (后台)
nohup $0 run > /dev/null 2>&1 &

# 查看状态
$0 status

# 测试通知
$0 test

# 系统诊断
$0 diagnose

# 查看日志 (最近50行)
$0 logs

# 清空日志
sudo $0 clear-logs

# 强制启动服务
sudo $0 force-start

# 强制停止服务
sudo $0 force-stop

# 重置计数 (谨慎使用!)
sudo $0 reset-state

# 重新配置
$0 setup

# 卸载
sudo $0 uninstall

# 交互菜单
sudo $0 menu

【日志文件】

位置: /var/lib/alicloud-traffic-monitor/traffic.log

日志包含:
  [INFO]   - 普通信息
  [WARN]   - 警告消息
  [ERROR]  - 错误消息
  [EVENT]  - 重要事件

自动轮转: >10MB 时压缩为 .gz，保留7天

【故障排查】

问题1: 无法读取网卡
  原因: 网卡名称错误
  解决: ls /sys/class/net/ 查看正确网卡名，修改INTERFACE

问题2: Telegram无法通知
  原因: Token或Chat ID错误
  解决: 运行 $0 test 测试，检查凭证

问题3: 服务未自动停止
  原因: 监控进程未运行
  解决: ps aux | grep monitor 检查，运行 nohup $0 run &

【开发信息】

Author  : Candies-Sven
Repo    : https://github.com/candies-sven-007/alicloud-traffic-monitor
Version : 2.0.0
License : MIT

支持系统: Alpine Linux, Debian, Ubuntu, CentOS
Init系统: OpenRC, Systemd
依赖项: bash, curl, awk, coreutils, ca-certificates

【许可证】

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software...

═════════════════════════════════════════════════════════════════════

MANUAL
}

# 补充的命令路由（支持带横线的命令）
case "${1:-}" in
    logs)
        cmd_logs
        ;;
    clear-logs)
        cmd_clear_logs
        ;;
    reset-state)
        cmd_reset_state
        ;;
    force-start)
        cmd_force_start
        ;;
    force-stop)
        cmd_force_stop
        ;;
    show-config)
        cmd_show_config
        ;;
    menu)
        show_interactive_menu
        ;;
    version)
        cmd_version
        ;;
    manual|help|--help|-h)
        print_banner
        cmd_manual
        ;;
esac
