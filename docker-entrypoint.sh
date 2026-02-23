#!/bin/bash
# Docker 入口脚本

# ========== 配置文件处理 ==========
# Docker 卷映射目录: /app/config/ (宿主机 ./config/)
# 应用配置文件: /app/config.yaml
CONFIG_DIR="/app/config"
CONFIG_FILE="/app/config.yaml"
CONFIG_EXAMPLE="/app/config.yaml.example"

# 修复 config.yaml 被错误创建为目录的问题
if [ -d "$CONFIG_FILE" ]; then
    echo "[警告] /app/config.yaml 是一个目录而不是文件，正在自动修复..."
    rm -rf "$CONFIG_FILE"
    echo "[信息] 已删除错误的 config.yaml 目录"
fi

# 优先从映射的配置目录读取
if [ -f "$CONFIG_DIR/config.yaml" ]; then
    cp "$CONFIG_DIR/config.yaml" "$CONFIG_FILE"
    echo "[信息] 已从 config/config.yaml 加载配置"
elif [ ! -f "$CONFIG_FILE" ]; then
    # 没有任何配置文件，从 example 创建默认配置
    if [ -f "$CONFIG_EXAMPLE" ]; then
        cp "$CONFIG_EXAMPLE" "$CONFIG_FILE"
        echo "[信息] 已从 config.yaml.example 创建默认配置文件"
        echo "[提示] 请编辑 config/config.yaml 配置你的账号信息"
    else
        echo "[信息] 未找到配置文件，使用环境变量或默认配置"
    fi
fi

# 确保日志目录存在
mkdir -p /app/logs

# ========== 启动虚拟显示 ==========
Xvfb :99 -screen 0 1920x1080x24 &
export DISPLAY=:99

# 等待 Xvfb 启动
sleep 2

# 执行命令
exec "$@"
