# Configuration Guide - Alibaba Cloud Traffic Monitor v2.0

Configuration file: `/etc/alicloud-traffic-monitor.conf`

## Parameters

### INTERFACE (必需)

The network interface to monitor for outbound traffic.

**Format:** `INTERFACE="eth0"`

**Common values:**
- `eth0` - Primary Ethernet interface (most common on Alibaba Cloud)
- `eth1` - Secondary interface
- `veth*` - Virtual Ethernet

**How to find your interface:**
```bash
# List all interfaces
ip link show

# Or use ifconfig
ifconfig

# Check which has internet connectivity
ip route show
```

**Example:**
```bash
INTERFACE="eth0"
```

---

### SINGBOX_SERVICE (必需)

The OpenRC service name to control. This service will be stopped when traffic limit is reached.

**Format:** `SINGBOX_SERVICE="sing-box"`

**Verify the service exists:**
```bash
rc-service sing-box status
```

**If using different service:**
```bash
# Find all services
rc-service -l | grep -i box

# Or check directly
ls -la /etc/init.d/ | grep -i sing
```

**Example:**
```bash
SINGBOX_SERVICE="sing-box"
```

---

### INTERVAL (可选)

How frequently to check traffic in seconds.

**Format:** `INTERVAL="1"`

**Valid range:** 1-60 seconds

**Performance vs. Accuracy:**
| Value | Behavior | CPU Usage |
|-------|----------|-----------|
| 1 | Most responsive, catch limit immediately | Higher |
| 5 | Good balance | Normal |
| 10 | Lower CPU, slight delay in notifications | Lower |
| 60 | Minimal checking | Minimal |

**Recommendation:**
- Busy servers: `INTERVAL="5"`
- Normal servers: `INTERVAL="1"` (default)
- Low resource VPS: `INTERVAL="10"`

**Example:**
```bash
INTERVAL="1"
```

---

### TG_BOT_TOKEN (可选)

Telegram bot authentication token for notifications.

**Format:** `TG_BOT_TOKEN="123456789:ABCDefGHIjklMNOpqrsTUVwxyz"`

**How to get:**
1. Open https://t.me/BotFather
2. Send `/newbot`
3. Follow prompts to create new bot
4. Save the token provided

**Token format:**
- `123456789` - Numeric prefix (9+ digits)
- `ABCDefGHIjklMNOpqrsTUVwxyz` - Alphanumeric suffix (26+ chars)

**Note:**
- Must set together with `TG_CHAT_ID`
- Leave empty to disable Telegram notifications

**Example:**
```bash
TG_BOT_TOKEN="1234567890:ABCdefghIjklmnoPQRstuvWxyz1234567"
```

---

### TG_CHAT_ID (可选)

Your Telegram chat ID for receiving notifications.

**Format:** `TG_CHAT_ID="987654321"`

**How to get:**
- Send message to https://t.me/userinfobot (it will reply with your ID)
- Or use https://t.me/IDBot

**Format variations:**
- Personal chat: Positive integer (e.g., `123456789`)
- Group chat: Negative integer (e.g., `-123456789`)

**Verify it works:**
```bash
alicloud-traffic-monitor test
```

**Note:**
- Must set together with `TG_BOT_TOKEN`
- Leave empty to disable Telegram notifications

**Example:**
```bash
TG_CHAT_ID="987654321"
```

---

## Example Configurations

### Minimal (No Notifications)
```bash
INTERFACE="eth0"
SINGBOX_SERVICE="sing-box"
INTERVAL="1"
TG_BOT_TOKEN=""
TG_CHAT_ID=""
```

### Standard (With Telegram)
```bash
INTERFACE="eth0"
SINGBOX_SERVICE="sing-box"
INTERVAL="1"
TG_BOT_TOKEN="1234567890:ABCDefGhijklMnopQRstUVwxyz1234567"
TG_CHAT_ID="987654321"
```

### Low-Resource VPS
```bash
INTERFACE="eth0"
SINGBOX_SERVICE="sing-box"
INTERVAL="10"
TG_BOT_TOKEN=""
TG_CHAT_ID=""
```

### Multiple VPS (Different Interfaces)
```bash
INTERFACE="eth1"
SINGBOX_SERVICE="sing-box"
INTERVAL="1"
TG_BOT_TOKEN="1111111111:AAA..."
TG_CHAT_ID="111111111"
```

---

## Configuration Validation

### Check Configuration Syntax
```bash
alicloud-traffic-monitor diagnose
```

### Test Telegram Setup
```bash
alicloud-traffic-monitor test
```

Expected output:
```
✅ Telegram test message sent successfully
```

### View Applied Configuration
Check the logs to see what configuration was loaded:
```bash
grep -i "configuration\|INTERFACE\|SERVICE" /var/lib/alicloud-traffic-monitor/traffic.log
```

---

## Advanced: System Constants

These are built-in constants that cannot be changed:

| Constant | Value | Description |
|----------|-------|-------------|
| REPORT_STEP | 10 GB | Traffic step for notifications |
| LIMIT | 200 GB | Hard limit before service stops |
| BYTE_PER_GB | 1,000,000,000 | Bytes per GB |

**Notification stages:**
- 10, 20, 30, 40, 50, 60, 70, 80, 90 GB: Regular notifications
- 100, 110, 120, 130, 140, 150, 160 GB: Regular notifications
- 170 GB (Stage 17): Warning - 30GB remaining
- 180 GB (Stage 18): Warning - 20GB remaining
- 190 GB (Stage 19): Warning - 10GB remaining
- 200 GB (Stage 20): **LIMIT REACHED** - Service stopped

---

## Editing Configuration

### Using Text Editor
```bash
sudo vi /etc/alicloud-traffic-monitor.conf
# Make changes and save

sudo rc-service alicloud-traffic-monitor restart
```

### Using sed (Non-interactive)
```bash
# Change interface
sudo sed -i 's/^INTERFACE=.*/INTERFACE="eth1"/' /etc/alicloud-traffic-monitor.conf

# Change interval
sudo sed -i 's/^INTERVAL=.*/INTERVAL="5"/' /etc/alicloud-traffic-monitor.conf

# Restart service
sudo rc-service alicloud-traffic-monitor restart
```

### Verify Changes
```bash
cat /etc/alicloud-traffic-monitor.conf
```

---

## Security Notes

### File Permissions
```bash
# Config file should only be readable by root
ls -l /etc/alicloud-traffic-monitor.conf
# Should show: -rw------- root root
```

### Backing Up Configuration
```bash
# Create backup
sudo cp /etc/alicloud-traffic-monitor.conf \
        /etc/alicloud-traffic-monitor.conf.backup

# Restore from backup
sudo cp /etc/alicloud-traffic-monitor.conf.backup \
        /etc/alicloud-traffic-monitor.conf
```

### Telegram Token Security
- Never commit token to public repositories
- Keep backup in secure location
- Rotate token in BotFather if compromised

---

## Troubleshooting Configuration

### "Configuration validation failed"

**Check:**
```bash
# Verify file syntax
bash -n /etc/alicloud-traffic-monitor.conf

# Check permissions
ls -l /etc/alicloud-traffic-monitor.conf

# View actual content
cat /etc/alicloud-traffic-monitor.conf
```

### "Interface not found"

**Solution:**
```bash
# List available interfaces
ip link show

# Update config with correct interface
INTERFACE="<interface-name>"
```

### "Service name not found"

**Solution:**
```bash
# List OpenRC services
rc-service -l

# Update config with correct service name
SINGBOX_SERVICE="<service-name>"
```

### Telegram not working after config change

**Solution:**
```bash
# Test Telegram
alicloud-traffic-monitor test

# Verify credentials in config
grep TG_ /etc/alicloud-traffic-monitor.conf
```

---

## Migration Guide

### From v1.0 to v2.0

Configuration format remains compatible! Your old config will work:

```bash
# Backup old config
cp /etc/alicloud-traffic-monitor.conf \
   /etc/alicloud-traffic-monitor.conf.v1.backup

# Install v2.0 (keeps your config)
sudo ./install.sh install

# Verify everything still works
alicloud-traffic-monitor status
```

---

**Next:** See [Troubleshooting Guide](troubleshooting.md) for common issues.
