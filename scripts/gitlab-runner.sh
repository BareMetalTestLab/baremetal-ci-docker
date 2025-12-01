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
    
    # Set default values
    RUNNER_NAME="${RUNNER_NAME:-baremetal-gitlab-runner}"
    RUNNER_TAGS="${RUNNER_TAGS:-baremetal,jlink,mcu}"
    RUNNER_EXECUTOR="${RUNNER_EXECUTOR:-shell}"

    # Register the runner if not already registered
    if [ ! -f "/home/runner/.gitlab-runner/config.toml" ]; then
        log_info "Registering GitLab Runner..."

        # Fix permissions for config directory
        sudo chmod 777 /home/runner/.gitlab-runner
        touch /home/runner/.gitlab-runner/config.toml
        sudo chmod 777 /home/runner/.gitlab-runner/config.toml

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
}

# Cleanup function to unregister runner on exit
cleanup_gitlab_runner() {
    log_info "Shutting down GitLab runner..."
    if [ -f "/home/runner/.gitlab-runner/config.toml" ]; then
        gitlab-runner unregister --all-runners
    fi
}

# Start GitLab Runner
start_gitlab_runner() {
    log_info "Starting GitLab Runner..."
    
    # Trap SIGTERM and SIGINT to cleanup before exit
    trap 'cleanup_gitlab_runner; exit 130' INT
    trap 'cleanup_gitlab_runner; exit 143' TERM
    
    # Start the runner
    gitlab-runner run --working-directory /home/runner/builds
}

# Main execution function for GitLab runner
run_gitlab_runner() {
    setup_gitlab_runner
    start_gitlab_runner
}
