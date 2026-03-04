# L1: Python 工具链镜像
# 包含：Python + uv + pip + 常用科学计算包（离线预置）
# 继承自 L0 base-ubuntu
ARG REGISTRY=ghcr.io/ckLXHL
ARG BASE_VERSION=22.04
FROM ${REGISTRY}/base-ubuntu:${BASE_VERSION}

ARG PYTHON_VERSION=3.12
ARG UV_VERSION=0.4.0

LABEL org.opencontainers.image.title="toolchain-python" \
      org.opencontainers.image.description="Python ${PYTHON_VERSION} + uv ${UV_VERSION} toolchain with CN mirrors" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package"

# 安装 Python 依赖
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        python3-setuptools \
        python3-wheel \
        # 构建依赖（编译 C 扩展需要）
        build-essential \
        libffi-dev \
        libssl-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        libncurses5-dev \
        libncursesw5-dev \
        zlib1g-dev \
        liblzma-dev \
        # 工具
        git \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 创建 python/python3 软链
RUN ln -sf /usr/bin/python3 /usr/bin/python

# 配置 pip 使用阿里云镜像源
RUN mkdir -p /root/.pip && cat > /root/.pip/pip.conf <<'EOF'
[global]
index-url = https://mirrors.aliyun.com/pypi/simple/
trusted-host = mirrors.aliyun.com
timeout = 60

[install]
trusted-host = mirrors.aliyun.com
EOF

# 升级 pip
RUN pip install --no-cache-dir --upgrade pip setuptools wheel

# 安装 uv（快速 Python 包管理器）
RUN set -eux; \
    pip install --no-cache-dir "uv==${UV_VERSION}" \
    || pip install --no-cache-dir uv

# 配置 uv 使用阿里云镜像源
ENV UV_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/ \
    UV_TRUSTED_HOST=mirrors.aliyun.com

# 预装常用 Python 包（离线预置，减少目标机网络需求）
RUN pip install --no-cache-dir \
    # 科学计算
    numpy \
    pandas \
    scipy \
    matplotlib \
    # 工具类
    requests \
    pyyaml \
    toml \
    click \
    rich \
    tqdm \
    # 开发工具
    ipython \
    pytest \
    black \
    ruff \
    mypy \
    # 异步
    aiohttp \
    httpx

# 验证安装
RUN python --version && pip --version && uv --version

WORKDIR /workspace

CMD ["/bin/bash"]
