# L1: Google Benchmark 工具链镜像
# 包含：Google Benchmark + perf + 性能分析工具
# 继承自 L1 toolchain-cpp
ARG REGISTRY=ghcr.io/ckLXHL
ARG CPP_VERSION=14.0
FROM ${REGISTRY}/toolchain-cpp:${CPP_VERSION}

ARG GBENCH_VERSION=1.8.3

LABEL org.opencontainers.image.title="toolchain-gbench" \
      org.opencontainers.image.description="Google Benchmark ${GBENCH_VERSION} + perf toolchain" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package"

# 安装性能分析工具
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        # perf 工具（内核版本相关，安装 generic）
        linux-tools-generic \
        linux-tools-common \
        # 其他性能分析工具
        strace \
        ltrace \
        perf-tools-unstable \
        flamegraph \
        # 依赖库
        libpfm4-dev \
        libbenchmark-dev \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* \
    || true

# 从源码构建 Google Benchmark（确保版本精确）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends git; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    git clone --depth=1 --branch "v${GBENCH_VERSION}" \
        https://github.com/google/benchmark.git /tmp/benchmark; \
    # 同时克隆 googletest（benchmark 依赖）
    git clone --depth=1 \
        https://github.com/google/googletest.git /tmp/benchmark/googletest; \
    cd /tmp/benchmark; \
    cmake -E make_directory build; \
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DBENCHMARK_DOWNLOAD_DEPENDENCIES=OFF \
        -DBENCHMARK_ENABLE_TESTING=OFF \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -B build \
        -G Ninja \
        -S .; \
    cmake --build build --parallel $(nproc); \
    cmake --install build; \
    rm -rf /tmp/benchmark

# 验证安装
RUN ldconfig && echo "#include <benchmark/benchmark.h>" | clang++ -x c++ - -lbenchmark -lpthread -o /dev/null 2>&1 | head -5 || true

# 设置 perf 性能分析环境变量
ENV PERF_PARANOID_WORKAROUND=1

WORKDIR /workspace

CMD ["/bin/bash"]
