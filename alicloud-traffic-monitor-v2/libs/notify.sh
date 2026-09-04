#!/bin/sh
# ==============================================================================
# notify.sh - 通知库
# 特性：Telegram集成、重试机制、错误处理
# ==============================================================================

set -u

export TG_API_TIMEOUT=15
export TG_RETRY_COUNT=3
export TG_RETRY_DELAY=2

# ─────────────────────────────────────────────────────────────────────────
# 验证Telegram配置
# ─────────────────────────────────────────────────────────────────────────
notify_is_configured() {
    [ -n "${TG_BOT_TOKEN:-}" ] && [ -n "${TG_CHAT_ID:-}" ]
}

# ─────────────────────────────────────────────────────────────────────────
# 发送Telegram消息（带重试机制）
# ─────────────────────────────────────────────────────────────────────────
notify_send_telegram() {
    local message="$1"
    local retry_count="${TG_RETRY_COUNT}"
    local retry_delay="${TG_RETRY_DELAY}"
    
    # 检查是否配置
    if ! notify_is_configured; then
        return 0  # 未配置则直接返回成功
    fi
    
    # 验证消息非空
    if [ -z "$message" ]; then
        return 1
    fi
    
    local attempt=0
    local response
    
    while [ "$attempt" -lt "$retry_count" ]; do
        attempt=$((attempt + 1))
        
        # 发送请求
        response="$(curl -fsS --max-time "$TG_API_TIMEOUT" -X POST \
            "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${TG_CHAT_ID}" \
            --data-urlencode "text=${message}" \
            --data-urlencode "parse_mode=HTML" \
            2>&1)" || {
            
            if [ "$attempt" -lt "$retry_count" ]; then
                sleep "$retry_delay"
                continue
            else
                return 1
            fi
        }
        
        # 验证响应
        if echo "$response" | grep -q '"ok":true'; then
            return 0
        elif echo "$response" | grep -q '"ok":false'; then
            # API错误，不重试
            return 1
        fi
        
        # 其他错误，重试
        if [ "$attempt" -lt "$retry_count" ]; then
            sleep "$retry_delay"
        fi
    done
    
    return 1
}

# ─────────────────────────────────────────────────────────────────────────
# 发送测试消息
# ─────────────────────────────────────────────────────────────────────────
notify_test() {
    if ! notify_is_configured; then
        echo "ERROR: Telegram is not configured" >&2
        return 1
    fi
    
    local test_msg="✅ <b>Alibaba Cloud Traffic Monitor - Test Message</b>\n\n🕐 $(date '+%Y-%m-%d %H:%M:%S')"
    
    if notify_send_telegram "$test_msg"; then
        echo "✅ Telegram test message sent successfully"
        return 0
    else
        echo "❌ Failed to send Telegram test message"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# 发送阶梯报告
# ─────────────────────────────────────────────────────────────────────────
notify_report() {
    local report_count="$1"
    local used_gb="$2"
    local percent="$3"
    local remain_gb="$4"
    local current_month="$5"
    
    local title warning
    
    case "$report_count" in
        17)
            title="⚠️ <b>【Alibaba Cloud Egress Protection】Traffic Warning</b>"
            warning="🟡 Entering final <b>30 GB</b> warning stage.\n"
            ;;
        18)
            title="⚠️ <b>【Alibaba Cloud Egress Protection】Traffic Warning</b>"
            warning="🟠 Entering final <b>20 GB</b> warning stage.\n"
            ;;
        19)
            title="🚨 <b>【Alibaba Cloud Egress Protection】Last Traffic Warning</b>"
            warning="🔴 Only <b>10 GB</b> remaining. sing-box will stop after 200 GB.\n"
            ;;
        *)
            title="📊 <b>【Alibaba Cloud Egress Protection】Traffic Report</b>"
            warning=""
            ;;
    esac
    
    local message="$title\n\n<b>Notification #${report_count}</b>\n\n📤 Monthly egress: <b>${used_gb} GB / 200 GB</b>\n📈 Usage rate: <b>${percent}%</b>\n📉 Remaining quota: <b>${remain_gb} GB</b>\n${warning}📅 Billing cycle: ${current_month}\n🕐 $(date '+%Y-%m-%d %H:%M:%S')"
    
    notify_send_telegram "$message"
}

# ─────────────────────────────────────────────────────────────────────────
# 发送限额达到通知
# ─────────────────────────────────────────────────────────────────────────
notify_limit_reached() {
    local used_gb="$1"
    local current_month="$2"
    
    local message="🛑 <b>【Alibaba Cloud Egress Protection】200 GB Limit Reached</b>\n\n<b>Notification #20 (Limit exceeded)</b>\n\n📤 Monthly egress: <b>${used_gb} GB / 200 GB</b>\n📉 Remaining quota: <b>0.00 GB</b>\n\n🚫 <b>sing-box has been automatically stopped</b>\n🔒 Circuit breaker locked for remaining month.\n⚠️ Service remains stopped even after VPS restart.\n🔄 Auto recovery on next month's 1st day at 00:00.\n\n📅 Current cycle: ${current_month}\n🕐 $(date '+%Y-%m-%d %H:%M:%S')"
    
    notify_send_telegram "$message"
}

# ─────────────────────────────────────────────────────────────────────────
# 发送新月份通知
# ─────────────────────────────────────────────────────────────────────────
notify_new_month() {
    local current_month="$1"
    
    local message="🔄 <b>【Alibaba Cloud Egress Protection】New Billing Cycle Started</b>\n\n📅 Cycle: ${current_month}-01 00:00:00\n💾 Monthly quota: <b>200 GB</b>\n📤 Current egress: <b>0.00 GB</b>\n📉 Remaining quota: <b>200.00 GB</b>\n🟢 <b>sing-box automatically recovered</b>\n📡 Monitoring interface: eth0 TX\n\n🕐 $(date '+%Y-%m-%d %H:%M:%S')"
    
    notify_send_telegram "$message"
}

# ─────────────────────────────────────────────────────────────────────────
# 发送错误通知
# ─────────────────────────────────────────────────────────────────────────
notify_error() {
    local error_type="$1"
    local error_message="$2"
    
    if ! notify_is_configured; then
        return 0
    fi
    
    local message="🚨 <b>【Alibaba Cloud Traffic Monitor】Error Detected</b>\n\n❌ Error type: ${error_type}\n📝 Message: ${error_message}\n🕐 $(date '+%Y-%m-%d %H:%M:%S')"
    
    notify_send_telegram "$message"
}

export -f notify_is_configured notify_send_telegram notify_test
export -f notify_report notify_limit_reached notify_new_month notify_error
