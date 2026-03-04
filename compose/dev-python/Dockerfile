# L3: Python 专用开发环境
# 包含：Python + uv + 常用工具
# 继承自 L1 toolchain-python + L1 toolchain-common
ARG REGISTRY=ghcr.io/ckLXHL
ARG PYTHON_VERSION=3.12
FROM ${REGISTRY}/toolchain-python:${PYTHON_VERSION} AS python-stage

ARG COMMON_VERSION=2.0
FROM ${REGISTRY}/toolchain-common:${COMMON_VERSION} AS final

LABEL org.opencontainers.image.title="compose-python" \
      org.opencontainers.image.description="Python development environment: Python, uv, Jupyter, common tools" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package"

# 从 python-stage 复制 Python 工具链
COPY --from=python-stage /usr/bin/python* /usr/bin/
COPY --from=python-stage /usr/bin/pip* /usr/bin/
COPY --from=python-stage /usr/local/bin/uv /usr/local/bin/uv
COPY --from=python-stage /usr/local/bin/uvx /usr/local/bin/uvx
COPY --from=python-stage /usr/lib/python3* /usr/lib/
COPY --from=python-stage /usr/local/lib/python3* /usr/local/lib/
COPY --from=python-stage /root/.pip /root/.pip

# 安装 Python 运行时依赖
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        python3 \
        python3-dev \
        python3-venv \
        # 数据处理依赖
        libhdf5-dev \
        libatlas-base-dev \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 安装 Jupyter Lab（数据科学开发常用）
RUN pip install --no-cache-dir \
    jupyterlab \
    ipykernel \
    nbconvert

# 创建 Python 项目模板
RUN mkdir -p /workspace/template-python
COPY pyproject.toml.template /workspace/template-python/pyproject.toml
COPY main.py.template /workspace/template-python/main.py

WORKDIR /workspace

RUN cat > /etc/motd <<'EOF'
╔═══════════════════════════════════════════════════╗
║          Cloud Dev Environment - Python           ║
║  Tools: Python, uv, pip, Jupyter Lab              ║
║  Template: /workspace/template-python/            ║
║  JupyterLab: jupyter lab --ip=0.0.0.0 --no-browser║
╚═══════════════════════════════════════════════════╝
EOF

EXPOSE 8888

CMD ["/bin/zsh"]
