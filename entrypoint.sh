#!/bin/bash

# Unified entrypoint script for GitHub Actions / GitLab Runner with J-Link support
# Selects runner based on CI_PLATFORM environment variable
# Note: CI_PLATFORM validation is done at build time in Dockerfile

set -e

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

# Ensure work directory exists and has correct permissions
log_info "Setting up work directory..."
if [ "${CI_PLATFORM}" = "gitlab" ]; then
    if [ ! -d "/home/runner/builds" ]; then
        mkdir -p /home/runner/builds
    fi
    if [ "$(stat -c %U /home/runner/builds)" != "runner" ]; then
        sudo chown -R runner:runner /home/runner/builds
    fi
else
    if [ ! -d "/home/runner/_work" ]; then
        mkdir -p /home/runner/_work
    fi
    if [ "$(stat -c %U /home/runner/_work)" != "runner" ]; then
        sudo chown -R runner:runner /home/runner/_work
    fi
fi

# Check for J-Link devices
log_info "Checking for J-Link devices..."
if command -v JLinkExe &> /dev/null; then
    JLINK_COUNT=$(JLinkExe -CommanderScript /dev/null 2>&1 | grep -c "J-Link" || echo "0")
    if [ "${JLINK_COUNT}" -gt "0" ]; then
        log_info "J-Link devices detected"
    else
        log_warn "No J-Link devices detected."
        log_warn "Make sure USB devices are properly passed to the container (privileged mode + /dev mount)."
    fi
else
    log_warn "JLinkExe not found in PATH"
fi

# Configure udev rules for specific J-Link devices if serial numbers are provided
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

# Validate required environment variables and configure runner
if [ "${CI_PLATFORM}" = "gitlab" ]; then
    # ============================================================================
    # GITLAB RUNNER CONFIGURATION
    # ============================================================================
    
    if [ -z "${GITLAB_URL}" ]; then
        log_error "GITLAB_URL is required for GitLab runner"
        exit 1
    fi

    if [ -z "${GITLAB_REGISTRATION_TOKEN}" ]; then
        log_error "GITLAB_REGISTRATION_TOKEN is required for GitLab runner"
        exit 1
    fi

    log_info "Configuring GitLab Runner..."
    
    # Set default values
    RUNNER_NAME="${RUNNER_NAME:-baremetal-gitlab-runner}"
    RUNNER_TAGS="${RUNNER_TAGS:-baremetal,jlink,mcu}"
    RUNNER_EXECUTOR="${RUNNER_EXECUTOR:-shell}"

    # Register the runner if not already registered
    if [ ! -f "/home/runner/.gitlab-runner/config.toml" ]; then
        log_info "Registering GitLab Runner..."
        
        gitlab-runner register \
            --non-interactive \
            --url "${GITLAB_URL}" \
            --registration-token "${GITLAB_REGISTRATION_TOKEN}" \
            --executor "${RUNNER_EXECUTOR}" \
            --description "${RUNNER_NAME}" \
            --tag-list "${RUNNER_TAGS}" \
            --run-untagged="${RUNNER_RUN_UNTAGGED:-false}" \
            --locked="${RUNNER_LOCKED:-false}" \
            --access-level="${RUNNER_ACCESS_LEVEL:-not_protected}" \
            --builds-dir "/home/runner/builds" \
            --cache-dir "/home/runner/cache"
        
        log_info "Runner registered successfully"
    else
        log_info "Runner already registered"
    fi

    # Cleanup function to unregister runner on exit
    cleanup() {
        log_info "Shutting down runner..."
        if [ -f "/home/runner/.gitlab-runner/config.toml" ]; then
            gitlab-runner unregister --all-runners
        fi
    }

    # Trap SIGTERM and SIGINT to cleanup before exit
    trap 'cleanup; exit 130' INT
    trap 'cleanup; exit 143' TERM

    # Start the runner
    log_info "Starting GitLab Runner..."
    gitlab-runner run --working-directory /home/runner/builds

else
    # ============================================================================
    # GITHUB ACTIONS RUNNER CONFIGURATION
    # ============================================================================
    
    if [ -z "${GITHUB_TOKEN}" ] && [ -z "${GITHUB_REGISTRATION_TOKEN}" ]; then
        log_error "Either GITHUB_TOKEN (PAT) or GITHUB_REGISTRATION_TOKEN is required"
        exit 1
    fi

    if [ -z "${GITHUB_OWNER}" ] && [ -z "${GITHUB_REPOSITORY}" ]; then
        log_error "Either GITHUB_OWNER (for organization) or GITHUB_REPOSITORY (for specific repo) is required"
        exit 1
    fi

    # Determine the runner registration URL and token URL
    if [ -n "${GITHUB_REPOSITORY}" ]; then
        # Register runner for a specific repository
        RUNNER_URL="https://github.com/${GITHUB_REPOSITORY}"
        TOKEN_URL="https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runners/registration-token"
        log_info "Registering runner for repository: ${GITHUB_REPOSITORY}"
    else
        # Register runner for an organization
        RUNNER_URL="https://github.com/${GITHUB_OWNER}"
        TOKEN_URL="https://api.github.com/orgs/${GITHUB_OWNER}/actions/runners/registration-token"
        log_info "Registering runner for organization: ${GITHUB_OWNER}"
    fi

    # Get registration token
    if [ -n "${GITHUB_REGISTRATION_TOKEN}" ]; then
        # Use provided registration token directly
        log_info "Using provided registration token"
        REGISTRATION_TOKEN="${GITHUB_REGISTRATION_TOKEN}"
    elif [ -n "${GITHUB_TOKEN}" ]; then
        # Get registration token from GitHub API using PAT
        log_info "Obtaining registration token from GitHub API..."
        REGISTRATION_TOKEN=$(curl -s -X POST -H "Authorization: token ${GITHUB_TOKEN}" \
            -H "Accept: application/vnd.github.v3+json" \
            "${TOKEN_URL}" | jq -r .token)
        
        if [ -z "${REGISTRATION_TOKEN}" ] || [ "${REGISTRATION_TOKEN}" == "null" ]; then
            log_error "Failed to obtain registration token from GitHub API"
            log_error "Please check your GITHUB_TOKEN has correct permissions (repo, admin:org)"
            exit 1
        fi
        log_info "Registration token obtained successfully"
    fi

    # Configure the runner if not already configured
    if [ ! -f ".runner" ]; then
        log_info "Configuring GitHub Actions runner..."
        
        ./config.sh \
            --url "${RUNNER_URL}" \
            --token "${REGISTRATION_TOKEN}" \
            --name "${RUNNER_NAME}" \
            --work "${RUNNER_WORKDIR}" \
            --labels "${RUNNER_LABELS}" \
            --runnergroup "${RUNNER_GROUP}" \
            --unattended \
            --replace
        
        log_info "Runner configured successfully"
    else
        log_info "Runner already configured"
    fi

    # Cleanup function to unregister runner on exit
    cleanup() {
        log_info "Shutting down runner..."
        if [ -f ".runner" ]; then
            ./config.sh remove --token "${REGISTRATION_TOKEN}"
        fi
    }

    # Trap SIGTERM and SIGINT to cleanup before exit
    trap 'cleanup; exit 130' INT
    trap 'cleanup; exit 143' TERM

    # Start the runner
    log_info "Starting GitHub Actions runner..."
    /home/runner/run.sh & wait $!
fi
