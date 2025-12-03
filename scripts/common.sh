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

# Check for PEAK CAN devices
check_peakcan_devices() {
    if [ "${ENABLE_PEAKCAN}" != "true" ]; then
        return 0
    fi
    
    log_info "Checking for PEAK CAN devices..."
    if [ -d "/dev" ]; then
        PCAN_COUNT=$(ls -1 /dev/pcan* 2>/dev/null | wc -l || echo "0")
        if [ "${PCAN_COUNT}" -gt "0" ]; then
            log_info "PEAK CAN devices detected: ${PCAN_COUNT} device(s)"
            ls -la /dev/pcan* 2>/dev/null || true
            return 0
        else
            log_warn "No PEAK CAN devices detected."
            log_warn "Make sure USB devices are properly passed to the container (privileged mode + /dev mount)."
            # Also check for USB PEAK devices
            PCAN_USB=$(lsusb | grep -i "0c72" || echo "")
            if [ -n "${PCAN_USB}" ]; then
                log_info "PEAK CAN USB device found in lsusb:"
                echo "${PCAN_USB}"
            fi
            return 1
        fi
    fi
    return 0
}
