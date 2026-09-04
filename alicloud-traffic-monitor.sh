#!/bin/sh
# ==============================================================================
# Alibaba Cloud ECS Outbound Traffic Monitor (alicloud-traffic-monitor)
# Alpine Linux + OpenRC + Telegram
# Version: v1.0.0
# Author: candies
# ==============================================================================

set -u

APP="alicloud-traffic-monitor"
CONF="/etc/alicloud-traffic-monitor.conf"
STATE_DIR="/var/lib/alicloud-traffic-monitor"
STATE="$STATE_DIR/state"
LOG="$STATE_DIR/traffic.log"
LOCK="$STATE_DIR/limit.lock"

# 默认参数（可通过配置文件覆盖）
INTERFACE="eth0"
SINGBOX_SERVICE="sing-box"
GB=1000000000
REPORT_STEP=$((10 * GB))
LIMIT=$((200 * GB))
INTERVAL=1

# 读取外部配置
if [ -r "$CONF" ]; then
    . "$CONF"
fi

format_gb() {
    awk -v b="$1" 'BEGIN { printf "%.2f", b / 1000000000 }'
}

get_tx() {
    local dev_path="/sys/class/net/$INTERFACE/statistics/tx_bytes"
    if [ -f "$dev_path" ]; then
        cat "$dev_path"
    else
        echo 0
    fi
}

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

send_tg() {
    local msg="$1"
    if [ -r "$CONF" ]; then
        . "$CONF"
    fi

    if [ -z "${TG_BOT_TOKEN:-}" ] || [ -z "${TG_CHAT_ID:-}" ]; then
        log "Telegram 未配置或为空，跳过通知"
        return 0
    fi

    local result
    result="$(curl -fsS --max-time 15 -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TG_CHAT_ID}" \
        --data-urlencode "text=${msg}" \
        --data-urlencode "parse_mode=HTML" 2>&1)" || {
        log "Telegram 发送失败: $result"
        return 1
    }

    if ! echo "$result" | grep -q '"ok":true'; then
        log "Telegram API 返回错误: $result"
    fi
}

save() {
    local tmp="$STATE.tmp"
    cat > "$tmp" <<EOF
CURRENT_MONTH='$CURRENT_MONTH'
MONTH_EGRESS='$MONTH_EGRESS'
LAST_TX='$LAST_TX'
REPORT_COUNT='$REPORT_COUNT'
NEXT_REPORT='$NEXT_REPORT'
LIMIT_REACHED='$LIMIT_REACHED'
EOF
    mv "$tmp" "$STATE"
}

load() {
    if [ -f "$STATE" ]; then
        . "$STATE"
    else
        CURRENT_MONTH="$(date '+%Y-%m')"
        MONTH_EGRESS=0
        LAST_TX="$(get_tx)"
        REPORT_COUNT=0
        NEXT_REPORT="$REPORT_STEP"
        LIMIT_REACHED=0
        save
    fi
}

stop_singbox() {
    rc-service "$SINGBOX_SERVICE" stop >/dev/null 2>&1 || true
    log "$SINGBOX_SERVICE 已停止"
}

start_singbox() {
    rc-service "$SINGBOX_SERVICE" start >/dev/null 2>&1 || true
    log "$SINGBOX_SERVICE 已恢复运行"
}

new_month() {
    CURRENT_MONTH="$(date '+%Y-%m')"
    MONTH_EGRESS=0
    REPORT_COUNT=0
    NEXT_REPORT="$REPORT_STEP"
    LIMIT_REACHED=0
    rm -f "$LOCK"

    LAST_TX="$(get_tx)"
    save
    start_singbox

    send_tg "🔄 <b>【阿里云出站保护】新自然月计费周期开始</b>

📅 周期：${CURRENT_MONTH}-01 00:00:00 起
💾 月度出站配额：<b>200 GB</b>
📤 当前已用出站：<b>0.00 GB</b>
📉 剩余出站：<b>200.00 GB</b>
🟢 <b>${SINGBOX_SERVICE} 已自动恢复运行</b>
📡 统计网卡：${INTERFACE} TX (出站流量)

🕐 $(date '+%Y-%m-%d %H:%M:%S')"
    log "新自然月触发: $CURRENT_MONTH"
}

report() {
    REPORT_COUNT=$((REPORT_COUNT + 1))
    local used remain remain_gb pct title warning

    used="$(format_gb "$MONTH_EGRESS")"
    remain=$((LIMIT - MONTH_EGRESS))
    if [ "$remain" -lt 0 ]; then
        remain=0
    fi
    remain_gb="$(format_gb "$remain")"
    pct="$(awk -v t="$MONTH_EGRESS" 'BEGIN { printf "%.1f", t / 200000000000 * 100 }')"

    case "$NEXT_REPORT" in
        $((170 * GB)))
            title="⚠️ <b>【阿里云出站保护】流量预警</b>"
            warning="🟡 已进入最后 <b>30 GB</b> 预警阶段。"
            ;;
        $((180 * GB)))
            title="⚠️ <b>【阿里云出站保护】流量预警</b>"
            warning="🟠 已进入最后 <b>20 GB</b> 预警阶段。"
            ;;
        $((190 * GB)))
            title="🚨 <b>【阿里云出站保护】最后一次流量预警</b>"
            warning="🔴 仅剩 <b>10 GB</b>，达到 200 GB 后将立即停止 ${SINGBOX_SERVICE}。"
            ;;
        *)
            title="📊 <b>【阿里云出站保护】流量使用报告</b>"
            warning=""
            ;;
    esac

    send_tg "${title}

<b>第 ${REPORT_COUNT} 次提示</b>

📤 本月公网出站：<b>${used} GB / 200 GB</b>
📈 出站使用率：<b>${pct}%</b>
📉 剩余额度：<b>${remain_gb} GB</b>

📡 监控网卡：${INTERFACE}
📤 统计指标：<b>TX (公网出站)</b>
${warning:+
$warning}
📅 计费周期：${CURRENT_MONTH}
🕐 $(date '+%Y-%m-%d %H:%M:%S')"

    NEXT_REPORT=$((NEXT_REPORT + REPORT_STEP))
    save
    log "阶梯报告 #${REPORT_COUNT} 已推送: ${used} GB"
}

limit_reached() {
    [ "$LIMIT_REACHED" -eq 1 ] && return 0
    LIMIT_REACHED=1
    touch "$LOCK"
    stop_singbox

    # 规范第 20 次提示序号
    REPORT_COUNT=20
    NEXT_REPORT=$((LIMIT + REPORT_STEP))
    save

    local used
    used="$(format_gb "$MONTH_EGRESS")"

    send_tg "🛑 <b>【阿里云出站保护】200 GB 流量额度已用尽</b>

<b>第 20 次提示（达到额度上限）</b>

📤 本月公网出站：<b>${used} GB / 200 GB</b>
📉 剩余额度：<b>0.00 GB</b>

🚫 <b>${SINGBOX_SERVICE} 已自动停止</b>
🔒 本月剩余时间保持熔断锁定。
⚠️ 即使 VPS 重启，也会再次阻止 ${SINGBOX_SERVICE} 运行。
🔄 下一个自然月 1 日 00:00 自动恢复。

📅 当前周期：${CURRENT_MONTH}
🕐 $(date '+%Y-%m-%d %H:%M:%S')"

    log "已触发 200 GB 熔断，锁定已生成"
}

run_monitor() {
    mkdir -p "$STATE_DIR"
    touch "$LOG"
    load

    local real
    real="$(date '+%Y-%m')"
    if [ "$CURRENT_MONTH" != "$real" ]; then
        new_month
    fi

    log "守护进程启动; 网卡=$INTERFACE; 周期=$CURRENT_MONTH"

    while :; do
        real="$(date '+%Y-%m')"
        if [ "$CURRENT_MONTH" != "$real" ]; then
            new_month
        fi

        local current_tx diff
        current_tx="$(get_tx)"

        if [ "$current_tx" -ge "$LAST_TX" ]; then
            diff=$((current_tx - LAST_TX))
        else
            diff="$current_tx"
            log "检测到 TX counter 重置/重启"
        fi

        MONTH_EGRESS=$((MONTH_EGRESS + diff))
        LAST_TX="$current_tx"

        # 仅针对 10GB ~ 190GB 的阶梯阶梯报告（严格 < LIMIT，避免与第 20 次熔断冲突）
        while [ "$MONTH_EGRESS" -ge "$NEXT_REPORT" ] && [ "$NEXT_REPORT" -lt "$LIMIT" ]; do
            report
        done

        # 达到或超出 200 GB
        if [ "$MONTH_EGRESS" -ge "$LIMIT" ]; then
            limit_reached
        fi

        # 熔断防御
        if [ "$LIMIT_REACHED" -eq 1 ] || [ -f "$LOCK" ]; then
            if rc-service "$SINGBOX_SERVICE" status 2>/dev/null | grep -q "started"; then
                stop_singbox
                log "防御生效：检测到 $SINGBOX_SERVICE 在熔断期启动，已再次强制停止"
            fi
        fi

        save
        sleep "$INTERVAL"
    done
}

status_cmd() {
    if [ ! -f "$STATE" ]; then
        echo "状态尚未初始化，请确认服务已启动。"
        exit 1
    fi
    . "$STATE"
    echo "=== Alibaba Cloud ECS Egress Traffic Monitor ==="
    echo "计费周期   : $CURRENT_MONTH"
    echo "公网出站   : $(format_gb "$MONTH_EGRESS") GB / 200 GB"
    echo "出站使用率 : $(awk -v t="$MONTH_EGRESS" 'BEGIN { printf "%.1f%%", t / 200000000000 * 100 }')"
    echo "剩余额度   : $(awk -v t="$MONTH_EGRESS" 'BEGIN { r = 200 - t / 1000000000; if (r < 0) r = 0; printf "%.2f GB", r }')"
    echo "提示计数   : 第 ${REPORT_COUNT} 次"
    echo "熔断锁定   : $([ "$LIMIT_REACHED" -eq 1 ] || [ -f "$LOCK" ] && echo "🚨 已锁定 (sing-box 保持关闭)" || echo "🟢 正常监控中")"
    echo "sing-box   : $(rc-service "$SINGBOX_SERVICE" status 2>/dev/null | grep -q "started" && echo "running" || echo "stopped")"
}

telegram_test() {
    if [ ! -r "$CONF" ]; then
        echo "找不到配置文件 $CONF"
        exit 1
    fi
    . "$CONF"
    curl -fsS --max-time 15 -X POST \
        "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TG_CHAT_ID}" \
        --data-urlencode "text=✅ <b>Alibaba Cloud ECS 流量监控测试通知</b>

📡 网卡：${INTERFACE}
📤 统计方向：TX / 公网出站
💾 月度额度：200 GB
📊 报告步长：10 GB
🛑 200 GB 自动熔断停止 sing-box

🕐 $(date '+%Y-%m-%d %H:%M:%S')" \
        --data-urlencode "parse_mode=HTML" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "✅ Telegram 测试通知发送成功！"
    else
        echo "❌ Telegram 测试通知发送失败，请检查 Token 与 Chat ID。"
    fi
}

case "${1:-}" in
    run)
        run_monitor
        ;;
    status)
        status_cmd
        ;;
    test|telegram-test)
        telegram_test
        ;;
    *)
        echo "用法: $0 {run|status|test}"
        exit 1
        ;;
esac
