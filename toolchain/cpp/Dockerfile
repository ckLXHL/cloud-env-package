# L1: C++ 工具链镜像
# 包含：GCC / Clang / CMake / Ninja / ccache
# 继承自 L0 base-ubuntu
ARG REGISTRY=ghcr.io/ckLXHL
ARG BASE_VERSION=22.04
FROM ${REGISTRY}/base-ubuntu:${BASE_VERSION}

ARG GCC_VERSION=14
ARG CLANG_VERSION=18
ARG CMAKE_VERSION=3.28.3
ARG NINJA_VERSION=1.11.1

LABEL org.opencontainers.image.title="toolchain-cpp" \
      org.opencontainers.image.description="C++ toolchain: GCC ${GCC_VERSION}, Clang ${CLANG_VERSION}, CMake ${CMAKE_VERSION}, Ninja ${NINJA_VERSION}" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package"

# 安装 GCC 与构建基础工具
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        # 构建基础
        build-essential \
        gcc-${GCC_VERSION} \
        g++-${GCC_VERSION} \
        gdb \
        # 链接器与库
        binutils \
        libc6-dev \
        libstdc++-${GCC_VERSION}-dev \
        # 构建工具
        make \
        pkg-config \
        autoconf \
        automake \
        libtool \
        # 代码覆盖与分析
        lcov \
        gcovr \
        valgrind \
        # 缓存加速
        ccache \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 设置 GCC 默认版本
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-${GCC_VERSION} 100 \
    && update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-${GCC_VERSION} 100 \
    && update-alternatives --install /usr/bin/gcov gcov /usr/bin/gcov-${GCC_VERSION} 100

# 安装 Clang（通过 LLVM 官方脚本，或直接从 apt）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        clang-${CLANG_VERSION} \
        clang-format-${CLANG_VERSION} \
        clang-tidy-${CLANG_VERSION} \
        lldb-${CLANG_VERSION} \
        lld-${CLANG_VERSION} \
        libc++-${CLANG_VERSION}-dev \
        libc++abi-${CLANG_VERSION}-dev \
    ; \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-${CLANG_VERSION} 100; \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${CLANG_VERSION} 100; \
    update-alternatives --install /usr/bin/clang-format clang-format /usr/bin/clang-format-${CLANG_VERSION} 100; \
    update-alternatives --install /usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-${CLANG_VERSION} 100; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 安装 CMake（从 GitHub 下载预编译二进制，构建时 GitHub 网络无封锁）
RUN set -eux; \
    ARCH=$(dpkg --print-architecture); \
    case "${ARCH}" in \
        amd64) CMAKE_ARCH="x86_64" ;; \
        arm64) CMAKE_ARCH="aarch64" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac; \
    CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${CMAKE_ARCH}.tar.gz"; \
    curl -fsSL "${CMAKE_URL}" -o /tmp/cmake.tar.gz; \
    tar -xzf /tmp/cmake.tar.gz -C /usr/local --strip-components=1; \
    rm -f /tmp/cmake.tar.gz; \
    cmake --version

# 安装 Ninja
RUN set -eux; \
    ARCH=$(dpkg --print-architecture); \
    case "${ARCH}" in \
        amd64) NINJA_ARCH="linux" ;; \
        arm64) NINJA_ARCH="linux" ;; \
        *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
    esac; \
    NINJA_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-${NINJA_ARCH}.zip"; \
    curl -fsSL "${NINJA_URL}" -o /tmp/ninja.zip; \
    unzip -q /tmp/ninja.zip -d /usr/local/bin/; \
    chmod +x /usr/local/bin/ninja; \
    rm -f /tmp/ninja.zip; \
    ninja --version

# 配置 ccache
ENV CCACHE_DIR=/root/.ccache \
    CCACHE_MAXSIZE=2G \
    PATH="/usr/lib/ccache:${PATH}"

# 验证安装
RUN gcc --version && g++ --version && clang --version && cmake --version && ninja --version

CMD ["/bin/bash"]
