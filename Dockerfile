# Docker container for baremetal MCU CI testing with GitHub Actions runner and Segger J-Link
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    jq \
    sudo \
    tar \
    unzip \
    ca-certificates \
    libusb-1.0-0 \
    udev \
    && rm -rf /var/lib/apt/lists/*

# Create a user for the GitHub runner (avoid running as root)
RUN useradd -m -s /bin/bash runner && \
    usermod -aG sudo runner && \
    echo "runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Install Segger J-Link Software
# Download and install the latest J-Link Software
# Note: For macOS hosts, J-Link must be installed on the host system
WORKDIR /tmp
RUN ARCH=$(uname -m) && \
    JLINK_VERSION="V794e" && \
    if [ "$ARCH" = "x86_64" ]; then \
        wget --post-data "accept_license_agreement=accepted" \
        https://www.segger.com/downloads/jlink/JLink_Linux_${JLINK_VERSION}_x86_64.deb \
        -O JLink.deb && \
        dpkg -i JLink.deb || apt-get install -f -y && \
        rm JLink.deb; \
    elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        wget --post-data "accept_license_agreement=accepted" \
        https://www.segger.com/downloads/jlink/JLink_Linux_${JLINK_VERSION}_arm64.deb \
        -O JLink.deb && \
        dpkg -i JLink.deb || apt-get install -f -y && \
        rm JLink.deb; \
    fi

# Add udev rules for J-Link devices
RUN echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1366", MODE="0666"' > /etc/udev/rules.d/99-jlink.rules

# Set up GitHub Actions runner directory
WORKDIR /home/runner
USER runner

# Download and extract GitHub Actions runner
# The version should be updated to the latest available
RUN RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//') && \
    curl -o actions-runner-linux-x64.tar.gz -L \
    https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    tar xzf actions-runner-linux-x64.tar.gz && \
    rm actions-runner-linux-x64.tar.gz

# Install runner dependencies
RUN sudo ./bin/installdependencies.sh

# Copy the entrypoint script
COPY --chown=runner:runner entrypoint.sh /home/runner/entrypoint.sh
RUN chmod +x /home/runner/entrypoint.sh

# Set working directory
WORKDIR /home/runner

# Expose J-Link tools to PATH
ENV PATH="/opt/SEGGER/JLink:${PATH}"

# Entrypoint to configure and start the runner
ENTRYPOINT ["/home/runner/entrypoint.sh"]
