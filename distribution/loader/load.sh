#!/bin/bash
# 目标机镜像加载脚本
# 从 OSS/OBS 下载并加载 Docker/Podman 镜像，无需外网访问
set -euo pipefail

# ============================================================
# 配置区域（按实际环境修改）
# ============================================================
REGISTRY_SOURCE="${REGISTRY_SOURCE:-oss}"  # oss 或 obs
SCENE="${SCENE:-full}"                      # full / cpp / python
ARCH="${ARCH:-}"                            # 留空则自动检测
VERSION="${VERSION:-latest}"
RUNTIME="${RUNTIME:-}"                      # 留空则自动检测

# OSS 配置（使用内网 Endpoint 实现免流量费用传输）
OSS_BUCKET="${OSS_BUCKET:-}"
OSS_ENDPOINT="${OSS_ENDPOINT:-}"           # 内网 Endpoint 示例: oss-cn-hangzhou-internal.aliyuncs.com
OSS_ACCESS_KEY="${OSS_ACCESS_KEY:-}"
OSS_SECRET_KEY="${OSS_SECRET_KEY:-}"

# OBS 配置
OBS_BUCKET="${OBS_BUCKET:-}"
OBS_ENDPOINT="${OBS_ENDPOINT:-}"
OBS_ACCESS_KEY="${OBS_ACCESS_KEY:-}"
OBS_SECRET_KEY="${OBS_SECRET_KEY:-}"

# HTTP 分发服务器（备选）
HTTP_BASE_URL="${HTTP_BASE_URL:-}"

WORK_DIR="${WORK_DIR:-/tmp/devenv-loader}"
INSTALL_DIR="${INSTALL_DIR:-/opt/devenv}"
PREFIX="devenv"

mkdir -p "${WORK_DIR}" "${INSTALL_DIR}"

# ============================================================
# 工具函数
# ============================================================
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }

# 检测系统架构
detect_arch() {
    if [ -n "${ARCH}" ]; then
        echo "${ARCH}"
        return
    fi
    local machine
    machine=$(uname -m)
    case "${machine}" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        arm64)   echo "arm64" ;;
        *) error "不支持的架构: ${machine}" ;;
    esac
}

# 检测可用的容器运行时
detect_runtime() {
    if [ -n "${RUNTIME}" ]; then
        echo "${RUNTIME}"
        return
    fi
    if command -v podman &>/dev/null; then
        echo "podman"
    elif command -v docker &>/dev/null; then
        echo "docker"
    elif command -v nerdctl &>/dev/null; then
        echo "nerdctl"
    else
        error "未找到容器运行时（docker/podman/nerdctl），请先安装"
    fi
}

# 根据场景获取所需镜像列表
get_images_for_scene() {
    local scene="$1"
    case "${scene}" in
        full)
            echo "toolchain-common toolchain-cpp toolchain-python services-docker services-ansible compose-full"
            ;;
        cpp)
            echo "toolchain-common toolchain-cpp toolchain-gbench compose-cpp"
            ;;
        python)
            echo "toolchain-common toolchain-python compose-python"
            ;;
        base)
            echo "base-ubuntu"
            ;;
        *)
            error "未知场景: ${scene}，可用场景: full/cpp/python/base"
            ;;
    esac
}

# 从 OSS 下载文件
download_from_oss() {
    local remote_path="$1"
    local local_path="$2"

    if ! command -v ossutil &>/dev/null; then
        error "ossutil 未安装，请先运行 bootstrap.sh 初始化环境"
    fi

    ossutil cp "oss://${OSS_BUCKET}/${remote_path}" "${local_path}" \
        --config-file ~/.ossutilconfig \
        --checkpoint-dir "${WORK_DIR}/.checkpoint" \
        --force
}

# 从 OBS 下载文件
download_from_obs() {
    local remote_path="$1"
    local local_path="$2"

    if ! command -v obsutil &>/dev/null; then
        error "obsutil 未安装，请先运行 bootstrap.sh 初始化环境"
    fi

    obsutil cp "obs://${OBS_BUCKET}/${remote_path}" "${local_path}" -f
}

# 从 HTTP 下载文件（支持断点续传）
download_from_http() {
    local url="$1"
    local local_path="$2"

    log "从 HTTP 下载: ${url}"
    curl -fsSL --retry 3 --retry-delay 5 -C - -o "${local_path}" "${url}"
}

# 统一下载函数
download_file() {
    local filename="$1"
    local local_path="${WORK_DIR}/${filename}"

    # 如果文件已存在且校验通过，跳过下载
    if [ -f "${local_path}" ] && [ -f "${local_path}.sha256" ]; then
        log "文件已存在，校验 SHA256..."
        if sha256sum -c "${local_path}.sha256" &>/dev/null; then
            log "校验通过，跳过下载: ${filename}"
            echo "${local_path}"
            return
        else
            warn "校验失败，重新下载: ${filename}"
            rm -f "${local_path}" "${local_path}.sha256"
        fi
    fi

    local remote_path="${PREFIX}/${VERSION}/images/${filename}"

    log "下载: ${filename}"
    case "${REGISTRY_SOURCE}" in
        oss)
            download_from_oss "${remote_path}" "${local_path}"
            download_from_oss "${remote_path}.sha256" "${local_path}.sha256"
            ;;
        obs)
            download_from_obs "${remote_path}" "${local_path}"
            download_from_obs "${remote_path}.sha256" "${local_path}.sha256"
            ;;
        http)
            download_from_http "${HTTP_BASE_URL}/${remote_path}" "${local_path}"
            download_from_http "${HTTP_BASE_URL}/${remote_path}.sha256" "${local_path}.sha256"
            ;;
        *)
            error "未知分发源: ${REGISTRY_SOURCE}，可用: oss/obs/http"
            ;;
    esac

    # 校验 SHA256
    log "校验 SHA256..."
    sha256sum -c "${local_path}.sha256" || error "SHA256 校验失败: ${filename}"
    log "校验通过: ${filename}"

    echo "${local_path}"
}

# 加载镜像
load_image() {
    local filepath="$1"
    local runtime="$2"

    log "加载镜像: $(basename "${filepath}") (运行时: ${runtime})"

    # 解压 .tar.zst
    local tar_path="${filepath%.zst}"
    if [ "${filepath}" != "${tar_path}" ]; then
        log "解压..."
        zstd -d "${filepath}" -o "${tar_path}" --force
    fi

    # 加载镜像
    case "${runtime}" in
        docker)
            docker load -i "${tar_path}"
            ;;
        podman)
            podman load -i "${tar_path}"
            ;;
        nerdctl)
            nerdctl load -i "${tar_path}"
            ;;
        *)
            error "未知运行时: ${runtime}"
            ;;
    esac

    # 清理解压的 tar 文件（保留 .zst 用于断点续传）
    rm -f "${tar_path}"
    log "加载完成: $(basename "${filepath}")"
}

# 获取 manifest
fetch_manifest() {
    local manifest_path="${WORK_DIR}/manifest.json"
    local remote_path="${PREFIX}/${VERSION}/manifest.json"

    log "获取版本清单..."
    case "${REGISTRY_SOURCE}" in
        oss)  download_from_oss "${remote_path}" "${manifest_path}" ;;
        obs)  download_from_obs "${remote_path}" "${manifest_path}" ;;
        http) download_from_http "${HTTP_BASE_URL}/${remote_path}" "${manifest_path}" ;;
    esac

    cat "${manifest_path}"
}

# 主流程
main() {
    local arch
    arch=$(detect_arch)
    local runtime
    runtime=$(detect_runtime)

    log "=========================================="
    log "Cloud Dev Environment Loader"
    log "场景: ${SCENE} | 架构: ${arch} | 运行时: ${runtime}"
    log "版本: ${VERSION} | 分发源: ${REGISTRY_SOURCE}"
    log "=========================================="

    # 获取所需镜像列表
    local images
    read -ra images <<< "$(get_images_for_scene "${SCENE}")"

    log "需要加载的镜像: ${images[*]}"

    # 配置分发工具
    if [ "${REGISTRY_SOURCE}" = "oss" ]; then
        : "${OSS_BUCKET:?需要设置 OSS_BUCKET}"
        ossutil config \
            --endpoint "${OSS_ENDPOINT}" \
            --access-key-id "${OSS_ACCESS_KEY}" \
            --access-key-secret "${OSS_SECRET_KEY}" \
            --config-file ~/.ossutilconfig 2>/dev/null || true
    elif [ "${REGISTRY_SOURCE}" = "obs" ]; then
        : "${OBS_BUCKET:?需要设置 OBS_BUCKET}"
        obsutil config \
            -i="${OBS_ACCESS_KEY}" \
            -k="${OBS_SECRET_KEY}" \
            -e="${OBS_ENDPOINT}" 2>/dev/null || true
    fi

    # 下载并加载每个镜像
    for image in "${images[@]}"; do
        local filename="devenv-${image}-${VERSION}-${arch}.tar.zst"
        local filepath
        filepath=$(download_file "${filename}")
        load_image "${filepath}" "${runtime}"
    done

    log "=========================================="
    log "所有镜像加载完成！"
    log "运行方式："
    log "  ${runtime} run -it --rm ghcr.io/ckLXHL/compose-${SCENE}:${VERSION}"
    log "=========================================="
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scene)     SCENE="$2"; shift 2 ;;
        --arch)      ARCH="$2"; shift 2 ;;
        --version)   VERSION="$2"; shift 2 ;;
        --runtime)   RUNTIME="$2"; shift 2 ;;
        --registry)  REGISTRY_SOURCE="$2"; shift 2 ;;
        --work-dir)  WORK_DIR="$2"; shift 2 ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "  --scene <full|cpp|python|base>  选择场景（默认: full）"
            echo "  --arch  <amd64|arm64>           指定架构（默认: 自动检测）"
            echo "  --version <version>              指定版本（默认: latest）"
            echo "  --runtime <docker|podman|nerdctl> 指定运行时（默认: 自动检测）"
            echo "  --registry <oss|obs|http>        指定分发源（默认: oss）"
            exit 0
            ;;
        *)
            error "未知参数: $1"
            ;;
    esac
done

main
