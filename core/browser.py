"""
浏览器控制模块
使用 DrissionPage 控制 Chrome 浏览器
支持 Windows / macOS / Linux (x64/ARM) 全平台
"""
import os
import sys
import time
import shutil
import platform
import subprocess
from pathlib import Path
from typing import Optional, List
from DrissionPage import ChromiumPage, ChromiumOptions
from .config import config


def is_linux() -> bool:
    """检测是否为 Linux 系统"""
    return platform.system().lower() == "linux"


def is_macos() -> bool:
    """检测是否为 macOS 系统"""
    return platform.system().lower() == "darwin"


def is_windows() -> bool:
    """检测是否为 Windows 系统"""
    return platform.system().lower() == "windows"


def is_arm() -> bool:
    """检测是否为 ARM 架构"""
    machine = platform.machine().lower()
    return machine in ("aarch64", "arm64", "armv7l", "armv8l")


def is_container() -> bool:
    """检测是否在容器环境中（Docker/LXC/Podman）"""
    if not is_linux():
        return False
    # Docker
    if os.path.exists("/.dockerenv"):
        return True
    # LXC/Podman
    if os.path.exists("/run/.containerenv"):
        return True
    # 检查 cgroup
    try:
        with open("/proc/1/cgroup", "r") as f:
            content = f.read()
            if "docker" in content or "lxc" in content or "kubepods" in content:
                return True
    except:
        pass
    # systemd-detect-virt
    try:
        result = subprocess.run(
            ["systemd-detect-virt", "-c"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            virt = result.stdout.strip().lower()
            if virt in ("lxc", "lxc-libvirt", "docker", "podman", "openvz"):
                return True
    except:
        pass
    return False


def is_root() -> bool:
    """检测是否以 root 用户运行"""
    if is_linux() or is_macos():
        return os.geteuid() == 0
    return False


def is_wsl() -> bool:
    """检测是否在 WSL 环境中"""
    if not is_linux():
        return False
    try:
        with open("/proc/version", "r") as f:
            content = f.read().lower()
            return "microsoft" in content or "wsl" in content
    except:
        pass
    return False


def is_virtual_machine() -> bool:
    """检测是否在虚拟机中"""
    if not is_linux():
        return False
    try:
        result = subprocess.run(
            ["systemd-detect-virt"],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode == 0:
            virt = result.stdout.strip().lower()
            if virt and virt != "none":
                return True
    except:
        pass
    # 检查 DMI 信息
    try:
        with open("/sys/class/dmi/id/product_name", "r") as f:
            product = f.read().lower()
            vm_keywords = ["vmware", "virtualbox", "kvm", "qemu", "hyper-v", "xen"]
            for kw in vm_keywords:
                if kw in product:
                    return True
    except:
        pass
    return False


def has_display() -> bool:
    """检测是否有图形显示环境"""
    if is_windows():
        return True
    if is_macos():
        return True
    # Linux 检测 DISPLAY 或 WAYLAND_DISPLAY
    if os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"):
        return True
    return False


def find_browser_path() -> str:
    """自动查找浏览器路径（只使用 Google Chrome，不使用 Snap Chromium）"""
    if is_windows():
        paths = [
            os.path.expandvars(r"%ProgramFiles%\Google\Chrome\Application\chrome.exe"),
            os.path.expandvars(r"%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"),
            os.path.expandvars(r"%LocalAppData%\Google\Chrome\Application\chrome.exe"),
        ]
    elif is_macos():
        paths = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        ]
    else:  # Linux - 只使用 Google Chrome
        paths = [
            "/usr/bin/google-chrome",
            "/usr/bin/google-chrome-stable",
            "/opt/google/chrome/chrome",
        ]

    for path in paths:
        if os.path.exists(path) and os.access(path, os.X_OK):
            return path

    # Linux/macOS: 尝试 which 命令（只找 google-chrome）
    if not is_windows():
        for cmd in ["google-chrome", "google-chrome-stable"]:
            try:
                result = subprocess.run(
                    ["which", cmd],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0:
                    path = result.stdout.strip()
                    if path and os.path.exists(path):
                        # 排除 Snap 版本
                        real_path = os.path.realpath(path)
                        if "snap" not in real_path:
                            return path
            except:
                pass

    return ""


def get_chrome_args() -> List[str]:
    """获取 Chrome 启动参数（跨平台）"""
    args = []

    # ===== 通用参数 =====
    args.append("--disable-blink-features=AutomationControlled")
    args.append("--no-first-run")
    args.append("--no-default-browser-check")
    args.append("--disable-infobars")
    args.append("--disable-popup-blocking")

    # ===== Linux 专用参数 =====
    if is_linux():
        # --no-sandbox: Linux 几乎必须
        # root 用户、容器、虚拟机、WSL 都需要
        args.append("--no-sandbox")

        # 禁用 /dev/shm（共享内存）
        # 很多 Linux 环境 /dev/shm 太小会导致崩溃
        args.append("--disable-dev-shm-usage")

        # 禁用 GPU（虚拟机/无 GPU 环境）
        args.append("--disable-gpu")

        # 禁用软件光栅化
        args.append("--disable-software-rasterizer")

        # 单进程模式（某些环境下更稳定）
        # args.append("--single-process")  # 可能导致问题，暂不启用

        # 禁用扩展
        args.append("--disable-extensions")

        # 禁用后台网络服务
        args.append("--disable-background-networking")

        # 禁用默认应用检查
        args.append("--disable-default-apps")

        # 禁用同步
        args.append("--disable-sync")

        # 禁用翻译
        args.append("--disable-translate")

        # 禁用后台定时器节流
        args.append("--disable-background-timer-throttling")

        # 禁用渲染器后台化
        args.append("--disable-renderer-backgrounding")

        # 禁用 IPC 洪水保护（避免连接断开）
        args.append("--disable-ipc-flooding-protection")

        # 虚拟机/WSL 额外参数
        if is_virtual_machine() or is_wsl():
            args.append("--disable-features=VizDisplayCompositor")

    # ===== macOS 专用参数 =====
    elif is_macos():
        # macOS 通常不需要 --no-sandbox
        # 但某些情况下可能需要
        if is_root():
            args.append("--no-sandbox")

        args.append("--disable-gpu")
        args.append("--disable-extensions")

    return args


class Browser:
    """浏览器控制类"""

    def __init__(self):
        self.page: Optional[ChromiumPage] = None
        self._port = 9222  # 默认调试端口

    def _setup_user_data_dir(self):
        """确保用户数据目录存在"""
        user_data_dir = Path(config.user_data_dir)
        user_data_dir.mkdir(parents=True, exist_ok=True)

    def _find_free_port(self) -> int:
        """查找可用端口"""
        import socket
        for port in range(9222, 9322):
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                    s.bind(('127.0.0.1', port))
                    return port
            except OSError:
                continue
        return 9222  # 默认返回 9222

    def _kill_existing_chrome(self):
        """关闭可能存在的 Chrome 进程（避免端口冲突）"""
        if is_linux() or is_macos():
            try:
                # 查找占用调试端口的进程
                result = subprocess.run(
                    ["lsof", "-ti", f":{self._port}"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0 and result.stdout.strip():
                    pids = result.stdout.strip().split('\n')
                    for pid in pids:
                        try:
                            subprocess.run(["kill", "-9", pid], timeout=5)
                        except:
                            pass
                    time.sleep(1)
            except:
                pass

    def _create_options(self) -> ChromiumOptions:
        """创建浏览器选项"""
        co = ChromiumOptions()

        # 用户数据目录（保存登录状态）
        user_data_dir = config.user_data_dir
        if user_data_dir:
            co.set_argument(f"--user-data-dir={user_data_dir}")

        # 有头/无头模式
        co.headless(config.headless)

        # 自定义浏览器路径（优先使用配置，否则自动检测）
        browser_path = config.browser_path
        if not browser_path:
            browser_path = find_browser_path()
        if browser_path:
            co.set_browser_path(browser_path)
            print(f"[浏览器] 使用浏览器: {browser_path}")
        else:
            print("[浏览器] 警告: 未找到浏览器，将使用系统默认")

        # 获取跨平台 Chrome 参数
        chrome_args = get_chrome_args()
        for arg in chrome_args:
            co.set_argument(arg)

        # Linux/macOS: 设置远程调试端口
        if is_linux() or is_macos():
            # 查找可用端口
            self._port = self._find_free_port()
            co.set_argument(f"--remote-debugging-port={self._port}")
            co.set_local_port(self._port)
            print(f"[浏览器] 调试端口: {self._port}")

        # 用户自定义 Chrome 参数（最后添加，可覆盖默认）
        for arg in config.chrome_args:
            co.set_argument(arg)

        return co

    def start(self, retry: int = 3) -> bool:
        """启动浏览器（带重试机制）"""
        for attempt in range(retry):
            try:
                # 确保用户数据目录存在
                self._setup_user_data_dir()

                # Linux/macOS: 清理可能占用端口的进程
                if is_linux() or is_macos():
                    self._kill_existing_chrome()

                options = self._create_options()
                self.page = ChromiumPage(options)
                print("[浏览器] 启动成功")
                return True
            except Exception as e:
                print(f"[浏览器] 启动失败 (尝试 {attempt + 1}/{retry}): {e}")
                if attempt < retry - 1:
                    # 等待后重试
                    time.sleep(2)
                    # 尝试使用不同端口
                    if is_linux() or is_macos():
                        self._port = self._find_free_port()

        print("[浏览器] 启动失败，已达最大重试次数")
        return False

    def quit(self):
        """关闭浏览器"""
        if self.page:
            try:
                self.page.quit()
                print("[浏览器] 已关闭")
            except Exception as e:
                print(f"[浏览器] 关闭异常: {e}")
            finally:
                self.page = None

    def goto(self, url: str, wait: float = 2) -> bool:
        """访问页面"""
        if not self.page:
            print("[浏览器] 浏览器未启动")
            return False
        try:
            self.page.get(url)
            time.sleep(wait)
            return True
        except Exception as e:
            print(f"[浏览器] 访问失败 {url}: {e}")
            return False

    def wait_for_cf(self, timeout: int = 120) -> bool:
        """
        等待 Cloudflare 5秒盾验证通过
        检测页面是否还在验证中
        """
        if not self.page:
            return False

        print("[浏览器] 检测 CF 验证...")
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                page_text = self.page.html.lower()
            except:
                time.sleep(2)
                continue

            # CF 验证中的特征
            cf_checking = any([
                "just a moment" in page_text,
                "请稍候" in page_text,
                "checking your browser" in page_text,
                "cf-browser-verification" in page_text,
            ])

            if not cf_checking:
                print("[浏览器] CF 验证通过")
                return True

            # 尝试点击 Turnstile 验证框
            try:
                turnstile = self.page.ele("css:input[type='checkbox']", timeout=1)
                if turnstile:
                    turnstile.click()
                    print("[浏览器] 点击 Turnstile 验证框")
            except:
                pass

            time.sleep(2)

        print("[浏览器] CF 验证超时")
        return False

    def check_rate_limit(self) -> bool:
        """检测 429 限流"""
        if not self.page:
            return False
        try:
            # 检查 HTTP 状态码（如果页面显示错误）
            page_title = self.page.title.lower() if self.page.title else ""
            page_text = self.page.html.lower()

            # 只检查明确的限流标识，避免误判
            rate_limited = any([
                "rate limited" in page_text,
                "too many requests" in page_title,
                "429 too many" in page_text,
                "<h1>429</h1>" in page_text,
            ])
            if rate_limited:
                print("[浏览器] 检测到 429 限流")
            return rate_limited
        except:
            return False

    def check_cf_403(self) -> bool:
        """检测 CF 403 错误"""
        if not self.page:
            return False
        try:
            # 检测弹出对话框
            dialog = self.page.ele("css:.dialog-body", timeout=1)
            if dialog and "403" in dialog.text.lower():
                print("[浏览器] 检测到 CF 403 错误")
                return True
            # 检测页面级 403
            page_text = self.page.html.lower() if self.page.html else ""
            if "403 forbidden" in page_text or "<h1>403</h1>" in page_text:
                print("[浏览器] 检测到 CF 403 页面")
                return True
        except:
            pass
        return False

    def close_403_dialog(self) -> bool:
        """关闭 403 错误对话框"""
        try:
            # 查找并点击"确定"按钮
            ok_btn = self.page.ele("css:.dialog-footer .btn-primary", timeout=2)
            if ok_btn:
                ok_btn.click()
                print("[浏览器] 已关闭 403 对话框")
                time.sleep(1)
                return True
            # 备选：查找任何对话框的确定按钮
            ok_btn = self.page.ele("css:button.btn-primary", timeout=1)
            if ok_btn and ("确定" in ok_btn.text or "OK" in ok_btn.text.upper()):
                ok_btn.click()
                print("[浏览器] 已关闭对话框")
                time.sleep(1)
                return True
        except:
            pass
        return False

    def handle_cf_403(self, current_url: str) -> bool:
        """处理 CF 403 错误，等待验证完成"""
        try:
            # 1. 先关闭 403 对话框
            self.close_403_dialog()

            # 2. 跳转到 challenge 页面
            challenge_url = f"https://linux.do/challenge?redirect={current_url}"
            print(f"[浏览器] 跳转到验证页面...")
            self.goto(challenge_url, wait=3)

            # 3. 等待 CF 验证完成（增加超时时间）
            if not self.wait_for_cf(timeout=180):
                print("[浏览器] CF 验证超时，等待用户手动处理...")
                # 额外等待用户手动处理
                time.sleep(30)
                return self.wait_for_cf(timeout=60)

            return True
        except Exception as e:
            print(f"[浏览器] 处理 CF 403 失败: {e}")
            return False

    def is_logged_in(self) -> bool:
        """检测是否已登录"""
        if not self.page:
            return False
        try:
            # 检查是否有用户头像或用户菜单
            user_menu = self.page.ele("css:.current-user", timeout=3)
            if user_menu:
                return True

            # 检查是否有登录按钮
            login_btn = self.page.ele("css:.login-button", timeout=1)
            if login_btn:
                return False

            return False
        except:
            return False

    def get_current_user(self) -> Optional[str]:
        """获取当前登录用户名"""
        if not self.page:
            return None
        try:
            # 方法1: 从用户头像 URL 提取用户名
            # 格式: /user_avatar/linux.do/USERNAME/48/xxx.png
            avatar = self.page.ele("css:#current-user img.avatar", timeout=3)
            if avatar:
                src = avatar.attr("src")
                if src and "/user_avatar/" in src:
                    # /user_avatar/linux.do/username/48/xxx.png
                    parts = src.split("/user_avatar/")[-1].split("/")
                    if len(parts) >= 2:
                        return parts[1]  # 用户名在第二段

            # 方法2: 从页面中的 /u/ 链接提取（备选）
            user_links = self.page.eles("css:a[href*='/u/']")
            for link in user_links[:10]:
                href = link.attr("href")
                if href and "/u/" in href and "/activity/" in href:
                    # https://linux.do/u/username/activity/drafts
                    return href.split("/u/")[-1].split("/")[0]
        except:
            pass
        return None


def clear_browser_cache(user_data_dir: str = None) -> dict:
    """
    清理浏览器缓存（仅 Linux 系统）
    用于节省容器/VPS 磁盘空间

    清理内容：
    - Cache: 网页缓存
    - Code Cache: JavaScript 代码缓存
    - GPUCache: GPU 缓存
    - ShaderCache: 着色器缓存
    - 临时文件: crash reports, blob_storage 等

    参数:
        user_data_dir: 用户数据目录，默认使用配置中的目录

    返回:
        dict: 清理结果统计
    """
    if not is_linux():
        return {"skipped": True, "reason": "非 Linux 系统，跳过清理"}

    if user_data_dir is None:
        user_data_dir = config.user_data_dir

    user_data_path = Path(user_data_dir)
    if not user_data_path.exists():
        return {"skipped": True, "reason": "用户数据目录不存在"}

    result = {
        "cleared": [],
        "not_found": [],
        "errors": [],
        "freed_bytes": 0
    }

    # 需要清理的缓存目录
    cache_dirs = [
        "Default/Cache",           # 网页缓存
        "Default/Code Cache",      # 代码缓存
        "Default/GPUCache",        # GPU 缓存
        "ShaderCache",             # 着色器缓存
        "GrShaderCache",           # Skia 着色器缓存
    ]

    # 需要清理的临时文件/目录
    temp_items = [
        "Crashpad",                # 崩溃报告
        "crash_reports",           # 崩溃报告
        "Default/blob_storage",    # Blob 存储
        "Default/Session Storage", # 会话存储（可选，不影响登录）
        "Default/Service Worker",  # Service Worker 缓存
        "BrowserMetrics",          # 浏览器指标
        "Default/optimization_guide_hint_cache_store",  # 优化提示缓存
    ]

    def get_dir_size(path: Path) -> int:
        """获取目录大小"""
        total = 0
        try:
            for entry in path.rglob("*"):
                if entry.is_file():
                    try:
                        total += entry.stat().st_size
                    except:
                        pass
        except:
            pass
        return total

    def safe_remove(path: Path, name: str) -> bool:
        """安全删除目录或文件"""
        try:
            if path.is_dir():
                size = get_dir_size(path)
                shutil.rmtree(path)
                result["freed_bytes"] += size
                result["cleared"].append(name)
                return True
            elif path.is_file():
                size = path.stat().st_size
                path.unlink()
                result["freed_bytes"] += size
                result["cleared"].append(name)
                return True
        except Exception as e:
            result["errors"].append(f"{name}: {e}")
        return False

    print("[缓存清理] 开始清理浏览器缓存...")

    # 清理缓存目录
    for cache_dir in cache_dirs:
        cache_path = user_data_path / cache_dir
        if cache_path.exists():
            safe_remove(cache_path, cache_dir.split("/")[-1])
        else:
            result["not_found"].append(cache_dir.split("/")[-1])

    # 清理临时文件
    for temp_item in temp_items:
        temp_path = user_data_path / temp_item
        if temp_path.exists():
            safe_remove(temp_path, temp_item.split("/")[-1])

    # 输出结果
    if result["cleared"]:
        for item in result["cleared"]:
            print(f"[缓存清理] 🗑️ 已清理: {item}")

    if not result["cleared"] and not result["errors"]:
        print("[缓存清理] ✨ 没有发现需要清理的缓存")

    if result["errors"]:
        for err in result["errors"]:
            print(f"[缓存清理] ⚠️ 清理失败: {err}")

    # 显示释放空间
    freed_mb = result["freed_bytes"] / (1024 * 1024)
    if freed_mb >= 0.01:
        print(f"[缓存清理] 🎉 清理完成！释放空间: {freed_mb:.2f} MB")
    else:
        print("[缓存清理] 🎉 清理完成！")

    return result
