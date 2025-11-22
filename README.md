# Baremetal MCU CI Testing with GitHub Actions Runner and Segger J-Link

Docker container for continuous integration testing of baremetal microcontroller devices. This container includes a self-hosted GitHub Actions runner with Segger J-Link support for flashing and debugging MCU hardware.

## Features

- **GitHub Actions Self-Hosted Runner**: Runs CI/CD workflows directly on hardware
- **Segger J-Link Support**: Full J-Link driver installation for MCU programming and debugging
- **USB Device Passthrough**: All J-Link devices are automatically passed through to the container
- **Automatic Runner Registration**: Configures and registers with GitHub on startup
- **Persistent Workspace**: Runner work directory is preserved across container restarts

## Prerequisites

- Docker Engine (20.10+) or Docker Desktop for Mac
- Docker Compose (2.0+)
- GitHub Personal Access Token with `repo` and `admin:org` (if using organization) permissions
- Segger J-Link device connected via USB

### Platform-Specific Requirements

**Linux:**
- Direct USB device passthrough supported
- Requires privileged container mode

**macOS:**
- Docker Desktop with USB device support (experimental feature)
- Alternative: Install J-Link tools on host macOS and use network connection
- Use the macOS-specific docker-compose configuration

## Quick Start

### 1. Clone or Create Project Directory

```bash
mkdir baremetal-github-docker-ci
cd baremetal-github-docker-ci
```

### 2. Create Environment Configuration

Copy the example environment file and fill in your details:

```bash
cp .env.example .env
```

Edit `.env` and set the following variables:

```bash
# GitHub token with repo and admin:org permissions
GITHUB_TOKEN=ghp_your_token_here

# For organization-level runner (recommended for multiple repos)
GITHUB_OWNER=your-org-name

# OR for repository-specific runner
GITHUB_REPOSITORY=owner/repo-name

# Runner configuration
RUNNER_NAME=baremetal-ci-runner
RUNNER_LABELS=baremetal,jlink,mcu
RUNNER_GROUP=default
```

### 3. Build and Run

**Cross-platform (recommended):**

Use the provided helper script that automatically detects your OS:

```bash
chmod +x run.sh
./run.sh up -d
```

**Manual commands:**

**On Linux:**

```bash
docker-compose up -d
```

**On macOS:**

```bash
# Use the macOS-specific configuration
docker-compose -f docker-compose.yml -f docker-compose.macos.yml up -d
```

**Note for macOS users:**

Due to limitations in Docker Desktop's USB passthrough, you have two options:

1. **Install J-Link on host macOS** and use J-Link Remote Server:
   ```bash
   # On macOS host
   brew install --cask segger-jlink
   JLinkRemoteServer
   
   # In container workflows, connect to host
   JLinkExe -ip host.docker.internal
   ```

2. **Enable USB device support** in Docker Desktop (Settings → Resources → USB Devices) and manually share J-Link devices with the container

### 4. Verify Runner Status

Check the logs to ensure the runner started successfully:

```bash
docker-compose logs -f
```

You should see messages indicating:
- J-Link device detection
- Runner configuration
- Connection to GitHub

Visit your repository or organization Settings → Actions → Runners to see the registered runner.

## Usage in GitHub Actions Workflows

Once the runner is online, you can use it in your workflows by specifying the runner labels:

```yaml
name: MCU Firmware CI

on: [push, pull_request]

jobs:
  build-and-flash:
    runs-on: [self-hosted, baremetal, jlink, mcu]
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Build firmware
        run: |
          # Your build commands here
          make clean
          make all
      
      - name: Check J-Link connection
        run: |
          JLinkExe -CommanderScript <<EOF
          connect
          exit
          EOF
      
      - name: Flash firmware
        run: |
          # Flash using J-Link
          JLinkExe -device STM32F407VG -if SWD -speed 4000 -autoconnect 1 -CommanderScript <<EOF
          r
          h
          loadfile build/firmware.hex
          r
          g
          exit
          EOF
      
      - name: Run tests
        run: |
          # Your test commands
          python test/run_tests.py
```

## J-Link Commands

The container includes all Segger J-Link command-line tools:

- `JLinkExe` - J-Link Commander
- `JLinkGDBServer` - GDB Server for debugging
- `JLinkSWOViewer` - SWO Viewer for trace data
- `JLinkRTTClient` - RTT Client for real-time transfer

### Example: List Connected J-Link Devices

```bash
docker exec baremetal-ci-runner JLinkExe -CommanderScript /dev/null
```

### Example: Flash Firmware

```bash
docker exec baremetal-ci-runner JLinkExe -device <MCU_NAME> -if SWD -speed 4000 -autoconnect 1 -CommanderScript flash.jlink
```

## Configuration Options

### Environment Variables

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `GITHUB_TOKEN` | Yes | GitHub Personal Access Token | - |
| `GITHUB_OWNER` | Conditional* | GitHub organization name | - |
| `GITHUB_REPOSITORY` | Conditional* | Repository in format `owner/repo` | - |
| `RUNNER_NAME` | No | Name for the runner | `baremetal-ci-runner` |
| `RUNNER_LABELS` | No | Comma-separated labels | `baremetal,jlink,mcu` |
| `RUNNER_GROUP` | No | Runner group | `default` |
| `RUNNER_WORKDIR` | No | Working directory for jobs | `_work` |

*Either `GITHUB_OWNER` (for org-level runner) or `GITHUB_REPOSITORY` (for repo-level runner) must be set.

## Troubleshooting

### Runner Not Appearing in GitHub

1. Check the container logs: `docker-compose logs -f`
2. Verify your `GITHUB_TOKEN` has correct permissions
3. Ensure the token hasn't expired

### J-Link Device Not Detected

**On Linux:**

1. Check if the device is connected: `lsusb | grep 1366`
2. Verify USB passthrough: `docker exec baremetal-ci-runner lsusb`
3. Check container privileges: ensure `privileged: true` in docker-compose.yml
4. Verify udev rules are loaded

**On macOS:**

1. Check if the device is visible on host: `system_profiler SPUSBDataType | grep -A 10 "J-Link"`
2. Option A: Use Docker Desktop USB device sharing feature (Settings → Resources → USB Devices)
3. Option B: Install J-Link on host macOS and use remote server:
   ```bash
   # Terminal 1 (macOS host)
   brew install --cask segger-jlink
   JLinkRemoteServer -port 19020
   
   # Terminal 2 (in container or workflows)
   docker exec baremetal-ci-runner JLinkExe -ip host.docker.internal:19020
   ```
4. Option C: Use host network mode in docker-compose:
   ```yaml
   network_mode: "host"
   ```

### Permission Issues with USB Devices

The container runs in privileged mode and should have access to all USB devices. If issues persist:

1. Check host udev rules: `/etc/udev/rules.d/99-jlink.rules`
2. Reload udev rules: `sudo udevadm control --reload-rules && sudo udevadm trigger`
3. Verify the runner user has proper permissions inside the container

## Maintenance

### Stopping the Runner

**Cross-platform:**
```bash
./run.sh down
```

**Manual commands:**

**On Linux:**
```bash
docker-compose down
```

**On macOS:**
```bash
docker-compose -f docker-compose.yml -f docker-compose.macos.yml down
```

The runner will automatically unregister from GitHub on shutdown.

### Updating the Runner

**Cross-platform:**
```bash
./run.sh down
./run.sh build --no-cache
./run.sh up -d
```

**Manual commands:**

**On Linux:**
```bash
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

**On macOS:**
```bash
docker-compose -f docker-compose.yml -f docker-compose.macos.yml down
docker-compose build --no-cache
docker-compose -f docker-compose.yml -f docker-compose.macos.yml up -d
```

### Viewing Logs

```bash
docker-compose logs -f
```

### Accessing Container Shell

```bash
docker exec -it baremetal-ci-runner bash
```

## Security Considerations

- Store `GITHUB_TOKEN` securely (use secrets management)
- Limit token permissions to only what's necessary
- Run container on trusted, isolated networks
- Regularly update the base image and J-Link software
- Monitor runner activity in GitHub Actions logs

## License

This project is provided as-is for CI/CD automation purposes.

## Support

For issues related to:
- **GitHub Actions Runner**: [actions/runner](https://github.com/actions/runner)
- **Segger J-Link**: [Segger Support](https://www.segger.com/support/)
- **Docker**: [Docker Documentation](https://docs.docker.com/)
