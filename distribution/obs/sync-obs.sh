#!/bin/bash
# 华为云OBS同步脚本
# 将 Docker 镜像导出为 .tar.zst 并上传到华为云OBS
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 加载配置
: "${HUAWEI_OBS_BUCKET:?需要设置 HUAWEI_OBS_BUCKET 环境变量}"
: "${HUAWEI_OBS_ENDPOINT:?需要设置 HUAWEI_OBS_ENDPOINT 环境变量}"
: "${HUAWEI_OBS_ACCESS_KEY:?需要设置 HUAWEI_OBS_ACCESS_KEY 环境变量}"
: "${HUAWEI_OBS_SECRET_KEY:?需要设置 HUAWEI_OBS_SECRET_KEY 环境变量}"

REGISTRY="${REGISTRY:-ghcr.io/ckLXHL}"
VERSION="${VERSION:-latest}"
ARCH="${ARCH:-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')}"
OBS_PREFIX="${OBS_PREFIX:-devenv}"
WORK_DIR="${WORK_DIR:-/tmp/devenv-obs}"
COMPRESS_LEVEL="${COMPRESS_LEVEL:-3}"

mkdir -p "${WORK_DIR}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }

# 安装 obsutil（如果尚未安装）
install_obsutil() {
    if command -v obsutil &>/dev/null; then
        return 0
    fi
    log "安装 obsutil..."
    OBSUTIL_ARCH="${ARCH}"
    case "${ARCH}" in
        amd64) OBSUTIL_ARCH="amd64" ;;
        arm64) OBSUTIL_ARCH="arm64" ;;
        *) error "不支持的架构: ${ARCH}"; exit 1 ;;
    esac
    local obsutil_ver="5.5.12"
    curl -fsSL "https://obs-community-intl.obs.ap-southeast-1.myhuaweicloud.com/obsutil/${obsutil_ver}/obsutil_linux_${OBSUTIL_ARCH}.tar.gz" \
        -o /tmp/obsutil.tar.gz
    tar -xzf /tmp/obsutil.tar.gz -C /tmp/
    install -m 755 /tmp/obsutil_linux_${OBSUTIL_ARCH}/obsutil /usr/local/bin/obsutil
    rm -rf /tmp/obsutil.tar.gz /tmp/obsutil_linux_${OBSUTIL_ARCH}/
    log "obsutil 安装完成"
}

# 配置 obsutil
configure_obsutil() {
    obsutil config \
        -i="${HUAWEI_OBS_ACCESS_KEY}" \
        -k="${HUAWEI_OBS_SECRET_KEY}" \
        -e="${HUAWEI_OBS_ENDPOINT}"
}

# 导出并压缩镜像
export_image() {
    local image_name="$1"
    local image_tag="${REGISTRY}/${image_name}:${VERSION}"
    local filename="devenv-${image_name}-${VERSION}-${ARCH}.tar.zst"
    local filepath="${WORK_DIR}/${filename}"

    log "导出镜像: ${image_tag} -> ${filename}"

    if command -v skopeo &>/dev/null; then
        skopeo copy \
            "docker://${image_tag}" \
            "oci-archive:${filepath%.zst}.tar" \
            --override-arch="${ARCH}"
        log "压缩: ${filename}"
        zstd -${COMPRESS_LEVEL} --rm "${filepath%.zst}.tar" -o "${filepath}"
    else
        docker pull "${image_tag}"
        docker save "${image_tag}" | zstd -${COMPRESS_LEVEL} -o "${filepath}"
    fi

    sha256sum "${filepath}" > "${filepath}.sha256"
    log "SHA256: $(cat "${filepath}.sha256")"

    echo "${filepath}"
}

# 上传到 OBS
upload_to_obs() {
    local filepath="$1"
    local filename
    filename="$(basename "${filepath}")"
    local obs_path="obs://${HUAWEI_OBS_BUCKET}/${OBS_PREFIX}/${VERSION}/images/${filename}"

    log "上传: ${filename} -> ${obs_path}"
    obsutil cp "${filepath}" "${obs_path}" \
        -f \
        -p=10 \
        -threshold=104857600

    obsutil cp "${filepath}.sha256" "${obs_path}.sha256" -f

    log "上传完成: ${obs_path}"
}

# 更新 latest
update_latest() {
    local image_name="$1"
    local filename="devenv-${image_name}-${VERSION}-${ARCH}.tar.zst"
    local latest_filename="devenv-${image_name}-latest-${ARCH}.tar.zst"
    local src="obs://${HUAWEI_OBS_BUCKET}/${OBS_PREFIX}/${VERSION}/images/${filename}"
    local dst="obs://${HUAWEI_OBS_BUCKET}/${OBS_PREFIX}/latest/${latest_filename}"

    log "更新 latest: ${src} -> ${dst}"
    obsutil cp "${src}" "${dst}" -f
    obsutil cp "${src}.sha256" "${dst}.sha256" -f
}

# 生成版本 manifest
generate_manifest() {
    local manifest_file="${WORK_DIR}/manifest.json"
    log "生成 manifest.json"

    python3 -c "
import json
import os
import glob
from datetime import datetime

manifest = {
    'version': '${VERSION}',
    'arch': '${ARCH}',
    'created_at': datetime.utcnow().isoformat() + 'Z',
    'images': []
}

for sha256_file in glob.glob('${WORK_DIR}/*.sha256'):
    tar_file = sha256_file[:-7]
    if os.path.exists(tar_file):
        with open(sha256_file) as f:
            sha256 = f.read().split()[0]
        filename = os.path.basename(tar_file)
        image_name = filename.replace('devenv-', '').replace('-${VERSION}-${ARCH}.tar.zst', '')
        manifest['images'].append({
            'name': image_name,
            'filename': filename,
            'sha256': sha256,
            'size': os.path.getsize(tar_file)
        })

with open('${manifest_file}', 'w') as f:
    json.dump(manifest, f, indent=2, ensure_ascii=False)
print(json.dumps(manifest, indent=2, ensure_ascii=False))
"

    obsutil cp "${manifest_file}" \
        "obs://${HUAWEI_OBS_BUCKET}/${OBS_PREFIX}/${VERSION}/manifest.json" -f
    obsutil cp "${manifest_file}" \
        "obs://${HUAWEI_OBS_BUCKET}/${OBS_PREFIX}/latest/manifest.json" -f
}

# 主流程
main() {
    local images=("$@")

    if [ ${#images[@]} -eq 0 ]; then
        log "未指定镜像，从 matrix.yaml 读取..."
        images=($(python3 -c "
import yaml
with open('${PROJECT_ROOT}/config/matrix.yaml') as f:
    config = yaml.safe_load(f)
print(' '.join(img['name'] for img in config['images']))
"))
    fi

    install_obsutil
    configure_obsutil

    for image in "${images[@]}"; do
        filepath=$(export_image "${image}")
        upload_to_obs "${filepath}"
        if [ "${UPDATE_LATEST:-true}" = "true" ]; then
            update_latest "${image}"
        fi
    done

    generate_manifest
    log "所有镜像已同步到华为云OBS"
}

main "$@"
