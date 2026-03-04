# L0: 麒麟 V10 arm64 基础镜像
# 基于 Ubuntu 22.04 arm64，模拟麒麟V10兼容环境
# 注：麒麟官方镜像需授权，此处使用 Ubuntu arm64 作为基础并替换源
ARG KYLIN_VERSION=v10
FROM ubuntu:22.04 AS base

ARG KYLIN_VERSION=v10

LABEL org.opencontainers.image.title="base-kylin-arm64" \
      org.opencontainers.image.description="Kylin ${KYLIN_VERSION} arm64 compatible base image" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package" \
      org.opencontainers.image.version="${KYLIN_VERSION}" \
      org.opencontainers.image.architecture="arm64"

# 配置国内镜像源（麒麟 V10 基于 Ubuntu 20.04/22.04，使用 ubuntu-ports 镜像）
RUN set -eux; \
    cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true; \
    cat > /etc/apt/sources.list <<'EOF'
deb https://mirrors.aliyun.com/ubuntu-ports/ jammy main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu-ports/ jammy-updates main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu-ports/ jammy-backports main restricted universe multiverse
deb https://mirrors.aliyun.com/ubuntu-ports/ jammy-security main restricted universe multiverse
EOF

# 安装基础工具
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https \
        locales \
        tzdata \
        gzip \
        bzip2 \
        xz-utils \
        zstd \
        unzip \
        zip \
        # 麒麟环境兼容工具
        libstdc++6 \
        libc6 \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 设置中文时区（麒麟系统默认中文环境）
RUN ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && dpkg-reconfigure -f noninteractive tzdata

# 设置中文 locale
RUN locale-gen zh_CN.UTF-8 en_US.UTF-8 \
    && update-locale LANG=zh_CN.UTF-8
ENV LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN:zh \
    LC_ALL=zh_CN.UTF-8

# 标识为麒麟兼容环境
ENV KYLIN_COMPAT=true \
    KYLIN_VERSION=${KYLIN_VERSION} \
    DEBIAN_FRONTEND=noninteractive

CMD ["/bin/bash"]
