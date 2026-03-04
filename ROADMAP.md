# ROADMAP — cloud-env-package

> 本文档记录项目演进路线，供人机协作时同步进度与决策依据。
> 背景：结合 kunpeng-kylin-ansible 项目目标（鲲鹏服务器 + 麒麟/openEuler 离线环境 Ansible 批量管理），
> cloud-env-package 的最终目标是**一条命令、完全离线、无须外网**地在目标机完成开发环境初始化。

---

## 当前状态（2026-03）

| 分类 | 状态 | 说明 |
|------|------|------|
| 仓库结构 | ✅ 完成 | 4 层镜像体系 + Makefile + Ansible + 分发脚本 |
| Dockerfile | ✅ 完成 | 11 个镜像，含 L0~L3 所有层 |
| GitHub Actions | ✅ 完成 | 构建/推送/同步 Workflow，均为手动触发 |
| GHCR 镜像 | ❌ 未构建 | 工作流存在，但从未实际运行过 |
| 国内云平台推送 | ❌ 未测试 | Secrets 未配置，链路未验证 |
| OSS/OBS 分发 | ❌ 未测试 | 脚本已写，未端到端运行 |
| 目标机验证 | ❌ 未测试 | 整个离线加载流程尚未跑通 |
| 自动化验证 | ❌ 缺失 | 无 Smoke Test，无构建后检查 |

---

## 阶段一：手动构建 GHCR 镜像并逐层验证（建议立即执行）

**结论：是的，应该立即开始手动构建。** 原因：所有后续工作（OSS 同步、目标机测试）都依赖 GHCR 上有可用镜像，且 Dockerfile 的实际可行性尚未被生产环境验证。

### 1.1 前置准备

- [ ] 确认 GitHub repo 的 Packages 写入权限（Settings → Actions → Workflow permissions → Read and write）
- [ ] 确认 `ghcr.io/${{ github.repository_owner }}` 命名空间可以公开访问（或设置 Package 为 public）

### 1.2 逐层构建与验证顺序

按 DAG 依赖顺序逐层触发，每层验证通过后再进入下一层：

```
L0: base-ubuntu / base-openeuler        ← 最先构建，无依赖
       ↓
L1: toolchain-common / toolchain-cpp / toolchain-python  ← 并行
       ↓
L1b: toolchain-gbench                   ← 依赖 toolchain-cpp
       ↓
L2: services-docker / services-ansible  ← 并行
       ↓
L3: compose-cpp / compose-python / compose-full  ← 并行
```

**触发方式**：GitHub Actions → Build Matrix → Run workflow → 选 `base`，验证后再选 `toolchain`，以此类推。

### 1.3 每层验证清单

构建成功推送到 GHCR 后，本地 `docker pull` 验证：

```bash
# L0 验证
docker run --rm ghcr.io/ckLXHL/base-ubuntu:22.04 cat /etc/os-release
docker run --rm ghcr.io/ckLXHL/base-openeuler:22.03-lts cat /etc/os-release

# L1 验证
docker run --rm ghcr.io/ckLXHL/toolchain-cpp:14.0 gcc --version
docker run --rm ghcr.io/ckLXHL/toolchain-cpp:14.0 cmake --version
docker run --rm ghcr.io/ckLXHL/toolchain-python:3.12 python3 --version

# L2 验证
docker run --rm ghcr.io/ckLXHL/services-ansible:2.16 ansible --version
docker run --rm --privileged ghcr.io/ckLXHL/services-docker:25.0 docker --version

# L3 验证（smoke test）
docker run --rm ghcr.io/ckLXHL/compose-full:latest bash -c "gcc --version && python3 --version && ansible --version"
```

### 1.4 预期问题与应对

| 潜在问题 | 原因 | 应对 |
|---------|------|------|
| `apt-get update` 失败 | 阿里云镜像源偶发不稳定 | 更换为备用源（清华/华为）|
| GCC 14 PPA 不可用 | Ubuntu 22.04 默认不含 | 使用 ubuntu-toolchain-r/test PPA 或下载预编译二进制 |
| Clang 18 安装超时 | LLVM apt 仓库较慢 | 使用 GitHub Releases 直接下载 binary |
| 镜像体积过大 | 未清理缓存 | 检查每个 `RUN` 是否有 `apt-get clean` |
| GHCR 推送权限失败 | Packages 权限未开 | 开启 repo Settings → Actions → Workflow permissions: Read and write |

---

## 阶段二：测试 GHCR → 国内云平台（OSS/ACR/OBS）推送链路

**结论：在阶段一完成（GHCR 镜像可用）后立即测试。** 这是离线分发链路的核心环节。

### 2.1 配置 GitHub Secrets

在 GitHub repo Settings → Secrets and variables → Actions 中添加：

| Secret 名称 | 说明 | 获取方式 |
|------------|------|---------|
| `ALIYUN_ACR_USERNAME` | 阿里云容器镜像服务用户名 | 阿里云 ACR 控制台 |
| `ALIYUN_ACR_PASSWORD` | 阿里云容器镜像服务密码 | 阿里云 ACR 控制台（固定密码） |
| `ALIYUN_OSS_BUCKET` | OSS 存储桶名 | 阿里云 OSS 控制台 |
| `ALIYUN_OSS_ENDPOINT` | OSS Endpoint（优先内网） | 如 `oss-cn-hangzhou-internal.aliyuncs.com` |
| `ALIYUN_OSS_ACCESS_KEY` | AccessKey ID | 阿里云 RAM 控制台 |
| `ALIYUN_OSS_SECRET_KEY` | AccessKey Secret | 阿里云 RAM 控制台 |
| `HUAWEI_SWR_USERNAME` | 华为云 SWR 用户名 | `cn-north-4@<AK>` 格式 |
| `HUAWEI_SWR_PASSWORD` | 华为云 SWR 密码 | SWR 登录凭证（临时或永久） |
| `HUAWEI_OBS_BUCKET` | 华为 OBS 存储桶名 | 华为云 OBS 控制台 |
| `HUAWEI_OBS_ENDPOINT` | 华为 OBS Endpoint | 如 `obs.cn-north-4.myhuaweicloud.com` |
| `HUAWEI_OBS_ACCESS_KEY` | 华为云 AccessKey ID | 华为云 IAM 控制台 |
| `HUAWEI_OBS_SECRET_KEY` | 华为云 AccessKey Secret | 华为云 IAM 控制台 |

### 2.2 分步测试链路

**步骤 1：测试 GHCR → 阿里云 ACR 镜像同步**
```
GitHub Actions → Push to Registries → registry: aliyun-acr → version: latest
```
- 验证：登录 ACR 控制台，确认镜像出现在命名空间下

**步骤 2：测试 GHCR → OSS 压缩包同步**（更重要，用于离线目标机）
```
GitHub Actions → Sync to 阿里云OSS → images: compose-full → version: latest
```
- 验证：检查 OSS 控制台中 `bucket/devenv/latest/` 是否有 `.tar.zst` 文件和 `manifest.json`

**步骤 3：模拟目标机离线下载**（在有网络的测试机上）
```bash
# 从 OSS 下载（需要配置 ossutil 或 wget + 预签名 URL）
ossutil cp oss://<bucket>/devenv/latest/devenv-compose-full-latest-amd64.tar.zst .
# 加载镜像
zstd -d devenv-compose-full-latest-amd64.tar.zst -c | docker load
# 验证
docker run --rm ghcr.io/ckLXHL/compose-full:latest bash -c "gcc --version"
```

### 2.3 验证矩阵

| 链路 | 测试命令/方法 | 通过条件 |
|------|-------------|---------|
| GHCR → ACR | push-registry.yml（aliyun-acr） | ACR 控制台可见镜像 |
| GHCR → OSS tar.zst | sync-oss.yml | OSS 有对应文件 + manifest.json |
| OSS → 目标机 docker load | 手动在测试机执行 load.sh | 容器成功运行 |
| GHCR → SWR | push-registry.yml（huawei-swr） | SWR 控制台可见镜像 |
| GHCR → OBS tar.zst | sync-obs.yml | OBS 有对应文件 |

---

## 阶段三：建立自动化验证框架（Smoke Test）

**目标**：在每次构建后自动验证镜像功能可用，将人工检查变为自动检查。

### 3.1 新增 `smoke-test.yml` Workflow

在 `.github/workflows/` 中添加 `smoke-test.yml`，由 `build-matrix.yml` 构建成功后触发：

```yaml
# 触发条件：build-matrix.yml 完成后，或手动触发
on:
  workflow_run:
    workflows: ["Build Matrix"]
    types: [completed]
  workflow_dispatch:
    inputs:
      image:
        description: '要测试的镜像（留空则测试全部）'
        required: false
```

**验证内容**：

| 镜像 | 验证命令 | 期望输出 |
|------|---------|---------|
| `base-ubuntu` | `cat /etc/os-release` | `Ubuntu 22.04` |
| `base-openeuler` | `cat /etc/os-release` | `openEuler 22.03` |
| `toolchain-cpp` | `gcc --version && cmake --version` | 版本号匹配 matrix.yaml |
| `toolchain-python` | `python3 --version && uv --version` | 版本号匹配 |
| `toolchain-common` | `git --version && zsh --version` | 正常输出 |
| `services-ansible` | `ansible --version` | `core 2.16.x` |
| `compose-full` | 完整 smoke test | 所有工具链均可用 |

### 3.2 验证脚本结构

```bash
# scripts/smoke-test.sh
#!/bin/bash
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/ckLXHL}"
IMAGE="${1:-compose-full}"
TAG="${2:-latest}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }

case "${IMAGE}" in
  toolchain-cpp)
    docker run --rm "${REGISTRY}/${IMAGE}:${TAG}" bash -c "
      gcc --version | grep -q 'gcc' || exit 1
      cmake --version | grep -q 'cmake' || exit 1
      ninja --version | grep -q '\.' || exit 1
    " && log "✅ ${IMAGE} smoke test passed"
    ;;
  # ... 其他镜像的测试
esac
```

### 3.3 引入镜像大小检查

防止 Dockerfile 改动导致镜像体积异常膨胀：

```yaml
- name: 检查镜像大小
  run: |
    SIZE=$(docker image inspect $IMAGE --format='{{.Size}}')
    MAX_SIZE=5368709120  # 5GB
    if [ "$SIZE" -gt "$MAX_SIZE" ]; then
      echo "❌ 镜像过大: $SIZE bytes (limit: $MAX_SIZE)"
      exit 1
    fi
    echo "✅ 镜像大小正常: $(numfmt --to=iec $SIZE)"
```

---

## 阶段四：端到端自动化（从手动到全自动工作流）

### 4.1 定时自动重建

在 `auto-update.yml` 中增加 `schedule` 触发，定期检查上游版本并重建：

```yaml
on:
  schedule:
    - cron: '0 2 1 * *'  # 每月 1 日 02:00 UTC 自动重建基础层
  workflow_dispatch:      # 保留手动触发
```

**分层重建策略**（与 matrix.yaml 中 `rebuild_schedule` 对应）：

| 重建频率 | 涉及层 | 触发方式 |
|---------|-------|---------|
| `monthly` | L0（base）、toolchain-common | 每月定时 |
| `on_version` | L1/L2（工具链版本更新时） | 上游版本检查脚本触发 |
| `on_demand` | L3（compose）| 手动或依赖层变更后触发 |

### 4.2 上游版本自动检测

增强 `auto-update.yml` 中的 `check-upstream-versions` job，检测并触发重建：

| 工具 | 检查 API | 当前版本 |
|------|---------|---------|
| CMake | `api.github.com/repos/Kitware/CMake/releases/latest` | 3.28.3 |
| GCC | Ubuntu Toolchain PPA RSS | 14 |
| Python | `python.org/ftp/python/` | 3.12 |
| uv | `api.github.com/repos/astral-sh/uv/releases/latest` | 0.4.0 |
| Google Benchmark | `api.github.com/repos/google/benchmark/releases/latest` | 1.8.3 |
| Ansible | PyPI JSON API | 9.3.0 |
| Docker CE | `api.github.com/repos/moby/moby/releases/latest` | 25.0 |

### 4.3 构建状态通知

在 `notify` job 中增加失败时的通知渠道：
- GitHub Issue 自动创建（构建失败时）
- 企业微信 Webhook（可选）

### 4.4 全自动流水线（目标状态）

```
[定时触发/版本更新检测]
        ↓
build-matrix.yml（逐层构建 + 推送 GHCR）
        ↓（build 成功后自动触发）
smoke-test.yml（验证各层镜像功能）
        ↓（smoke test 通过后）
push-registry.yml（镜像同步 → 阿里云ACR / 华为SWR）
        ↓（push 成功后）
sync-oss.yml + sync-obs.yml（压缩包同步 → OSS / OBS）
        ↓
notify.yml（汇总报告，失败时告警）
```

---

## 阶段五：目标机端到端验证（Staging 环境）

**目标**：在一台"干净"的 Ubuntu 22.04 / openEuler 22.03 机器上，完整跑通离线部署流程。

### 5.1 手动验证步骤

1. 准备一台**无外网访问**的测试机（或关闭网络后测试）
2. 提前从 OSS 下载镜像包到本地：
   ```bash
   # 在有网络的机器上下载
   ossutil cp -r oss://<bucket>/devenv/latest/ ./devenv-packages/
   ```
3. 将包复制到目标机（scp 或 USB 介质）
4. 在目标机执行：
   ```bash
   bash load.sh --scene full --arch amd64
   devenv /path/to/project  # 验证容器可正常启动
   ```
5. 在容器内验证完整工具链功能

### 5.2 Ansible 批量验证

使用 `ansible/playbooks/health-check.yml` 对多台目标机批量验证：

```bash
# 编辑 ansible/inventory/hosts.ini，添加测试机
make ansible-health
```

---

## 未来计划：arm64 支持（麒麟/鲲鹏 ARM）

> **触发条件**：amd64 所有阶段验证稳定（完成阶段一至三）后再启动。

### 为什么需要 arm64

- 鲲鹏（Kunpeng）服务器使用 ARMv8 架构，运行麒麟（Kylin）OS
- 政企场景中国产化要求往往需要鲲鹏 + 麒麟/openEuler 组合
- kunpeng-kylin-ansible 的目标机即为此类环境

### 扩展步骤

1. **在 matrix.yaml 中为每个镜像增加 `linux/arm64` 平台**
2. **为 build-matrix.yml 增加 QEMU 模拟器支持**：
   ```yaml
   - name: Set up QEMU
     uses: docker/setup-qemu-action@v3
     with:
       platforms: arm64
   ```
3. **在 Dockerfile 中处理 arm64 差异**：
   - GCC 14：从 Ubuntu arm64 PPA 或源码编译
   - CMake：从 GitHub Releases 下载 `cmake-*-linux-aarch64.sh`
   - Google Benchmark：需要在 arm64 下编译
4. **增加 arm64 smoke test**
5. **测试麒麟 OS 兼容性**：openEuler 22.03 arm64 作为替代

### 优先级建议

| 镜像 | arm64 优先级 | 说明 |
|------|------------|------|
| `base-openeuler` | ⭐⭐⭐ 最高 | 直接替代麒麟 OS，arm64 版本官方支持 |
| `toolchain-common` | ⭐⭐⭐ 最高 | Git/zsh 等基础工具，无架构障碍 |
| `toolchain-python` | ⭐⭐ 高 | Python 官方支持 arm64 |
| `toolchain-cpp` | ⭐⭐ 高 | GCC/Clang arm64 版本成熟 |
| `services-ansible` | ⭐ 中 | 依赖 Python，跟随 python 镜像 |
| `compose-full` | ⭐ 中 | 最终组合层，等上层稳定后构建 |
| `toolchain-gbench` | △ 低 | 性能测试工具，arm64 编译较复杂 |

---

## 进度跟踪

```
阶段一：手动构建 GHCR 镜像
  [TODO] 开启 GitHub repo Packages 写权限
  [TODO] 触发 build-matrix.yml → layer: base
  [TODO] 验证 base-ubuntu + base-openeuler 镜像可 pull
  [TODO] 触发 build-matrix.yml → layer: toolchain
  [TODO] 验证 GCC/CMake/Python 版本
  [TODO] 触发 build-matrix.yml → layer: services
  [TODO] 触发 build-matrix.yml → layer: compose
  [TODO] 完整 smoke test compose-full 镜像

阶段二：国内云平台推送
  [TODO] 配置 GitHub Secrets（阿里云 ACR + OSS）
  [TODO] 测试 GHCR → ACR 推送
  [TODO] 测试 GHCR → OSS 压缩包同步
  [TODO] 模拟目标机离线 docker load

阶段三：自动化验证
  [TODO] 编写 scripts/smoke-test.sh
  [TODO] 新增 .github/workflows/smoke-test.yml
  [TODO] 集成到 build-matrix.yml 构建后自动触发

阶段四：端到端自动化
  [TODO] auto-update.yml 增加定时触发
  [TODO] 增强上游版本检测（全部工具）
  [TODO] 实现 push/sync 串联自动化
  [TODO] 构建失败通知机制

阶段五：目标机验证
  [TODO] 准备 Staging 测试机（无外网）
  [TODO] 端到端验证离线加载流程
  [TODO] Ansible 批量健康检查

未来：arm64 支持
  [TODO] amd64 完全稳定后启动
  [TODO] base-openeuler arm64 作为首个 arm64 镜像
```

---

*最后更新：2026-03 | 维护者：ckLXHL + GitHub Copilot*
