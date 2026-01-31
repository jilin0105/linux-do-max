# ============================================================
# LinuxDO 签到 - Windows 一键安装脚本
# 支持: Windows 10/11 (x64)
# ============================================================

param(
    [switch]$SkipConfig,
    [switch]$SkipCron,
    [switch]$Help
)

# 版本信息
$VERSION = "1.1.0"
$SCRIPT_NAME = "LinuxDO 签到一键安装脚本"

# 颜色函数
function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

function Print-Banner {
    Write-Host ""
    Write-ColorOutput "╔════════════════════════════════════════════════════════════╗" "Cyan"
    Write-ColorOutput "║        $SCRIPT_NAME v$VERSION        ║" "Green"
    Write-ColorOutput "╚════════════════════════════════════════════════════════════╝" "Cyan"
    Write-Host ""
}

function Print-Info { Write-ColorOutput "[信息] $args" "Blue" }
function Print-Success { Write-ColorOutput "[成功] $args" "Green" }
function Print-Warning { Write-ColorOutput "[警告] $args" "Yellow" }
function Print-Error { Write-ColorOutput "[错误] $args" "Red" }
function Print-Step { Write-ColorOutput "[步骤] $args" "Magenta" }

# ============================================================
# 系统检测
# ============================================================

function Detect-System {
    Print-Step "检测系统环境..."

    $script:OS_VERSION = [System.Environment]::OSVersion.Version
    $script:OS_NAME = (Get-CimInstance Win32_OperatingSystem).Caption
    $script:ARCH = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    $script:PYTHON_PATH = $null
    $script:CHROME_PATH = $null

    # 检测 Python
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        $script:PYTHON_PATH = $pythonCmd.Source
        $pythonVersion = & python --version 2>&1
    }

    # 检测 Chrome
    $chromePaths = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LocalAppData\Google\Chrome\Application\chrome.exe"
    )
    foreach ($path in $chromePaths) {
        if (Test-Path $path) {
            $script:CHROME_PATH = $path
            break
        }
    }

    # 打印检测结果
    Write-Host ""
    Write-Host "┌─────────────────────────────────────────┐"
    Write-Host "│           系统环境检测结果              │"
    Write-Host "├─────────────────────────────────────────┤"
    Write-Host ("│ {0,-15} │ {1,-21} │" -f "操作系统", "Windows")
    Write-Host ("│ {0,-15} │ {1,-21} │" -f "版本", "$($OS_VERSION.Major).$($OS_VERSION.Minor)")
    Write-Host ("│ {0,-15} │ {1,-21} │" -f "架构", $ARCH)
    Write-Host ("│ {0,-15} │ {1,-21} │" -f "Python", $(if ($PYTHON_PATH) { "已安装" } else { "未安装" }))
    Write-Host ("│ {0,-15} │ {1,-21} │" -f "Chrome", $(if ($CHROME_PATH) { "已安装" } else { "未安装" }))
    Write-Host "└─────────────────────────────────────────┘"
    Write-Host ""
}

# ============================================================
# 依赖检查
# ============================================================

function Check-Dependencies {
    Print-Step "检查依赖..."

    $missing = @()

    # 检查 Python
    if (-not $PYTHON_PATH) {
        $missing += "Python"
        Print-Warning "未检测到 Python"
        Print-Info "请从 https://www.python.org/downloads/ 下载安装"
        Print-Info "安装时请勾选 'Add Python to PATH'"
    } else {
        Print-Success "Python 已安装: $PYTHON_PATH"
    }

    # 检查 Chrome
    if (-not $CHROME_PATH) {
        $missing += "Chrome"
        Print-Warning "未检测到 Chrome"
        Print-Info "请从 https://www.google.com/chrome/ 下载安装"
    } else {
        Print-Success "Chrome 已安装: $CHROME_PATH"
    }

    if ($missing.Count -gt 0) {
        Write-Host ""
        Print-Error "缺少必要依赖: $($missing -join ', ')"
        Print-Info "请安装后重新运行此脚本"
        Read-Host "按 Enter 退出"
        exit 1
    }
}

# ============================================================
# Python 环境
# ============================================================

function Setup-PythonEnv {
    Print-Step "配置 Python 环境..."

    # 创建虚拟环境
    if (-not (Test-Path "venv")) {
        Print-Info "创建虚拟环境..."
        & python -m venv venv
    }

    # 激活虚拟环境
    $activateScript = ".\venv\Scripts\Activate.ps1"
    if (Test-Path $activateScript) {
        & $activateScript
    }

    # 升级 pip
    Print-Info "升级 pip..."
    & .\venv\Scripts\python.exe -m pip install --upgrade pip

    # 安装依赖
    Print-Info "安装 Python 依赖..."
    & .\venv\Scripts\pip.exe install -r requirements.txt

    Print-Success "Python 环境配置完成"
}

# ============================================================
# 一键配置
# ============================================================

function Interactive-Config {
    Print-Step "交互式配置..."
    Write-Host ""

    # 检查是否已有配置文件
    if (Test-Path "config.yaml") {
        Write-ColorOutput "检测到已有配置文件 config.yaml" "Yellow"
        $reconfig = Read-Host "是否重新配置？[y/N]"
        if ($reconfig -notmatch "^[Yy]$") {
            Print-Info "跳过配置，使用现有配置文件"
            return
        }
    }

    Write-Host ""
    Write-Host "┌─────────────────────────────────────────┐"
    Write-Host "│           一键配置向导                  │"
    Write-Host "└─────────────────────────────────────────┘"
    Write-Host ""

    # 用户名
    $username = Read-Host "Linux.do 用户名 (可选，直接回车跳过)"

    # 密码
    $password = ""
    if ($username) {
        $securePassword = Read-Host "Linux.do 密码 (可选，直接回车跳过)" -AsSecureString
        $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword))
    }

    # 浏览帖子数量
    $browseCount = Read-Host "每次浏览帖子数量 [默认: 10]"
    if (-not $browseCount) { $browseCount = "10" }

    # 点赞概率
    $likeProb = Read-Host "点赞概率 (0-1) [默认: 0.3]"
    if (-not $likeProb) { $likeProb = "0.3" }

    # 无头模式
    $headless = Read-Host "无头模式 (true/false) [默认: false]"
    if (-not $headless) { $headless = "false" }

    # Telegram 配置
    Write-Host ""
    Write-Host "Telegram 通知配置（可选）:"
    $tgToken = Read-Host "Telegram Bot Token (直接回车跳过)"
    $tgChatId = ""
    if ($tgToken) {
        $tgChatId = Read-Host "Telegram Chat ID"
    }

    # 用户数据目录
    $defaultUserDataDir = "$env:USERPROFILE\.linuxdo-browser"
    $userDataDir = Read-Host "用户数据目录 [默认: $defaultUserDataDir]"
    if (-not $userDataDir) { $userDataDir = $defaultUserDataDir }

    # 生成配置文件
    Print-Info "生成配置文件..."

    $configContent = @"
# ============================================================
# LinuxDO 签到配置文件
# 由一键安装脚本自动生成
# 生成时间: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# ============================================================

# ========== 账号配置 ==========
username: "$username"
password: "$password"

# ========== 浏览器配置 ==========
user_data_dir: "$($userDataDir -replace '\\', '/')"
headless: $headless
browser_path: "$($CHROME_PATH -replace '\\', '/')"

# ========== 签到配置 ==========
browse_count: $browseCount
like_probability: $likeProb
browse_interval_min: 3
browse_interval_max: 8

# ========== Telegram 通知 ==========
tg_bot_token: "$tgToken"
tg_chat_id: "$tgChatId"
"@

    $configContent | Out-File -FilePath "config.yaml" -Encoding UTF8

    Print-Success "配置文件已生成: config.yaml"

    # 创建用户数据目录
    if (-not (Test-Path $userDataDir)) {
        New-Item -ItemType Directory -Path $userDataDir -Force | Out-Null
    }
    Print-Success "用户数据目录已创建: $userDataDir"
}

# ============================================================
# 定时任务配置
# ============================================================

function Setup-ScheduledTask {
    Print-Step "配置定时任务..."
    Write-Host ""

    $setupTask = Read-Host "是否设置 Windows 定时任务？[y/N]"
    if ($setupTask -notmatch "^[Yy]$") {
        Print-Info "跳过定时任务配置"
        return
    }

    $scriptDir = Get-Location
    $pythonPath = "$scriptDir\venv\Scripts\python.exe"
    $mainScript = "$scriptDir\main.py"

    # 检查是否已存在任务
    $existingTask = Get-ScheduledTask -TaskName "LinuxDO-Checkin" -ErrorAction SilentlyContinue
    if ($existingTask) {
        Print-Warning "已存在 LinuxDO 签到任务"
        $overwrite = Read-Host "是否覆盖？[y/N]"
        if ($overwrite -match "^[Yy]$") {
            Unregister-ScheduledTask -TaskName "LinuxDO-Checkin" -Confirm:$false
        } else {
            return
        }
    }

    # 选择执行时间
    Write-Host ""
    Write-Host "选择签到时间:"
    Write-Host "  1. 每天 8:00 和 20:00（推荐）"
    Write-Host "  2. 每天 9:00"
    Write-Host "  3. 自定义"
    $timeChoice = Read-Host "请选择 [1-3]"

    $triggers = @()
    switch ($timeChoice) {
        "1" {
            $triggers += New-ScheduledTaskTrigger -Daily -At 8:00AM
            $triggers += New-ScheduledTaskTrigger -Daily -At 8:00PM
        }
        "2" {
            $triggers += New-ScheduledTaskTrigger -Daily -At 9:00AM
        }
        "3" {
            $customTime1 = Read-Host "输入第一个时间 (如 08:00)"
            $triggers += New-ScheduledTaskTrigger -Daily -At $customTime1
            $customTime2 = Read-Host "第二个时间 (直接回车跳过)"
            if ($customTime2) {
                $triggers += New-ScheduledTaskTrigger -Daily -At $customTime2
            }
        }
        default {
            $triggers += New-ScheduledTaskTrigger -Daily -At 8:00AM
            $triggers += New-ScheduledTaskTrigger -Daily -At 8:00PM
        }
    }

    # 创建日志目录
    $logsDir = "$scriptDir\logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    }

    # 创建任务
    $action = New-ScheduledTaskAction -Execute $pythonPath -Argument $mainScript -WorkingDirectory $scriptDir
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

    Register-ScheduledTask -TaskName "LinuxDO-Checkin" -Trigger $triggers -Action $action -Settings $settings -Description "LinuxDO 自动签到任务"

    Print-Success "定时任务已设置"
    Print-Info "查看任务: 任务计划程序 -> LinuxDO-Checkin"
}

# ============================================================
# 首次登录
# ============================================================

function First-Login {
    Print-Step "首次登录..."
    Write-Host ""

    $doLogin = Read-Host "是否现在进行首次登录？[Y/n]"
    if ($doLogin -match "^[Nn]$") {
        Print-Info "跳过首次登录"
        Print-Info "稍后运行: .\venv\Scripts\python.exe main.py --first-login"
        return
    }

    & .\venv\Scripts\python.exe main.py --first-login
}

# ============================================================
# 测试运行
# ============================================================

function Test-Run {
    Print-Step "测试运行..."
    Write-Host ""

    $doTest = Read-Host "是否进行测试运行？[y/N]"
    if ($doTest -notmatch "^[Yy]$") {
        Print-Info "跳过测试运行"
        return
    }

    & .\venv\Scripts\python.exe main.py
}

# ============================================================
# 安装完成
# ============================================================

function Print-Completion {
    Write-Host ""
    Write-ColorOutput "╔════════════════════════════════════════════════════════════╗" "Green"
    Write-ColorOutput "║                    安装完成！                              ║" "Green"
    Write-ColorOutput "╚════════════════════════════════════════════════════════════╝" "Green"
    Write-Host ""
    Write-Host "后续操作："
    Write-Host ""
    Write-ColorOutput "  1. 首次登录（如果还没完成）:" "Cyan"
    Write-Host "     .\venv\Scripts\python.exe main.py --first-login"
    Write-Host ""
    Write-ColorOutput "  2. 手动运行签到:" "Cyan"
    Write-Host "     .\venv\Scripts\python.exe main.py"
    Write-Host ""
    Write-ColorOutput "  3. 查看日志:" "Cyan"
    Write-Host "     Get-Content logs\checkin.log -Tail 50"
    Write-Host ""
    Write-ColorOutput "  4. 修改配置:" "Cyan"
    Write-Host "     notepad config.yaml"
    Write-Host ""
    Write-Host "项目地址: https://github.com/xtgm/linux-do-max"
    Write-Host ""
}

# ============================================================
# 主函数
# ============================================================

function Main {
    Print-Banner

    # 检查是否在项目目录
    if (-not (Test-Path "requirements.txt")) {
        Print-Error "请在项目目录下运行此脚本"
        Print-Info "cd path\to\linuxdo-checkin"
        Print-Info ".\install.ps1"
        Read-Host "按 Enter 退出"
        exit 1
    }

    # 系统检测
    Detect-System

    # 依赖检查
    Check-Dependencies

    # 确认安装
    Write-Host ""
    $confirm = Read-Host "是否开始安装？[Y/n]"
    if ($confirm -match "^[Nn]$") {
        Print-Info "安装已取消"
        exit 0
    }

    # 安装流程
    Write-Host ""
    Setup-PythonEnv
    Write-Host ""
    if (-not $SkipConfig) {
        Interactive-Config
        Write-Host ""
    }
    if (-not $SkipCron) {
        Setup-ScheduledTask
        Write-Host ""
    }
    First-Login
    Write-Host ""
    Test-Run
    Write-Host ""
    Print-Completion

    Read-Host "按 Enter 退出"
}

# 运行主函数
Main
