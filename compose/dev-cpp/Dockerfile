# L3: C++ 专用开发环境
# 包含：C++ 工具链 + Google Benchmark + 通用工具
# 继承自 L1 toolchain-gbench（已包含 toolchain-cpp）
ARG REGISTRY=ghcr.io/ckLXHL
ARG GBENCH_VERSION=1.8.3
FROM ${REGISTRY}/toolchain-gbench:${GBENCH_VERSION} AS gbench-stage

ARG COMMON_VERSION=2.0
FROM ${REGISTRY}/toolchain-common:${COMMON_VERSION} AS final

LABEL org.opencontainers.image.title="compose-cpp" \
      org.opencontainers.image.description="C++ development environment: GCC, Clang, CMake, Ninja, Google Benchmark" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package"

# 从 gbench-stage 复制 C++ 工具链和 Google Benchmark
COPY --from=gbench-stage /usr/bin/gcc* /usr/bin/
COPY --from=gbench-stage /usr/bin/g++* /usr/bin/
COPY --from=gbench-stage /usr/bin/clang* /usr/bin/
COPY --from=gbench-stage /usr/local/bin/cmake /usr/local/bin/cmake
COPY --from=gbench-stage /usr/local/bin/ninja /usr/local/bin/ninja
COPY --from=gbench-stage /usr/local/lib/libbenchmark* /usr/local/lib/
COPY --from=gbench-stage /usr/local/include/benchmark /usr/local/include/benchmark
COPY --from=gbench-stage /usr/local/share/cmake-* /usr/local/share/

# 安装 C++ 运行时依赖
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        libstdc++-14-dev \
        gdb \
        valgrind \
        linux-tools-generic \
        linux-tools-common \
        ccache \
        make \
        pkg-config \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 配置 ccache
ENV CCACHE_DIR=/root/.ccache \
    CCACHE_MAXSIZE=2G \
    PATH="/usr/lib/ccache:${PATH}"

# 创建 C++ 项目模板
RUN mkdir -p /workspace/template-cpp
COPY CMakeLists.txt.template /workspace/template-cpp/CMakeLists.txt
COPY benchmark-example.cpp.template /workspace/template-cpp/benchmark-example.cpp

WORKDIR /workspace

RUN cat > /etc/motd <<'EOF'
╔═══════════════════════════════════════════════════╗
║          Cloud Dev Environment - C++              ║
║  Tools: GCC, Clang, CMake, Ninja, Google Bench    ║
║  Template: /workspace/template-cpp/               ║
╚═══════════════════════════════════════════════════╝
EOF

CMD ["/bin/zsh"]
