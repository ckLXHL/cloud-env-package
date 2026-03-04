# L2: Docker-in-Docker / Podman 服务镜像
# 包含：Docker CE / Podman / nerdctl + containerd
# 继承自 L1 toolchain-common
ARG REGISTRY=ghcr.io/ckLXHL
ARG COMMON_VERSION=2.0
FROM ${REGISTRY}/toolchain-common:${COMMON_VERSION}

ARG DOCKER_VERSION=25.0
ARG PODMAN_VERSION=4.9

LABEL org.opencontainers.image.title="services-docker" \
      org.opencontainers.image.description="Docker CE ${DOCKER_VERSION} / Podman ${PODMAN_VERSION} container runtime" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package"

# 安装 Podman（无守护进程，无需 root，优先推荐）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        podman \
        buildah \
        skopeo \
        # 容器网络工具
        containernetworking-plugins \
        uidmap \
        slirp4netns \
        fuse-overlayfs \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 安装 Docker CE（使用阿里云镜像源）
RUN set -eux; \
    # 添加 Docker 阿里云 GPG key
    curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | \
        gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg; \
    # 添加 Docker 阿里云源
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
        https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
        $(lsb_release -cs) stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 配置 Docker 使用国内镜像加速
RUN mkdir -p /etc/docker && cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://registry.cn-hangzhou.aliyuncs.com",
    "https://mirror.ccs.tencentyun.com",
    "https://hub-mirror.c.163.com"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF

# 配置 Podman 使用国内镜像加速
RUN mkdir -p /etc/containers && cat > /etc/containers/registries.conf <<'EOF'
unqualified-search-registries = ["docker.io", "ghcr.io"]

[[registry]]
prefix = "docker.io"
insecure = false
blocked = false
location = "registry.cn-hangzhou.aliyuncs.com"

[[registry.mirror]]
location = "registry.cn-hangzhou.aliyuncs.com"
EOF

# 安装 nerdctl（Docker 兼容的 containerd CLI）
RUN set -eux; \
    ARCH=$(dpkg --print-architecture); \
    NERDCTL_VERSION="1.7.6"; \
    case "${ARCH}" in \
        amd64) NERDCTL_ARCH="amd64" ;; \
        arm64) NERDCTL_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/containerd/nerdctl/releases/download/v${NERDCTL_VERSION}/nerdctl-${NERDCTL_VERSION}-linux-${NERDCTL_ARCH}.tar.gz" \
        -o /tmp/nerdctl.tar.gz; \
    tar -xzf /tmp/nerdctl.tar.gz -C /usr/local/bin/; \
    rm -f /tmp/nerdctl.tar.gz; \
    nerdctl --version

# DinD (Docker-in-Docker) 初始化脚本
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

VOLUME /var/lib/docker

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/bin/bash"]
