#!/bin/bash
# 目标机一键加载脚本（load 封装）
# 从 OSS/OBS 下载并加载镜像，封装 distribution/loader/load.sh
# 用法: ./scripts/load.sh [选项]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 直接透传参数给 load.sh
exec bash "${PROJECT_ROOT}/distribution/loader/load.sh" "$@"
