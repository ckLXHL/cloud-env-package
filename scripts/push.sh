#!/bin/bash
# 推送统一入口脚本
# 用法: ./scripts/push.sh [选项]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

LAYER="${LAYER:-all}"
IMAGE="${IMAGE:-}"
REGISTRY="${REGISTRY:-ghcr}"
VERSION="${VERSION:-latest}"
ALL_REGISTRIES="${ALL_REGISTRIES:-false}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; exit 1; }

# 从 registry.yaml 获取仓库 URL
get_registry_url() {
    local name="$1"
    python3 -c "
import yaml
with open('${PROJECT_ROOT}/config/registry.yaml') as f:
    config = yaml.safe_load(f)
for reg in config['registries']:
    if reg['name'] == '${name}':
        print(reg['url'])
        break
else:
    print('${name}')
"
}

# 获取所有仓库名称
get_all_registries() {
    python3 -c "
import yaml
with open('${PROJECT_ROOT}/config/registry.yaml') as f:
    config = yaml.safe_load(f)
print(' '.join(r['name'] for r in config['registries']))
"
}

# 获取镜像列表
get_images() {
    python3 -c "
import yaml
with open('${PROJECT_ROOT}/config/matrix.yaml') as f:
    config = yaml.safe_load(f)

filter_layer = '${LAYER}'
filter_image = '${IMAGE}'

images = config['images']
layer_map = {'base': 0, 'toolchain': 1, 'services': 2, 'compose': 3}

if filter_layer != 'all' and filter_layer in layer_map:
    images = [img for img in images if img.get('layer') == layer_map[filter_layer]]

if filter_image:
    images = [img for img in images if filter_image in img['name']]

for img in images:
    print(f\"{img['name']}|{img.get('version', 'latest')}\")
"
}

# 推送单个镜像到指定仓库
push_to_registry() {
    local image_name="$1"
    local version="$2"
    local target_registry="$3"

    local src_registry
    src_registry=$(get_registry_url "ghcr")
    local dst_registry
    dst_registry=$(get_registry_url "${target_registry}")

    local src_tag="${src_registry}/${image_name}:${version}"
    local dst_tag="${dst_registry}/${image_name}:${version}"
    local dst_latest="${dst_registry}/${image_name}:latest"

    log "推送: ${src_tag} -> ${dst_tag}"

    if command -v skopeo &>/dev/null; then
        # 使用 skopeo 复制（支持跨仓库推送，无需本地 pull）
        skopeo copy \
            --all \
            "docker://${src_tag}" \
            "docker://${dst_tag}"
        skopeo copy \
            --all \
            "docker://${src_tag}" \
            "docker://${dst_latest}"
    else
        # 回退到 docker
        docker pull "${src_tag}"
        docker tag "${src_tag}" "${dst_tag}"
        docker tag "${src_tag}" "${dst_latest}"
        docker push "${dst_tag}"
        docker push "${dst_latest}"
    fi

    log "推送完成: ${dst_tag}"
}

# 创建多架构 manifest
push_manifest() {
    local image_name="$1"
    local version="$2"
    local registry_url="$3"

    local manifest_tag="${registry_url}/${image_name}:${version}"
    local amd64_tag="${registry_url}/${image_name}:${version}-amd64"
    local arm64_tag="${registry_url}/${image_name}:${version}-arm64"

    log "创建 manifest: ${manifest_tag}"
    docker manifest create "${manifest_tag}" \
        --amend "${amd64_tag}" \
        --amend "${arm64_tag}"
    docker manifest push "${manifest_tag}"
    log "Manifest 创建完成: ${manifest_tag}"
}

# 主推送流程
main() {
    local target_registries

    if [ "${ALL_REGISTRIES}" = "true" ]; then
        read -ra target_registries <<< "$(get_all_registries)"
    else
        read -ra target_registries <<< "${REGISTRY}"
    fi

    log "推送到仓库: ${target_registries[*]}"

    while IFS='|' read -r name version; do
        [ -z "${name}" ] && continue
        for reg in "${target_registries[@]}"; do
            push_to_registry "${name}" "${version}" "${reg}"
        done
    done < <(get_images)

    log "所有推送任务完成"
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --layer)   LAYER="$2"; shift 2 ;;
        --image)   IMAGE="$2"; shift 2 ;;
        --registry) REGISTRY="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --all-registries) ALL_REGISTRIES="true"; shift ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "  --layer <base|toolchain|services|compose|all>  推送指定层"
            echo "  --image <name>   推送指定镜像"
            echo "  --registry <name>  目标仓库（默认: ghcr）"
            echo "  --all-registries   推送到所有配置的仓库"
            echo "  --version <ver>  指定版本（默认: latest）"
            exit 0 ;;
        *) error "未知参数: $1" ;;
    esac
done

main
