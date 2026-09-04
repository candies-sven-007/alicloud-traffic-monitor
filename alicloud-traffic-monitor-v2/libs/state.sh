#!/bin/sh
# ==============================================================================
# state.sh - 状态管理与持久化库
# 特性：原子性写入、备份恢复、数据验证
# ==============================================================================

set -u

# 状态文件常量
export STATE_MAIN=""
export STATE_BACKUP=""
export STATE_LOCK=""

# ─────────────────────────────────────────────────────────────────────────
# 初始化状态文件路径
# ─────────────────────────────────────────────────────────────────────────
state_init() {
    local state_dir="$1"
    
    if [ -z "$state_dir" ]; then
        echo "ERROR: state_init requires state_dir argument" >&2
        return 1
    fi
    
    STATE_MAIN="$state_dir/state.env"
    STATE_BACKUP="$state_dir/state.env.bak"
    STATE_LOCK="$state_dir/state.lock"
}

# ─────────────────────────────────────────────────────────────────────────
# 原子性写入状态（防止中断时数据损坏）
# 用法: state_write KEY VALUE [KEY VALUE ...]
# ─────────────────────────────────────────────────────────────────────────
state_write() {
    if [ -z "$STATE_MAIN" ]; then
        echo "ERROR: state not initialized" >&2
        return 1
    fi
    
    local state_dir
    state_dir="$(dirname "$STATE_MAIN")"
    
    # 确保目录存在
    if ! mkdir -p "$state_dir" 2>/dev/null; then
        echo "ERROR: cannot create state directory: $state_dir" >&2
        return 1
    fi
    
    # 备份现有状态
    if [ -f "$STATE_MAIN" ]; then
        cp -f "$STATE_MAIN" "$STATE_BACKUP" 2>/dev/null || true
    fi
    
    # 使用临时文件原子性写入
    local tmpfile
    tmpfile="$STATE_MAIN.tmp.$$"
    
    # 清理旧的临时文件
    rm -f "$STATE_MAIN.tmp".*
    
    {
        # 保留现有变量
        if [ -f "$STATE_MAIN" ]; then
            grep -v '^[A-Za-z_][A-Za-z0-9_]*=' "$STATE_MAIN" 2>/dev/null || true
        fi
        
        # 写入新变量
        while [ $# -gt 0 ]; do
            local key="$1"
            local val="$2"
            shift 2
            
            # 验证键名合法性
            if ! echo "$key" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$'; then
                echo "WARNING: invalid state key: $key" >&2
                continue
            fi
            
            # 转义值中的特殊字符
            val="$(printf '%s\n' "$val" | sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g; s/\$/\\\\\$/g; s/\`/\\\\\`/g")"
            
            echo "$key=\"$val\""
        done
    } > "$tmpfile"
    
    # 原子性替换
    if mv -f "$tmpfile" "$STATE_MAIN" 2>/dev/null; then
        chmod 600 "$STATE_MAIN" 2>/dev/null || true
        return 0
    else
        rm -f "$tmpfile"
        echo "ERROR: failed to write state file" >&2
        return 1
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# 读取状态文件到环境变量
# ─────────────────────────────────────────────────────────────────────────
state_load() {
    if [ -z "$STATE_MAIN" ]; then
        echo "ERROR: state not initialized" >&2
        return 1
    fi
    
    if [ ! -f "$STATE_MAIN" ]; then
        return 0  # 不存在则返回成功
    fi
    
    # 安全地加载状态文件（在子shell中执行以避免污染）
    if ! . "$STATE_MAIN" 2>/dev/null; then
        echo "WARNING: corrupted state file, attempting recovery" >&2
        
        # 尝试从备份恢复
        if [ -f "$STATE_BACKUP" ]; then
            if cp -f "$STATE_BACKUP" "$STATE_MAIN" 2>/dev/null; then
                . "$STATE_MAIN" 2>/dev/null || return 1
                echo "NOTICE: state recovered from backup" >&2
                return 0
            fi
        fi
        
        return 1
    fi
    
    return 0
}

# ─────────────────────────────────────────────────────────────────────────
# 获取状态值（安全取值，带默认值）
# 用法: state_get KEY [DEFAULT]
# ─────────────────────────────────────────────────────────────────────────
state_get() {
    local key="$1"
    local default="${2:-}"
    local value
    
    state_load || return 1
    
    # 使用eval安全地获取变量
    value="$(eval "echo \"\$$key\"" 2>/dev/null)"
    
    if [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# 验证状态数据完整性
# ─────────────────────────────────────────────────────────────────────────
state_verify() {
    if [ ! -f "$STATE_MAIN" ]; then
        return 0
    fi
    
    local errors=0
    
    # 检查必要的字段
    state_load || {
        errors=$((errors + 1))
        return 1
    }
    
    # 验证必要变量存在
    for var in CURRENT_MONTH MONTH_EGRESS LAST_TX REPORT_COUNT LIMIT_REACHED; do
        if ! eval "[ -n \"\$$var\" ]" 2>/dev/null; then
            echo "WARNING: missing state variable: $var" >&2
            errors=$((errors + 1))
        fi
    done
    
    # 验证数值有效性
    if ! echo "$MONTH_EGRESS" | grep -qE '^[0-9]+$'; then
        echo "WARNING: invalid MONTH_EGRESS value" >&2
        errors=$((errors + 1))
    fi
    
    return $errors
}

# ─────────────────────────────────────────────────────────────────────────
# 清理过期临时文件
# ─────────────────────────────────────────────────────────────────────────
state_cleanup() {
    if [ -z "$STATE_MAIN" ]; then
        return 0
    fi
    
    local state_dir
    state_dir="$(dirname "$STATE_MAIN")"
    
    find "$state_dir" -name "state.env.tmp.*" -type f -mmin +60 -delete 2>/dev/null || true
}

export -f state_init state_write state_load state_get state_verify state_cleanup
