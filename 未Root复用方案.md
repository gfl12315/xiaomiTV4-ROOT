# 未 Root 小米电视4 复用方案（零额外硬件）

> 目标: 拿这个 U 盘插到**任何一台同款未 Root 的小米电视4（txl_xmen 平台）**上完成 TWRP + 持久 Root，全程不需要 TTL 串口、USB A-to-A 线、USB Burning Tool。
> 硬件清单: 一个 U 盘（本包）+ WiFi 同网段电脑（跑 adb）+ USB 鼠标（TWRP 界面操作，可选）

## 环节验证状态

| 环节 | 验证方式 | 状态 |
|---|---|---|
| ADB 网络连接（未 root shell 身份） | 本机 shell 用户等效测试 | ✓ |
| `adb shell reboot update`（未 root 可执行） | 本机 shell 身份实测两次成功 | ✓ |
| U-Boot 自动引导 U 盘 TWRP（xmen.recovery） | 本机实测两次进入 TWRP | ✓ |
| TWRP 鼠标/界面操作刷 zip | fix.zip 已在 TWRP 里刷入成功 | ✓ |
| Magisk v19.1 兼容 Android 6.0.1 老内核 | CSDN 小米 4A/4S/4X 用户实测 | ✓ |
| 未 root 手写 ORS 自动化 | shell 用户写 /cache/recovery 实测被拒 | ✗（自动化仅限已 root 设备） |

## 六步操作流程（未 Root 电视）

1. **电视开 ADB**: 设置 → 关于 → 连续点击"产品型号"开启开发者模式 → 产品与安全 → 打开 ADB 调试
2. **电脑连接**: `adb connect 电视IP`（同 WiFi）
3. **触发**: `adb shell reboot update` —— 电视重启，U-Boot 自动引导 U 盘里的 TWRP
4. **TWRP 操作**: 插 USB 鼠标 → Install → 选择 U 盘上的 `Magisk-v19.1.zip` → 滑动刷入
   - 若提示无法挂载: 先进 Mount 勾选 System 再刷（小米 4A 用户同款经验）
5. **重启**: TWRP 里 Reboot → System
6. **验收**: 开机后装 Magisk Manager APK（zip 内自带 common/magisk.apk），确认 Root 授权

## U 盘文件清单（本包）

| 文件 | 用途 |
|---|---|
| `xmen.recovery` | TWRP 镜像——U-Boot `recovery_from_udisk` 原生识别名（主通道），由发布包 usb_pack/twrp.img 复制改名 |
| `recovery.img` | 同镜像备用名（部分固件版本识别此名，小米 4A 用户实测经验），由 usb_pack/twrp.img 复制改名 |
| `twrp.img` | 同镜像备用名 |
| `Magisk-v19.1.zip` | Root 包（Android 6.0.1 实测兼容版） |
| `test_ors.zip` | OpenRecoveryScript 闭环验证包（已 root 设备用，无害） |
| `aml_autoscript` | U-Boot 脚本（本机固件未编译 source 命令，不生效，留着无害） |

## 已知边界

- **aml_autoscript 在本系列固件上不生效**: 小米 txl 固件未编译 U-Boot 的 `source` 命令（`CONFIG_CMD_SOURCE` 未定义），env 里的 `autoscr` 调用是死代码。U 盘自动化在 U-Boot 层做不到，自动化由 TWRP 内手动操作或 OpenRecoveryScript（需 root）承担。
- **xmen.recovery 优先**: 若电视没进 TWRP，确认 U 盘是 FAT32、单分区、根目录平铺，以及电视 USB 口供电正常（多数 U 盘插上后指示灯亮）。
- **回滚**: recovery 分区被改动时，用 backup/recovery.img（官方原版）按回滚表恢复；仅引导不落盘则电视分区分毫未动。
