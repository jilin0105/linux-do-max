#!/bin/bash
# ============================================================
# LinuxDO 签到 - ARM 设备安装脚本
# 适用于: 树莓派、Orange Pi、ARM 服务器等
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 重置颜色

# 打印带颜色的消息
print_info() { echo -e "${BLUE}[信息]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }

# 检测系统架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        aarch64|arm64)
            print_success "检测到 ARM64 架构"
            IS_ARM=true
            ;;
        armv7l|armhf)
            print_warning "检测到 ARM32 架构（armv7）"
            print_warning "ARM32 支持有限，建议使用 ARM64 系统"
            IS_ARM=true
            ;;
        x86_64|amd64)
            print_info "检测到 x86_64 架构"
            IS_ARM=false
            ;;
        *)
            print_error "未知架构: $ARCH"
            exit 1
            ;;
    esac
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        print_info "操作系统: $PRETTY_NAME"
    else
        print_error "无法检测操作系统"
        exit 1
    fi
}

# 检测是否为树莓派
detect_raspberry_pi() {
    if [ -f /proc/device-tree/model ]; then
        MODEL=$(cat /proc/device-tree/model)
        if [[ "$MODEL" == *"Raspberry Pi"* ]]; then
            print_success "检测到树莓派: $MODEL"
            IS_RASPBERRY_PI=true
            return
        fi
    fi
    IS_RASPBERRY_PI=false
}

# 安装系统依赖
install_dependencies() {
    print_info "安装系统依赖..."

    case $OS in
        debian|ubuntu|raspbian|kylin|uos|deepin|linuxmint|pop|elementary|zorin|kali|parrot)
            # 基于 Debian/Ubuntu 的发行版（包括国产系统：银河麒麟、统信UOS、深度Deepin）
            sudo apt-get update
            sudo apt-get install -y \
                python3 \
                python3-pip \
                python3-venv \
                chromium-browser \
                chromium-chromedriver \
                xvfb \
                fonts-wqy-zenhei \
                fonts-wqy-microhei \
                libatk1.0-0 \
                libatk-bridge2.0-0 \
                libcups2 \
                libdrm2 \
                libxkbcommon0 \
                libxcomposite1 \
                libxdamage1 \
                libxfixes3 \
                libxrandr2 \
                libgbm1 \
                libasound2
            ;;
        alpine)
            sudo apk update
            sudo apk add \
                python3 \
                py3-pip \
                chromium \
                chromium-chromedriver \
                xvfb \
                font-wqy-zenhei \
                ttf-wqy-zenhei
            ;;
        arch|manjaro)
            sudo pacman -Syu --noconfirm \
                python \
                python-pip \
                chromium \
                xorg-server-xvfb \
                wqy-zenhei
            ;;
        fedora|centos|rhel)
            sudo dnf install -y \
                python3 \
                python3-pip \
                chromium \
                chromedriver \
                xorg-x11-server-Xvfb \
                wqy-zenhei-fonts
            ;;
        *)
            print_error "不支持的操作系统: $OS"
            print_info "请手动安装: Python 3.8+, Chromium, Xvfb"
            ;;
    esac

    print_success "系统依赖安装完成"
}

# 安装 Python 依赖
install_python_deps() {
    print_info "安装 Python 依赖..."

    # 创建虚拟环境（推荐）
    if [ ! -d "venv" ]; then
        python3 -m venv venv
        print_success "创建虚拟环境: venv/"
    fi

    # 激活虚拟环境
    source venv/bin/activate

    # 升级 pip
    pip install --upgrade pip

    # 安装依赖
    pip install -r requirements.txt

    print_success "Python 依赖安装完成"
}

# 配置 Chromium 路径
configure_chromium() {
    print_info "配置 Chromium 路径..."

    # 查找 Chromium 可执行文件（不使用 Snap 版本）
    CHROMIUM_PATHS=(
        "/usr/bin/google-chrome"
        "/usr/bin/google-chrome-stable"
        "/usr/bin/chromium-browser"
        "/usr/bin/chromium"
        "/usr/lib/chromium/chromium"
    )

    CHROMIUM_PATH=""
    for path in "${CHROMIUM_PATHS[@]}"; do
        if [ -x "$path" ]; then
            # 排除 Snap 版本
            real_path=$(readlink -f "$path" 2>/dev/null || echo "$path")
            if echo "$real_path" | grep -q "snap"; then
                print_warning "跳过 Snap 版浏览器: $path"
                continue
            fi
            CHROMIUM_PATH=$path
            break
        fi
    done

    # 如果没找到，尝试 which 命令
    if [ -z "$CHROMIUM_PATH" ]; then
        for cmd in google-chrome google-chrome-stable chromium-browser chromium; do
            p=$(which "$cmd" 2>/dev/null)
            if [ -n "$p" ] && [ -x "$p" ]; then
                real_path=$(readlink -f "$p" 2>/dev/null || echo "$p")
                if ! echo "$real_path" | grep -q "snap"; then
                    CHROMIUM_PATH="$p"
                    break
                fi
            fi
        done
    fi

    if [ -z "$CHROMIUM_PATH" ]; then
        print_error "未找到 Chromium/Chrome，请手动安装"
        exit 1
    fi

    print_success "Chromium 路径: $CHROMIUM_PATH"

    # 检查 config.yaml 是否被错误创建为目录
    if [ -d "config.yaml" ]; then
        print_warning "config.yaml 是一个目录而不是文件，正在自动修复..."
        rm -rf "config.yaml"
        print_success "已删除错误的 config.yaml 目录"
    fi

    # 如果 config.yaml 不存在，从 example 创建
    if [ ! -f "config.yaml" ]; then
        if [ -f "config.yaml.example" ]; then
            cp config.yaml.example config.yaml
            print_info "已从 config.yaml.example 创建配置文件"
        fi
    fi

    # 更新配置文件
    if [ -f "config.yaml" ]; then
        # 更新浏览器路径
        if grep -q "browser_path:" config.yaml; then
            sed -i "s|browser_path:.*|browser_path: \"$CHROMIUM_PATH\"|" config.yaml
        else
            echo "browser_path: \"$CHROMIUM_PATH\"" >> config.yaml
        fi

        # 检测容器/受限环境，自动添加 chrome_args
        IS_CONTAINER=false
        if [ -f "/.dockerenv" ] || grep -q "docker\|lxc" /proc/1/cgroup 2>/dev/null || \
           [ -f "/run/.containerenv" ] || systemd-detect-virt -c &>/dev/null; then
            IS_CONTAINER=true
        fi

        # ARM + Linux 环境自动配置 chrome_args
        if ! grep -q "chrome_args:" config.yaml; then
            cat >> config.yaml << 'CHROME_ARGS_EOF'

# Chrome 额外启动参数（ARM 设备自动配置）
chrome_args:
  - "--no-sandbox"
  - "--disable-dev-shm-usage"
  - "--disable-gpu"
CHROME_ARGS_EOF
            print_info "已自动添加 Chrome 启动参数 (--no-sandbox 等)"
        fi

        if [ "$IS_CONTAINER" = true ]; then
            print_warning "检测到容器环境，已确保 --no-sandbox 参数"
        fi

        print_success "已更新 config.yaml"
    fi
}

# 创建用户数据目录
create_user_data_dir() {
    USER_DATA_DIR="$HOME/.linuxdo-browser"
    mkdir -p "$USER_DATA_DIR"
    chmod 755 "$USER_DATA_DIR"
    print_success "用户数据目录: $USER_DATA_DIR"
}

# 测试 Chromium
test_chromium() {
    print_info "测试 Chromium..."

    if [ -z "$CHROMIUM_PATH" ]; then
        # 重新检测浏览器路径
        for p in /usr/bin/google-chrome /usr/bin/google-chrome-stable /usr/bin/chromium-browser /usr/bin/chromium; do
            if [ -x "$p" ]; then
                real_path=$(readlink -f "$p" 2>/dev/null || echo "$p")
                if ! echo "$real_path" | grep -q "snap"; then
                    CHROMIUM_PATH="$p"
                    break
                fi
            fi
        done
    fi

    if [ -z "$CHROMIUM_PATH" ]; then
        print_error "未检测到浏览器，无法测试"
        return 1
    fi

    # 验证版本
    BROWSER_VERSION=$("$CHROMIUM_PATH" --version 2>/dev/null | head -1)
    if [ -n "$BROWSER_VERSION" ]; then
        print_success "检测到浏览器: $CHROMIUM_PATH"
        print_info "浏览器版本: $BROWSER_VERSION"
    else
        print_warning "无法获取浏览器版本信息"
    fi

    # 如果有图形界面，进行启动测试
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        print_info "即将打开浏览器窗口，请确认浏览器能正常显示..."
        echo ""

        "$CHROMIUM_PATH" --no-sandbox --disable-dev-shm-usage --disable-gpu "https://linux.do" &
        BROWSER_PID=$!

        echo ""
        print_info "浏览器已启动 (进程号: $BROWSER_PID)"
        print_info "如果看到 Linux.do 论坛页面，说明浏览器正常工作"
        echo ""

        read -p "浏览器是否正常显示？[Y/n]: " BROWSER_OK

        kill $BROWSER_PID 2>/dev/null
        wait $BROWSER_PID 2>/dev/null

        if [ "$BROWSER_OK" = "n" ] || [ "$BROWSER_OK" = "N" ]; then
            print_warning "浏览器启动测试未通过，但可能仍然可用"
        else
            print_success "浏览器启动测试通过！"
        fi
    elif command -v xvfb-run &> /dev/null; then
        # 无图形界面，使用 xvfb-run 测试版本
        xvfb-run -a "$CHROMIUM_PATH" --version 2>/dev/null && \
            print_success "Chromium 测试通过（xvfb-run）" || \
            print_warning "Chromium 测试失败"
    else
        print_warning "Xvfb 未安装且无图形界面，建议安装 Xvfb 或设置 headless: true"
    fi
}

# 检查更新
check_update_on_start() {
    PYTHON_CMD=""
    if [ -f "venv/bin/python" ]; then
        PYTHON_CMD="venv/bin/python"
    elif command -v python3 &>/dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &>/dev/null; then
        PYTHON_CMD="python"
    fi

    if [ -z "$PYTHON_CMD" ]; then
        print_info "未检测到 Python 环境，跳过更新检查"
        return
    fi

    if [ ! -f "updater.py" ] || [ ! -f "version.py" ]; then
        return
    fi

    print_info "检查更新中..."

    UPDATE_INFO=$($PYTHON_CMD -c "
from updater import check_update
from version import __version__
info = check_update(silent=True)
if info:
    print(f'CURRENT={__version__}')
    print(f'LATEST={info[\"latest_version\"]}')
else:
    print(f'CURRENT={__version__}')
    print('LATEST=NONE')
" 2>/dev/null)

    if [ $? -ne 0 ]; then
        print_warning "更新检查失败，可能缺少依赖"
        print_info "如果是首次使用，请选择 1. 完整安装"
        echo ""
        return
    fi

    CURRENT_VER=$(echo "$UPDATE_INFO" | grep "CURRENT=" | cut -d= -f2)
    LATEST_VER=$(echo "$UPDATE_INFO" | grep "LATEST=" | cut -d= -f2)

    if [ "$LATEST_VER" = "NONE" ]; then
        print_success "当前版本 v$CURRENT_VER 已是最新"
        echo ""
        return
    fi

    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  发现新版本: v$LATEST_VER  (当前: v$CURRENT_VER)"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""

    read -p "是否现在更新？[Y/n]: " do_update
    if [ "$do_update" = "n" ] || [ "$do_update" = "N" ]; then
        print_info "跳过更新"
        echo ""
        return
    fi

    echo ""
    print_info "正在更新..."
    $PYTHON_CMD -c "from updater import prompt_update; prompt_update()"
    echo ""
    print_warning "更新完成，请重新运行此脚本"
    read -p "按回车键退出..."
    exit 0
}

# 手动检查更新
manual_update() {
    PYTHON_CMD=""
    if [ -f "venv/bin/python" ]; then
        PYTHON_CMD="venv/bin/python"
    elif command -v python3 &>/dev/null; then
        PYTHON_CMD="python3"
    elif command -v python &>/dev/null; then
        PYTHON_CMD="python"
    fi

    if [ -z "$PYTHON_CMD" ]; then
        print_error "未检测到 Python 环境"
        print_info "请先运行 1. 完整安装"
        return
    fi

    $PYTHON_CMD main.py --check-update
}

# 树莓派特殊优化
raspberry_pi_optimize() {
    if [ "$IS_RASPBERRY_PI" = true ]; then
        print_info "应用树莓派优化..."

        # 增加 GPU 内存（如果是树莓派）
        if [ -f /boot/config.txt ]; then
            if ! grep -q "gpu_mem=" /boot/config.txt; then
                print_warning "建议在 /boot/config.txt 中添加: gpu_mem=128"
            fi
        fi

        # 创建 swap（如果内存不足）
        TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
        if [ "$TOTAL_MEM" -lt 2048 ]; then
            print_warning "内存较小 (${TOTAL_MEM}MB)，建议增加 swap"
            print_info "运行: sudo dphys-swapfile swapoff && sudo nano /etc/dphys-swapfile"
            print_info "设置 CONF_SWAPSIZE=2048，然后运行: sudo dphys-swapfile setup && sudo dphys-swapfile swapon"
        fi

        print_success "树莓派优化提示完成"
    fi
}

# 交互式配置
interactive_config() {
    print_info "配置向导..."
    echo ""

    if [ -f "config.yaml" ]; then
        echo -e "${YELLOW}检测到已有配置文件${NC}"
        read -p "是否重新配置？[y/N]: " RECONFIG
        [ "$RECONFIG" != "y" ] && [ "$RECONFIG" != "Y" ] && return
    fi

    echo ""
    echo "=== 基本配置 ==="
    read -p "Linux.do 用户名（可选，按回车跳过）: " USERNAME
    [ -n "$USERNAME" ] && read -p "Linux.do 密码（可选）: " PASSWORD

    read -p "浏览帖子数量 [10]: " BROWSE_COUNT
    BROWSE_COUNT=${BROWSE_COUNT:-10}

    read -p "点赞概率（0-1）[0.3]: " LIKE_PROB
    LIKE_PROB=${LIKE_PROB:-0.3}

    # ARM 设备默认无头模式
    HAS_DISPLAY=false
    [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ] && HAS_DISPLAY=true

    if [ "$HAS_DISPLAY" = true ]; then
        HEADLESS_DEFAULT="false"
    else
        HEADLESS_DEFAULT="true"
    fi
    read -p "无头模式（true/false）[$HEADLESS_DEFAULT]: " HEADLESS
    HEADLESS=${HEADLESS:-$HEADLESS_DEFAULT}

    echo ""
    echo "=== Telegram 通知（可选）==="
    read -p "Telegram Bot Token（按回车跳过）: " TG_TOKEN
    [ -n "$TG_TOKEN" ] && read -p "Telegram Chat ID: " TG_CHAT_ID

    USER_DATA_DIR="$HOME/.linuxdo-browser"
    read -p "用户数据目录 [$USER_DATA_DIR]: " INPUT_DIR
    USER_DATA_DIR=${INPUT_DIR:-$USER_DATA_DIR}

    echo ""
    echo "=== 缓存配置（ARM 设备重要）==="
    read -p "磁盘缓存大小限制 MB（0=自动，推荐50）[0]: " CACHE_SIZE
    CACHE_SIZE=${CACHE_SIZE:-0}

    read -p "磁盘剩余空间告警阈值 MB（0=禁用）[500]: " DISK_THRESHOLD
    DISK_THRESHOLD=${DISK_THRESHOLD:-500}

    # 检测浏览器路径
    BROWSER_PATH=""
    for p in /usr/bin/google-chrome /usr/bin/google-chrome-stable /usr/bin/chromium-browser /usr/bin/chromium; do
        if [ -x "$p" ]; then
            real_path=$(readlink -f "$p" 2>/dev/null || echo "$p")
            if ! echo "$real_path" | grep -q "snap"; then
                BROWSER_PATH="$p"
                break
            fi
        fi
    done

    if [ -z "$BROWSER_PATH" ]; then
        print_warning "未检测到浏览器，请手动设置 browser_path"
    fi

    # 检测容器环境
    IS_CONTAINER=false
    if [ -f "/.dockerenv" ] || grep -q "docker\|lxc" /proc/1/cgroup 2>/dev/null || \
       [ -f "/run/.containerenv" ] || systemd-detect-virt -c &>/dev/null; then
        IS_CONTAINER=true
    fi

    # 生成 chrome_args
    CHROME_ARGS_BLOCK=""
    CHROME_ARGS_BLOCK="chrome_args:"
    CHROME_ARGS_BLOCK="$CHROME_ARGS_BLOCK
  - \"--no-sandbox\"
  - \"--disable-dev-shm-usage\"
  - \"--disable-gpu\""

    if [ "$IS_CONTAINER" = true ]; then
        print_warning "检测到容器环境，已自动添加 --no-sandbox 等参数"
    fi

    # 生成配置文件
    cat > config.yaml << EOF
# LinuxDO 签到配置文件
# 由 ARM 安装脚本自动生成

# ========== 账号配置 ==========
username: "${USERNAME}"
password: "${PASSWORD}"

# ========== 浏览器配置 ==========
user_data_dir: "${USER_DATA_DIR}"
headless: ${HEADLESS}
browser_path: "${BROWSER_PATH}"

# Chrome 额外启动参数（ARM 设备自动配置）
${CHROME_ARGS_BLOCK}

# ========== 签到配置 ==========
browse_count: ${BROWSE_COUNT}
like_probability: ${LIKE_PROB}
browse_interval_min: 15
browse_interval_max: 30

# ========== Telegram 通知 ==========
tg_bot_token: "${TG_TOKEN}"
tg_chat_id: "${TG_CHAT_ID}"

# ========== 缓存清理（ARM 设备重要）==========
cache_size_limit: ${CACHE_SIZE}
disk_free_threshold: ${DISK_THRESHOLD}
EOF

    mkdir -p "$USER_DATA_DIR"
    print_success "配置已保存: config.yaml"
}

# 设置定时任务
setup_cron() {
    print_info "设置定时任务..."

    PROJECT_PATH=$(pwd)

    # 获取 Python 路径（优先 venv）
    local py_cmd
    py_cmd=$(get_python_cmd) || return 1

    # 如果是相对路径，拼接为绝对路径
    case "$py_cmd" in
        /*) PYTHON_FULL="$py_cmd" ;;
        *)  PYTHON_FULL="$PROJECT_PATH/$py_cmd" ;;
    esac

    # 创建日志目录
    mkdir -p "$PROJECT_PATH/logs"

    # Xvfb 前缀
    XVFB_PREFIX=""
    if command -v xvfb-run &> /dev/null; then
        XVFB_PREFIX="xvfb-run -a "
        print_info "检测到 Xvfb，将使用虚拟显示"
    else
        print_warning "未检测到 Xvfb，如果运行失败请安装: sudo apt install xvfb"
    fi

    # cron 任务标识
    CRON_TAG="# LinuxDO-Checkin"

    # 检查是否已存在任务
    if crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
        print_warning "已存在 LinuxDO 签到任务"
        read -p "是否删除旧任务并重新配置？[Y/n]: " REDO
        if [ "$REDO" = "n" ] || [ "$REDO" = "N" ]; then
            print_info "跳过定时任务设置"
            return
        fi
        # 删除旧任务
        crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab - 2>/dev/null || true
        print_success "已删除旧定时任务"
    fi

    echo ""
    echo "========================================"
    echo "定时任务配置"
    echo "========================================"
    echo ""

    # 输入次数
    read -p "请输入每天执行的次数（1-4次，默认2）: " task_count
    task_count=${task_count:-2}
    if [ "$task_count" -lt 1 ]; then task_count=1; fi
    if [ "$task_count" -gt 4 ]; then task_count=4; fi

    echo ""
    echo "请输入每次执行的时间（24小时制，如 08:00）："
    echo ""

    # 收集时间
    declare -a times
    for i in $(seq 1 $task_count); do
        case $i in
            1) default="08:00" ;;
            2) default="20:00" ;;
            3) default="12:00" ;;
            4) default="18:00" ;;
        esac
        read -p "第 $i 次执行时间（默认 $default）: " input_time
        times[$i]=${input_time:-$default}
    done

    # 构建 cron 条目
    REMINDER_CMD="${XVFB_PREFIX}${PYTHON_FULL} ${PROJECT_PATH}/reminder.py >> ${PROJECT_PATH}/logs/reminder.log 2>&1"
    CHECKIN_CMD="${XVFB_PREFIX}${PYTHON_FULL} ${PROJECT_PATH}/main.py >> ${PROJECT_PATH}/logs/checkin.log 2>&1"

    cron_entries=""
    for i in $(seq 1 $task_count); do
        time_str=${times[$i]}
        hour=$(echo $time_str | cut -d: -f1 | sed 's/^0//')
        minute=$(echo $time_str | cut -d: -f2 | sed 's/^0//')

        # 提醒任务
        cron_entries="${cron_entries}${minute} ${hour} * * * ${REMINDER_CMD} ${CRON_TAG}-Reminder-${i}\n"

        # 签到任务（提醒后1分钟）
        checkin_minute=$((minute + 1))
        checkin_hour=$hour
        if [ $checkin_minute -ge 60 ]; then
            checkin_minute=$((checkin_minute - 60))
            checkin_hour=$((checkin_hour + 1))
        fi
        if [ $checkin_hour -ge 24 ]; then
            checkin_hour=$((checkin_hour - 24))
        fi
        cron_entries="${cron_entries}${checkin_minute} ${checkin_hour} * * * ${CHECKIN_CMD} ${CRON_TAG}-${i}\n"

        printf "[成功] %s - Telegram 提醒\n" "$time_str"
        printf "[成功] %02d:%02d - 自动签到\n" "$checkin_hour" "$checkin_minute"
    done

    # 添加到 crontab
    (crontab -l 2>/dev/null || true; echo -e "$cron_entries") | crontab -

    echo ""
    echo "========================================"
    print_success "已创建 $task_count 组定时任务"
    print_info "日志文件: $PROJECT_PATH/logs/"
    print_info "查看任务: crontab -l | grep LinuxDO"
    echo "========================================"
    echo ""
}

# 显示菜单
show_menu() {
    echo ""
    echo "┌──────────────────────────────────────────┐"
    echo "│     LinuxDO 签到 - ARM 设备安装脚本     │"
    echo "├──────────────────────────────────────────┤"
    echo "│  系统信息:                               │"
    printf "│    架构: %-29s │\n" "$(uname -m)"
    printf "│    系统: %-29s │\n" "${PRETTY_NAME:0:29}"
    if [ "$IS_RASPBERRY_PI" = true ]; then
        printf "│    设备: %-29s │\n" "${MODEL:0:29}"
    fi
    echo "├──────────────────────────────────────────┤"
    echo "│  1. 完整安装（推荐）                     │"
    echo "│  2. 仅安装系统依赖                       │"
    echo "│  3. 仅安装 Python 依赖                   │"
    echo "│  4. 配置 Chromium 路径                   │"
    echo "│  5. 测试 Chromium                        │"
    echo "│  6. 编辑配置文件                         │"
    echo "│  7. 设置定时任务                         │"
    echo "│  8. 首次登录                             │"
    echo "│  9. 运行签到                             │"
    echo "│  10. 查看系统信息                        │"
    echo "│  11. 检查更新                            │"
    echo "│  0. 退出                                 │"
    echo "└──────────────────────────────────────────┘"
    echo ""
}

# 获取 Python 可执行路径（优先 venv）
get_python_cmd() {
    if [ -f "venv/bin/python" ]; then
        echo "venv/bin/python"
    elif command -v python3 &>/dev/null; then
        echo "python3"
    elif command -v python &>/dev/null; then
        echo "python"
    else
        print_error "未找到 Python，请先运行 1. 完整安装"
        return 1
    fi
}

# 首次登录
first_login() {
    print_info "启动首次登录..."

    local py_cmd
    py_cmd=$(get_python_cmd) || return 1

    # 检查是否有图形界面
    if [ -z "$DISPLAY" ]; then
        print_warning "未检测到图形界面"
        echo ""
        echo "首次登录需要图形界面来手动操作浏览器登录。"
        echo ""
        echo "请选择以下方式之一："
        echo ""
        echo "  方式1: VNC 远程桌面（推荐）"
        echo "    1) 在 ARM 设备上安装 VNC: sudo apt install tigervnc-standalone-server"
        echo "    2) 启动 VNC: vncserver :1"
        echo "    3) 用 VNC 客户端连接后，在 VNC 桌面中运行本脚本"
        echo ""
        echo "  方式2: SSH X11 转发"
        echo "    1) 在本地电脑安装 X Server（Windows: VcXsrv/Xming，Mac: XQuartz）"
        echo "    2) SSH 连接时加 -X 参数: ssh -X user@arm-device"
        echo "    3) 设置 DISPLAY: export DISPLAY=localhost:10.0"
        echo "    4) 重新运行本脚本"
        echo ""
        echo "  方式3: 直接连接显示器"
        echo "    将 ARM 设备连接到显示器，在本地桌面环境中运行"
        echo ""
        echo "  方式4: 在其他电脑完成首次登录"
        echo "    1) 在有图形界面的电脑上运行首次登录"
        echo "    2) 将 ~/.linuxdo-browser 目录复制到 ARM 设备"
        echo "    3) 之后的自动签到可以在 ARM 设备上无头运行"
        echo ""
        read -p "按回车键返回主菜单..."
        return
    fi

    "$py_cmd" main.py --first-login
}

# 运行签到
run_checkin() {
    print_info "运行签到..."

    local py_cmd
    py_cmd=$(get_python_cmd) || return 1

    if command -v xvfb-run &> /dev/null; then
        xvfb-run -a "$py_cmd" main.py
    else
        "$py_cmd" main.py
    fi
}

# 显示系统信息
show_system_info() {
    echo ""
    echo "┌──────────────────────────────────────────┐"
    echo "│              系统信息                    │"
    echo "├──────────────────────────────────────────┤"
    printf "│ 架构         │ %-22s │\n" "$(uname -m)"
    printf "│ 内核         │ %-22s │\n" "$(uname -r | cut -c1-22)"
    printf "│ 系统         │ %-22s │\n" "${PRETTY_NAME:0:22}"
    echo ""
    echo "处理器:"
    if [ -f /proc/cpuinfo ]; then
        grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2
        echo "核心数: $(nproc)"
    fi
    echo ""
    echo "内存:"
    free -h | head -2
    echo ""
    echo "磁盘:"
    df -h / | tail -1
    echo ""
    if [ "$IS_RASPBERRY_PI" = true ]; then
        echo "树莓派信息:"
        echo "  型号: $MODEL"
        if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
            TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
            echo "  温度: $((TEMP/1000))°C"
        fi
    fi
    echo ""
}

# 完整安装
full_install() {
    print_info "开始完整安装..."
    echo ""

    # 1. 安装系统依赖和 Python 依赖
    install_dependencies
    install_python_deps

    # 2. 确保 config.yaml 是文件而非目录
    if [ -d "config.yaml" ]; then
        print_warning "config.yaml 是一个目录而不是文件，正在自动修复..."
        rm -rf "config.yaml"
    fi

    # 3. 创建用户数据目录
    create_user_data_dir

    # 4. 测试浏览器
    configure_chromium
    test_chromium

    # 5. 树莓派优化
    raspberry_pi_optimize

    # 6. 交互式配置（会自动检测浏览器路径并写入 config.yaml）
    interactive_config

    # 7. 设置定时任务
    setup_cron

    echo ""
    print_success "========================================"
    print_success "安装完成！"
    print_success "========================================"
    echo ""
    print_info "后续操作:"
    print_info "  1. 首次登录: ./scripts/setup_arm.sh 然后选择 8"
    print_info "  2. 运行签到: ./scripts/setup_arm.sh 然后选择 9"
    print_info "  3. 编辑配置: ./scripts/setup_arm.sh 然后选择 6"
    print_info "  4. 查看日志: tail -f logs/checkin.log"
    echo ""
}

# 主函数
main() {
    # 检测环境
    detect_arch
    detect_os
    detect_raspberry_pi

    # 创建日志目录
    mkdir -p logs

    # 检查 config.yaml 是否被错误创建为目录
    if [ -d "config.yaml" ]; then
        print_warning "config.yaml 是一个目录而不是文件，正在自动修复..."
        rm -rf "config.yaml"
        print_success "已删除错误的 config.yaml 目录"
        if [ -f "config.yaml.example" ]; then
            cp config.yaml.example config.yaml
            print_info "已从 config.yaml.example 创建默认配置文件"
        fi
    fi

    # 如果有参数，直接执行
    case "$1" in
        install)
            full_install
            exit 0
            ;;
        deps)
            install_dependencies
            exit 0
            ;;
        python)
            install_python_deps
            exit 0
            ;;
        cron)
            setup_cron
            exit 0
            ;;
        login)
            first_login
            exit 0
            ;;
        run)
            run_checkin
            exit 0
            ;;
        update)
            manual_update
            exit 0
            ;;
    esac

    # 启动时检查更新
    check_update_on_start

    # 交互式菜单
    while true; do
        show_menu
        read -p "请输入选项 [0-11]: " choice

        case $choice in
            1) full_install ;;
            2) install_dependencies ;;
            3) install_python_deps ;;
            4) configure_chromium ;;
            5) test_chromium ;;
            6) interactive_config ;;
            7) setup_cron ;;
            8) first_login ;;
            9) run_checkin ;;
            10) show_system_info ;;
            11) manual_update ;;
            0)
                print_info "退出"
                exit 0
                ;;
            *)
                print_error "无效选项"
                ;;
        esac

        echo ""
        read -p "按回车键继续..."
    done
}

# 运行主函数
main "$@"
