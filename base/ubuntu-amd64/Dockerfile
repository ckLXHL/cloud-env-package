# L0: Ubuntu 22.04 amd64 基础镜像
# 包含：最小系统 + 国内源 + CA证书 + 基础工具
ARG UBUNTU_VERSION=22.04
FROM ubuntu:${UBUNTU_VERSION} AS base

ARG UBUNTU_VERSION=22.04

LABEL org.opencontainers.image.title="base-ubuntu-amd64" \
      org.opencontainers.image.description="Ubuntu ${UBUNTU_VERSION} amd64 base image with CN mirrors" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package" \
      org.opencontainers.image.version="${UBUNTU_VERSION}" \
      org.opencontainers.image.architecture="amd64"

# 替换为阿里云镜像源，避免访问官方源超时
RUN set -eux; \
    # 备份原始 sources.list
    cp /etc/apt/sources.list /etc/apt/sources.list.bak; \
    # 替换为阿里云镜像源
    cat > /etc/apt/sources.list <<'EOF'
deb https://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
EOF

# 安装基础依赖、CA证书和常用工具
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        # CA 证书
        ca-certificates \
        # 网络工具
        curl \
        wget \
        # 基础工具
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        # 文本处理
        locales \
        tzdata \
        # 压缩/解压工具（包含 zstd）
        gzip \
        bzip2 \
        xz-utils \
        zstd \
        unzip \
        zip \
    ; \
    # 清理 apt 缓存，减小镜像体积
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 设置中文时区
RUN ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && dpkg-reconfigure -f noninteractive tzdata

# 设置 locale
RUN locale-gen en_US.UTF-8 zh_CN.UTF-8 \
    && update-locale LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# 禁用交互式 apt 提示
ENV DEBIAN_FRONTEND=noninteractive

CMD ["/bin/bash"]
