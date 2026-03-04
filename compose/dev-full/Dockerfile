# L3: 完整开发环境（Full Dev Environment）
# 包含所有工具链：C++、Python、Ansible、Docker、Git工具
# 继承自 L2 services-docker（已包含 toolchain-common）
ARG REGISTRY=ghcr.io/ckLXHL
ARG DOCKER_VERSION=2.0
FROM ${REGISTRY}/services-docker:${DOCKER_VERSION} AS docker-stage

# 从 toolchain-cpp 获取 C++ 工具链
ARG CPP_VERSION=14.0
FROM ${REGISTRY}/toolchain-cpp:${CPP_VERSION} AS cpp-stage

# 从 toolchain-python 获取 Python 工具链
ARG PYTHON_VERSION=3.12
FROM ${REGISTRY}/toolchain-python:${PYTHON_VERSION} AS python-stage

# 从 services-ansible 获取 Ansible
ARG ANSIBLE_VERSION=2.16
FROM ${REGISTRY}/services-ansible:${ANSIBLE_VERSION} AS ansible-stage

# 最终镜像：基于 services-docker（包含 toolchain-common）
FROM docker-stage AS final

LABEL org.opencontainers.image.title="compose-full" \
      org.opencontainers.image.description="Full development environment: C++, Python, Ansible, Docker, common tools" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package"

# 从 cpp-stage 复制 C++ 工具链
COPY --from=cpp-stage /usr/bin/gcc* /usr/bin/
COPY --from=cpp-stage /usr/bin/g++* /usr/bin/
COPY --from=cpp-stage /usr/bin/clang* /usr/bin/
COPY --from=cpp-stage /usr/local/bin/cmake /usr/local/bin/cmake
COPY --from=cpp-stage /usr/local/bin/ninja /usr/local/bin/ninja
COPY --from=cpp-stage /usr/lib/ccache /usr/lib/ccache
COPY --from=cpp-stage /usr/local/share/cmake-* /usr/local/share/

# 从 python-stage 复制 Python 工具链
COPY --from=python-stage /usr/bin/python* /usr/bin/
COPY --from=python-stage /usr/bin/pip* /usr/bin/
COPY --from=python-stage /usr/lib/python3* /usr/lib/
COPY --from=python-stage /usr/local/lib/python3* /usr/local/lib/
COPY --from=python-stage /root/.pip /root/.pip

# 从 ansible-stage 复制 Ansible（使用 pip 安装路径，与 Python 版本无关）
COPY --from=ansible-stage /usr/local/bin/ansible* /usr/local/bin/
COPY --from=ansible-stage /etc/ansible /etc/ansible
COPY --from=ansible-stage /usr/share/ansible /usr/share/ansible

# 安装额外的运行时依赖（从 cpp 和 python 引入）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        # C++ 运行时依赖
        libstdc++6 \
        libgcc-s1 \
        # Python 运行时依赖
        python3 \
        python3-dev \
        # 通用工具
        make \
        pkg-config \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 设置工作目录
WORKDIR /workspace

# 欢迎信息
RUN cat > /etc/motd <<'EOF'
╔═══════════════════════════════════════════════════╗
║          Cloud Dev Environment - Full             ║
║  Tools: C++, Python, Ansible, Docker, Git         ║
║  Run 'help-devenv' for usage guide                ║
╚═══════════════════════════════════════════════════╝
EOF

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/bin/zsh"]
