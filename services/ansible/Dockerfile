# L2: Ansible 服务镜像
# 包含：Ansible + 常用 Collection + 运维工具
# 继承自 L1 toolchain-python
ARG REGISTRY=ghcr.io/ckLXHL
ARG PYTHON_VERSION=3.12
FROM ${REGISTRY}/toolchain-python:${PYTHON_VERSION}

ARG ANSIBLE_VERSION=9.3.0

LABEL org.opencontainers.image.title="services-ansible" \
      org.opencontainers.image.description="Ansible ${ANSIBLE_VERSION} + common collections" \
      org.opencontainers.image.source="https://github.com/ckLXHL/cloud-env-package"

# 安装系统依赖
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        # SSH 客户端
        openssh-client \
        sshpass \
        # 加密依赖
        libssl-dev \
        libffi-dev \
        # 网络工具
        rsync \
        netcat-openbsd \
        # 工具
        git \
        jq \
    ; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# 安装 Ansible
RUN pip install --no-cache-dir \
    "ansible==${ANSIBLE_VERSION}" \
    ansible-lint \
    molecule \
    molecule-docker \
    # Ansible 常用依赖
    paramiko \
    cryptography \
    jmespath \
    netaddr \
    # Mitogen 加速
    mitogen

# 安装常用 Ansible Collection
RUN ansible-galaxy collection install \
    community.general \
    community.docker \
    community.crypto \
    ansible.posix \
    ansible.utils \
    --collections-path /usr/share/ansible/collections

# 配置 Ansible 默认设置
RUN mkdir -p /etc/ansible && cat > /etc/ansible/ansible.cfg <<'EOF'
[defaults]
# 库存文件位置
inventory = /workspace/ansible/inventory/hosts.ini

# 不检查 host key（开发环境，生产环境应启用）
host_key_checking = False

# 并行数量
forks = 20

# 回调插件
stdout_callback = yaml
bin_ansible_callbacks = True

# 日志
log_path = /tmp/ansible.log

# 角色路径
roles_path = /workspace/ansible/roles:/usr/share/ansible/roles

# Collection 路径
collections_paths = /usr/share/ansible/collections:~/.ansible/collections

[privilege_escalation]
become = True
become_method = sudo
become_ask_pass = False

[ssh_connection]
# SSH 复用连接，加速批量操作
ssh_args = -C -o ControlMaster=auto -o ControlPersist=60s
pipelining = True
EOF

# 创建 SSH config
RUN mkdir -p ~/.ssh && cat > ~/.ssh/config <<'EOF'
Host *
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3
    ControlMaster auto
    ControlPath ~/.ssh/cm-%r@%h:%p
    ControlPersist 60s
EOF
RUN chmod 600 ~/.ssh/config

# 验证安装
RUN ansible --version && ansible-galaxy --version

WORKDIR /workspace

CMD ["/bin/bash"]
