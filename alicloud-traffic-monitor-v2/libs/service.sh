#!/bin/sh
# ==============================================================================
# service.sh - 服务管理库
# 特性：OpenRC/systemd兼容、安全的服务控制、状态检测
# ==============================================================================

set -u

# 检测init系统
export INIT_SYSTEM=""

# ─────────────────────────────────────────────────────────────────────────
# 检测初始化系统
# ─────────────────────────────────────────────────────────────────────────
service_detect_init() {
    if [ -d "/run/openrc" ] || [ -f "/etc/inittab" ] && grep -q "^si::sysinit" /etc/inittab 2>/dev/null; then
        INIT_SYSTEM="openrc"
    elif [ -d "/run/systemd" ] || [ -L "/sbin/init" ] && grep -q "systemd" "/sbin/init" 2>/dev/null; then
        INIT_SYSTEM="systemd"
    else
        INIT_SYSTEM="unknown"
    fi
    
    echo "$INIT_SYSTEM"
}

# ─────────────────────────────────────────────────────────────────────────
# 停止服务
# ─────────────────────────────────────────────────────────────────────────
service_stop() {
    local service="$1"
    
    if [ -z "$INIT_SYSTEM" ]; then
        service_detect_init >/dev/null
    fi
    
    case "$INIT_SYSTEM" in
        openrc)
            rc-service "$service" stop >/dev/null 2>&1 || return 1
            ;;
        systemd)
            systemctl stop "$service" >/dev/null 2>&1 || return 1
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# ─────────────────────────────────────────────────────────────────────────
# 启动服务
# ─────────────────────────────────────────────────────────────────────────
service_start() {
    local service="$1"
    
    if [ -z "$INIT_SYSTEM" ]; then
        service_detect_init >/dev/null
    fi
    
    case "$INIT_SYSTEM" in
        openrc)
            rc-service "$service" start >/dev/null 2>&1 || return 1
            ;;
        systemd)
            systemctl start "$service" >/dev/null 2>&1 || return 1
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# ─────────────────────────────────────────────────────────────────────────
# 重启服务
# ─────────────────────────────────────────────────────────────────────────
service_restart() {
    local service="$1"
    
    if [ -z "$INIT_SYSTEM" ]; then
        service_detect_init >/dev/null
    fi
    
    case "$INIT_SYSTEM" in
        openrc)
            rc-service "$service" restart >/dev/null 2>&1 || return 1
            ;;
        systemd)
            systemctl restart "$service" >/dev/null 2>&1 || return 1
            ;;
        *)
            return 1
            ;;
    esac
    
    return 0
}

# ─────────────────────────────────────────────────────────────────────────
# 检查服务状态
# ─────────────────────────────────────────────────────────────────────────
service_is_running() {
    local service="$1"
    
    if [ -z "$INIT_SYSTEM" ]; then
        service_detect_init >/dev/null
    fi
    
    case "$INIT_SYSTEM" in
        openrc)
            rc-service "$service" status >/dev/null 2>&1 && return 0
            ;;
        systemd)
            systemctl is-active "$service" >/dev/null 2>&1 && return 0
            ;;
        *)
            return 1
            ;;
    esac
    
    return 1
}

# ─────────────────────────────────────────────────────────────────────────
# 获取服务状态（人可读格式）
# ─────────────────────────────────────────────────────────────────────────
service_get_status() {
    local service="$1"
    
    if service_is_running "$service"; then
        echo "running"
    else
        echo "stopped"
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# 尝试启动服务
# ─────────────────────────────────────────────────────────────────────────
service_try_start() {
    local service="$1"
    
    if service_is_running "$service"; then
        return 0
    fi
    
    service_start "$service"
}

# ─────────────────────────────────────────────────────────────────────────
# 尝试停止服务
# ─────────────────────────────────────────────────────────────────────────
service_try_stop() {
    local service="$1"
    
    if ! service_is_running "$service"; then
        return 0
    fi
    
    service_stop "$service"
}

# ─────────────────────────────────────────────────────────────────────────
# 等待服务状态变化
# 用法: service_wait_status SERVICE TARGET_STATUS [TIMEOUT]
# TARGET_STATUS: "running" 或 "stopped"
# ─────────────────────────────────────────────────────────────────────────
service_wait_status() {
    local service="$1"
    local target="$2"
    local timeout="${3:-10}"
    local elapsed=0
    
    while [ "$elapsed" -lt "$timeout" ]; do
        local current_status
        current_status="$(service_get_status "$service")"
        
        if [ "$current_status" = "$target" ]; then
            return 0
        fi
        
        sleep 1
        elapsed=$((elapsed + 1))
    done
    
    return 1
}

export -f service_detect_init service_stop service_start service_restart
export -f service_is_running service_get_status service_try_start service_try_stop
export -f service_wait_status
