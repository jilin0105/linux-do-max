"""
青龙面板入口
薄封装，调用 main.py 的签到逻辑

青龙面板使用方法：
1. 将项目文件上传到青龙面板的 scripts 目录
2. 添加定时任务：python3 ql_main.py
3. 在青龙面板的环境变量中配置：
   - LINUXDO_USERNAME: Linux.do 用户名（注意前缀）
   - LINUXDO_PASSWORD: Linux.do 密码
   - TG_BOT_TOKEN: Telegram Bot Token
   - TG_CHAT_ID: Telegram Chat ID
   - HEADLESS: true/false（青龙面板建议 false + Xvfb）
"""
import sys
import os

# 添加项目根目录到 Python 路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from core.checkin import Checkin
from version import __version__


def check_update_silent():
    """静默检查更新（仅显示提示，不阻塞）"""
    try:
        from updater import check_update
        update_info = check_update(silent=True)
        if update_info:
            print(f"[提示] 发现新版本 v{update_info['latest_version']}，请手动更新")
            print(f"[提示] 更新命令: git pull origin main")
            print()
    except:
        pass


def main():
    """青龙面板入口"""
    print("=" * 50)
    print(f"LinuxDO 签到 - 青龙面板模式 v{__version__}")
    print("=" * 50)

    # 静默检查更新（不阻塞）
    check_update_silent()

    # 打印环境变量配置状态（不打印敏感信息）
    env_status = {
        "LINUXDO_USERNAME": "✅" if os.environ.get("LINUXDO_USERNAME") else "❌",
        "LINUXDO_PASSWORD": "✅" if os.environ.get("LINUXDO_PASSWORD") else "❌",
        "TG_BOT_TOKEN": "✅" if os.environ.get("TG_BOT_TOKEN") else "❌",
        "TG_CHAT_ID": "✅" if os.environ.get("TG_CHAT_ID") else "❌",
        "USER_DATA_DIR": os.environ.get("USER_DATA_DIR", "默认"),
        "HEADLESS": os.environ.get("HEADLESS", "false"),
    }

    print("\n环境变量配置状态：")
    for key, value in env_status.items():
        print(f"  {key}: {value}")
    print()

    # 创建新的签到实例（避免状态累积）
    checkin = Checkin()
    success = checkin.run()

    if success:
        print("\n✅ 签到任务完成")
        return 0
    else:
        print("\n❌ 签到任务失败")
        return 1


if __name__ == "__main__":
    sys.exit(main())
