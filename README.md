# alicloud-traffic-monitor

[![Release](https://img.shields.io/github/v/release/candies/alicloud-traffic-monitor?color=blue)](https://github.com/candies/alicloud-traffic-monitor/releases)
[![Platform](https://img.shields.io/badge/platform-Alpine%20Linux-brightgreen)](https://alpinelinux.org/)
[![Init](https://img.shields.io/badge/init-OpenRC-orange)](https://wiki.alpinelinux.org/wiki/OpenRC)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

专为**阿里云 ECS (Alpine Linux + OpenRC)** 打造的高可靠公网出站流量监控与 `sing-box` 熔断保护程序。

---

## 🌟 核心特性

- **严格单向计费防护**：只统计 `eth0` TX（出站流量，即向外发送/客户端下载流量），完全不计入 RX 入站。
- **阶梯 Telegram 通知**：
  - 每累积 10 GB 发送一次结构化报告（从第 1 次至第 20 次）。
  - **170 GB**：第 17 次提示（预警剩余 30 GB）。
  - **180 GB**：第 18 次提示（预警剩余 20 GB）。
  - **190 GB**：第 19 次提示（最后一次预警，剩余 10 GB）。
  - **200 GB**：第 20 次提示（达到额度上限并熔断）。彻底杜绝 200 GB 重复提示或序号跳变。
- **双重熔断与重启防御**：
  - 达到 200 GB 立即执行 `rc-service sing-box stop` 并写入持久化锁定标记。
  - 即使 VPS 意外重启被 OpenRC `default` runlevel 拉起，守护进程也会在 1 秒内检测并强制再次停用。
- **自然月自动复位**：
  - 每月 1 日 00:00 自动清零本月流量、解除锁定、重新拉起 `sing-box` 并发送新周期报告。
- **系统弹性容灾**：
  - 正确处理网卡计数器重置与服务器重启，不丢统计、不产生负数或跳变。
  - 配置与状态完全持久化于 `/var/lib/alicloud-traffic-monitor/`。

---

## ⚠️ 阿里云出站计费与 Linux TX 差异说明

- 本工具直接读取 Linux 内核提供的 `/sys/class/net/eth0/statistics/tx_bytes` 物理网卡计数。
- 阿里云官方账单系统通常存在 **1~3 小时的出账/数据延迟**。
- 内核统计与云厂商计费网关在抓包截断、底层协议头开销上可能存在极微小（<1%）偏差。建议预留足够的安全边际。

---

## 🚀 快速安装

### 1. 一键脚本安装（推荐）

```bash
# 确保已安装 git
apk add --no-cache git

# 克隆仓库
git clone https://github.com/candies/alicloud-traffic-monitor.git
cd alicloud-traffic-monitor

# 赋予权限并安装
chmod +x install.sh
./install.sh install
```

根据终端交互提示输入你的 Telegram `Bot Token` 与 `Chat ID` 即可一键完成环境初始化。

---

## 🛠 管理与运维命令

```bash
# 查看实时出站流量与锁定状态
alicloud-traffic-monitor status

# 发送 Telegram 测试告警
alicloud-traffic-monitor test

# 检查服务与更新状态
./install.sh update

# 实时查看监控运行日志
tail -f /var/lib/alicloud-traffic-monitor/traffic.log

# 彻底卸载
./install.sh uninstall
```

---

## 📖 详细文档

- [完整安装指南](docs/installation.md)
- [配置说明及进阶选项](docs/configuration.md)
- [常见问题与故障排查](docs/troubleshooting.md)

---

## 📄 开源许可证

本项目基于 [MIT License](LICENSE) 协议开源。
