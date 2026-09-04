# 安装与部署指南

本文档介绍如何在 Alpine Linux ECS 实例上部署 `alicloud-traffic-monitor`。

## 准备工作

1. 确保服务器运行 Alpine Linux 并使用 OpenRC 初始化系统。
2. 确保 `sing-box` 已经注册为系统服务（`rc-service sing-box status` 可识别）。
3. 准备好 Telegram Bot Token 及目标 Chat ID。

## 安装步骤

```bash
# 1. 安装基础依赖
apk add --no-cache git

# 2. 克隆仓库
git clone https://github.com/candies/alicloud-traffic-monitor.git
cd alicloud-traffic-monitor

# 3. 执行安装
chmod +x install.sh
./install.sh install
```

脚本将引导输入 Telegram Bot Token 与 Chat ID，自动生成权限为 `600` 的配置文件 `/etc/alicloud-traffic-monitor.conf`，并将服务添加至 OpenRC 的 `default` 运行级别。
