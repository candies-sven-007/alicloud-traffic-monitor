# Installation Guide - Alibaba Cloud Traffic Monitor v2.0

## Prerequisites

- Alpine Linux 3.14+ (or compatible)
- Root access
- Internet connection (for dependency installation)
- sing-box service installed and working
- (Optional) Telegram bot for notifications

## Step 1: Prepare System

### Update Alpine Packages
```bash
apk update
apk add --no-cache ca-certificates curl
```

## Step 2: Installation

### Option A: Automated Installation (Recommended)

```bash
# Navigate to project directory
cd alicloud-traffic-monitor-v2

# Make install script executable
chmod +x install.sh

# Run installation with root privileges
sudo ./install.sh install
```

The script will:
1. ✅ Install required dependencies (curl, awk, coreutils, ca-certificates)
2. ✅ Create state directory (`/var/lib/alicloud-traffic-monitor`)
3. ✅ Install main binary to `/usr/local/sbin/alicloud-traffic-monitor`
4. ✅ Install OpenRC service to `/etc/init.d/alicloud-traffic-monitor`
5. ✅ Create configuration file with interactive setup
6. ✅ Register service for auto-start
7. ✅ Test Telegram configuration
8. ✅ Start the service

### Option B: Manual Installation

If you prefer manual setup:

```bash
# Create directories
sudo mkdir -p /var/lib/alicloud-traffic-monitor
sudo mkdir -p /usr/local/sbin
sudo mkdir -p /etc/init.d

# Copy binary
sudo cp bin/alicloud-traffic-monitor /usr/local/sbin/
sudo chmod 755 /usr/local/sbin/alicloud-traffic-monitor

# Copy service file
sudo cp openrc/alicloud-traffic-monitor /etc/init.d/
sudo chmod 755 /etc/init.d/alicloud-traffic-monitor

# Copy config (and customize)
sudo cp config/alicloud-traffic-monitor.conf.example \
          /etc/alicloud-traffic-monitor.conf
sudo chmod 600 /etc/alicloud-traffic-monitor.conf

# Edit config
sudo vi /etc/alicloud-traffic-monitor.conf

# Register service
sudo rc-update add alicloud-traffic-monitor default

# Start service
sudo rc-service alicloud-traffic-monitor start
```

## Step 3: Configuration

### Essential Settings

Edit `/etc/alicloud-traffic-monitor.conf`:

```bash
# The network interface to monitor
INTERFACE="eth0"

# The service to control (sing-box)
SINGBOX_SERVICE="sing-box"

# Check interval in seconds
INTERVAL="1"
```

### (Optional) Telegram Setup

1. Create Telegram bot:
   - Open https://t.me/BotFather
   - Send `/start`
   - Send `/newbot`
   - Follow instructions to get Bot Token

2. Get your Chat ID:
   - Send any message to https://t.me/userinfobot
   - It will reply with your Chat ID (or use @IDBot)

3. Update configuration:
```bash
TG_BOT_TOKEN="123456789:ABCDefGHIjklMNOpqrsTUVwxyz"
TG_CHAT_ID="987654321"
```

## Step 4: Verify Installation

### Check Service Status
```bash
rc-service alicloud-traffic-monitor status
```

Expected output: `* status: started`

### View Current Traffic
```bash
alicloud-traffic-monitor status
```

### Send Test Notification
```bash
alicloud-traffic-monitor test
```

### Check Logs
```bash
tail -f /var/lib/alicloud-traffic-monitor/traffic.log
```

### Run Diagnostics
```bash
alicloud-traffic-monitor diagnose
```

## Step 5: Enable Auto-Start (Optional)

The installation script automatically registers the service. To verify:

```bash
rc-update show | grep alicloud-traffic-monitor
```

Expected output: `alicloud-traffic-monitor | default`

## Troubleshooting

### Service Won't Start

**Symptom:** `rc-service alicloud-traffic-monitor start` fails

**Solution:**
1. Check configuration exists: `test -f /etc/alicloud-traffic-monitor.conf`
2. Verify interface: `ip link show` should show eth0
3. Check logs: `cat /var/lib/alicloud-traffic-monitor/traffic.log`

### Telegram Notifications Not Working

**Symptom:** `alicloud-traffic-monitor test` fails

**Solution:**
1. Verify internet connection: `curl -I https://api.telegram.org`
2. Check Bot Token format (should be: `123456789:ABCDefGHI...`)
3. Verify Chat ID is numeric
4. Ensure config file is readable: `cat /etc/alicloud-traffic-monitor.conf`

### High CPU Usage

**Symptom:** CPU usage above 5%

**Solution:**
- Increase `INTERVAL` in config (e.g., `INTERVAL="5"` or `INTERVAL="10"`)
- Higher values = less frequent checks but higher latency

### Cannot Find Interface

**Symptom:** `ERROR: network interface not found: eth0`

**Solution:**
1. List available interfaces: `ip link show`
2. Update `INTERFACE` in `/etc/alicloud-traffic-monitor.conf`
3. Restart service: `rc-service alicloud-traffic-monitor restart`

## Post-Installation

### First Time Setup Checklist

- [ ] Configuration file created and verified
- [ ] Telegram credentials configured (if using)
- [ ] Test notification sent successfully
- [ ] Service starts automatically after reboot
- [ ] Log file is being written

### Routine Maintenance

**Monthly:**
- Review logs for errors
- Verify notification delivery works
- Check available disk space

**Quarterly:**
- Update Alpine packages: `apk update && apk upgrade`
- Update this tool: `sudo ./install.sh update`
- Test full workflow with test command

## Uninstallation

To completely remove the application:

```bash
cd alicloud-traffic-monitor-v2
sudo ./install.sh uninstall
```

This will:
- Stop the service
- Remove the service file
- Offer to remove configuration and logs

## Support

For issues:
1. Run `alicloud-traffic-monitor diagnose`
2. Check `/var/lib/alicloud-traffic-monitor/traffic.log`
3. Ensure configuration is correct: `cat /etc/alicloud-traffic-monitor.conf`

---

**Next:** Review [Configuration Guide](configuration.md) for advanced options.
