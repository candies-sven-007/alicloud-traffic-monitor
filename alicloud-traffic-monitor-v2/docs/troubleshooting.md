# Troubleshooting Guide - Alibaba Cloud Traffic Monitor v2.0

## Quick Diagnostics

Run the built-in diagnostic tool:
```bash
alicloud-traffic-monitor diagnose
```

This checks:
- ✅ Network interface availability
- ✅ TX bytes readable
- ✅ Service status
- ✅ Configuration file
- ✅ State file integrity

## Common Issues

### Service Won't Start

**Symptom:**
```
* ERROR: service alicloud-traffic-monitor does not exist
```

**Check:**
```bash
rc-service alicloud-traffic-monitor status
```

**Solutions:**

1. **Verify installation:**
   ```bash
   ls -l /etc/init.d/alicloud-traffic-monitor
   ls -l /usr/local/sbin/alicloud-traffic-monitor
   ```

2. **Check configuration exists:**
   ```bash
   cat /etc/alicloud-traffic-monitor.conf
   ```

3. **Reinstall service:**
   ```bash
   sudo cp openrc/alicloud-traffic-monitor /etc/init.d/
   sudo chmod 755 /etc/init.d/alicloud-traffic-monitor
   sudo rc-service alicloud-traffic-monitor start
   ```

4. **View detailed errors:**
   ```bash
   /usr/local/sbin/alicloud-traffic-monitor run
   # This will show errors directly instead of daemonizing
   ```

---

### Service Keeps Restarting

**Symptom:**
```
respawn: stopped alicloud-traffic-monitor
respawn: restarting alicloud-traffic-monitor after 5 seconds
```

**Causes:**

1. **Configuration error:**
   ```bash
   alicloud-traffic-monitor diagnose
   ```

2. **Bad interface:**
   ```bash
   # Verify interface exists
   ip link show eth0
   
   # List available interfaces
   ip link show
   ```

3. **Missing dependencies:**
   ```bash
   which curl
   which awk
   which cat
   ```

**Solutions:**

1. Fix configuration:
   ```bash
   sudo vi /etc/alicloud-traffic-monitor.conf
   sudo rc-service alicloud-traffic-monitor restart
   ```

2. Install missing commands:
   ```bash
   apk add --no-cache curl awk coreutils ca-certificates
   ```

3. Check logs for details:
   ```bash
   tail -50 /var/lib/alicloud-traffic-monitor/traffic.log
   grep ERROR /var/lib/alicloud-traffic-monitor/traffic.log
   ```

---

### No Traffic Detected

**Symptom:**
```
alicloud-traffic-monitor status
# Shows 0.00 GB / 200 GB
```

**Causes:**

1. **Wrong interface:**
   - Data is flowing on different interface
   - eth0 might not be the WAN interface

2. **Service not connected:**
   - sing-box service not running
   - No traffic through monitored interface

**Solutions:**

1. **Check which interface has traffic:**
   ```bash
   # Run while traffic is flowing
   watch -n 1 'cat /sys/class/net/*/statistics/tx_bytes'
   
   # Or use iftop if installed
   iftop -i eth0
   ```

2. **Check if sing-box is using this interface:**
   ```bash
   rc-service sing-box status
   
   # Check sing-box listening
   netstat -tlnp | grep sing
   ```

3. **Update interface if needed:**
   ```bash
   sudo sed -i 's/^INTERFACE=.*/INTERFACE="eth1"/' /etc/alicloud-traffic-monitor.conf
   sudo rc-service alicloud-traffic-monitor restart
   ```

---

### Telegram Notifications Not Working

**Symptom:**
```
alicloud-traffic-monitor test
# ❌ Failed to send Telegram test message
```

**Check Telegram:**

1. **Test internet connectivity:**
   ```bash
   curl -I https://api.telegram.org
   # Should return HTTP 200
   ```

2. **Test Telegram API directly:**
   ```bash
   # Replace with your token and chat ID
   curl -X POST \
     "https://api.telegram.org/bot<YOUR_TOKEN>/sendMessage" \
     -d "chat_id=<YOUR_CHAT_ID>" \
     -d "text=Test"
   ```

3. **Verify token format:**
   ```bash
   grep TG_BOT_TOKEN /etc/alicloud-traffic-monitor.conf
   # Should show: TG_BOT_TOKEN="123456789:ABCDefGhijklMnopQRstUVwxyz"
   ```

4. **Verify chat ID format:**
   ```bash
   grep TG_CHAT_ID /etc/alicloud-traffic-monitor.conf
   # Should show numeric value, e.g., TG_CHAT_ID="987654321"
   ```

**Common Problems:**

| Problem | Solution |
|---------|----------|
| `Bad token` error | Check token format with BotFather |
| `Chat not found` error | Verify chat ID is correct (use @IDBot to check) |
| Timeout (curl slow) | Check network connectivity |
| `unauthorized` error | Token might be expired, generate new one |
| Connection refused | Firewall blocking outbound HTTPS (port 443) |

**Solutions:**

1. **Regenerate Bot Token:**
   - Go to https://t.me/BotFather
   - Send `/mybots`
   - Select your bot
   - Send `/revoke`
   - Send `/newbot` to get new token

2. **Verify Chat ID:**
   - Send any message to https://t.me/userinfobot
   - It will reply with your ID

3. **Update configuration:**
   ```bash
   sudo vi /etc/alicloud-traffic-monitor.conf
   # Update TG_BOT_TOKEN and TG_CHAT_ID
   
   sudo rc-service alicloud-traffic-monitor restart
   
   # Test again
   alicloud-traffic-monitor test
   ```

---

### High CPU Usage

**Symptom:**
```
ps aux | grep alicloud
# Shows 30-50% CPU usage
```

**Cause:**
- `INTERVAL` too low (checking too frequently)

**Solution:**

1. **Increase check interval:**
   ```bash
   sudo sed -i 's/^INTERVAL=.*/INTERVAL="5"/' /etc/alicloud-traffic-monitor.conf
   sudo rc-service alicloud-traffic-monitor restart
   ```

2. **Recommended intervals:**
   - Production: `INTERVAL="5"` to `INTERVAL="10"`
   - Development: `INTERVAL="1"`
   - Very busy: `INTERVAL="30"` to `INTERVAL="60"`

---

### Incorrect Traffic Reported

**Symptom:**
```
alicloud-traffic-monitor status
# Shows huge jump in traffic or negative values
```

**Causes:**

1. **Counter reset (reboot):**
   - Expected - handled automatically
   - Shows in logs as "TX counter reset detected"

2. **Overflow:**
   - Should not happen (64-bit protection)
   - Check logs for warnings

3. **Wrong interface:**
   - Including both RX and TX
   - Monitoring wrong network path

**Verify:**

```bash
# Check raw TX value
cat /sys/class/net/eth0/statistics/tx_bytes

# Should increase when downloading/uploading
# Check state file
cat /var/lib/alicloud-traffic-monitor/state.env
```

---

### Service Stopped But sing-box Still Running

**Symptom:**
```
alicloud-traffic-monitor status
# Circuit Breaker: 🚨 LOCKED

rc-service sing-box status
# sing-box is still running
```

**Cause:**
- Service wasn't properly stopped when limit reached

**Solution:**

1. **Manually stop service:**
   ```bash
   sudo rc-service sing-box stop
   ```

2. **Verify lock file:**
   ```bash
   ls -l /var/lib/alicloud-traffic-monitor/limit.lock
   # Should exist if locked
   ```

3. **Check logs:**
   ```bash
   grep -i "circuit\|stop" /var/lib/alicloud-traffic-monitor/traffic.log
   ```

---

### New Month Didn't Reset

**Symptom:**
```
alicloud-traffic-monitor status
# Still showing last month's data on 2nd day
```

**Causes:**

1. **Clock skew:**
   - System time is wrong
   - Date appears to be still in previous month

2. **Stale state file:**
   - Data wasn't actually reset

**Solutions:**

1. **Check system time:**
   ```bash
   date
   # Should show current date/time
   
   # Fix if wrong
   ntpd -qn
   ```

2. **Manual reset (last resort):**
   ```bash
   # Backup current state
   sudo cp /var/lib/alicloud-traffic-monitor/state.env \
           /var/lib/alicloud-traffic-monitor/state.env.backup
   
   # Reset state
   sudo rm /var/lib/alicloud-traffic-monitor/state.env
   sudo rc-service alicloud-traffic-monitor restart
   ```

---

### Log File Growing Too Large

**Symptom:**
```
du -sh /var/lib/alicloud-traffic-monitor/
# 500MB or larger
```

**Cause:**
- Logs not being rotated (shouldn't happen with v2.0)

**Solution:**

1. **Check log settings:**
   ```bash
   head -20 /usr/local/sbin/alicloud-traffic-monitor | grep LOG_MAX
   ```

2. **Manual cleanup:**
   ```bash
   # Archive old logs
   sudo gzip /var/lib/alicloud-traffic-monitor/traffic.log
   
   # Start fresh
   sudo touch /var/lib/alicloud-traffic-monitor/traffic.log
   sudo rc-service alicloud-traffic-monitor restart
   ```

---

### Cannot Read Configuration

**Symptom:**
```
ERROR: config file not readable: /etc/alicloud-traffic-monitor.conf
```

**Solutions:**

1. **Check file permissions:**
   ```bash
   ls -l /etc/alicloud-traffic-monitor.conf
   # Should show: -rw------- root root
   ```

2. **Fix permissions:**
   ```bash
   sudo chmod 600 /etc/alicloud-traffic-monitor.conf
   sudo chown root:root /etc/alicloud-traffic-monitor.conf
   ```

3. **Recreate file:**
   ```bash
   sudo cp config/alicloud-traffic-monitor.conf.example \
           /etc/alicloud-traffic-monitor.conf
   sudo chmod 600 /etc/alicloud-traffic-monitor.conf
   sudo vi /etc/alicloud-traffic-monitor.conf
   ```

---

## Accessing Logs

### Live Monitoring
```bash
tail -f /var/lib/alicloud-traffic-monitor/traffic.log
```

### Search for Errors
```bash
grep ERROR /var/lib/alicloud-traffic-monitor/traffic.log
```

### Search for Events
```bash
grep EVENT /var/lib/alicloud-traffic-monitor/traffic.log
```

### Last 100 Lines
```bash
tail -100 /var/lib/alicloud-traffic-monitor/traffic.log
```

### Entire Log
```bash
cat /var/lib/alicloud-traffic-monitor/traffic.log
```

---

## Debugging

### Enable Debug Logging

Modify `/usr/local/sbin/alicloud-traffic-monitor` to enable debug output:

Search for `LOG_LEVEL` and change from:
```bash
export LOG_LEVEL="${LOG_LEVEL:-INFO}"
```

To:
```bash
export LOG_LEVEL="${LOG_LEVEL:-DEBUG}"
```

Then restart:
```bash
sudo rc-service alicloud-traffic-monitor restart
```

### Run in Foreground

Instead of daemon mode (useful for debugging):
```bash
sudo /usr/local/sbin/alicloud-traffic-monitor run
```

Press Ctrl+C to stop. This will show output directly instead of logging.

---

## Getting Help

**Include this info when reporting issues:**

1. Output of diagnostics:
   ```bash
   alicloud-traffic-monitor diagnose
   ```

2. Configuration (redact tokens):
   ```bash
   cat /etc/alicloud-traffic-monitor.conf
   ```

3. Status:
   ```bash
   alicloud-traffic-monitor status
   ```

4. Recent logs:
   ```bash
   tail -50 /var/lib/alicloud-traffic-monitor/traffic.log
   ```

5. System info:
   ```bash
   uname -a
   rc-service --list | head -5
   ```

---

**Still having issues?** Check the [Configuration Guide](configuration.md) or [Installation Guide](INSTALL.md).
