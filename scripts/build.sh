#!/bin/bash
# 构建统一入口脚本
# 用法: ./scripts/build.sh [选项]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 默认值
LAYER="${LAYER:-all}"
IMAGE="${IMAGE:-}"
ARCH="${ARCH:-}"
DRY_RUN="${DRY_RUN:-false}"
PUSH="${PUSH:-false}"
CACHE="${CACHE:-true}"
REGISTRY="${REGISTRY:-ghcr.io/ckLXHL}"
PLATFORM_MAP_amd64="linux/amd64"
PLATFORM_MAP_arm64="linux/arm64"
PLATFORM_MAP_all="linux/amd64,linux/arm64"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }

# 确保 BuildKit 可用
export DOCKER_BUILDKIT=1

# 检查 buildx 支持
check_buildx() {
    if ! docker buildx version &>/dev/null; then
        error "需要 Docker Buildx，请升级 Docker 或安装 buildx 插件"
    fi
    # 创建多架构 builder（如果不存在）
    if ! docker buildx inspect devenv-builder &>/dev/null; then
        log "创建多架构 builder..."
        docker buildx create \
            --name devenv-builder \
            --driver docker-container \
            --use \
            --bootstrap
    else
        docker buildx use devenv-builder
    fi
}

# 构建单个镜像
build_image() {
    local name="$1"
    local context="$2"
    local dockerfile="$3"
    local version="$4"
    local build_args="${5:-}"
    local platforms="${6:-linux/amd64,linux/arm64}"

    local tag="${REGISTRY}/${name}:${version}"
    local latest_tag="${REGISTRY}/${name}:latest"

    log "构建: ${tag} (平台: ${platforms})"

    if [ "${DRY_RUN}" = "true" ]; then
        log "[DRY RUN] docker buildx build --platform ${platforms} -t ${tag} ${context}"
        return 0
    fi

    local build_cmd=(
        docker buildx build
        --platform "${platforms}"
        --file "${PROJECT_ROOT}/${dockerfile}"
        --tag "${tag}"
        --tag "${latest_tag}"
        --build-arg "REGISTRY=${REGISTRY}"
    )

    # 解析 build_args（格式: KEY=VALUE,KEY2=VALUE2）
    if [ -n "${build_args}" ]; then
        IFS=',' read -ra args_array <<< "${build_args}"
        for arg in "${args_array[@]}"; do
            build_cmd+=(--build-arg "${arg}")
        done
    fi

    # 缓存策略
    if [ "${CACHE}" = "true" ]; then
        build_cmd+=(
            --cache-from "type=registry,ref=${tag}-cache"
            --cache-to "type=registry,ref=${tag}-cache,mode=max"
        )
    fi

    # 推送或仅构建
    # 注意: --load 仅支持单架构构建；多架构时使用 --push 或 --output type=oci
    if [ "${PUSH}" = "true" ]; then
        build_cmd+=(--push)
    else
        # 多架构构建时无法使用 --load，改用 --output 导出到本地 OCI 包
        local platform_count
        platform_count=$(echo "${platforms}" | tr ',' '\n' | wc -l)
        if [ "${platform_count}" -gt 1 ]; then
            local oci_dir="${WORK_DIR:-/tmp/devenv-build}/${name}"
            mkdir -p "${oci_dir}"
            build_cmd+=(--output "type=oci,dest=${oci_dir}/image.tar")
            log "多架构本地导出到: ${oci_dir}/image.tar"
        else
            build_cmd+=(--load)
        fi
    fi

    build_cmd+=("${PROJECT_ROOT}/${context}")

    "${build_cmd[@]}"
    log "构建完成: ${tag}"
}

# 从 matrix.yaml 读取构建配置
build_from_matrix() {
    local filter_layer="${1:-all}"
    local filter_image="${2:-}"
    local filter_arch="${3:-}"

    python3 -c "
import yaml
import sys
import json

with open('${PROJECT_ROOT}/config/matrix.yaml') as f:
    config = yaml.safe_load(f)

filter_layer = '${filter_layer}'
filter_image = '${filter_image}'
filter_arch = '${filter_arch}'

images = config['images']

# 过滤
if filter_layer != 'all':
    layer_map = {'base': 0, 'toolchain': 1, 'services': 2, 'compose': 3}
    if filter_layer in layer_map:
        images = [img for img in images if img.get('layer') == layer_map[filter_layer]]

if filter_image:
    images = [img for img in images if filter_image in img['name']]

# 拓扑排序（DAG）
def topo_sort(images):
    name_to_img = {img['name']: img for img in images}
    visited = set()
    result = []

    def visit(name):
        if name in visited:
            return
        visited.add(name)
        img = name_to_img.get(name)
        if img:
            for dep in img.get('depends_on', []):
                visit(dep)
            result.append(img)

    for img in images:
        visit(img['name'])
    return result

sorted_images = topo_sort(images)

for img in sorted_images:
    platforms = img.get('platforms', ['linux/amd64', 'linux/arm64'])
    if filter_arch:
        platforms = [p for p in platforms if filter_arch in p]
    platforms_str = ','.join(platforms)

    build_args = ','.join(f\"{k}={v}\" for k, v in img.get('build_args', {}).items())
    print(f\"{img['name']}|{img.get('context', img['name'])}|{img.get('dockerfile', img['name'] + '/Dockerfile')}|{img.get('version', 'latest')}|{build_args}|{platforms_str}\")
"
}

# 主构建流程
main() {
    check_buildx

    log "开始构建 (LAYER=${LAYER}, IMAGE=${IMAGE:-*}, ARCH=${ARCH:-all})"

    while IFS='|' read -r name context dockerfile version build_args platforms; do
        [ -z "${name}" ] && continue
        build_image "${name}" "${context}" "${dockerfile}" "${version}" "${build_args}" "${platforms}"
    done < <(build_from_matrix "${LAYER}" "${IMAGE}" "${ARCH}")

    log "所有构建任务完成"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --layer)   LAYER="$2"; shift 2 ;;
        --image)   IMAGE="$2"; shift 2 ;;
        --arch)    ARCH="$2"; shift 2 ;;
        --dry-run) DRY_RUN="true"; shift ;;
        --push)    PUSH="true"; shift ;;
        --no-cache) CACHE="false"; shift ;;
        --registry) REGISTRY="$2"; shift 2 ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "  --layer <base|toolchain|services|compose|all>  构建指定层（默认: all）"
            echo "  --image <name>   构建指定镜像"
            echo "  --arch <amd64|arm64>  指定架构（默认: 双架构）"
            echo "  --push           构建后推送到镜像仓库"
            echo "  --no-cache       不使用缓存"
            echo "  --dry-run        预览模式，不实际构建"
            echo "  --registry <url> 镜像仓库地址（默认: ghcr.io/ckLXHL）"
            exit 0 ;;
        *) error "未知参数: $1" ;;
    esac
done

main
