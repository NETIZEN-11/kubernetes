#!/bin/bash

# Local Node E2E Test Runner - Addresses GitHub issue #137722
# Easy way to run Kubernetes node e2e tests locally using Docker

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
FOCUS=""
SKIP="\[Flaky\]|\[Slow\]|\[Serial\]"
PARALLELISM=1
TEST_ARGS=""

# Functions
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Local Node E2E Test Runner - Addresses GitHub issue #137722

OPTIONS:
    -f, --focus FOCUS        Regexp for tests to run (default: all)
    -s, --skip SKIP         Regexp for tests to skip (default: [Flaky]|[Slow]|[Serial])
    -p, --parallelism NUM    Number of parallel tests (default: 1)
    --test-args ARGS         Additional test arguments
    -h, --help             Show help

EXAMPLES:
    $0                                    # Run all tests
    $0 --focus "Kubelet"              # Run specific tests
    $0 --parallelism 4                   # Run in parallel
    $0 --test-args "--prepull-images=false"  # Custom args

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--focus) FOCUS="$2"; shift 2 ;;
        -s|--skip) SKIP="$2"; shift 2 ;;
        -p|--parallelism) PARALLELISM="$2"; shift 2 ;;
        --test-args) TEST_ARGS="$2"; shift 2 ;;
        -h|--help) show_usage; exit 0 ;;
        *) print_error "Unknown option: $1"; show_usage; exit 1 ;;
    esac
done

# Check Docker
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed"
    exit 1
fi

if ! docker info &> /dev/null; then
    print_error "Docker daemon is not running"
    exit 1
fi

# Change to k8s root
cd "$(dirname "$0")/../.."
KUBE_ROOT=$(pwd)

print_status "Building Docker image..."
docker build -t k8s-node-e2e-local -f test/e2e_node/local/Dockerfile .

if [ $? -ne 0 ]; then
    print_error "Failed to build Docker image"
    exit 1
fi

print_success "Docker image built successfully"

# Prepare test command
TEST_CMD="make test-e2e-node REMOTE=false"
TEST_CMD="$TEST_CMD FOCUS=\"$FOCUS\""
TEST_CMD="$TEST_CMD SKIP=\"$SKIP\""
TEST_CMD="$TEST_CMD PARALLELISM=$PARALLELISM"

if [ -n "$TEST_ARGS" ]; then
    TEST_CMD="$TEST_CMD TEST_ARGS=\"$TEST_ARGS\""
fi

print_status "Running node e2e tests..."
print_status "Command: $TEST_CMD"

# Run tests in Docker container
docker run --rm \
    --privileged \
    --network host \
    --pid host \
    -v "$KUBE_ROOT:/kubernetes:rw" \
    -v /tmp:/tmp:rw \
    -v /var/lib/containerd:/var/lib/containerd:rw \
    -v /var/lib/kubelet:/var/lib/kubelet:rw \
    -v /run/containerd:/run/containerd:rw \
    -e FOCUS="$FOCUS" \
    -e SKIP="$SKIP" \
    -e PARALLELISM="$PARALLELISM" \
    -e TEST_ARGS="$TEST_ARGS" \
    k8s-node-e2e-local \
    bash -c "cd /kubernetes && $TEST_CMD"

TEST_EXIT_CODE=$?

if [ $TEST_EXIT_CODE -eq 0 ]; then
    print_success "All tests passed!"
else
    print_error "Tests failed with exit code: $TEST_EXIT_CODE"
fi

exit $TEST_EXIT_CODE
