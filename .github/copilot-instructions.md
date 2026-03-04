# Cloud Dev Environment - Copilot Instructions

## 项目概述

这是一个面向国内封锁网络环境的一体化开发环境管理方案，通过分层 Docker 镜像构建、OSS/OBS 对象存储分发，实现目标机（Ubuntu x86_64 / 麒麟 ARM64）的完全离线容器化开发环境部署。

## 架构说明

```
GitHub Actions（构建/推送）→ GHCR → 阿里云OSS/华为OBS → 目标机 docker load
```

### 镜像层级

| 层 | 目录 | 内容 |
|----|------|------|
| L0 | `base/` | Ubuntu 22.04 / 麒麟 V10 最小系统 + 国内镜像源 |
| L1 | `toolchain/` | GCC/Clang/CMake/Python/通用工具 |
| L2 | `services/` | Docker/Podman/Ansible |
| L3 | `compose/` | 面向场景的组合镜像（full/cpp/python）|

## Dockerfile 编写规范

### 必须遵守的原则

1. **所有外部依赖必须离线预置**：构建时通过 GitHub 网络下载所有依赖，运行时无需访问外网
2. **使用国内镜像源**：
   - apt: 阿里云 mirrors.aliyun.com/ubuntu（x86_64）或 mirrors.aliyun.com/ubuntu-ports（arm64）
   - pip: mirrors.aliyun.com/pypi/simple/
   - Docker 加速: registry.cn-hangzhou.aliyuncs.com
3. **多架构支持**：所有镜像必须同时支持 `linux/amd64` 和 `linux/arm64`
4. **继承关系**：通过 `FROM ${REGISTRY}/layer-name:version` 继承，不重复安装
5. **LABEL 规范**：每个 Dockerfile 必须包含标准 OCI 标签

### Dockerfile 模板结构

```dockerfile
# 层级注释：L0/L1/L2/L3
ARG REGISTRY=ghcr.io/ckLXHL
ARG BASE_VERSION=22.04
FROM ${REGISTRY}/base-ubuntu:${BASE_VERSION}

ARG TOOL_VERSION=x.y.z

LABEL org.opencontainers.image.title="image-name" \
      org.opencontainers.image.description="描述" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package"

# 替换镜像源（如果是 L0）
RUN set -eux; \
    cat > /etc/apt/sources.list <<'EOF'
deb https://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
...
EOF

# 安装工具（分组，每 RUN 清理 apt 缓存）
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        package1 \
        package2 \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 验证安装
RUN tool --version
```

### 关键规范

- 每个 `RUN apt-get install` 后必须跟 `apt-get clean && rm -rf /var/lib/apt/lists/*`
- 使用 `--no-install-recommends` 减小镜像体积
- 从 GitHub 下载二进制时，在 `RUN` 中检测架构：
  ```bash
  ARCH=$(dpkg --print-architecture)
  case "${ARCH}" in
      amd64) TOOL_ARCH="x86_64" ;;
      arm64) TOOL_ARCH="aarch64" ;;
  esac
  ```
- 在 L1+ 层使用 `ARG REGISTRY=ghcr.io/ckLXHL` 引用基础镜像

## Shell 脚本规范

- 所有脚本以 `#!/bin/bash` 开头，第二行 `set -euo pipefail`
- 提供 `--help` 选项和标准的参数解析（`while [[ $# -gt 0 ]]; do case "$1" in`）
- 使用 `log()` 和 `error()` 函数统一日志格式：
  ```bash
  log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
  error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }
  ```
- 变量使用环境变量覆盖模式：`VARIABLE="${VARIABLE:-default_value}"`
- 重要的外部工具使用前检查是否存在

## YAML 文件规范

- config/*.yaml：使用 `version: "1.0"` 字段标识版本
- GitHub Actions workflows：
  - 使用最新的 actions 版本（checkout@v4, setup-buildx-action@v3 等）
  - 所有敏感值通过 `${{ secrets.XXX }}` 引用
  - 支持 `workflow_dispatch` 手动触发
  - 使用 `needs` 保证 DAG 构建顺序

## Ansible Playbook 规范

- 使用 YAML 格式（不使用 JSON）
- task name 使用中文描述（便于理解）
- 变量从环境变量读取：`"{{ lookup('env', 'VAR_NAME') }}"`
- 敏感变量通过 Ansible Vault 加密存储
- 使用 `failed_when: false` + `register` 处理可选步骤

## 配置文件规范

### matrix.yaml 格式

```yaml
images:
  - name: image-name      # 镜像名（不含 registry 前缀）
    layer: 0              # 层级 0-3
    context: path/to/ctx  # Docker build context
    dockerfile: path/to/Dockerfile
    platforms:
      - linux/amd64
      - linux/arm64
    version: "x.y.z"      # 主版本号
    depends_on:           # 依赖的镜像名列表
      - base-ubuntu
    build_args:           # Docker build-arg
      KEY: value
```

### 文件命名规范

- 分发包：`devenv-{image-name}-{version}-{arch}.tar.zst`
- 示例：`devenv-compose-full-1.0.0-amd64.tar.zst`

## 国内封锁规避最佳实践

1. **构建阶段**（GitHub Actions 环境，无封锁）：
   - 所有依赖直接从官方源下载
   - pip 使用阿里云镜像（防止偶发限速）
   - apt 使用阿里云镜像（加速构建）

2. **分发阶段**：
   - 优先使用 OSS/OBS 内网 Endpoint（`-internal` 后缀）
   - 生成 manifest.json + SHA256 校验文件
   - 使用 zstd 压缩（比 gzip 快 3-5 倍）

3. **运行阶段**（目标机）：
   - 优先使用 Podman（无守护进程，无 root 需求）
   - Docker 配置国内镜像加速
   - 避免运行时拉取任何镜像（全部离线加载）

## 常用命令速查

```bash
# 构建
make build                    # 全量构建
make build LAYER=toolchain   # 构建工具链层
make build IMAGE=cpp         # 构建指定镜像

# 推送
make push REGISTRY=aliyun-acr
make push-all-registries

# 同步
make sync TARGET=oss
make sync TARGET=all

# 目标机操作
make bootstrap SCENE=full    # 一键初始化
devenv                       # 启动开发容器
```
