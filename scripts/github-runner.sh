#!/bin/bash

# GitHub Actions Runner configuration and execution

# Source common functions
source /home/runner/scripts/common.sh

# Setup GitHub Actions runner
setup_github_runner() {
    log_info "Setting up GitHub Actions Runner..."
    
    # Validate required environment variables
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
}

# Cleanup function to unregister runner on exit
cleanup_github_runner() {
    log_info "Shutting down GitHub Actions runner..."
    if [ -f ".runner" ]; then
        ./config.sh remove --token "${REGISTRATION_TOKEN}"
    fi
}

# Start GitHub Actions runner
start_github_runner() {
    log_info "Starting GitHub Actions runner..."
    
    # Trap SIGTERM and SIGINT to cleanup before exit
    trap 'cleanup_github_runner; exit 130' INT
    trap 'cleanup_github_runner; exit 143' TERM
    
    # Start the runner
    /home/runner/run.sh & wait $!
}

# Main execution function for GitHub runner
run_github_runner() {
    setup_github_runner
    start_github_runner
}
