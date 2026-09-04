#!/bin/sh
# ============================================================================
# Alibaba Cloud Traffic Monitor - VPS One-Click Deploy Script
# 在VPS上执行此脚本即可一键部署
# ============================================================================

set -u

GITHUB_RAW_URL="${1:-https://github.com/candies/alicloud-traffic-monitor/archive/refs/heads/main.zip}"
INSTALL_DIR="/opt/alicloud-traffic-monitor"
WORK_DIR="/tmp/deploy-$$"

echo "================================================"
echo "Alibaba Cloud Traffic Monitor - VPS Deploy"
echo "================================================"
echo ""

# 检查root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ ERROR: This script requires root privileges"
    echo "Run: sudo $0"
    exit 1
fi

# 清理函数
cleanup() {
    rm -rf "$WORK_DIR"
}

trap cleanup EXIT

# 1. 准备环境
echo "📦 Step 1: Preparing environment..."
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 安装依赖
apk update >/dev/null 2>&1
apk add --no-cache curl unzip >/dev/null 2>&1

echo "✅ Environment ready"
echo ""

# 2. 下载项目
echo "⬇️  Step 2: Downloading project from GitHub..."
echo "URL: $GITHUB_RAW_URL"

if ! curl -fsSL "$GITHUB_RAW_URL" -o project.zip; then
    echo "❌ Failed to download. Check:"
    echo "   1. Internet connectivity: ping github.com"
    echo "   2. GitHub accessible: curl -I https://github.com"
    echo "   3. URL is correct: $GITHUB_RAW_URL"
    exit 1
fi

echo "✅ Downloaded successfully"
echo ""

# 3. 解压
echo "📂 Step 3: Extracting..."
unzip -q project.zip

# 查找解压目录
EXTRACTED=$(find . -maxdepth 1 -type d -name "*alicloud*" | head -1)

if [ -z "$EXTRACTED" ]; then
    echo "❌ Failed to find extracted directory"
    exit 1
fi

echo "✅ Extracted: $EXTRACTED"
echo ""

# 4. 安装
echo "⚙️  Step 4: Installing..."
rm -rf "$INSTALL_DIR" 2>/dev/null || true
mkdir -p "$(dirname "$INSTALL_DIR")"
mv "$EXTRACTED" "$INSTALL_DIR"

cd "$INSTALL_DIR"
chmod +x install.sh

if ! ./install.sh install; then
    echo "❌ Installation failed"
    exit 1
fi

echo ""
echo "================================================"
echo "✅ Installation Complete!"
echo "================================================"
echo ""
echo "Quick commands:"
echo ""
echo "  查看状态:"
echo "    alicloud-traffic-monitor status"
echo ""
echo "  测试通知:"
echo "    alicloud-traffic-monitor test"
echo ""
echo "  查看日志:"
echo "    tail -f /var/lib/alicloud-traffic-monitor/traffic.log"
echo ""
echo "  管理服务:"
echo "    rc-service alicloud-traffic-monitor {start|stop|restart|status}"
echo ""
echo "Documentation: $INSTALL_DIR/docs/"
echo ""
