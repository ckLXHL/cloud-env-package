#!/bin/bash
# Docker-in-Docker 初始化脚本
set -eux

# 如果需要启动 Docker 守护进程
if [ "${START_DOCKER:-false}" = "true" ]; then
    # 挂载 cgroup（如果尚未挂载）
    if ! mountpoint -q /sys/fs/cgroup; then
        mount -t cgroup2 none /sys/fs/cgroup 2>/dev/null || true
    fi

    # 启动 dockerd
    dockerd \
        --host=unix:///var/run/docker.sock \
        --storage-driver=overlay2 \
        &

    # 等待 dockerd 就绪
    timeout=30
    while ! docker info >/dev/null 2>&1; do
        if [ $timeout -le 0 ]; then
            echo "Timed out waiting for Docker daemon"
            exit 1
        fi
        sleep 1
        timeout=$((timeout - 1))
    done

    echo "Docker daemon ready"
fi

exec "$@"
