#!/bin/bash
# 目标机一键初始化脚本
# 功能：检测系统、安装运行时、从 OSS/OBS 拉取镜像
# 可通过内网 HTTP 直接下载：
#   curl -fsSL https://your-oss-bucket/devenv/bootstrap.sh | bash
# 或：
#   bash bootstrap.sh --scene full --registry oss
set -euo pipefail

# ============================================================
# 配置区（修改为实际值）
# ============================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SCENE="${SCENE:-full}"
ARCH="${ARCH:-}"
REGISTRY_SOURCE="${REGISTRY_SOURCE:-oss}"
VERSION="${VERSION:-latest}"
RUNTIME="${RUNTIME:-}"
INSTALL_DIR="${INSTALL_DIR:-/opt/devenv}"
SKIP_RUNTIME_INSTALL="${SKIP_RUNTIME_INSTALL:-false}"

# ============================================================
# 工具函数
# ============================================================
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BOOTSTRAP] $*"; }
error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BOOTSTRAP] ERROR: $*" >&2; exit 1; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [BOOTSTRAP] WARN: $*" >&2; }

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

banner() {
    echo -e "${BOLD}${GREEN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║         Cloud Dev Environment Bootstrap              ║"
    echo "║         一键初始化开发环境                              ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检测系统架构
detect_arch() {
    if [ -n "${ARCH}" ]; then
        echo "${ARCH}"
        return
    fi
    case "$(uname -m)" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        arm64)   echo "arm64" ;;
        *) error "不支持的架构: $(uname -m)" ;;
    esac
}

# 检测发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "${ID}"
    else
        echo "unknown"
    fi
}

# 检测可用运行时
detect_runtime() {
    if [ -n "${RUNTIME}" ]; then
        echo "${RUNTIME}"
        return
    fi
    for rt in podman docker nerdctl; do
        if command -v "${rt}" &>/dev/null; then
            echo "${rt}"
            return
        fi
    done
    echo ""
}

# 安装容器运行时
install_runtime() {
    local distro="$1"
    local arch="$2"

    log "安装容器运行时..."

    case "${distro}" in
        ubuntu|debian)
            apt-get update -qq
            # 优先安装 Podman（无守护进程，无需 root）
            if apt-cache show podman &>/dev/null 2>&1; then
                log "安装 Podman..."
                apt-get install -y -qq podman uidmap slirp4netns
            else
                log "安装 Docker CE（使用阿里云镜像源）..."
                apt-get install -y -qq curl gnupg lsb-release
                curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | \
                    gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
                echo "deb [arch=${arch} signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
                    https://mirrors.aliyun.com/docker-ce/linux/ubuntu \
                    $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
                apt-get update -qq
                apt-get install -y -qq docker-ce docker-ce-cli containerd.io
                systemctl start docker
                systemctl enable docker
            fi
            ;;
        kylin|neokylin)
            log "麒麟系统：安装 Docker CE..."
            # 麒麟使用 yum/dnf
            if command -v yum &>/dev/null; then
                yum install -y docker-ce docker-ce-cli containerd.io \
                    --setopt=baseurl=https://mirrors.aliyun.com/docker-ce/linux/centos/\$releasever/\$basearch/stable
                systemctl start docker
                systemctl enable docker
            fi
            ;;
        *)
            warn "不支持的发行版 ${distro}，尝试使用现有运行时..."
            ;;
    esac
}

# 安装必要工具（zstd、curl）
install_prerequisites() {
    local distro="$1"

    log "安装前置工具..."
    case "${distro}" in
        ubuntu|debian)
            apt-get install -y -qq curl wget zstd ca-certificates python3 python3-pip jq
            ;;
        kylin|centos|rhel)
            yum install -y curl wget zstd ca-certificates python3 python3-pip jq
            ;;
    esac
}

# 主流程
main() {
    banner

    # 检测环境
    local arch distro
    arch=$(detect_arch)
    distro=$(detect_distro)

    log "系统信息: ${distro} / ${arch}"
    log "安装场景: ${SCENE}"
    log "分发源: ${REGISTRY_SOURCE}"
    log "版本: ${VERSION}"

    # 检查是否 root
    if [ "$(id -u)" != "0" ]; then
        warn "建议以 root 权限运行以安装系统工具"
    fi

    # 安装前置工具
    install_prerequisites "${distro}"

    # 检查/安装运行时
    local runtime
    runtime=$(detect_runtime)

    if [ -z "${runtime}" ] && [ "${SKIP_RUNTIME_INSTALL}" != "true" ]; then
        install_runtime "${distro}" "${arch}"
        runtime=$(detect_runtime)
    fi

    if [ -z "${runtime}" ]; then
        error "未找到可用的容器运行时（docker/podman/nerdctl），请手动安装"
    fi

    log "使用运行时: ${runtime}"

    # 创建安装目录
    mkdir -p "${INSTALL_DIR}/scripts"

    # 复制或下载 load.sh
    if [ -f "${PROJECT_ROOT}/distribution/loader/load.sh" ]; then
        cp "${PROJECT_ROOT}/distribution/loader/load.sh" "${INSTALL_DIR}/scripts/load.sh"
    fi
    chmod +x "${INSTALL_DIR}/scripts/load.sh"

    # 执行镜像加载
    log "开始下载并加载镜像..."
    ARCH="${arch}" \
    RUNTIME="${runtime}" \
    SCENE="${SCENE}" \
    VERSION="${VERSION}" \
    REGISTRY_SOURCE="${REGISTRY_SOURCE}" \
    bash "${INSTALL_DIR}/scripts/load.sh"

    # 创建快捷命令
    cat > "${INSTALL_DIR}/devenv.sh" <<EOF
#!/bin/bash
# 启动开发环境
RUNTIME="${runtime}"
SCENE="${SCENE}"
VERSION="${VERSION}"
WORKSPACE="\${1:-\$(pwd)}"
exec \${RUNTIME} run -it --rm \\
    -v "\${WORKSPACE}:/workspace" \\
    -v ~/.ssh:/root/.ssh:ro \\
    --network host \\
    ghcr.io/ckLXHL/compose-\${SCENE}:\${VERSION} \\
    /bin/zsh
EOF
    chmod +x "${INSTALL_DIR}/devenv.sh"

    # 创建系统级快捷命令
    if [ -w /usr/local/bin ]; then
        ln -sf "${INSTALL_DIR}/devenv.sh" /usr/local/bin/devenv
        log "已创建命令: devenv"
    fi

    echo ""
    echo -e "${BOLD}${GREEN}初始化完成！${NC}"
    echo ""
    echo "使用方法："
    echo "  devenv              # 在当前目录启动开发环境"
    echo "  devenv /path/to/src # 挂载指定目录"
    echo ""
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scene)    SCENE="$2"; shift 2 ;;
        --arch)     ARCH="$2"; shift 2 ;;
        --version)  VERSION="$2"; shift 2 ;;
        --registry) REGISTRY_SOURCE="$2"; shift 2 ;;
        --runtime)  RUNTIME="$2"; shift 2 ;;
        --skip-runtime) SKIP_RUNTIME_INSTALL="true"; shift ;;
        -h|--help)
            echo "用法: $0 [选项]"
            echo "  --scene <full|cpp|python>  安装场景（默认: full）"
            echo "  --arch <amd64|arm64>       系统架构（默认: 自动检测）"
            echo "  --version <ver>            版本（默认: latest）"
            echo "  --registry <oss|obs|http>  分发源（默认: oss）"
            echo "  --runtime <docker|podman>  指定运行时"
            echo "  --skip-runtime             跳过运行时安装"
            exit 0 ;;
        *) error "未知参数: $1" ;;
    esac
done

main
