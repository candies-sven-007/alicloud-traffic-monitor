#!/bin/sh
# ==============================================================================
# alicloud-traffic-monitor 安装与运维管理脚本
# ==============================================================================

set -u

APP="alicloud-traffic-monitor"
BIN="/usr/local/sbin/$APP"
INIT="/etc/init.d/$APP"
CONF="/etc/$APP.conf"
STATE_DIR="/var/lib/$APP"
LOG="$STATE_DIR/traffic.log"

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "错误：请使用 root 权限运行此脚本。"
        exit 1
    fi
}

install() {
    check_root
    echo "=== 开始安装 Alibaba Cloud ECS 出站流量保护器 ==="

    apk update
    apk add --no-cache curl awk coreutils ca-certificates git

    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"
    touch "$LOG"

    # 安装二进制执行文件
    if [ -f "alicloud-traffic-monitor.sh" ]; then
        cp alicloud-traffic-monitor.sh "$BIN"
    else
        echo "错误：未在当前目录找到 alicloud-traffic-monitor.sh"
        exit 1
    fi
    chmod 755 "$BIN"

    # 安装 OpenRC 服务脚本
    if [ -f "openrc/alicloud-traffic-monitor" ]; then
        cp openrc/alicloud-traffic-monitor "$INIT"
    else
        echo "错误：未在当前目录找到 openrc/alicloud-traffic-monitor"
        exit 1
    fi
    chmod 755 "$INIT"

    # 配置向导
    if [ ! -f "$CONF" ]; then
        echo ""
        echo "--- 请输入 Telegram 通知配置 ---"
        printf "请输入 TG_BOT_TOKEN: "
        read -r input_token
        printf "请输入 TG_CHAT_ID: "
        read -r input_chat_id

        if [ -z "$input_token" ] || [ -z "$input_chat_id" ]; then
            echo "错误：Token 和 Chat ID 不能为空！"
            exit 1
        fi

        cat > "$CONF" <<EOF
INTERFACE="eth0"
SINGBOX_SERVICE="sing-box"
INTERVAL=1
TG_BOT_TOKEN="$input_token"
TG_CHAT_ID="$input_chat_id"
EOF
        chmod 600 "$CONF"
        echo "配置文件已生成至: $CONF"
    else
        echo "已检测到已有配置文件 $CONF，保留现有配置。"
    fi

    # 注册开机自启
    rc-update add "$APP" default >/dev/null 2>&1 || true

    echo ""
    echo "正在测试 Telegram 通知通道..."
    "$BIN" test || true

    # 启动/重启服务
    rc-service "$APP" restart >/dev/null 2>&1 || rc-service "$APP" start

    echo ""
    echo "✅ 安装完成！"
    echo "- 服务状态 : rc-service $APP status"
    echo "- 流量查看 : $BIN status"
    echo "- 实时日志 : tail -f $LOG"
}

update() {
    check_root
    echo "=== 开始拉取最新代码并热更新 ==="
    if [ -d ".git" ]; then
        git fetch --all
        git reset --hard origin/main
    else
        echo "当前目录非 Git 仓库，跳过 git pull。"
    fi

    if [ -f "alicloud-traffic-monitor.sh" ]; then
        cp alicloud-traffic-monitor.sh "$BIN"
        chmod 755 "$BIN"
    fi

    if [ -f "openrc/alicloud-traffic-monitor" ]; then
        cp openrc/alicloud-traffic-monitor "$INIT"
        chmod 755 "$INIT"
    fi

    rc-service "$APP" restart
    echo "✅ 热更新成功！当前运行版本已重载。"
}

uninstall() {
    check_root
    echo "=== 正在卸载 Alibaba Cloud ECS 出站流量保护器 ==="
    rc-service "$APP" stop >/dev/null 2>&1 || true
    rc-update del "$APP" default >/dev/null 2>&1 || true

    rm -f "$BIN"
    rm -f "$INIT"

    echo "程序及 OpenRC 服务已移除。"
    printf "是否同时删除配置文件与历史统计数据 ($CONF, $STATE_DIR)? [y/N]: "
    read -r clean_data
    case "$clean_data" in
        [yY][eE][sS]|[yY])
            rm -f "$CONF"
            rm -rf "$STATE_DIR"
            echo "配置与历史数据已全部清除。"
            ;;
        *)
            echo "配置与历史数据仍保留在 $CONF 与 $STATE_DIR 中。"
            ;;
    esac
    echo "✅ 卸载完成。"
}

case "${1:-}" in
    install)
        install
        ;;
    update)
        update
        ;;
    status)
        "$BIN" status
        ;;
    test)
        "$BIN" test
        ;;
    uninstall)
        uninstall
        ;;
    *)
        echo "用法: $0 {install|update|status|test|uninstall}"
        exit 1
        ;;
esac
