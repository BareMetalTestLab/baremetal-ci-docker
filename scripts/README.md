# Scripts Structure

This project has been reorganized to improve modularity and maintainability.

## Scripts Layout

```
scripts/
├── common.sh          # Common functions for both platforms
├── github-runner.sh   # GitHub Actions Runner logic
└── gitlab-runner.sh   # GitLab Runner logic

entrypoint.sh          # Main entry point
```

## File Descriptions

### `scripts/common.sh`
Contains common functions used by both platforms:
- **Logging**: `log_info()`, `log_warn()`, `log_error()`
- **Directory setup**: `setup_work_directory()`
- **J-Link checks**: `check_jlink_devices()`
- **udev configuration**: `configure_jlink_udev_rules()`

### `scripts/github-runner.sh`
GitHub Actions specific logic:
- `setup_github_runner()` - runner configuration
- `cleanup_github_runner()` - cleanup on exit
- `start_github_runner()` - start runner
- `run_github_runner()` - main function

### `scripts/gitlab-runner.sh`
GitLab CI specific logic:
- `setup_gitlab_runner()` - runner configuration
- `cleanup_gitlab_runner()` - cleanup on exit
- `start_gitlab_runner()` - start runner
- `run_gitlab_runner()` - main function

### `entrypoint.sh`
Main entrypoint that:
1. Loads common functions
2. Sets up work directories
3. Checks J-Link devices
4. Loads and starts the appropriate runner based on `CI_PLATFORM`

## Benefits of New Structure

1. **Modularity**: Code is split into logical blocks
2. **Reusability**: Common code in `common.sh` is used by both platforms
3. **Readability**: Each file has a clear responsibility
4. **Maintainability**: Changes to one platform don't affect the other
5. **Extensibility**: Easy to add support for new CI platforms

## Dockerfile Changes

Dockerfile has been updated to copy all scripts:

```dockerfile
# Copy scripts directory and entrypoint
COPY --chown=runner:runner scripts/ /home/runner/scripts/
COPY --chown=runner:runner entrypoint.sh /home/runner/entrypoint.sh
RUN chmod +x /home/runner/entrypoint.sh && \
    chmod +x /home/runner/scripts/*.sh
```

## Backward Compatibility

Functionality is fully preserved, only the code organization has changed.
