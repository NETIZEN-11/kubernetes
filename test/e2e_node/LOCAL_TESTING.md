# Local Node E2E Testing

This document provides instructions for running Kubernetes node e2e tests locally without requiring GCP setup or complex infrastructure.

## Overview

The local node e2e testing setup provides a containerized environment that reuses the containerd CI approach for local development. This makes it much easier to run node e2e tests without the pain of setting up cloud infrastructure.

## Prerequisites

- Docker (latest version)
- Docker Compose
- Git
- At least 4GB RAM available
- Linux or macOS (Windows with WSL2 supported)

## Quick Start

### Option 1: Using the Convenience Script (Recommended)

```bash
# Clone the Kubernetes repository
git clone https://github.com/kubernetes/kubernetes.git
cd kubernetes

# Run all node e2e tests
./test/e2e_node/local/run-local-e2e.sh

# Run specific tests
./test/e2e_node/local/run-local-e2e.sh --focus "Kubelet"

# Run tests in parallel
./test/e2e_node/local/run-local-e2e.sh --parallelism 4

# Run with custom test arguments
./test/e2e_node/local/run-local-e2e.sh --test-args "--prepull-images=false"
```

### Option 2: Using Docker Compose Directly

```bash
# Build and start the test environment
cd test/e2e_node/local
docker-compose up -d

# Run tests in the container
docker-compose exec node-e2e bash -c "
  cd /kubernetes
  make test-e2e-node REMOTE=false FOCUS='Kubelet' PARALLELISM=2
"

# View logs
docker-compose logs -f

# Clean up
docker-compose down
```

### Option 3: Using the Makefile Target

```bash
# Run tests using the new make target
make test-e2e-node-local

# With custom options
make test-e2e-node-local FOCUS="Kubelet" PARALLELISM=4
```

## Configuration Options

### Environment Variables

- `CONTAINER_RUNTIME_ENDPOINT`: Container runtime endpoint (default: `unix:///run/containerd/containerd.sock`)
- `IMAGE_SERVICE_ENDPOINT`: Image service endpoint (default: same as container runtime)
- `KUBELET_CONFIG_FILE`: Path to kubelet configuration file
- `FOCUS`: Regexp pattern for tests to run
- `SKIP`: Regexp pattern for tests to skip (default: `[Flaky]|[Slow]|[Serial]`)
- `PARALLELISM`: Number of parallel tests (default: 1)
- `ARTIFACTS`: Directory to store test artifacts

### Test Arguments

Common test arguments you might want to use:

```bash
# Skip prepulling images for faster tests
--test-args="--prepull-images=false"

# Use custom kubelet flags
--test-args="--kubelet-flags='--feature-gates=ExampleFeature=true'"

# Run with specific system spec
--system-spec-name="gke"

# Custom timeout
--test-timeout="60m"
```

## Troubleshooting

### Common Issues

1. **Permission Denied Errors**
   ```bash
   # Ensure Docker daemon is running and you have permissions
   sudo usermod -aG docker $USER
   # Log out and log back in
   ```

2. **Container Runtime Connection Issues**
   ```bash
   # Check if containerd is running
   docker-compose exec node-e2e ctr version
   
   # Restart containerd if needed
   docker-compose exec node-e2e systemctl restart containerd
   ```

3. **Build Failures**
   ```bash
   # Clean build artifacts
   docker-compose exec node-e2e make clean
   
   # Rebuild dependencies
   docker-compose exec node-e2e make WHAT=cmd/kubelet
   ```

4. **Test Timeouts**
   ```bash
   # Increase timeout
   ./test/e2e_node/local/run-local-e2e.sh --test-args "--test-timeout=120m"
   
   # Reduce parallelism
   ./test/e2e_node/local/run-local-e2e.sh --parallelism 1
   ```

### Debug Mode

For debugging test failures, you can:

```bash
# Run with verbose logging
./test/e2e_node/local/run-local-e2e.sh --test-args="--v=4"

# Run a single test in debug mode
./test/e2e_node/local/run-local-e2e.sh --focus "SpecificTestName" --parallelism 1

# Access the container directly for debugging
docker-compose exec node-e2e bash
```

## Advanced Usage

### Custom Container Runtime

The setup supports both containerd and Docker as container runtimes:

```bash
# Use Docker instead of containerd
export CONTAINER_RUNTIME_ENDPOINT="unix:///var/run/docker.sock"
export IMAGE_SERVICE_ENDPOINT="unix:///var/run/docker.sock"
./test/e2e_node/local/run-local-e2e.sh
```

### Custom System Specifications

You can use different system specifications for testing:

```bash
# Use GKE system spec
./test/e2e_node/local/run-local-e2e.sh --system-spec-name="gke"

# Use custom system spec file
./test/e2e_node/local/run-local-e2e.sh --system-spec-name="custom" \
  --system-spec-file="/path/to/custom/spec.yaml"
```

### Integration with IDEs

For IDE integration, you can set up the environment:

1. **VS Code**: Use the Docker extension to attach to the container
2. **GoLand**: Configure Docker Compose as a remote interpreter
3. **Vim/Neovim**: Use `docker-compose exec` for remote development

## CI/CD Integration

The GitHub Actions workflow (`.github/workflows/node-e2e-local.yml`) demonstrates how to integrate local node e2e testing into CI/CD pipelines:

- Runs tests on both containerd and Docker
- Supports manual triggering with custom parameters
- Uploads test artifacts and logs
- Uses matrix strategy for different configurations

## Performance Tips

1. **Use Local Registry**: Set up a local Docker registry to avoid image pulls
2. **Cache Build Artifacts**: Mount a volume for build cache
3. **Parallel Execution**: Use appropriate parallelism based on your hardware
4. **Skip Prepulling**: Use `--prepull-images=false` for faster test startup

## Contributing

When contributing to the node e2e testing setup:

1. Test your changes with the local setup
2. Update this documentation if you add new features
3. Ensure Docker images build successfully
4. Test on multiple platforms if possible

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Look at the GitHub Actions workflow for reference
3. Search existing issues in the Kubernetes repository
4. File a new issue with detailed logs and system information

## Related Documentation

- [Kubernetes E2E Testing Guide](https://git.k8s.io/community/contributors/devel/sig-testing/e2e-tests.md)
- [Node E2E Tests](https://git.k8s.io/community/contributors/devel/sig-node/e2e-node-tests.md)
- [Container Runtime Interface (CRI)](https://github.com/kubernetes/cri-api)
