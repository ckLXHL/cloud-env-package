# cloud-env-package

> 面向国内封锁网络环境的一体化开发环境管理方案

**当前阶段**：仅支持 `linux/amd64`（x86_64）。arm64 为可选未来计划，待 amd64 验证稳定后手动扩展。

## 总体架构

```
GitHub (源码 / Actions / Copilot / Packages)
         ↓
   分层镜像构建体系（BuildKit，手动触发）
         ↓
    GHCR → 阿里云OSS / 华为OBS（对象存储分发）
         ↓
目标环境（Ubuntu x86_64 / openEuler x86_64）
         ↓
   本地 Docker / Podman / containerd 运行时
```

## 项目结构

```
cloud-env-package/
├── .github/
│   ├── workflows/
│   │   ├── build-matrix.yml       # 手动触发分层构建
│   │   ├── push-registry.yml      # 手动触发推送镜像仓库
│   │   ├── sync-oss.yml           # 手动触发同步到阿里云OSS
│   │   ├── sync-obs.yml           # 手动触发同步到华为OBS
│   │   └── auto-update.yml        # 手动触发全量重建
│   └── copilot-instructions.md    # Copilot 上下文定制
│
├── base/                          # L0：基础系统层
│   ├── ubuntu-amd64/              # Ubuntu 22.04 amd64
│   └── openeuler-amd64/           # openEuler 22.03 amd64（无授权问题）
│
├── toolchain/                     # L1：语言与工具链层
│   ├── cpp/                       # GCC/Clang/CMake/Ninja
│   ├── gbench/                    # Google Benchmark
│   ├── python/                    # Python + uv/pip
│   └── common/                    # Git/zsh/tmux/vim/SSH
│
├── services/                      # L2：可选服务层
│   ├── docker/                    # Docker CE / Podman
│   └── ansible/                   # Ansible + Collection
│
├── compose/                       # L3：场景组合层
│   ├── dev-full/
│   ├── dev-cpp/
│   └── dev-python/
│
├── distribution/                  # 分发管理
│   ├── oss/                       # 阿里云OSS脚本
│   ├── obs/                       # 华为OBS脚本
│   └── loader/                    # 目标机拉取/加载脚本
│
├── ansible/                       # 自动化运维
│   ├── playbooks/
│   │   ├── bootstrap.yml
│   │   ├── deploy-env.yml
│   │   ├── update-env.yml
│   │   └── health-check.yml
│   └── inventory/
│
├── scripts/                       # 统一操作脚本
│   ├── build.sh
│   ├── push.sh
│   ├── sync.sh
│   ├── load.sh
│   └── bootstrap.sh
│
├── config/
│   ├── matrix.yaml                # 构建矩阵定义
│   ├── registry.yaml              # 镜像仓库配置
│   └── mirror.yaml                # 国内镜像源配置
│
└── Makefile                       # 顶层统一入口
```

## 分层镜像体系

| 层级 | 镜像名 | 核心内容 | 架构 | 重建频率 |
|------|--------|----------|------|----------|
| L0 | `base-ubuntu` | Ubuntu 22.04 最小系统 + 国内源 + 证书 | amd64 | 月度 |
| L0 | `base-openeuler` | openEuler 22.03 LTS（替代麒麟，无授权问题）| amd64 | 月度 |
| L1-a | `toolchain-cpp` | GCC/Clang/CMake/Ninja | amd64 | 按版本 |
| L1-b | `toolchain-gbench` | Google Benchmark + perf | amd64 | 按版本 |
| L1-c | `toolchain-python` | Python + uv/pip + 常用包 | amd64 | 按版本 |
| L1-d | `toolchain-common` | Git/zsh/tmux/SSH/vim | amd64 | 月度 |
| L2-a | `services-docker` | Docker CE / Podman | amd64 | 按版本 |
| L2-b | `services-ansible` | Ansible + Collection | amd64 | 按版本 |
| L3 | `compose-full/cpp/python` | 面向场景组合 | amd64 | 按需 |

> **arm64 计划**：待 amd64 验证稳定后，可手动为每个镜像增加 arm64 构建。

## 快速开始

### 手动触发构建（GitHub Actions）

所有 Workflow 均为手动触发（`workflow_dispatch`），在 GitHub Actions 页面选择工作流并点击 **Run workflow**。

```bash
# 等效的 Makefile 命令（需要本地配置 Docker Buildx）
# 全量构建
make build-all

# 按层构建
make build LAYER=base
make build LAYER=toolchain

# 单镜像构建
make build IMAGE=cpp

# 预览模式
make build-dry IMAGE=cpp
```

### 推送到镜像仓库

```bash
# 推送到阿里云ACR
make push REGISTRY=aliyun-acr

# 推送工具链层到GHCR
make push LAYER=toolchain REGISTRY=ghcr

# 全量推送到所有仓库
make push-all-registries
```

### 同步到对象存储

```bash
# 同步到阿里云OSS
make sync TARGET=oss

# 同步到华为OBS
make sync TARGET=obs

# 同步到所有
make sync TARGET=all
```

### 目标机一键初始化

```bash
# 完整环境（包含 C++/Python/Ansible/Docker）
./scripts/bootstrap.sh --scene full

# 仅 C++ 环境
./scripts/bootstrap.sh --scene cpp

# 指定架构（麒麟 ARM64）
./scripts/bootstrap.sh --scene full --arch arm64 --registry oss
```

初始化完成后，使用以下命令启动开发容器：

```bash
devenv              # 在当前目录启动
devenv /path/to/src # 挂载指定目录
```

### Ansible 批量管理

```bash
# 编辑目标机清单
vim ansible/inventory/hosts.ini

# 初始化新机器
make ansible-bootstrap

# 部署开发环境
make ansible-deploy SCENE=full

# 批量更新
make ansible-update

# 健康检查
make ansible-health
```

## 配置说明

### 必要的 GitHub Secrets

| Secret | 说明 |
|--------|------|
| `ALIYUN_ACR_USERNAME` | 阿里云容器镜像服务用户名 |
| `ALIYUN_ACR_PASSWORD` | 阿里云容器镜像服务密码 |
| `HUAWEI_SWR_USERNAME` | 华为云SWR用户名 |
| `HUAWEI_SWR_PASSWORD` | 华为云SWR密码 |
| `ALIYUN_OSS_BUCKET` | 阿里云OSS存储桶名 |
| `ALIYUN_OSS_ENDPOINT` | 阿里云OSS Endpoint（内网优先）|
| `ALIYUN_OSS_ACCESS_KEY` | 阿里云 AccessKey ID |
| `ALIYUN_OSS_SECRET_KEY` | 阿里云 AccessKey Secret |
| `HUAWEI_OBS_BUCKET` | 华为OBS存储桶名 |
| `HUAWEI_OBS_ENDPOINT` | 华为OBS Endpoint |
| `HUAWEI_OBS_ACCESS_KEY` | 华为云 AccessKey ID |
| `HUAWEI_OBS_SECRET_KEY` | 华为云 AccessKey Secret |

### 分发文件命名规范

```
devenv-{image}-{version}-{arch}.tar.zst
# 示例
devenv-compose-full-1.0.0-amd64.tar.zst
devenv-toolchain-cpp-14.0-arm64.tar.zst
```

### OBS/OSS 目录结构

```
bucket/devenv/
├── latest/
│   ├── manifest.json
│   └── images/
│       ├── devenv-compose-full-latest-amd64.tar.zst
│       └── ...
└── v1.0.0/
    ├── manifest.json
    └── images/
        └── ...
```

## 版本回滚

```bash
make rollback VERSION=v1.1.0 SCENE=full
```

## 成本估算

| 资源 | 方案 | 预估费用 |
|------|------|----------|
| CI 构建 | GitHub Actions 免费额度 | ¥0 |
| 镜像存储 | GHCR 免费额度 + OSS 低频 | ¥1~5/月 |
| 分发流量 | OSS/OBS 内网传输（同地域免费） | ¥0 |
| Copilot | GitHub Copilot Individual | ~¥70/月 |
| 镜像仓库 | 阿里云ACR个人版 / 华为SWR免费版 | ¥0 |

**总计：约 ¥70~75/月**