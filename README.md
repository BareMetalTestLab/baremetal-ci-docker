# Baremetal MCU CI Testing with GitHub/GitLab Runner, Segger J-Link and PEAK CAN

Docker container for continuous integration testing of baremetal microcontroller devices. This container includes self-hosted CI runners (GitHub Actions or GitLab CI) with Segger J-Link support for flashing and debugging MCU hardware, plus PEAK CAN support via SocketCAN for CAN bus testing.

## Choose Your CI Platform

This Docker image supports both **GitHub Actions** and **GitLab CI**. Select your platform in the `.env` file:

```bash
# In .env file
CI_PLATFORM=github    # for GitHub Actions
# or
CI_PLATFORM=gitlab    # for GitLab CI
```

Then simply run:
```bash
docker-compose up -d
```

For detailed GitLab-specific documentation, see [README.gitlab.md](README.gitlab.md).

## Features

- **GitHub Actions Self-Hosted Runner**: Runs CI/CD workflows directly on hardware
- **GitLab Runner Support**: Alternative to GitHub Actions for GitLab CI/CD
- **Segger J-Link Support**: Full J-Link driver installation for MCU programming and debugging
- **PEAK CAN Support**: SocketCAN interface for CAN bus communication and testing
- **USB Device Passthrough**: All USB devices are automatically passed through to the container
- **Automatic Runner Registration**: Configures and registers with GitHub/GitLab on startup
- **Persistent Workspace**: Runner work directory is preserved across container restarts

## Prerequisites

- Docker Engine (20.10+)
- Docker Compose (2.0+)
- GitHub Personal Access Token with `repo` and `admin:org` (if using organization) permissions
- Segger J-Link device connected via USB (optional)
- PEAK CAN USB device connected (optional, for CAN bus testing)
- **Linux host required** for USB device passthrough

### Platform-Specific Requirements

**Linux:**
- Direct USB device passthrough supported
- Requires privileged container mode
- For PEAK CAN: `peak_usb` kernel module must be available on host

## Quick Start

### 1. Clone or Create Project Directory

```bash
git clone https://github.com/RoboticsHardwareSolutions/baremetal-ci-docker.git
cd baremetal-ci-docker
```

### 2. Create Environment Configuration

Copy the example environment file and fill in your details:

```bash
cp .env.example .env
```

Edit `.env` and set:

**For GitHub Actions (`CI_PLATFORM=github`):**

```bash
# Platform selection
CI_PLATFORM=github

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

**For GitLab CI (`CI_PLATFORM=gitlab`):**

See [README.gitlab.md](README.gitlab.md) for GitLab-specific configuration.

### 3. Build and Run

```bash
docker-compose up -d
```

The container will automatically start the appropriate runner based on your `CI_PLATFORM` setting.

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

## PEAK CAN Support (SocketCAN)

The container automatically configures PEAK CAN USB devices as SocketCAN interfaces on startup. This provides a standard Linux CAN interface for testing.

### Automatic Configuration

When the container starts, it will:
1. Detect PEAK CAN USB devices (vendor ID 0x0c72)
2. Load required kernel modules (`peak_usb`, `can`, `can_raw`)
3. Configure the CAN interface with the baudrate from `PCAN_BAUDRATE` (default: 125000 bps)
4. Bring up the `can0` interface automatically

### Using CAN in CI Workflows

**Example GitHub Actions workflow:**

```yaml
name: CAN Bus Testing

on: [push, pull_request]

jobs:
  can-test:
    runs-on: [self-hosted, baremetal, socketcan]
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Check CAN interface
        run: |
          ip -details link show can0
          # Should show: bitrate 125000 sample-point 0.875
      
      - name: Monitor CAN traffic
        run: |
          # Start monitoring in background
          candump can0 > can_traffic.log &
          CANDUMP_PID=$!
          
          # Your CAN test commands here
          sleep 5
          
          # Stop monitoring
          kill $CANDUMP_PID
          cat can_traffic.log
      
      - name: Send CAN message
        run: |
          # Send a CAN message (ID 0x123, 8 bytes of data)
          cansend can0 123#1122334455667788
      
      - name: Python CAN example
        run: |
          python3 << 'EOF'
          import can
          
          # Open CAN bus
          bus = can.Bus(interface='socketcan', channel='can0')
          
          # Send message
          msg = can.Message(arbitration_id=0x123,
                          data=[0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88],
                          is_extended_id=False)
          bus.send(msg)
          print(f"Sent: {msg}")
          
          # Receive message (with timeout)
          msg = bus.recv(timeout=1.0)
          if msg:
              print(f"Received: {msg}")
          
          bus.shutdown()
          EOF
```

**Example GitLab CI pipeline:**

```yaml
test_can_communication:
  tags:
    - baremetal
    - socketcan
  script:
    - ip -details link show can0
    - candump can0 &
    - sleep 1
    - cansend can0 123#DEADBEEF
    - pkill candump
```

### Reconfiguring CAN Baudrate

You can change the CAN baudrate during CI execution:

```bash
# Stop the interface
sudo ip link set can0 down

# Change baudrate (e.g., to 500 kbit/s)
sudo ip link set can0 type can bitrate 500000

# Bring interface back up
sudo ip link set can0 up

# Verify
ip -details link show can0
```

**Common baudrates:**
- 125000 (125 kbit/s) - default
- 250000 (250 kbit/s)
- 500000 (500 kbit/s)
- 1000000 (1 Mbit/s)

### Available CAN Utilities

The container includes `can-utils` package with:

- `candump` - Display CAN messages
- `cansend` - Send single CAN messages
- `cangen` - Generate random CAN traffic
- `cansequence` - Send and check sequence of CAN messages
- `cansniffer` - Interactive CAN traffic analyzer
- `canplayer` - Replay CAN log files
- `canlogger` - Log CAN traffic to file

### Troubleshooting CAN

**CAN interface not appearing:**

1. Check if PEAK CAN device is connected:
   ```bash
   docker exec baremetal-ci-runner lsusb | grep 0c72
   ```

2. Load `peak_usb` module on host:
   ```bash
   sudo modprobe peak_usb
   ```

3. Check container logs:
   ```bash
   docker-compose logs | grep -i can
   ```

**Permission denied errors:**

The container runs with limited sudo access. Only these commands are allowed:
- `sudo ip` - for managing CAN interfaces
- `sudo modprobe` - for loading kernel modules
- `sudo chown` - for file permissions

## Configuration Options

### Environment Variables

All configuration is done in the `.env` file. Copy `.env.example` to `.env` and configure:

#### Platform Selection

| Variable | Required | Description | Default |
|----------|----------|-------------|---------|
| `CI_PLATFORM` | Yes | CI platform to use: `github` or `gitlab` | `github` |

#### GitHub Actions Configuration (when `CI_PLATFORM=github`)

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `GITHUB_TOKEN` | Conditional* | GitHub Personal Access Token with `repo` and `admin:org` permissions. Generate at [GitHub Settings](https://github.com/settings/tokens) | `ghp_xxxxxxxxxxxx` |
| `GITHUB_REGISTRATION_TOKEN` | Conditional* | Direct registration token (expires in 1 hour). Get from organization or repo runner settings | `ALNAPSP4xxxx` |
| `GITHUB_OWNER` | Conditional** | Organization name for org-level runner | `your-org-name` |
| `GITHUB_REPOSITORY` | Conditional** | Repository in format `owner/repo` for repo-level runner | `owner/repo-name` |
| `RUNNER_NAME` | No | Runner name shown in GitHub | `baremetal-ci-runner` |
| `RUNNER_LABELS` | No | Comma-separated labels for workflow targeting | `baremetal,jlink,mcu` |
| `RUNNER_GROUP` | No | Runner group (org runners only) | `default` |

*Either `GITHUB_TOKEN` or `GITHUB_REGISTRATION_TOKEN` is required  
**Either `GITHUB_OWNER` (org-level) or `GITHUB_REPOSITORY` (repo-level) is required

#### GitLab CI Configuration (when `CI_PLATFORM=gitlab`)

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `GITLAB_URL` | No | GitLab instance URL | `https://gitlab.com` |
| `GITLAB_REGISTRATION_TOKEN` | Yes | Registration token from project/group/instance settings | `GR1348941xxxx` |
| `RUNNER_NAME` | No | Runner name shown in GitLab | `baremetal-ci-runner` |
| `RUNNER_TAGS` | No | Comma-separated tags for job targeting | `baremetal,jlink,mcu` |
| `RUNNER_EXECUTOR` | No | Executor type (use `shell` for hardware testing) | `shell` |

**Getting GitLab Registration Token:**
- **Project**: Settings → CI/CD → Runners → Specific runners
- **Group**: Settings → CI/CD → Runners
- **Instance**: Admin Area → Overview → Runners

#### Common Configuration (both platforms)

| Variable | Required | Description | Example |
|----------|----------|-------------|---------|
| `CONTAINER_NAME` | No | Unique container name (change if cloning repo multiple times) | `baremetal-ci-runner-1` |
| `ENABLE_JLINK` | No | Install Segger J-Link software (`true`/`false`) | `false` |
| `PCAN_BAUDRATE` | No | CAN bus baudrate in bits/second for PEAK CAN device | `125000` |
| `ADDITIONAL_PACKAGES` | No | Space-separated apt packages to install during build | `gdb-multiarch openocd` |

## Troubleshooting

### Runner Not Appearing in GitHub

1. Check the container logs: `docker-compose logs -f`
2. Verify your `GITHUB_TOKEN` has correct permissions
3. Ensure the token hasn't expired

### J-Link Device Not Detected

1. Check if the device is connected: `lsusb | grep 1366`
2. Verify USB passthrough: `docker exec baremetal-ci-runner lsusb`
3. Check container privileges: ensure `privileged: true` in docker-compose.yml
4. Verify udev rules are loaded on host:
   ```bash
   sudo udevadm control --reload-rules && sudo udevadm trigger
   ```

### Permission Issues with USB Devices

The container runs in privileged mode and should have access to all USB devices. If issues persist:

1. Check host udev rules: `/etc/udev/rules.d/99-jlink.rules`
2. Reload udev rules: `sudo udevadm control --reload-rules && sudo udevadm trigger`
3. Verify the runner user has proper permissions inside the container

## Maintenance

### Stopping the Runner

```bash
docker-compose down
```

The runner will automatically unregister from GitHub on shutdown.

### Updating the Runner

```bash
docker-compose down
docker-compose build --no-cache
docker-compose up -d
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
