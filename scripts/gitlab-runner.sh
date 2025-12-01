#!/bin/bash

# GitLab Runner configuration and execution

# Source common functions
source /home/runner/scripts/common.sh

# Setup GitLab Runner
setup_gitlab_runner() {
    log_info "Setting up GitLab Runner..."
    
    # Validate required environment variables
    if [ -z "${GITLAB_URL}" ]; then
        log_error "GITLAB_URL is required for GitLab runner"
        exit 1
    fi

    if [ -z "${GITLAB_REGISTRATION_TOKEN}" ]; then
        log_error "GITLAB_REGISTRATION_TOKEN is required for GitLab runner"
        exit 1
    fi
    
    RUNNER_EXECUTOR="${RUNNER_EXECUTOR:-shell}"

    # Register the runner if not already registered (check if [[runners]] section exists)
    if ! grep -q "^\[\[runners\]\]" /etc/gitlab-runner/config.toml 2>/dev/null; then
        log_info "Registering GitLab Runner..."

        # Note: When using authentication token (glrt-*), tags and other settings
        # are configured in GitLab UI, not via registration parameters
        gitlab-runner register \
            --non-interactive \
            --config /etc/gitlab-runner/config.toml \
            --url "${GITLAB_URL}" \
            --token "${GITLAB_REGISTRATION_TOKEN}" \
            --executor "${RUNNER_EXECUTOR}" \
            --builds-dir "/home/runner/builds" \
            --cache-dir "/home/runner/cache"
        
        # Fix permissions for config file after registration
        sudo chown -R runner:runner /etc/gitlab-runner
        sudo find /etc/gitlab-runner -type f -exec chmod 644 {} \;
        
        log_info "Runner registered successfully"
    else
        log_info "Runner already registered"
        # Fix permissions anyway
        sudo chown -R runner:runner /etc/gitlab-runner
        sudo find /etc/gitlab-runner -type f -exec chmod 644 {} \;
    fi
}

# Cleanup function to unregister runner on exit
cleanup_gitlab_runner() {
    log_info "Shutting down GitLab runner..."
    if [ -f "/etc/gitlab-runner/config.toml" ]; then
        gitlab-runner unregister --all-runners --config /etc/gitlab-runner/config.toml
    fi
}

# Start GitLab Runner
start_gitlab_runner() {
    log_info "Starting GitLab Runner..."
    
    # Trap SIGTERM and SIGINT to cleanup before exit
    trap 'cleanup_gitlab_runner; exit 130' INT
    trap 'cleanup_gitlab_runner; exit 143' TERM
    
    # Start the runner
    gitlab-runner run --config /etc/gitlab-runner/config.toml --working-directory /home/runner/builds
}

# Main execution function for GitLab runner
run_gitlab_runner() {
    setup_gitlab_runner
    start_gitlab_runner
}
