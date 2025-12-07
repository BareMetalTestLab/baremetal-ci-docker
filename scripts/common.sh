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
    if [ "${ENABLE_JLINK}" != "true" ]; then
        return 0
    fi
    
    if command -v JLinkExe &> /dev/null; then
        log_info "Checking for J-Link devices..."
        JLINK_COUNT=$(JLinkExe -CommanderScript /dev/null 2>&1 | grep -c "J-Link" || echo "0")
        if [ "${JLINK_COUNT}" -gt "0" ]; then
            log_info "J-Link devices detected"
            return 0
        else
            log_warn "No J-Link devices detected."
            log_warn "Make sure USB devices are properly passed to the container (privileged mode + /dev mount)."
            return 1
        fi
    fi
    return 0
}

# Setup SocketCAN interface for PEAK CAN devices
setup_socketcan() {
    # Skip if PEAK CAN is not enabled
    if [ "${ENABLE_PEAKCAN}" != "true" ]; then
        return 0
    fi
    
    local BAUDRATE=${PCAN_BAUDRATE:-125000}
    
    log_info "Setting up SocketCAN interface with baudrate ${BAUDRATE}..."
    
    # Check if PEAK CAN USB device is connected
    if ! lsusb | grep -q "0c72"; then
        log_warn "No PEAK CAN USB device detected (vendor ID 0c72)"
        return 1
    fi
    
    log_info "PEAK CAN USB device detected"
    
    # Load required kernel modules (should be on host)
    if [ -d "/lib/modules/$(uname -r)" ]; then
        sudo modprobe can 2>/dev/null || log_warn "Could not load 'can' module"
        sudo modprobe can_raw 2>/dev/null || log_warn "Could not load 'can_raw' module"
        sudo modprobe peak_usb 2>/dev/null || log_warn "Could not load 'peak_usb' module (may need to be loaded on host)"
    fi
    
    # Wait a bit for device to appear
    sleep 1
    
    # Find CAN interface
    CAN_INTERFACE=$(ip link show | grep -o "can[0-9]*" | head -n 1)
    
    if [ -z "${CAN_INTERFACE}" ]; then
        log_warn "No CAN interface found. The peak_usb module may need to be loaded on the host system."
        log_info "To load the module on host, run: sudo modprobe peak_usb"
        return 1
    fi
    
    log_info "Found CAN interface: ${CAN_INTERFACE}"
    
    # Bring down the interface first (in case it's already up)
    sudo ip link set ${CAN_INTERFACE} down 2>/dev/null || true
    
    # Configure and bring up the interface
    sudo ip link set ${CAN_INTERFACE} type can bitrate ${BAUDRATE} || {
        log_error "Failed to configure ${CAN_INTERFACE} with bitrate ${BAUDRATE}"
        return 1
    }
    
    sudo ip link set ${CAN_INTERFACE} up || {
        log_error "Failed to bring up ${CAN_INTERFACE}"
        return 1
    }
    
    log_info "SocketCAN interface ${CAN_INTERFACE} is up with baudrate ${BAUDRATE}"
    log_info "You can test it with: candump ${CAN_INTERFACE}"
    
    return 0
}

