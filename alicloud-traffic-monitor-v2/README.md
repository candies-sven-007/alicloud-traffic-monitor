# Alibaba Cloud Traffic Monitor v2.0

> **Redesigned for reliability and maintainability**

[![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)](.)
[![Platform](https://img.shields.io/badge/platform-Alpine%20Linux-brightgreen)](https://alpinelinux.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Advanced Alibaba Cloud ECS outbound traffic monitor with `sing-box` circuit breaker protection for Alpine Linux + OpenRC.

**Major Improvements in v2.0:**
- ✅ Atomic state management (防止状态损坏)
- ✅ Comprehensive error handling (完善的错误处理)
- ✅ Structured logging with rotation (结构化日志)
- ✅ Modular architecture (模块化设计)
- ✅ Better configuration validation (配置验证)
- ✅ System resilience & recovery (系统恢复能力)

---

## 🌟 Core Features

### Billing Protection
- **Egress-only tracking**: Only counts `eth0` TX (outbound), never RX (inbound)
- **Atomic state storage**: No data corruption on unexpected shutdown
- **Circuit breaker**: Automatically stops `sing-box` when 200GB limit is reached
- **Persistent lock**: Service remains stopped even after VPS reboot

### Smart Notifications
- **Tiered alerts**: Step notifications at 10GB intervals (1-19) + limit reached (20)
- **Structured messages**: HTML-formatted Telegram notifications with metrics
- **Smart warnings**:
  - Stage 17 (170GB): ⚠️ Last 30GB remaining
  - Stage 18 (180GB): 🟠 Last 20GB remaining  
  - Stage 19 (190GB): 🚨 Last 10GB remaining
  - Stage 20 (200GB): 🛑 Limit reached, service stopped

### Automatic Monthly Recovery
- **Auto-reset**: Every month on 1st at 00:00, traffic is zeroed and service recovered
- **Stateless**: Complete state reset without manual intervention
- **Notification**: Sends new-cycle notification to confirm recovery

### System Resilience
- **Counter reset detection**: Handles system reboot/network card reset gracefully
- **Overflow protection**: 64-bit integer overflow guards
- **Error recovery**: Automatic error counting and failsafe mechanisms
- **Backup states**: Automatic state file backups for corruption recovery

---

## 📋 Architecture

### Modular Design

```
libs/
├── state.sh       - Atomic state management & persistence
├── logger.sh      - Structured logging with rotation
├── config.sh      - Configuration validation & defaults
├── network.sh     - Network monitoring & calculations
├── notify.sh      - Telegram notifications with retries
└── service.sh     - OpenRC/systemd service control

bin/
└── alicloud-traffic-monitor  - Main monitoring daemon
```

### Error Handling Strategy
- **Graceful degradation**: Non-critical errors don't stop monitoring
- **Retry mechanism**: Telegram notifications retry 3 times with 2s delay
- **Threshold-based restart**: Service restarts after 10 consecutive errors
- **State recovery**: Automatic fallback to backup state if corruption detected

---

## ⚙️ Configuration

### Basic Setup

```bash
sudo ./install.sh install
```

Interactive wizard will prompt for:
- Network interface (default: eth0)
- Service name (default: sing-box)
- Telegram Bot Token (optional)
- Telegram Chat ID (optional)

### Configuration File

Location: `/etc/alicloud-traffic-monitor.conf`

```bash
INTERFACE="eth0"                    # Network interface to monitor
SINGBOX_SERVICE="sing-box"          # Service to control
INTERVAL="1"                        # Check interval (1-60s)
TG_BOT_TOKEN=""                     # Telegram bot token
TG_CHAT_ID=""                       # Telegram chat ID
```

### Get Telegram Credentials

1. **Bot Token**: Create bot at https://t.me/BotFather
2. **Chat ID**: Get your ID from https://t.me/userinfobot

---

## 🚀 Quick Start

### Installation (Alpine Linux)

```bash
# Clone or extract
cd alicloud-traffic-monitor-v2

# Install (requires root)
sudo chmod +x install.sh
sudo ./install.sh install

# Follow interactive setup wizard
```

### Commands

```bash
# View current status
alicloud-traffic-monitor status

# Send test notification
alicloud-traffic-monitor test

# Run diagnostics
alicloud-traffic-monitor diagnose

# View logs
tail -f /var/lib/alicloud-traffic-monitor/traffic.log

# Manage service
rc-service alicloud-traffic-monitor {start|stop|restart|status}
```

### Service Management

```bash
# Check service status
rc-service alicloud-traffic-monitor status

# View real-time logs
tail -f /var/lib/alicloud-traffic-monitor/traffic.log

# Show statistics (every 10GB)
alicloud-traffic-monitor status

# Test Telegram
alicloud-traffic-monitor test
```

---

## 📊 Monitoring Output

### Status Command
```
=== alicloud-traffic-monitor Status ===

Version             : 2.0.0
Status              : running

Billing Cycle       : 2026-09
Egress Used         : 45.23 GB / 200 GB
Usage Rate          : 22.6 %
Remaining Quota     : 154.77 GB

Notification Count  : 5
Circuit Breaker     : 🟢 OK

Last Updated        : 2026-09-04 12:34:56
```

### Telegram Notifications

**Tier 5 (50GB):**
```
📊 【Alibaba Cloud Egress Protection】Traffic Report
第 5 次提示
📤 Monthly egress: 50.00 GB / 200 GB
📈 Usage rate: 25.0%
📉 Remaining quota: 150.00 GB
```

**Tier 17 (170GB - Warning):**
```
⚠️ 【Alibaba Cloud Egress Protection】Traffic Warning
🟡 Entering final 30 GB warning stage
```

**Tier 20 (200GB - Limit):**
```
🛑 【Alibaba Cloud Egress Protection】200 GB Limit Reached
🚫 sing-box has been automatically stopped
🔒 Circuit breaker locked for remaining month
```

---

## 🔧 Troubleshooting

### Check Network Interface

```bash
alicloud-traffic-monitor diagnose
```

### Verify Telegram Configuration

```bash
alicloud-traffic-monitor test
```

### Inspect Logs

```bash
# Last 50 lines
tail -50 /var/lib/alicloud-traffic-monitor/traffic.log

# Real-time follow
tail -f /var/lib/alicloud-traffic-monitor/traffic.log

# Search for errors
grep ERROR /var/lib/alicloud-traffic-monitor/traffic.log
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Service won't start | Check `/etc/alicloud-traffic-monitor.conf` exists and is readable |
| Telegram not working | Verify Bot Token and Chat ID format |
| Service keeps restarting | Check logs for initialization errors |
| High CPU usage | Increase `INTERVAL` in config (e.g., 5-10s) |
| Cannot read interface | Verify interface name: `ip link show` |

---

## 📝 Logs

### Log Location
- Path: `/var/lib/alicloud-traffic-monitor/traffic.log`
- Format: `[YYYY-MM-DD HH:MM:SS] [LEVEL] message`
- Auto-rotation: When exceeds 10MB

### Log Levels
- `DEBUG`: Detailed diagnostic information
- `INFO`: General operational information  
- `WARN`: Warning conditions that may need attention
- `ERROR`: Error conditions
- `EVENT`: Important state changes (NEW_MONTH, LIMIT_REACHED, etc.)

---

## 🛠 Uninstallation

```bash
sudo ./install.sh uninstall
```

Prompts whether to keep or delete configuration and statistics.

---

## 📖 Documentation

- [Configuration Guide](docs/configuration.md)
- [Installation Guide](docs/installation.md)
- [Troubleshooting](docs/troubleshooting.md)

---

## 🔐 Security

### File Permissions
- Binary: 755 (`-rwxr-xr-x`)
- Config: 600 (`-rw-------`) - readable only by root
- State dir: 700 (`drwx------`) - accessible only by root
- Logs: 644 (`-rw-r--r--`)

### Secrets Handling
- Telegram tokens stored only in config file with restricted permissions
- No secrets logged to output
- No API responses containing sensitive data stored

---

## 📄 License

MIT License - See [LICENSE](LICENSE) file for details

---

## 🤝 Support

### Reporting Issues
Please include:
1. Full output of `alicloud-traffic-monitor diagnose`
2. Relevant log lines (redact sensitive info)
3. Configuration (redact tokens)
4. OS/Alpine version

### Contributing
Pull requests welcome for bug fixes and improvements.

---

## 🗓 Version History

### v2.0.0 (2026-09-04)
**Major Redesign**
- Modular architecture with separate library files
- Atomic state management preventing data corruption
- Comprehensive error handling and recovery
- Structured logging with automatic rotation
- Enhanced configuration validation
- Better service control and diagnostics

### v1.0.0 (2026-09-03)
**Initial Release**
- Basic traffic monitoring
- Simple state management
- Telegram notifications
- OpenRC service integration

---

**Made for reliable Alibaba Cloud ECS protection on Alpine Linux**
