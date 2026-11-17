# SSH / 远程管理使用说明（boot_full.img 完全体）

## 连接方式
```
ssh -i tv_client_ed25519 root@电视IP
```
- 端口 22，密钥认证（私钥 = 本文件夹 ssh\tv_client_ed25519）
- 登录即 root，默认目录 /data/local/tmp
- 文件传输: SFTP（WinSCP/FileZilla 填同样密钥）

## 开机自动运行的服务
| 服务 | 端口 | 位置 | 说明 |
|---|---|---|---|
| dropbear SSH | 22 | /data/local/tmp/dropbear | 密钥认证 root 直登 |
| httpd 文件服务器 | 8080 | /data/local/tmp/httpd | 浏览器 http://电视IP:8080 浏览/下载 /sdcard |
| adbd | 5555 | 系统自带 | adb connect 电视IP:5555，免授权 |

以上全部开机自动启动，重启不丢。

## /heal 自愈系统（随 boot 分区，开机自动执行）
- 系统分区丢 su → 60 秒内自动从 /data 重装
- build.prop / install-recovery.sh 被还原 → 自动补写
- ADB 被关 → adbwatch 每 20 秒巡查拉回
- 日志: /data/local/tmp/heal.log 与 adbwatch.log
- 便捷命令: sysrw（系统分区转可写）/ sysro（转回只读）

## /data 依赖文件（工厂重置 data 后需重新推送）
su / dropbear / sftp / bb / httpd / install-recovery.sh.new2 → /data/local/tmp/

## 内核身份标记
- 开机日志(dmesg)第一行与 /proc/version 均含 XMENOK01 —— 确认跑的是完全体内核

## 三版本一键对调（swap_boot.bat）
- backup\boot.img 官方原版 / boot_test.img 实验版 / boot_full.img 完全体
