#!/bin/sh
# ============================================================================
# Alibaba Cloud Traffic Monitor - Installation & Management Script
# ============================================================================

set -u

APP_NAME="alicloud-traffic-monitor"
APP_VERSION="2.0.0"

# Installation paths
BIN="/usr/local/sbin/$APP_NAME"
INIT="/etc/init.d/$APP_NAME"
CONF="/etc/$APP_NAME.conf"
STATE_DIR="/var/lib/$APP_NAME"
LOG_FILE="$STATE_DIR/traffic.log"

# ─────────────────────────────────────────────────────────────────────────
# Utility Functions
# ─────────────────────────────────────────────────────────────────────────

msg() {
    echo "$@"
}

err() {
    echo "ERROR: $*" >&2
}

success() {
    echo "✅ $*"
}

warn() {
    echo "⚠️  WARNING: $*" >&2
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        err "This script requires root privileges"
        exit 1
    fi
}

detect_init_system() {
    if [ -d "/run/openrc" ] || [ -f "/etc/inittab" ]; then
        echo "openrc"
    elif [ -d "/run/systemd" ]; then
        echo "systemd"
    else
        echo "unknown"
    fi
}

# ─────────────────────────────────────────────────────────────────────────
# Installation Functions
# ─────────────────────────────────────────────────────────────────────────

cmd_install() {
    check_root
    
    msg "=== Installing $APP_NAME v$APP_VERSION ==="
    echo ""
    
    # Detect init system
    local init_system
    init_system="$(detect_init_system)"
    
    if [ "$init_system" = "unknown" ]; then
        err "Cannot detect init system (OpenRC/systemd required)"
        exit 1
    fi
    
    msg "Init system detected: $init_system"
    echo ""
    
    # Install dependencies
    msg "Installing dependencies..."
    if ! apk update >/dev/null 2>&1; then
        err "Failed to update package cache"
        exit 1
    fi
    
    if ! apk add --no-cache curl awk coreutils ca-certificates 2>/dev/null; then
        err "Failed to install dependencies"
        exit 1
    fi
    success "Dependencies installed"
    echo ""
    
    # Create state directory
    msg "Creating state directory..."
    if ! mkdir -p "$STATE_DIR"; then
        err "Failed to create state directory: $STATE_DIR"
        exit 1
    fi
    
    chmod 700 "$STATE_DIR"
    touch "$LOG_FILE" || true
    chmod 644 "$LOG_FILE" || true
    
    success "State directory created: $STATE_DIR"
    echo ""
    
    # Install binary
    msg "Installing binary..."
    
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    
    if [ ! -f "$script_dir/bin/$APP_NAME" ]; then
        err "Binary not found: $script_dir/bin/$APP_NAME"
        exit 1
    fi
    
    cp "$script_dir/bin/$APP_NAME" "$BIN" || {
        err "Failed to install binary"
        exit 1
    }
    
    chmod 755 "$BIN"
    success "Binary installed to: $BIN"
    echo ""
    
    # Install OpenRC service
    if [ "$init_system" = "openrc" ]; then
        msg "Installing OpenRC service..."
        
        if [ ! -f "$script_dir/openrc/$APP_NAME" ]; then
            err "Service file not found: $script_dir/openrc/$APP_NAME"
            exit 1
        fi
        
        cp "$script_dir/openrc/$APP_NAME" "$INIT" || {
            err "Failed to install service file"
            exit 1
        }
        
        chmod 755 "$INIT"
        success "Service file installed to: $INIT"
    fi
    echo ""
    
    # Setup configuration
    if [ ! -f "$CONF" ]; then
        msg "Setting up configuration..."
        echo ""
        
        # Copy example config
        if [ -f "$script_dir/config/$APP_NAME.conf.example" ]; then
            cp "$script_dir/config/$APP_NAME.conf.example" "$CONF"
        fi
        
        # Interactive setup
        "$BIN" --setup || true
    else
        warn "Configuration file already exists: $CONF"
    fi
    echo ""
    
    # Register service
    if [ "$init_system" = "openrc" ]; then
        msg "Registering service..."
        
        if rc-update add "$APP_NAME" default >/dev/null 2>&1; then
            success "Service registered for auto-start"
        else
            warn "Failed to register service for auto-start"
        fi
    fi
    echo ""
    
    # Test Telegram
    msg "Testing Telegram notifications..."
    if "$BIN" test; then
        success "Telegram test passed"
    else
        warn "Telegram test failed (this is optional)"
    fi
    echo ""
    
    # Start service
    msg "Starting service..."
    if [ "$init_system" = "openrc" ]; then
        if rc-service "$APP_NAME" restart >/dev/null 2>&1; then
            success "Service started"
        else
            warn "Failed to start service, try manually: rc-service $APP_NAME start"
        fi
    fi
    echo ""
    
    # Summary
    msg "=== Installation Complete ==="
    echo ""
    msg "Quick start:"
    echo "  • View status:        $BIN status"
    echo "  • View logs:          tail -f $LOG_FILE"
    echo "  • Diagnose:           $BIN diagnose"
    echo "  • Manage service:     rc-service $APP_NAME {start|stop|restart|status}"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────
# Update Function
# ─────────────────────────────────────────────────────────────────────────

cmd_update() {
    check_root
    
    msg "=== Updating $APP_NAME ==="
    echo ""
    
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    
    # Git update (if available)
    if [ -d ".git" ]; then
        msg "Updating from git repository..."
        if git fetch --all >/dev/null 2>&1 && git reset --hard origin/main >/dev/null 2>&1; then
            success "Git repository updated"
        else
            warn "Failed to update from git"
        fi
    fi
    
    # Update binary
    msg "Updating binary..."
    if [ -f "$script_dir/bin/$APP_NAME" ]; then
        cp "$script_dir/bin/$APP_NAME" "$BIN"
        chmod 755 "$BIN"
        success "Binary updated"
    fi
    
    # Update service file
    if [ -f "$script_dir/openrc/$APP_NAME" ]; then
        cp "$script_dir/openrc/$APP_NAME" "$INIT"
        chmod 755 "$INIT"
        success "Service file updated"
    fi
    echo ""
    
    # Restart service
    msg "Restarting service..."
    if rc-service "$APP_NAME" restart >/dev/null 2>&1; then
        success "Service restarted"
    else
        warn "Failed to restart service"
    fi
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────
# Status Function
# ─────────────────────────────────────────────────────────────────────────

cmd_status() {
    "$BIN" status
}

# ─────────────────────────────────────────────────────────────────────────
# Logs Function
# ─────────────────────────────────────────────────────────────────────────

cmd_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        err "Log file not found: $LOG_FILE"
        exit 1
    fi
    
    tail -f "$LOG_FILE"
}

# ─────────────────────────────────────────────────────────────────────────
# Uninstall Function
# ─────────────────────────────────────────────────────────────────────────

cmd_uninstall() {
    check_root
    
    msg "=== Uninstalling $APP_NAME ==="
    echo ""
    
    # Stop service
    msg "Stopping service..."
    rc-service "$APP_NAME" stop >/dev/null 2>&1 || true
    rc-update del "$APP_NAME" default >/dev/null 2>&1 || true
    success "Service stopped"
    echo ""
    
    # Remove files
    msg "Removing installation files..."
    rm -f "$BIN"
    rm -f "$INIT"
    success "Installation files removed"
    echo ""
    
    # Ask about data removal
    printf "Remove configuration and data? [y/N]: "
    read -r response
    
    case "$response" in
        [yY]|[yY][eE][sS])
            msg "Removing configuration and data..."
            rm -f "$CONF"
            rm -rf "$STATE_DIR"
            success "Configuration and data removed"
            ;;
        *)
            msg "Keeping configuration and data at:"
            echo "  • Config: $CONF"
            echo "  • Data:   $STATE_DIR"
            ;;
    esac
    echo ""
    
    success "Uninstallation complete"
}

# ─────────────────────────────────────────────────────────────────────────
# Main Entry
# ─────────────────────────────────────────────────────────────────────────

print_usage() {
    cat << EOF
$APP_NAME Installation & Management Script v$APP_VERSION

Usage: $0 {install|update|status|logs|uninstall}

Commands:
  install     Install the application (requires root)
  update      Update to latest version (requires root)
  status      Show current status
  logs        Show real-time logs
  uninstall   Uninstall the application (requires root)

Examples:
  sudo ./install.sh install
  ./install.sh status
  tail -f /var/lib/alicloud-traffic-monitor/traffic.log

EOF
}

case "${1:-}" in
    install)
        cmd_install
        ;;
    update)
        cmd_update
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs
        ;;
    uninstall)
        cmd_uninstall
        ;;
    *)
        print_usage
        exit 1
        ;;
esac
