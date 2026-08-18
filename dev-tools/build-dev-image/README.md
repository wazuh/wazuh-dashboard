# Wazuh Dashboard Development Images

This directory contains tools and scripts for building Docker images for the Wazuh Dashboard development environment.

For the `4.14.x` line, the image bundles only the three repositories this version actually uses:

- `wazuh-dashboard` (base)
- `wazuh-security-dashboards-plugin`
- `wazuh-dashboard-plugins`

## Files Overview

- **build-multiarch.sh**: Multi-architecture build script (AMD64 and ARM64)
- **wzd.dockerfile**: Dockerfile for building the development environment
- **install-plugins.sh**: Script that installs Wazuh plugins during build
- **entrypoint.sh**: Container startup script
- **plugins**: List of plugin repositories to clone
- **README.md**: This documentation

## Quick Start

### Using the Multi-Architecture Script (Recommended)

Requirements:

- `buildx` plugin: https://github.com/docker/buildx
- QEMU (for arch emulation builds)

```bash
# Make the script executable
chmod +x build-multiarch.sh

# Build with default values (local only)
./build-multiarch.sh

# Build and push to registry
./build-multiarch.sh --push

# Build with custom branches
./build-multiarch.sh -w 4.14.8 -s 4.14.8 -p 4.14.8 --tag 4.14.8 --push
```

### Manual Docker Build

```bash
docker build \
  --build-arg NODE_VERSION=18.19.0 \
  --build-arg WAZUH_DASHBOARD_BRANCH=4.14.8 \
  --build-arg WAZUH_DASHBOARD_SECURITY_BRANCH=4.14.8 \
  --build-arg WAZUH_DASHBOARD_PLUGINS_BRANCH=4.14.8 \
  -t quay.io/wazuh/osd-dev:4.14.8 \
  -f wzd.dockerfile .
```

## Multi-Architecture Build Script

The `build-multiarch.sh` script simplifies building images for both AMD64 and ARM64 architectures.

### Script Options

| Option              | Short | Description                      | Default                   |
| ------------------- | ----- | --------------------------------- | -------------------------- |
| `--node-version`    | `-n`  | Node.js version                   | `18.19.0`                  |
| `--wazuh-branch`    | `-w`  | Wazuh Dashboard branch            | `4.14.8`                   |
| `--security-branch` | `-s`  | Wazuh Dashboard Security branch   | `4.14.8`                   |
| `--plugins-branch`  | `-p`  | Wazuh Dashboard Plugins branch    | `4.14.8`                   |
| `--tag`             | `-t`  | Docker image tag                  | `4.14.8`                   |
| `--platform`        | `-pl` | Target platform (architecture)    | `linux/amd64,linux/arm64`  |
| `--push`            |       | Push image to registry            | `false` (local build)      |
| `--help`            | `-h`  | Show help message                 |                            |

### Examples

```bash
# Development build with a specific branch
./build-multiarch.sh --wazuh-branch 4.14.8 --tag latest

# All branches from a feature branch
./build-multiarch.sh -w feature/my-feature -s feature/my-feature -p feature/my-feature --tag feature-test

# Specific version build and push
./build-multiarch.sh --node-version 18.19.0 --tag 4.14.8 --push
```

## Manual Docker Commands

### Single Architecture Build

```bash
# For ARM64 (if you're on AMD64)
docker build --platform linux/arm64 \
  --build-arg NODE_VERSION=18.19.0 \
  --build-arg WAZUH_DASHBOARD_BRANCH=4.14.8 \
  -t quay.io/wazuh/osd-dev:4.14.8-arm64 \
  -f wzd.dockerfile .

# For AMD64 (if you're on ARM64)
docker build --platform linux/amd64 \
  --build-arg NODE_VERSION=18.19.0 \
  --build-arg WAZUH_DASHBOARD_BRANCH=4.14.8 \
  -t quay.io/wazuh/osd-dev:4.14.8-amd64 \
  -f wzd.dockerfile .
```

### Multi-Architecture Manual Build

```bash
# Create builder
docker buildx create --use --name multiarch

# Build for multiple platforms
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg NODE_VERSION=18.19.0 \
  --build-arg WAZUH_DASHBOARD_BRANCH=4.14.8 \
  -t quay.io/wazuh/osd-dev:4.14.8 \
  -f wzd.dockerfile \
  --push .
```

## Registry Setup

### Setting up Quay.io Credentials (One-time setup)

1. Login to Quay.io and navigate to User Settings
2. Click on `CLI Password: Generate Encrypted Password`
3. In the new window that opens, click on `Docker Configuration` and follow the steps

### Authentication

```bash
# Login to Quay.io
docker login quay.io
```

### Push Images

```bash
# Push single image
docker push quay.io/wazuh/osd-dev:version

# Multi-arch images are pushed automatically with --push flag in buildx
```

## Build Arguments

- **NODE_VERSION**: Node.js runtime version (check `.nvmrc` file for compatibility)
- **WAZUH_DASHBOARD_BRANCH**: `wazuh-dashboard` repository branch
- **WAZUH_DASHBOARD_SECURITY_BRANCH**: `wazuh-security-dashboards-plugin` branch
- **WAZUH_DASHBOARD_PLUGINS_BRANCH**: `wazuh-dashboard-plugins` branch

## What the Image Contains

The built image includes:

- Node.js runtime environment
- Wazuh Dashboard with the specified branch
- The Wazuh security plugin and the core Wazuh plugins (from `wazuh-dashboard-plugins`)
- Development dependencies
- Configured workspace at `/home/node/kbn`

## Usage

### Running the Container

```bash
# Run development server
docker run -it --rm \
  -p 5601:5601 \
  quay.io/wazuh/osd-dev:4.14.8

# Run with volume mounting for development
docker run -it --rm \
  -p 5601:5601 \
  -v $(pwd):/workspace \
  quay.io/wazuh/osd-dev:4.14.8
```

### Multi-Platform Support

When you pull the image, Docker automatically downloads the correct architecture:

```bash
# This works on both AMD64 and ARM64
docker pull quay.io/wazuh/osd-dev:4.14.8
```

## Troubleshooting

### Builder Issues

```bash
# Remove and recreate builder
docker buildx rm multiarch
docker buildx create --use --name multiarch
```

### Platform Support Check

```bash
# Check available platforms
docker buildx inspect multiarch
```

### Node Version Compatibility

Always check the `.nvmrc` file in the target branch to ensure Node.js version compatibility.

## Development Workflow

1. **Feature Development**: Build with a feature branch for testing
2. **Integration Testing**: Build with `4.14.8` (or the relevant patch/minor branch)
3. **Release Preparation**: Build with release branches and push to registry

Example workflow:

```bash
# Feature development
./build-multiarch.sh --wazuh-branch feature/my-feature --tag feature-test

# Integration testing
./build-multiarch.sh -w 4.14.8 -s 4.14.8 -p 4.14.8 --tag 2.19.6

# Release candidate
./build-multiarch.sh -w migrate-4.14.8-to-2.19.6 -s migrate-4.14.8-to-2.19.6.0 -p migrate-4.14.8-to-2.19.6 --tag 2.19.6 --push
```
