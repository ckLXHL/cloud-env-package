#!/bin/bash
# Compose 入口脚本：初始化开发环境
set -e

# 显示欢迎信息
cat /etc/motd 2>/dev/null || true

# 如果需要启动 SSH
if [ "${START_SSH:-false}" = "true" ]; then
    service ssh start || true
fi

exec "$@"
