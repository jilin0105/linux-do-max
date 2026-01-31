#!/bin/bash
# ============================================================
# LinuxDO 签到 - 一键安装脚本
# 支持: Linux (Debian/Ubuntu/CentOS/Fedora/Arch/Alpine)
#       macOS (Intel/Apple Silicon)
#       ARM (树莓派/Orange Pi/电视盒子/ARM服务器)
# ============================================================

set -e

# 版本信息
VERSION="1.1.0"
SCRIPT_NAME="LinuxDO 签到一键安装脚本"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 打印函数
print_banner() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}        ${GREEN}$SCRIPT_NAME v$VERSION${NC}        ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_info() { echo -e "${BLUE}[信息]${NC} $1"; }
print_success() { echo -e "${GREEN}[成功]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${NC} $1"; }
print_error() { echo -e "${RED}[错误]${NC} $1"; }
print_step() { echo -e "${PURPLE}[步骤]${NC} $1"; }

# ============================================================
# 系统检测
# ============================================================

detect_system() {
    print_step "检测系统环境..."

    # 检测操作系统
    case "$(uname -s)" in
        Linux*)
            OS_TYPE="linux"
            ;;
        Darwin*)
            OS_TYPE="macos"
            ;;
        CYGWIN*|MINGW*|MSYS*)
            OS_TYPE="windows"
            print_error "Windows 请使用 install.ps1 脚本"
            exit 1
            ;;
        *)
            print_error "不支持的操作系统: $(uname -s)"
            exit 1
            ;;
    esac

    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64)
            ARCH_TYPE="x64"
            ;;
        aarch64|arm64)
            ARCH_TYPE="arm64"
            IS_ARM=true
            ;;
        armv7l|armhf)
            ARCH_TYPE="arm32"
            IS_ARM=true
            print_warning "ARM32 支持有限，建议使用 ARM64 系统"
            ;;
        *)
            ARCH_TYPE="unknown"
            print_warning "未知架构: $ARCH"
            ;;
    esac

    # 检测 Linux 发行版
    if [ "$OS_TYPE" = "linux" ]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            DISTRO=$ID
            DISTRO_VERSION=$VERSION_ID
            DISTRO_NAME=$PRETTY_NAME
        elif [ -f /etc/redhat-release ]; then
            DISTRO="rhel"
            DISTRO_NAME=$(cat /etc/redhat-release)
        else
            DISTRO="unknown"
            DISTRO_NAME="Unknown Linux"
        fi

        # 检测包管理器
        if command -v apt-get &> /dev/null; then
            PKG_MANAGER="apt"
        elif command -v dnf &> /dev/null; then
            PKG_MANAGER="dnf"
        elif command -v yum &> /dev/null; then
            PKG_MANAGER="yum"
        elif command -v pacman &> /dev/null; then
            PKG_MANAGER="pacman"
        elif command -v apk &> /dev/null; then
            PKG_MANAGER="apk"
        elif command -v zypper &> /dev/null; then
            PKG_MANAGER="zypper"
        else
            PKG_MANAGER="unknown"
        fi
    fi

    # 检测是否为树莓派
    IS_RASPBERRY_PI=false
    if [ -f /proc/device-tree/model ]; then
        MODEL=$(cat /proc/device-tree/model 2>/dev/null || echo "")
        if [[ "$MODEL" == *"Raspberry Pi"* ]]; then
            IS_RASPBERRY_PI=true
        fi
    fi

    # 检测是否在 Docker 容器中
    IS_DOCKER=false
    if [ -f /.dockerenv ] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        IS_DOCKER=true
    fi

    # 检测是否有图形界面
    HAS_DISPLAY=false
    if [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; then
        HAS_DISPLAY=true
    fi

    # 打印检测结果
    echo ""
    echo "┌─────────────────────────────────────────┐"
    echo "│           系统环境检测结果              │"
    echo "├─────────────────────────────────────────┤"
    printf "│ %-15s │ %-21s │\n" "操作系统" "$OS_TYPE"
    printf "│ %-15s │ %-21s │\n" "架构" "$ARCH ($ARCH_TYPE)"
    if [ "$OS_TYPE" = "linux" ]; then
        printf "│ %-15s │ %-21s │\n" "发行版" "$DISTRO"
        printf "│ %-15s │ %-21s │\n" "包管理器" "$PKG_MANAGER"
    fi
    if [ "$OS_TYPE" = "macos" ]; then
        printf "│ %-15s │ %-21s │\n" "macOS版本" "$(sw_vers -productVersion)"
    fi
    printf "│ %-15s │ %-21s │\n" "ARM设备" "$([ "$IS_ARM" = true ] && echo '是' || echo '否')"
    printf "│ %-15s │ %-21s │\n" "树莓派" "$([ "$IS_RASPBERRY_PI" = true ] && echo '是' || echo '否')"
    printf "│ %-15s │ %-21s │\n" "Docker容器" "$([ "$IS_DOCKER" = true ] && echo '是' || echo '否')"
    printf "│ %-15s │ %-21s │\n" "图形界面" "$([ "$HAS_DISPLAY" = true ] && echo '有' || echo '无')"
    echo "└─────────────────────────────────────────┘"
    echo ""
}

# ============================================================
# 依赖安装
# ============================================================

install_dependencies() {
    print_step "安装系统依赖..."

    case "$OS_TYPE" in
        linux)
            install_linux_deps
            ;;
        macos)
            install_macos_deps
            ;;
    esac

    print_success "系统依赖安装完成"
}

install_linux_deps() {
    case "$PKG_MANAGER" in
        apt)
            print_info "使用 apt 安装依赖..."
            sudo apt-get update
            sudo apt-get install -y \
                python3 \
                python3-pip \
                python3-venv \
                chromium-browser || sudo apt-get install -y chromium \
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
                libasound2 \
                curl \
                git
            ;;
        dnf|yum)
            print_info "使用 $PKG_MANAGER 安装依赖..."
            sudo $PKG_MANAGER install -y \
                python3 \
                python3-pip \
                chromium \
                chromedriver \
                xorg-x11-server-Xvfb \
                wqy-zenhei-fonts \
                curl \
                git
            ;;
        pacman)
            print_info "使用 pacman 安装依赖..."
            sudo pacman -Syu --noconfirm \
                python \
                python-pip \
                chromium \
                xorg-server-xvfb \
                wqy-zenhei \
                curl \
                git
            ;;
        apk)
            print_info "使用 apk 安装依赖..."
            sudo apk update
            sudo apk add \
                python3 \
                py3-pip \
                chromium \
                chromium-chromedriver \
                xvfb \
                font-wqy-zenhei \
                ttf-wqy-zenhei \
                curl \
                git
            ;;
        zypper)
            print_info "使用 zypper 安装依赖..."
            sudo zypper install -y \
                python3 \
                python3-pip \
                chromium \
                xorg-x11-server-Xvfb \
                wqy-zenhei-fonts \
                curl \
                git
            ;;
        *)
            print_warning "未知包管理器，请手动安装: Python 3.8+, Chromium, Xvfb"
            ;;
    esac
}

install_macos_deps() {
    print_info "检测 macOS 依赖..."

    # 检查 Homebrew
    if ! command -v brew &> /dev/null; then
        print_info "安装 Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # 安装依赖
    print_info "使用 Homebrew 安装依赖..."
    brew install python3 || true

    # 检查 Chrome
    if [ ! -d "/Applications/Google Chrome.app" ] && [ ! -d "/Applications/Chromium.app" ]; then
        print_warning "未检测到 Chrome/Chromium，请手动安装"
        print_info "下载地址: https://www.google.com/chrome/"
    fi
}

# ============================================================
# Python 环境
# ============================================================

setup_python_env() {
    print_step "配置 Python 环境..."

    # 创建虚拟环境
    if [ ! -d "venv" ]; then
        print_info "创建虚拟环境..."
        python3 -m venv venv
    fi

    # 激活虚拟环境
    source venv/bin/activate

    # 升级 pip
    print_info "升级 pip..."
    pip install --upgrade pip

    # 安装依赖
    print_info "安装 Python 依赖..."
    pip install -r requirements.txt

    print_success "Python 环境配置完成"
}

# ============================================================
# 浏览器配置
# ============================================================

configure_browser() {
    print_step "配置浏览器..."

    # 查找浏览器路径
    BROWSER_PATHS=(
        "/usr/bin/chromium-browser"
        "/usr/bin/chromium"
        "/usr/lib/chromium/chromium"
        "/snap/bin/chromium"
        "/usr/bin/google-chrome"
        "/usr/bin/google-chrome-stable"
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        "/Applications/Chromium.app/Contents/MacOS/Chromium"
    )

    BROWSER_PATH=""
    for path in "${BROWSER_PATHS[@]}"; do
        if [ -x "$path" ]; then
            BROWSER_PATH=$path
            break
        fi
    done

    if [ -z "$BROWSER_PATH" ]; then
        print_warning "未找到浏览器，请手动配置 browser_path"
    else
        print_success "浏览器路径: $BROWSER_PATH"
        DETECTED_BROWSER_PATH=$BROWSER_PATH
    fi
}

# ============================================================
# 一键配置
# ============================================================

interactive_config() {
    print_step "交互式配置..."
    echo ""

    # 检查是否已有配置文件
    if [ -f "config.yaml" ]; then
        echo -e "${YELLOW}检测到已有配置文件 config.yaml${NC}"
        read -p "是否重新配置？[y/N]: " RECONFIG
        if [[ ! "$RECONFIG" =~ ^[Yy]$ ]]; then
            print_info "跳过配置，使用现有配置文件"
            return
        fi
    fi

    echo ""
    echo "┌─────────────────────────────────────────┐"
    echo "│           一键配置向导                  │"
    echo "└─────────────────────────────────────────┘"
    echo ""

    # 用户名（可选）
    read -p "Linux.do 用户名 (可选，直接回车跳过): " INPUT_USERNAME

    # 密码（可选）
    if [ -n "$INPUT_USERNAME" ]; then
        read -s -p "Linux.do 密码 (可选，直接回车跳过): " INPUT_PASSWORD
        echo ""
    fi

    # 浏览帖子数量
    read -p "每次浏览帖子数量 [默认: 10]: " INPUT_BROWSE_COUNT
    INPUT_BROWSE_COUNT=${INPUT_BROWSE_COUNT:-10}

    # 点赞概率
    read -p "点赞概率 (0-1) [默认: 0.3]: " INPUT_LIKE_PROB
    INPUT_LIKE_PROB=${INPUT_LIKE_PROB:-0.3}

    # 无头模式
    if [ "$HAS_DISPLAY" = true ]; then
        HEADLESS_DEFAULT="false"
    else
        HEADLESS_DEFAULT="true"
    fi
    read -p "无头模式 (true/false) [默认: $HEADLESS_DEFAULT]: " INPUT_HEADLESS
    INPUT_HEADLESS=${INPUT_HEADLESS:-$HEADLESS_DEFAULT}

    # Telegram 配置
    echo ""
    echo "Telegram 通知配置（可选）:"
    read -p "Telegram Bot Token (直接回车跳过): " INPUT_TG_TOKEN
    if [ -n "$INPUT_TG_TOKEN" ]; then
        read -p "Telegram Chat ID: " INPUT_TG_CHAT_ID
    fi

    # 用户数据目录
    DEFAULT_USER_DATA_DIR="$HOME/.linuxdo-browser"
    read -p "用户数据目录 [默认: $DEFAULT_USER_DATA_DIR]: " INPUT_USER_DATA_DIR
    INPUT_USER_DATA_DIR=${INPUT_USER_DATA_DIR:-$DEFAULT_USER_DATA_DIR}

    # 生成配置文件
    print_info "生成配置文件..."

    cat > config.yaml << EOF
# ============================================================
# LinuxDO 签到配置文件
# 由一键安装脚本自动生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================

# ========== 账号配置 ==========
username: "${INPUT_USERNAME}"
password: "${INPUT_PASSWORD}"

# ========== 浏览器配置 ==========
user_data_dir: "${INPUT_USER_DATA_DIR}"
headless: ${INPUT_HEADLESS}
browser_path: "${DETECTED_BROWSER_PATH:-}"

# ========== 签到配置 ==========
browse_count: ${INPUT_BROWSE_COUNT}
like_probability: ${INPUT_LIKE_PROB}
browse_interval_min: 3
browse_interval_max: 8

# ========== Telegram 通知 ==========
tg_bot_token: "${INPUT_TG_TOKEN}"
tg_chat_id: "${INPUT_TG_CHAT_ID}"
EOF

    print_success "配置文件已生成: config.yaml"

    # 创建用户数据目录
    mkdir -p "$INPUT_USER_DATA_DIR"
    print_success "用户数据目录已创建: $INPUT_USER_DATA_DIR"
}

# ============================================================
# 定时任务配置
# ============================================================

setup_cron() {
    print_step "配置定时任务..."

    if [ "$OS_TYPE" = "macos" ]; then
        setup_launchd
    else
        setup_linux_cron
    fi
}

setup_linux_cron() {
    echo ""
    read -p "是否设置定时任务？[y/N]: " SETUP_CRON
    if [[ ! "$SETUP_CRON" =~ ^[Yy]$ ]]; then
        print_info "跳过定时任务配置"
        return
    fi

    SCRIPT_DIR=$(pwd)
    PYTHON_PATH="$SCRIPT_DIR/venv/bin/python"

    # 检查是否已存在任务
    if crontab -l 2>/dev/null | grep -q "linuxdo-checkin"; then
        print_warning "已存在 LinuxDO 签到任务"
        read -p "是否覆盖？[y/N]: " OVERWRITE
        if [[ "$OVERWRITE" =~ ^[Yy]$ ]]; then
            # 删除旧任务
            crontab -l 2>/dev/null | grep -v "linuxdo-checkin" | grep -v "LinuxDO" | crontab -
        else
            return
        fi
    fi

    # 选择执行时间
    echo ""
    echo "选择签到时间:"
    echo "  1. 每天 8:00 和 20:00（推荐）"
    echo "  2. 每天 9:00"
    echo "  3. 自定义"
    read -p "请选择 [1-3]: " TIME_CHOICE

    case $TIME_CHOICE in
        1)
            CRON_SCHEDULE_1="0 8 * * *"
            CRON_SCHEDULE_2="0 20 * * *"
            ;;
        2)
            CRON_SCHEDULE_1="0 9 * * *"
            CRON_SCHEDULE_2=""
            ;;
        3)
            read -p "输入 cron 表达式 (如 0 8 * * *): " CRON_SCHEDULE_1
            read -p "第二个时间点 (直接回车跳过): " CRON_SCHEDULE_2
            ;;
        *)
            CRON_SCHEDULE_1="0 8 * * *"
            CRON_SCHEDULE_2="0 20 * * *"
            ;;
    esac

    # 创建日志目录
    mkdir -p "$SCRIPT_DIR/logs"

    # 添加 cron 任务
    (crontab -l 2>/dev/null; echo "# LinuxDO 签到任务 - linuxdo-checkin") | crontab -
    (crontab -l 2>/dev/null; echo "$CRON_SCHEDULE_1 cd $SCRIPT_DIR && xvfb-run -a $PYTHON_PATH main.py >> logs/checkin.log 2>&1") | crontab -

    if [ -n "$CRON_SCHEDULE_2" ]; then
        (crontab -l 2>/dev/null; echo "$CRON_SCHEDULE_2 cd $SCRIPT_DIR && xvfb-run -a $PYTHON_PATH main.py >> logs/checkin.log 2>&1") | crontab -
    fi

    print_success "定时任务已设置"
    print_info "查看任务: crontab -l | grep -i linuxdo"
}

setup_launchd() {
    echo ""
    read -p "是否设置 macOS 定时任务？[y/N]: " SETUP_LAUNCHD
    if [[ ! "$SETUP_LAUNCHD" =~ ^[Yy]$ ]]; then
        print_info "跳过定时任务配置"
        return
    fi

    SCRIPT_DIR=$(pwd)
    PLIST_PATH="$HOME/Library/LaunchAgents/com.linuxdo.checkin.plist"

    # 创建 plist 文件
    cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.linuxdo.checkin</string>
    <key>ProgramArguments</key>
    <array>
        <string>$SCRIPT_DIR/venv/bin/python</string>
        <string>$SCRIPT_DIR/main.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$SCRIPT_DIR</string>
    <key>StartCalendarInterval</key>
    <array>
        <dict>
            <key>Hour</key>
            <integer>8</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
        <dict>
            <key>Hour</key>
            <integer>20</integer>
            <key>Minute</key>
            <integer>0</integer>
        </dict>
    </array>
    <key>StandardOutPath</key>
    <string>$SCRIPT_DIR/logs/checkin.log</string>
    <key>StandardErrorPath</key>
    <string>$SCRIPT_DIR/logs/checkin.log</string>
</dict>
</plist>
EOF

    # 加载任务
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    launchctl load "$PLIST_PATH"

    print_success "macOS 定时任务已设置"
    print_info "查看任务: launchctl list | grep linuxdo"
}

# ============================================================
# 首次登录
# ============================================================

first_login() {
    print_step "首次登录..."

    if [ "$HAS_DISPLAY" = false ]; then
        echo ""
        print_warning "未检测到图形界面"
        echo ""
        echo "首次登录需要图形界面来手动操作浏览器登录。"
        echo ""
        echo "请选择以下方式之一："
        echo ""
        echo "  ${GREEN}方式1: VNC 远程桌面（推荐）${NC}"
        echo "    1) 安装 VNC: sudo apt install tigervnc-standalone-server"
        echo "    2) 启动 VNC: vncserver :1"
        echo "    3) 用 VNC 客户端连接后重新运行本脚本"
        echo ""
        echo "  ${GREEN}方式2: SSH X11 转发${NC}"
        echo "    1) 本地安装 X Server (Windows: VcXsrv, Mac: XQuartz)"
        echo "    2) SSH 连接: ssh -X user@host"
        echo "    3) 设置: export DISPLAY=localhost:10.0"
        echo ""
        echo "  ${GREEN}方式3: 在其他电脑完成首次登录${NC}"
        echo "    1) 在有图形界面的电脑上运行首次登录"
        echo "    2) 将 ~/.linuxdo-browser 目录复制到本机"
        echo "    3) 之后可以无头模式运行"
        echo ""
        read -p "按 Enter 继续（跳过首次登录）..."
        return
    fi

    echo ""
    read -p "是否现在进行首次登录？[Y/n]: " DO_LOGIN
    if [[ "$DO_LOGIN" =~ ^[Nn]$ ]]; then
        print_info "跳过首次登录"
        print_info "稍后运行: python main.py --first-login"
        return
    fi

    source venv/bin/activate
    python main.py --first-login
}

# ============================================================
# 测试运行
# ============================================================

test_run() {
    print_step "测试运行..."

    echo ""
    read -p "是否进行测试运行？[y/N]: " DO_TEST
    if [[ ! "$DO_TEST" =~ ^[Yy]$ ]]; then
        print_info "跳过测试运行"
        return
    fi

    source venv/bin/activate

    if [ "$HAS_DISPLAY" = true ]; then
        python main.py
    else
        if command -v xvfb-run &> /dev/null; then
            xvfb-run -a python main.py
        else
            print_warning "无图形界面且未安装 Xvfb，尝试无头模式..."
            python main.py
        fi
    fi
}

# ============================================================
# 安装完成
# ============================================================

print_completion() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                    ${GREEN}安装完成！${NC}                              ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "后续操作："
    echo ""
    echo "  ${CYAN}1. 首次登录（如果还没完成）:${NC}"
    echo "     source venv/bin/activate"
    echo "     python main.py --first-login"
    echo ""
    echo "  ${CYAN}2. 手动运行签到:${NC}"
    echo "     source venv/bin/activate"
    echo "     python main.py"
    echo ""
    echo "  ${CYAN}3. 无头模式运行（服务器）:${NC}"
    echo "     xvfb-run -a ./venv/bin/python main.py"
    echo ""
    echo "  ${CYAN}4. 查看日志:${NC}"
    echo "     tail -f logs/checkin.log"
    echo ""
    echo "  ${CYAN}5. 修改配置:${NC}"
    echo "     nano config.yaml"
    echo ""

    if [ "$HAS_DISPLAY" = false ]; then
        echo -e "${YELLOW}提示: 当前无图形界面，首次登录请参考上述方案${NC}"
        echo ""
    fi

    echo "项目地址: https://github.com/xtgm/linux-do-max"
    echo ""
}

# ============================================================
# 主函数
# ============================================================

main() {
    print_banner

    # 检查是否在项目目录
    if [ ! -f "requirements.txt" ]; then
        print_error "请在项目目录下运行此脚本"
        print_info "cd /path/to/linuxdo-checkin && ./install.sh"
        exit 1
    fi

    # 系统检测
    detect_system

    # 确认安装
    echo ""
    read -p "是否开始安装？[Y/n]: " CONFIRM
    if [[ "$CONFIRM" =~ ^[Nn]$ ]]; then
        print_info "安装已取消"
        exit 0
    fi

    # 安装流程
    echo ""
    install_dependencies
    echo ""
    setup_python_env
    echo ""
    configure_browser
    echo ""
    interactive_config
    echo ""
    setup_cron
    echo ""
    first_login
    echo ""
    test_run
    echo ""
    print_completion
}

# 运行主函数
main "$@"
