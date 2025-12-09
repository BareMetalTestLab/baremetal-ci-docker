# Docker container for baremetal MCU CI testing with GitHub Actions runner and Segger J-Link
FROM ubuntu:24.04

# Build argument to select CI platform (passed from docker-compose.yml via .env)
# Must be 'github' or 'gitlab'
# Note: Using RUNNER_PLATFORM instead of CI_PLATFORM to avoid conflicts with
# GitLab CI predefined variables (CI_ prefix is reserved)
ARG RUNNER_PLATFORM
ARG ADDITIONAL_PACKAGES
ARG ENABLE_JLINK
ARG ENABLE_PEAKCAN

# Validate RUNNER_PLATFORM at build time
RUN if [ -z "${RUNNER_PLATFORM}" ]; then \
        echo "ERROR: RUNNER_PLATFORM is not set"; \
        echo "Please set RUNNER_PLATFORM in your .env file to 'github' or 'gitlab'"; \
        exit 1; \
    fi && \
    if [ "${RUNNER_PLATFORM}" != "github" ] && [ "${RUNNER_PLATFORM}" != "gitlab" ]; then \
        echo "ERROR: Invalid RUNNER_PLATFORM=${RUNNER_PLATFORM}"; \
        echo "RUNNER_PLATFORM must be 'github' or 'gitlab'"; \
        echo "Running both runners simultaneously is not supported"; \
        exit 1; \
    fi

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies and build tools
# Note: apt-get clean and cache removal in same RUN to reduce image size
RUN apt-get update && \
    apt-get install -y \
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
        usbutils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install additional packages if specified
RUN if [ "${ADDITIONAL_PACKAGES}" ]; then \
        apt-get update && \
        apt-get install -y ${ADDITIONAL_PACKAGES} && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    fi

# Install SocketCAN utilities (optional, controlled by ENABLE_PEAKCAN)
RUN if [ "${ENABLE_PEAKCAN}" = "true" ]; then \
        apt-get update && \
        apt-get install -y can-utils iproute2 && \
        apt-get clean && \
        rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    else \
        echo "Skipping SocketCAN utilities installation (ENABLE_PEAKCAN=${ENABLE_PEAKCAN})"; \
    fi

# Create a user for the GitHub runner (avoid running as root)
RUN useradd -m -s /bin/bash runner && \
    usermod -aG sudo runner && \
    echo "# Limited sudo access for CI runner" >> /etc/sudoers.d/runner && \
    echo "runner ALL=(ALL) NOPASSWD: /usr/sbin/ip" >> /etc/sudoers.d/runner && \
    echo "runner ALL=(ALL) NOPASSWD: /usr/sbin/modprobe" >> /etc/sudoers.d/runner && \
    echo "runner ALL=(ALL) NOPASSWD: /usr/bin/chown" >> /etc/sudoers.d/runner && \
    echo "runner ALL=(ALL) NOPASSWD: /usr/bin/find" >> /etc/sudoers.d/runner && \
    chmod 0440 /etc/sudoers.d/runner

# Workaround: J-Link postinstall script calls udevadm which doesn't work in Docker build
# Temporarily replace udevadm with a stub that does nothing
RUN if [ -f /bin/udevadm ]; then \
        mv /bin/udevadm /bin/udevadm.real; \
    fi && \
    echo '#!/bin/bash' > /bin/udevadm && \
    echo 'exit 0' >> /bin/udevadm && \
    chmod +x /bin/udevadm

# Install Segger J-Link Software (optional, controlled by ENABLE_JLINK)
# Note: CLI tools work without X11 dependencies (--force-depends ignores GUI deps)
# GUI tools (J-Link Configurator) won't work, but CLI (JLinkExe, JLinkGDBServer) will
WORKDIR /tmp
RUN if [ "${ENABLE_JLINK}" = "true" ]; then \
        ARCH=$(uname -m) && \
        JLINK_VERSION="V794e" && \
        if [ "$ARCH" = "x86_64" ]; then \
            wget --post-data "accept_license_agreement=accepted" \
            https://www.segger.com/downloads/jlink/JLink_Linux_${JLINK_VERSION}_x86_64.deb \
            -O JLink.deb && \
            dpkg --force-depends -i JLink.deb && \
            rm JLink.deb; \
        elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
            wget --post-data "accept_license_agreement=accepted" \
            https://www.segger.com/downloads/jlink/JLink_Linux_${JLINK_VERSION}_arm64.deb \
            -O JLink.deb && \
            dpkg --force-depends -i JLink.deb && \
            rm JLink.deb; \
        fi && \
        echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1366", MODE="0666"' > /etc/udev/rules.d/99-jlink.rules; \
    else \
        echo "Skipping J-Link installation (ENABLE_JLINK=${ENABLE_JLINK})"; \
    fi

# Restore real udevadm after J-Link installation
RUN if [ -f /bin/udevadm.real ]; then \
        rm /bin/udevadm && \
        mv /bin/udevadm.real /bin/udevadm; \
    fi

# Set up GitHub Actions runner directory
WORKDIR /home/runner
USER runner

# Download and extract GitHub Actions runner (only if CI_PLATFORM=github)
# The version should be updated to the latest available
# Automatically detect architecture and download appropriate version
RUN if [ "${CI_PLATFORM}" = "github" ]; then \
        RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//') && \
        ARCH=$(uname -m) && \
        if [ "$ARCH" = "x86_64" ]; then \
            RUNNER_ARCH="x64"; \
        elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
            RUNNER_ARCH="arm64"; \
        else \
            echo "Unsupported architecture: $ARCH" && exit 1; \
        fi && \
        curl -o actions-runner-linux.tar.gz -L \
        https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz && \
        tar xzf actions-runner-linux.tar.gz && \
        rm actions-runner-linux.tar.gz; \
    else \
        echo "Skipping GitHub Actions runner installation (CI_PLATFORM=${CI_PLATFORM})"; \
    fi

# Install GitLab Runner (only if CI_PLATFORM=gitlab)
USER root
RUN if [ "${CI_PLATFORM}" = "gitlab" ]; then \
        curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | bash && \
        apt-get download gitlab-runner && \
        dpkg --force-depends -i gitlab-runner_*.deb && \
        rm gitlab-runner_*.deb && \
        apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
        usermod -aG sudo gitlab-runner && \
        mkdir -p /home/runner/builds && \
        chown -R runner:runner /home/runner/builds && \
        mkdir -p /etc/gitlab-runner && \
        chown -R runner:runner /etc/gitlab-runner; \
    else \
        echo "Skipping GitLab Runner installation (CI_PLATFORM=${CI_PLATFORM})"; \
    fi
USER runner

# Skip runner dependencies installation to avoid X11 libraries
# The runner works without .NET dependencies for basic shell/script jobs

# Copy scripts directory and entrypoint
COPY --chown=runner:runner scripts/ /home/runner/scripts/
COPY --chown=runner:runner entrypoint.sh /home/runner/entrypoint.sh
RUN chmod +x /home/runner/entrypoint.sh && \
    chmod +x /home/runner/scripts/*.sh

# Set working directory
WORKDIR /home/runner

# Expose J-Link tools to PATH
ENV PATH="/opt/SEGGER/JLink:${PATH}"

# Entrypoint to configure and start the runner
ENTRYPOINT ["/home/runner/entrypoint.sh"]
