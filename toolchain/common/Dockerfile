# L1: 通用开发工具镜像
# 包含：Git / zsh / tmux / SSH / vim / neovim / fzf / ripgrep
# 继承自 L0 base-ubuntu
ARG REGISTRY=ghcr.io/ckLXHL
ARG BASE_VERSION=22.04
FROM ${REGISTRY}/base-ubuntu:${BASE_VERSION}

LABEL org.opencontainers.image.title="toolchain-common" \
      org.opencontainers.image.description="Common development tools: Git, zsh, tmux, vim, SSH" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package"

# 安装常用开发工具
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        # 版本控制
        git \
        git-lfs \
        # Shell 增强
        zsh \
        bash-completion \
        # 终端复用
        tmux \
        screen \
        # 编辑器
        vim \
        nano \
        # 网络工具
        openssh-client \
        openssh-server \
        netcat-openbsd \
        net-tools \
        iputils-ping \
        dnsutils \
        # 系统工具
        htop \
        tree \
        jq \
        less \
        file \
        # 搜索与文本处理
        ripgrep \
        fd-find \
        silversearcher-ag \
        grep \
        sed \
        gawk \
        # 压缩工具
        p7zip-full \
        # 进程管理
        procps \
        psmisc \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 安装 fzf（命令行模糊搜索）
RUN set -eux; \
    git clone --depth=1 https://github.com/junegunn/fzf.git ~/.fzf; \
    ~/.fzf/install --all --no-update-rc; \
    rm -rf ~/.fzf/.git

# 安装 Oh My Zsh（离线安装，不需要网络）
RUN set -eux; \
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git ~/.oh-my-zsh; \
    cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc; \
    # 设置主题为 agnoster
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="agnoster"/' ~/.zshrc; \
    rm -rf ~/.oh-my-zsh/.git

# 配置 Git 全局默认设置
RUN git config --global core.editor "vim" \
    && git config --global init.defaultBranch "main" \
    && git config --global pull.rebase false \
    && git config --global color.ui auto

# 配置 SSH 服务
RUN set -eux; \
    mkdir -p /var/run/sshd; \
    # 允许 root 登录（开发环境使用）
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config; \
    # 保持连接活跃
    echo "ClientAliveInterval 60" >> /etc/ssh/sshd_config; \
    echo "ClientAliveCountMax 3" >> /etc/ssh/sshd_config

# 创建 tmux 基础配置
RUN cat > ~/.tmux.conf <<'EOF'
# 使用 Ctrl-a 作为前缀键
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# 支持鼠标
set -g mouse on

# 设置颜色
set -g default-terminal "screen-256color"

# 窗口自动重命名
setw -g automatic-rename on

# 从 1 开始编号
set -g base-index 1
setw -g pane-base-index 1
EOF

# 配置 vim 基础设置
RUN cat > ~/.vimrc <<'EOF'
set number
set tabstop=4
set shiftwidth=4
set expandtab
set autoindent
set smartindent
set hlsearch
set incsearch
set ignorecase
set smartcase
set ruler
set showcmd
set wildmenu
syntax on
colorscheme desert
EOF

# 设置默认 shell 为 zsh
SHELL ["/bin/zsh", "-c"]
ENV SHELL=/bin/zsh

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]
