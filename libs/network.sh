#!/bin/sh
# ==============================================================================
# network.sh - 网络监控库
# 特性：安全的流量读取、数值计算、溢出保护
# ==============================================================================

set -u

# ─────────────────────────────────────────────────────────────────────────
# 获取网卡TX字节数
# ─────────────────────────────────────────────────────────────────────────
net_get_tx_bytes() {
    local interface="$1"
    local tx_path="/sys/class/net/$interface/statistics/tx_bytes"
    
    if [ ! -f "$tx_path" ]; then
        echo "ERROR: tx_bytes file not found: $tx_path" >&2
        return 1
    fi
    
    local tx_bytes
    tx_bytes="$(cat "$tx_path" 2>/dev/null)"
    
    if [ -z "$tx_bytes" ] || ! echo "$tx_bytes" | grep -qE '^[0-9]+$'; then
        echo "ERROR: invalid tx_bytes value: $tx_bytes" >&2
        return 1
    fi
    
    echo "$tx_bytes"
}

# ─────────────────────────────────────────────────────────────────────────
# 格式化字节为GB（保留2位小数）
# ─────────────────────────────────────────────────────────────────────────
net_format_bytes_to_gb() {
    local bytes="$1"
    
    # 验证输入
    if ! echo "$bytes" | grep -qE '^[0-9]+$'; then
        echo "ERROR: invalid bytes value: $bytes" >&2
        return 1
    fi
    
    # 使用awk进行浮点运算
    echo "$bytes" | awk '{ printf "%.2f", $1 / 1000000000 }'
}

# ─────────────────────────────────────────────────────────────────────────
# 计算百分比
# ─────────────────────────────────────────────────────────────────────────
net_calculate_percentage() {
    local used="$1"
    local total="$2"
    
    # 验证输入
    if ! echo "$used" | grep -qE '^[0-9]+$' || ! echo "$total" | grep -qE '^[0-9]+$'; then
        echo "ERROR: invalid input for percentage calculation" >&2
        return 1
    fi
    
    if [ "$total" -eq 0 ]; then
        echo "0.0"
        return 0
    fi
    
    echo "$used" | awk -v t="$total" '{ printf "%.1f", $1 / t * 100 }'
}

# ─────────────────────────────────────────────────────────────────────────
# 安全的64位整数加法（防溢出）
# ─────────────────────────────────────────────────────────────────────────
net_safe_add() {
    local a="$1"
    local b="$2"
    local max=9223372036854775807  # 2^63 - 1
    
    # 验证输入
    if ! echo "$a" | grep -qE '^[0-9]+$' || ! echo "$b" | grep -qE '^[0-9]+$'; then
        echo "ERROR: invalid input for addition" >&2
        return 1
    fi
    
    # 溢出检查
    if [ "$a" -gt $((max - b)) ]; then
        echo "ERROR: integer overflow detected" >&2
        return 1
    fi
    
    echo $((a + b))
}

# ─────────────────────────────────────────────────────────────────────────
# 计算差值（处理计数器重置）
# 用法: net_calculate_delta CURRENT LAST
# 返回: 差值（如果计数器重置则返回CURRENT）
# ─────────────────────────────────────────────────────────────────────────
net_calculate_delta() {
    local current="$1"
    local last="$2"
    
    # 验证输入
    if ! echo "$current" | grep -qE '^[0-9]+$' || ! echo "$last" | grep -qE '^[0-9]+$'; then
        echo "ERROR: invalid input for delta calculation" >&2
        return 1
    fi
    
    if [ "$current" -ge "$last" ]; then
        # 正常情况
        echo $((current - last))
    else
        # 计数器重置（系统重启或网卡重置）
        echo "$current"
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# 获取网卡速度
# ─────────────────────────────────────────────────────────────────────────
net_get_speed() {
    local interface="$1"
    local speed_path="/sys/class/net/$interface/speed"
    
    if [ ! -f "$speed_path" ]; then
        return 1
    fi
    
    cat "$speed_path" 2>/dev/null || return 1
}

# ─────────────────────────────────────────────────────────────────────────
# 检查网卡状态
# ─────────────────────────────────────────────────────────────────────────
net_is_interface_up() {
    local interface="$1"
    local state_path="/sys/class/net/$interface/operstate"
    
    if [ ! -f "$state_path" ]; then
        return 1
    fi
    
    local state
    state="$(cat "$state_path" 2>/dev/null)"
    
    [ "$state" = "up" ]
}

# ─────────────────────────────────────────────────────────────────────────
# 检测TX计数器重置
# ─────────────────────────────────────────────────────────────────────────
net_detect_reset() {
    local current="$1"
    local last="$2"
    
    # 验证输入
    if ! echo "$current" | grep -qE '^[0-9]+$' || ! echo "$last" | grep -qE '^[0-9]+$'; then
        return 1
    fi
    
    # 如果当前值小于上次值，说明发生了重置
    [ "$current" -lt "$last" ]
}

# ─────────────────────────────────────────────────────────────────────────
# 获取剩余流量
# ─────────────────────────────────────────────────────────────────────────
net_calculate_remaining() {
    local used="$1"
    local limit="$2"
    
    # 验证输入
    if ! echo "$used" | grep -qE '^[0-9]+$' || ! echo "$limit" | grep -qE '^[0-9]+$'; then
        echo "ERROR: invalid input for remaining calculation" >&2
        return 1
    fi
    
    local remain
    remain=$((limit - used))
    
    if [ "$remain" -lt 0 ]; then
        echo 0
    else
        echo "$remain"
    fi
}

export -f net_get_tx_bytes net_format_bytes_to_gb net_calculate_percentage
export -f net_safe_add net_calculate_delta net_get_speed net_is_interface_up
export -f net_detect_reset net_calculate_remaining
