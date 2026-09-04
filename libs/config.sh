#!/bin/sh
# ==============================================================================
# config.sh - 配置管理库
# 特性：参数验证、默认值、配置检查
# ==============================================================================

set -u

# 全局配置变量
export INTERFACE="${INTERFACE:-eth0}"
export SINGBOX_SERVICE="${SINGBOX_SERVICE:-sing-box}"
export INTERVAL="${INTERVAL:-1}"
export TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"
export TG_CHAT_ID="${TG_CHAT_ID:-}"

# 系统常量
export BYTE_PER_GB=1000000000
export REPORT_STEP=$((10 * BYTE_PER_GB))
export LIMIT=$((200 * BYTE_PER_GB))

# ─────────────────────────────────────────────────────────────────────────
# 加载配置文件
# ─────────────────────────────────────────────────────────────────────────
config_load() {
    local conf_file="$1"
    
    if [ -z "$conf_file" ]; then
        echo "ERROR: config_load requires conf_file argument" >&2
        return 1
    fi
    
    if [ ! -f "$conf_file" ]; then
        echo "WARNING: config file not found: $conf_file" >&2
        return 0
    fi
    
    if [ ! -r "$conf_file" ]; then
        echo "ERROR: config file not readable: $conf_file" >&2
        return 1
    fi
    
    # 安全加载配置（在子shell中）
    if . "$conf_file" 2>/dev/null; then
        return 0
    else
        echo "ERROR: invalid config file: $conf_file" >&2
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# 验证配置参数
# ─────────────────────────────────────────────────────────────────────────
config_validate() {
    local errors=0
    
    # 验证网卡名称
    if [ -z "$INTERFACE" ]; then
        echo "ERROR: INTERFACE is not set" >&2
        errors=$((errors + 1))
    elif [ ! -d "/sys/class/net/$INTERFACE" ]; then
        echo "ERROR: network interface not found: $INTERFACE" >&2
        errors=$((errors + 1))
    fi
    
    # 验证服务名称
    if [ -z "$SINGBOX_SERVICE" ]; then
        echo "ERROR: SINGBOX_SERVICE is not set" >&2
        errors=$((errors + 1))
    fi
    
    # 验证轮询间隔
    if ! echo "$INTERVAL" | grep -qE '^[0-9]+$'; then
        echo "ERROR: INTERVAL must be a positive integer: $INTERVAL" >&2
        errors=$((errors + 1))
    elif [ "$INTERVAL" -lt 1 ] || [ "$INTERVAL" -gt 60 ]; then
        echo "ERROR: INTERVAL must be between 1 and 60 seconds" >&2
        errors=$((errors + 1))
    fi
    
    # 验证Telegram配置（可选，但需要同时配置）
    if [ -n "$TG_BOT_TOKEN" ] && [ -z "$TG_CHAT_ID" ]; then
        echo "ERROR: TG_CHAT_ID must be set if TG_BOT_TOKEN is set" >&2
        errors=$((errors + 1))
    fi
    
    if [ -n "$TG_CHAT_ID" ] && [ -z "$TG_BOT_TOKEN" ]; then
        echo "ERROR: TG_BOT_TOKEN must be set if TG_CHAT_ID is set" >&2
        errors=$((errors + 1))
    fi
    
    # 验证Token格式（基本检查）
    if [ -n "$TG_BOT_TOKEN" ]; then
        if ! echo "$TG_BOT_TOKEN" | grep -qE '^[0-9]{8,}:[A-Za-z0-9_-]{27,}$'; then
            echo "WARNING: TG_BOT_TOKEN format looks invalid" >&2
        fi
    fi
    
    if [ -n "$TG_CHAT_ID" ]; then
        if ! echo "$TG_CHAT_ID" | grep -qE '^-?[0-9]+$'; then
            echo "WARNING: TG_CHAT_ID format looks invalid" >&2
        fi
    fi
    
    return $errors
}

# ─────────────────────────────────────────────────────────────────────────
# 显示配置信息
# ─────────────────────────────────────────────────────────────────────────
config_show() {
    echo "=== Configuration ==="
    echo "INTERFACE           : $INTERFACE"
    echo "SINGBOX_SERVICE     : $SINGBOX_SERVICE"
    echo "INTERVAL            : ${INTERVAL}s"
    echo "TELEGRAM_CONFIGURED : $([ -n "$TG_BOT_TOKEN" ] && echo 'yes' || echo 'no')"
    echo "REPORT_STEP         : $((REPORT_STEP / BYTE_PER_GB)) GB"
    echo "LIMIT               : $((LIMIT / BYTE_PER_GB)) GB"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────
# 生成配置文件模板
# ─────────────────────────────────────────────────────────────────────────
config_generate_template() {
    local output_file="$1"
    
    cat > "$output_file" << 'EOF'
# Alibaba Cloud Traffic Monitor - Configuration File
# 阿里云流量监控 - 配置文件

# Network Interface to monitor (网卡名称)
# Default: eth0
INTERFACE="eth0"

# Service name to control (受控服务名称)
# Default: sing-box
SINGBOX_SERVICE="sing-box"

# Check interval in seconds (检查间隔，秒)
# Default: 1 (must be 1-60)
INTERVAL="1"

# Telegram Bot Token (Telegram 机器人 Token)
# Get from BotFather: https://t.me/BotFather
TG_BOT_TOKEN=""

# Telegram Chat ID (Telegram 聊天 ID)
# Get from your bot or IDBot
TG_CHAT_ID=""
EOF
    
    chmod 600 "$output_file"
    return 0
}

# ─────────────────────────────────────────────────────────────────────────
# 交互式配置向导
# ─────────────────────────────────────────────────────────────────────────
config_interactive() {
    local output_file="$1"
    
    echo ""
    echo "=== Alibaba Cloud Traffic Monitor - Configuration Wizard ==="
    echo ""
    
    # 网卡名称
    printf "Network interface [eth0]: "
    read -r input_interface
    INTERFACE="${input_interface:-eth0}"
    
    # 验证网卡
    if [ ! -d "/sys/class/net/$INTERFACE" ]; then
        echo "ERROR: Interface $INTERFACE not found!"
        return 1
    fi
    
    # 服务名称
    printf "Service name to control [sing-box]: "
    read -r input_service
    SINGBOX_SERVICE="${input_service:-sing-box}"
    
    # Telegram配置
    printf "Enable Telegram notifications? (y/n) [n]: "
    read -r enable_tg
    
    if [ "$enable_tg" = "y" ] || [ "$enable_tg" = "Y" ]; then
        printf "Telegram Bot Token: "
        read -r input_token
        
        if [ -z "$input_token" ]; then
            echo "ERROR: Bot Token cannot be empty"
            return 1
        fi
        
        printf "Telegram Chat ID: "
        read -r input_chat_id
        
        if [ -z "$input_chat_id" ]; then
            echo "ERROR: Chat ID cannot be empty"
            return 1
        fi
        
        TG_BOT_TOKEN="$input_token"
        TG_CHAT_ID="$input_chat_id"
    fi
    
    # 保存配置
    cat > "$output_file" << EOFCONF
# Alibaba Cloud Traffic Monitor Configuration
# Generated: $(date)

INTERFACE="$INTERFACE"
SINGBOX_SERVICE="$SINGBOX_SERVICE"
INTERVAL="1"
TG_BOT_TOKEN="$TG_BOT_TOKEN"
TG_CHAT_ID="$TG_CHAT_ID"
EOFCONF
    
    chmod 600 "$output_file"
    
    echo ""
    echo "✅ Configuration saved to: $output_file"
    echo ""
    
    return 0
}

export -f config_load config_validate config_show config_generate_template config_interactive
