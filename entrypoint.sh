#!/bin/bash

# Unified entrypoint script for GitHub Actions / GitLab Runner with J-Link support
# Selects runner based on CI_PLATFORM environment variable
# Note: CI_PLATFORM validation is done at build time in Dockerfile

set -e

# Source common functions
source /home/runner/scripts/common.sh

# Ensure work directory exists and has correct permissions
if [ "${CI_PLATFORM}" = "gitlab" ]; then
    log_info "CI_PLATFORM is set to gitlab"
    setup_work_directory "/home/runner/builds"
else
    log_info "CI_PLATFORM is set to github"
    setup_work_directory "/home/runner/_work"
fi

# Check for J-Link devices (if installed)
check_jlink_devices || true

# Load and execute platform-specific runner
if [ "${CI_PLATFORM}" = "gitlab" ]; then
    source /home/runner/scripts/gitlab-runner.sh
    run_gitlab_runner
else
    source /home/runner/scripts/github-runner.sh
    run_github_runner
fi
