#!/bin/bash

# Helper script to run docker-compose with the correct configuration
# Detects the OS and uses appropriate compose files

set -e

# Detect operating system
OS="$(uname -s)"

case "${OS}" in
    Linux*)
        echo "Detected Linux - using standard configuration"
        docker-compose "$@"
        ;;
    Darwin*)
        echo "Detected macOS - using macOS-specific configuration"
        docker-compose -f docker-compose.yml -f docker-compose.macos.yml "$@"
        ;;
    *)
        echo "Unknown OS: ${OS}"
        echo "Falling back to standard configuration"
        docker-compose "$@"
        ;;
esac
