#!/bin/bash
# OSS/OBS 同步入口脚本
# 将构建好的镜像同步到阿里云OSS和/或华为OBS
# 用法: ./scripts/sync.sh [选项]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET="${TARGET:-oss}"    # oss / obs / all
VERSION="${VERSION:-latest}"
ARCH="${ARCH:-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')}"
IMAGES="${IMAGES:-}"       # 留空则同步所有镜像

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }

main() {
    case "${TARGET}" in
        oss)
            log "同步到阿里云OSS..."
            export VERSION ARCH
            [ -n "${IMAGES}" ] && export IMAGES
            bash "${PROJECT_ROOT}/distribution/oss/sync-oss.sh" ${IMAGES}
            ;;
        obs)
            log "同步到华为OBS..."
            export VERSION ARCH
            [ -n "${IMAGES}" ] && export IMAGES
            bash "${PROJECT_ROOT}/distribution/obs/sync-obs.sh" ${IMAGES}
            ;;
        all)
            log "同步到所有对象存储..."
            export VERSION ARCH
            bash "${PROJECT_ROOT}/distribution/oss/sync-oss.sh" ${IMAGES}
            bash "${PROJECT_ROOT}/distribution/obs/sync-obs.sh" ${IMAGES}
            ;;
        *)
            error "未知目标: ${TARGET}，可用: oss/obs/all"
            ;;
    esac

    log "同步完成"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)  TARGET="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --arch)    ARCH="$2"; shift 2 ;;
        --images)  IMAGES="$2"; shift 2 ;;
        oss)       TARGET="oss"; shift ;;
        obs)       TARGET="obs"; shift ;;
        all)       TARGET="all"; shift ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "  --target <oss|obs|all>  同步目标（默认: oss）"
            echo "  --version <ver>          版本标签"
            echo "  --arch <amd64|arm64>     架构"
            echo "  --images <list>          指定镜像列表（空格分隔）"
            exit 0 ;;
        *) error "未知参数: $1" ;;
    esac
done

main
