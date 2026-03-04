#!/bin/bash
# 阿里云OSS同步脚本
# 将 Docker 镜像导出为 .tar.zst 并上传到阿里云OSS
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# 加载配置
: "${ALIYUN_OSS_BUCKET:?需要设置 ALIYUN_OSS_BUCKET 环境变量}"
: "${ALIYUN_OSS_ENDPOINT:?需要设置 ALIYUN_OSS_ENDPOINT 环境变量}"
: "${ALIYUN_OSS_ACCESS_KEY:?需要设置 ALIYUN_OSS_ACCESS_KEY 环境变量}"
: "${ALIYUN_OSS_SECRET_KEY:?需要设置 ALIYUN_OSS_SECRET_KEY 环境变量}"

REGISTRY="${REGISTRY:-ghcr.io/ckLXHL}"
VERSION="${VERSION:-latest}"
ARCH="${ARCH:-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')}"
OSS_PREFIX="${OSS_PREFIX:-devenv}"
WORK_DIR="${WORK_DIR:-/tmp/devenv-oss}"
COMPRESS_LEVEL="${COMPRESS_LEVEL:-3}"  # zstd 压缩级别，1-22，3为平衡点

mkdir -p "${WORK_DIR}"

# 日志函数
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }

# 安装 ossutil（如果尚未安装）
install_ossutil() {
    if command -v ossutil &>/dev/null; then
        return 0
    fi
    log "安装 ossutil..."
    OSSUTIL_ARCH="${ARCH}"
    case "${ARCH}" in
        amd64) OSSUTIL_ARCH="amd64" ;;
        arm64) OSSUTIL_ARCH="arm64" ;;
        *) error "不支持的架构: ${ARCH}"; exit 1 ;;
    esac
    curl -fsSL "https://gosspublic.alicdn.com/ossutil/1.7.17/ossutil-v1.7.17-linux-${OSSUTIL_ARCH}.zip" \
        -o /tmp/ossutil.zip
    unzip -q /tmp/ossutil.zip -d /tmp/ossutil/
    install -m 755 /tmp/ossutil/ossutil-v1.7.17-linux-${OSSUTIL_ARCH}/ossutil /usr/local/bin/ossutil
    rm -rf /tmp/ossutil.zip /tmp/ossutil/
    log "ossutil 安装完成"
}

# 配置 ossutil
configure_ossutil() {
    ossutil config \
        --endpoint "${ALIYUN_OSS_ENDPOINT}" \
        --access-key-id "${ALIYUN_OSS_ACCESS_KEY}" \
        --access-key-secret "${ALIYUN_OSS_SECRET_KEY}" \
        --config-file ~/.ossutilconfig
}

# 导出并压缩镜像
export_image() {
    local image_name="$1"
    local image_tag="${REGISTRY}/${image_name}:${VERSION}"
    local filename="devenv-${image_name}-${VERSION}-${ARCH}.tar.zst"
    local filepath="${WORK_DIR}/${filename}"

    log "导出镜像: ${image_tag} -> ${filename}"

    # 使用 skopeo 或 docker 导出
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

    # 计算 SHA256
    sha256sum "${filepath}" > "${filepath}.sha256"
    log "SHA256: $(cat "${filepath}.sha256")"

    echo "${filepath}"
}

# 上传到 OSS
upload_to_oss() {
    local filepath="$1"
    local filename
    filename="$(basename "${filepath}")"
    local oss_path="oss://${ALIYUN_OSS_BUCKET}/${OSS_PREFIX}/${VERSION}/images/${filename}"

    log "上传: ${filename} -> ${oss_path}"
    ossutil cp "${filepath}" "${oss_path}" \
        --config-file ~/.ossutilconfig \
        --checkpoint-dir "${WORK_DIR}/.checkpoint" \
        --part-size 104857600 \
        --parallel 5 \
        --force

    # 同时上传 SHA256
    ossutil cp "${filepath}.sha256" "${oss_path}.sha256" \
        --config-file ~/.ossutilconfig --force

    log "上传完成: ${oss_path}"
}

# 更新 latest 软链（通过复制方式实现）
update_latest() {
    local image_name="$1"
    local filename="devenv-${image_name}-${VERSION}-${ARCH}.tar.zst"
    local latest_filename="devenv-${image_name}-latest-${ARCH}.tar.zst"
    local src="oss://${ALIYUN_OSS_BUCKET}/${OSS_PREFIX}/${VERSION}/images/${filename}"
    local dst="oss://${ALIYUN_OSS_BUCKET}/${OSS_PREFIX}/latest/${latest_filename}"

    log "更新 latest: ${src} -> ${dst}"
    ossutil cp "${src}" "${dst}" \
        --config-file ~/.ossutilconfig --force
    ossutil cp "${src}.sha256" "${dst}.sha256" \
        --config-file ~/.ossutilconfig --force
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

    ossutil cp "${manifest_file}" \
        "oss://${ALIYUN_OSS_BUCKET}/${OSS_PREFIX}/${VERSION}/manifest.json" \
        --config-file ~/.ossutilconfig --force
    ossutil cp "${manifest_file}" \
        "oss://${ALIYUN_OSS_BUCKET}/${OSS_PREFIX}/latest/manifest.json" \
        --config-file ~/.ossutilconfig --force
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

    install_ossutil
    configure_ossutil

    for image in "${images[@]}"; do
        filepath=$(export_image "${image}")
        upload_to_oss "${filepath}"
        if [ "${UPDATE_LATEST:-true}" = "true" ]; then
            update_latest "${image}"
        fi
    done

    generate_manifest
    log "所有镜像已同步到阿里云OSS"
}

main "$@"
