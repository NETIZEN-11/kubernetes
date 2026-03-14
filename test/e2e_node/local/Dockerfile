# Local Node E2E Testing Docker Image
# Simplified container for running Kubernetes node e2e tests locally
# Addresses GitHub issue #137722

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV CONTAINERD_VERSION=1.7.18
ENV CNI_PLUGINS_VERSION=1.4.0

# Install essential dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    wget \
    iptables \
    socat \
    conntrack \
    ebtables \
    iproute2 \
    tar \
    systemd \
    && rm -rf /var/lib/apt/lists/*

# Install containerd
RUN wget -O containerd.tar.gz "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz" \
    && tar -C /usr/local -xzf containerd.tar.gz \
    && rm containerd.tar.gz

# Install CNI plugins
RUN wget -O cni-plugins.tgz "https://github.com/containernetworking/plugins/releases/download/v${CNI_PLUGINS_VERSION}/cni-plugins-linux-amd64-v${CNI_PLUGINS_VERSION}.tgz" \
    && mkdir -p /opt/cni/bin \
    && tar -C /opt/cni/bin -xzf cni-plugins.tgz \
    && rm cni-plugins.tgz

# Create containerd config directory
RUN mkdir -p /etc/containerd

# Create minimal containerd configuration
RUN cat > /etc/containerd/config.toml << 'EOF'
version = 2

[plugins]
  [plugins."io.containerd.grpc.v1.cri"]
    sandbox_image = "registry.k8s.io/pause:3.9"
    
    [plugins."io.containerd.grpc.v1.cri".containerd]
      snapshotter = "overlayfs"
      
    [plugins."io.containerd.grpc.v1.cri".cni]
      bin_dir = "/opt/cni/bin"
      conf_dir = "/etc/cni/net.d"

  [plugins."io.containerd.grpc.v1.cri".registry]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
        endpoint = ["https://registry-1.docker.io"]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io"]
        endpoint = ["https://registry.k8s.io"]
EOF

# Create systemd service for containerd
RUN cat > /etc/systemd/system/containerd.service << 'EOF'
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/usr/local/bin/containerd
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF

# Create test directory and entrypoint
WORKDIR /kubernetes

RUN cat > /entrypoint.sh << 'EOF'
#!/bin/bash
set -e

echo "Starting containerd..."
systemctl daemon-reload
systemctl enable containerd
systemctl start containerd

# Wait for containerd to be ready
echo "Waiting for containerd to be ready..."
for i in {1..30}; do
    if ctr version >/dev/null 2>&1; then
        echo "containerd is ready"
        break
    fi
    echo "Waiting for containerd... ($i/30)"
    sleep 2
done

echo "Environment ready for node e2e tests"
exec "$@"
EOF

RUN chmod +x /entrypoint.sh

EXPOSE 8080 10250

ENTRYPOINT ["/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
