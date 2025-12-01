#!/bin/bash

# Common functions and utilities shared between CI platforms

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Setup work directory with correct permissions
setup_work_directory() {
    local work_dir=$1
    
    log_info "Setting up work directory: ${work_dir}..."
    
    if [ ! -d "${work_dir}" ]; then
        mkdir -p "${work_dir}"
    fi
    
    if [ "$(stat -c %U ${work_dir})" != "runner" ]; then
        sudo chown -R runner:runner "${work_dir}"
    fi
}

# Check for J-Link devices
check_jlink_devices() {
    log_info "Checking for J-Link devices..."
    
    if command -v JLinkExe &> /dev/null; then
        JLINK_COUNT=$(JLinkExe -CommanderScript /dev/null 2>&1 | grep -c "J-Link" || echo "0")
        if [ "${JLINK_COUNT}" -gt "0" ]; then
            log_info "J-Link devices detected"
            return 0
        else
            log_warn "No J-Link devices detected."
            log_warn "Make sure USB devices are properly passed to the container (privileged mode + /dev mount)."
            return 1
        fi
    else
        log_warn "JLinkExe not found in PATH"
        return 1
    fi
}

# Configure udev rules for specific J-Link devices
configure_jlink_udev_rules() {
    if [ -n "${JLINK_SERIAL_NUMBERS}" ]; then
        log_info "Configuring udev rules for specific J-Link devices..."
        IFS=',' read -ra SERIALS <<< "${JLINK_SERIAL_NUMBERS}"
        for SERIAL in "${SERIALS[@]}"; do
            SERIAL=$(echo "$SERIAL" | xargs) # Trim whitespace
            if [ -n "$SERIAL" ]; then
                log_info "Adding udev rule for J-Link S/N: ${SERIAL}"
                echo "SUBSYSTEM==\"usb\", ATTR{idVendor}==\"1366\", ATTR{serial}==\"${SERIAL}\", MODE=\"0666\", GROUP=\"plugdev\"" | sudo tee -a /etc/udev/rules.d/99-jlink-specific.rules > /dev/null
            fi
        done
        
        # Reload udev rules
        if [ -f /etc/udev/rules.d/99-jlink-specific.rules ]; then
            log_info "Reloading udev rules..."
            sudo udevadm control --reload-rules 2>/dev/null || true
            sudo udevadm trigger 2>/dev/null || true
        fi
    fi
}
