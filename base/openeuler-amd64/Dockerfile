# L0: openEuler 22.03 amd64 基础镜像
# 包含：最小系统 + 国内源 + CA证书 + 基础工具
# openEuler 无授权问题，可直接使用官方镜像
ARG OPENEULER_VERSION=22.03-lts
FROM openeuler/openeuler:${OPENEULER_VERSION}

ARG OPENEULER_VERSION=22.03-lts

LABEL org.opencontainers.image.title="base-openeuler" \
      org.opencontainers.image.description="openEuler ${OPENEULER_VERSION} amd64 base image with CN mirrors" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package" \
      org.opencontainers.image.version="${OPENEULER_VERSION}" \
      org.opencontainers.image.architecture="amd64"

# 替换为华为云 openEuler 镜像源
RUN set -eux; \
    # 备份原始 repo 文件
    cp /etc/yum.repos.d/openEuler.repo /etc/yum.repos.d/openEuler.repo.bak; \
    # 替换为华为云镜像源
    cat > /etc/yum.repos.d/openEuler.repo <<'EOF'
[OS]
name=OS
baseurl=https://mirrors.huaweicloud.com/openeuler/openEuler-22.03-LTS/OS/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://mirrors.huaweicloud.com/openeuler/openEuler-22.03-LTS/OS/$basearch/RPM-GPG-KEY-openEuler

[everything]
name=everything
baseurl=https://mirrors.huaweicloud.com/openeuler/openEuler-22.03-LTS/everything/$basearch/
enabled=1
gpgcheck=1
gpgkey=https://mirrors.huaweicloud.com/openeuler/openEuler-22.03-LTS/everything/$basearch/RPM-GPG-KEY-openEuler
EOF

# 安装基础工具
RUN set -eux; \
    yum install -y \
        # CA 证书
        ca-certificates \
        # 网络工具
        curl \
        wget \
        # 基础工具
        gnupg2 \
        # 文本处理
        glibc-locale-source \
        glibc-langpack-en \
        glibc-langpack-zh \
        # 压缩/解压工具
        gzip \
        bzip2 \
        xz \
        zstd \
        unzip \
        zip \
    ; \
    yum clean all; \
    rm -rf /var/cache/yum

# 设置中文时区
RUN ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

# 设置 locale
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

CMD ["/bin/bash"]
