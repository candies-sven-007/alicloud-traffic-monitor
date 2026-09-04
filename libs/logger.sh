#!/bin/sh
# ==============================================================================
# logger.sh - 日志管理库
# 特性：日志轮转、级别控制、结构化输出
# ==============================================================================

set -u

export LOG_FILE=""
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
export LOG_MAX_SIZE=$((10 * 1024 * 1024))  # 10MB

# 日志级别定义
readonly LOG_LEVEL_DEBUG=0
readonly LOG_LEVEL_INFO=1
readonly LOG_LEVEL_WARN=2
readonly LOG_LEVEL_ERROR=3

# ─────────────────────────────────────────────────────────────────────────
# 初始化日志系统
# ─────────────────────────────────────────────────────────────────────────
log_init() {
    local logfile="$1"
    
    if [ -z "$logfile" ]; then
        echo "ERROR: log_init requires logfile argument" >&2
        return 1
    fi
    
    LOG_FILE="$logfile"
    
    # 创建日志目录
    local logdir
    logdir="$(dirname "$LOG_FILE")"
    
    if ! mkdir -p "$logdir" 2>/dev/null; then
        echo "ERROR: cannot create log directory: $logdir" >&2
        return 1
    fi
    
    # 创建日志文件
    touch "$LOG_FILE" 2>/dev/null || {
        echo "ERROR: cannot create log file: $LOG_FILE" >&2
        return 1
    }
    
    chmod 644 "$LOG_FILE" 2>/dev/null || true
    
    return 0
}

# ─────────────────────────────────────────────────────────────────────────
# 内部日志函数
# ─────────────────────────────────────────────────────────────────────────
_log() {
    local level="$1"
    local message="$2"
    local timestamp
    
    if [ -z "$LOG_FILE" ]; then
        return 1
    fi
    
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    # 写入日志文件（使用>>避免覆盖）
    {
        printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message"
    } >> "$LOG_FILE" 2>/dev/null || true
    
    # 同时输出到stderr（用于调试）
    if [ "${3:-0}" -eq 1 ]; then
        printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >&2
    fi
    
    # 检查日志轮转
    log_rotate
}

# ─────────────────────────────────────────────────────────────────────────
# 日志级别检查
# ─────────────────────────────────────────────────────────────────────────
_get_log_level_num() {
    case "$1" in
        DEBUG) echo "$LOG_LEVEL_DEBUG" ;;
        INFO)  echo "$LOG_LEVEL_INFO" ;;
        WARN)  echo "$LOG_LEVEL_WARN" ;;
        ERROR) echo "$LOG_LEVEL_ERROR" ;;
        *)     echo "$LOG_LEVEL_INFO" ;;
    esac
}

_should_log() {
    local msg_level="$1"
    local configured_level
    
    msg_level="$(_get_log_level_num "$msg_level")"
    configured_level="$(_get_log_level_num "$LOG_LEVEL")"
    
    [ "$msg_level" -ge "$configured_level" ]
}

# ─────────────────────────────────────────────────────────────────────────
# 公共日志函数
# ─────────────────────────────────────────────────────────────────────────
log_debug() {
    _should_log "DEBUG" && _log "DEBUG" "$*" 0
}

log_info() {
    _should_log "INFO" && _log "INFO" "$*" 0
}

log_warn() {
    _should_log "WARN" && _log "WARN" "$*" 1
}

log_error() {
    _should_log "ERROR" && _log "ERROR" "$*" 1
}

# ─────────────────────────────────────────────────────────────────────────
# 结构化日志输出（用于重要事件）
# ─────────────────────────────────────────────────────────────────────────
log_event() {
    local event_type="$1"
    shift
    
    local message="EVENT[${event_type}]: $*"
    _log "EVENT" "$message" 1
}

# ─────────────────────────────────────────────────────────────────────────
# 日志轮转（按大小）
# ─────────────────────────────────────────────────────────────────────────
log_rotate() {
    if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
        return 0
    fi
    
    local current_size
    current_size="$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)"
    
    if [ "$current_size" -gt "$LOG_MAX_SIZE" ]; then
        local timestamp
        timestamp="$(date '+%Y%m%d_%H%M%S')"
        
        local archive="${LOG_FILE}.${timestamp}.gz"
        
        if gzip -c "$LOG_FILE" > "$archive" 2>/dev/null; then
            > "$LOG_FILE"  # 清空原日志文件
            chmod 644 "$archive" 2>/dev/null || true
            
            # 只保留最近 7 个归档
            find "$(dirname "$LOG_FILE")" -name "$(basename "$LOG_FILE").*.gz" -type f -mtime +7 -delete 2>/dev/null || true
        fi
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# 显示日志文件
# ─────────────────────────────────────────────────────────────────────────
log_tail() {
    local lines="${1:-50}"
    
    if [ -z "$LOG_FILE" ] || [ ! -f "$LOG_FILE" ]; then
        echo "No log file found" >&2
        return 1
    fi
    
    tail -n "$lines" "$LOG_FILE"
}

export -f log_init log_debug log_info log_warn log_error log_event log_rotate log_tail
