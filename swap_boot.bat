@echo off
REM 用法: swap_boot.bat 镜像文件
REM 例:  swap_boot.bat boot_full.img      （完全体）
REM      swap_boot.bat boot_test.img      （实验版）
REM      swap_boot.bat backup\boot.img    （官方原版）
if "%~1"=="" ( echo 用法: swap_boot.bat 镜像文件 & exit /b 1 )
if not exist "%~1" ( echo 文件不存在: %~1 & exit /b 1 )
echo [1/3] 正在推送 %~1 ...
adb push "%~1" /sdcard/boot_swap.img
echo [2/3] 正在写入 boot 分区（root 权限）...
adb shell "su -c 'dd if=/sdcard/boot_swap.img of=/dev/block/boot bs=4096; sync'"
echo [3/3] 重启生效...
adb shell reboot
echo 完成。开机日志身份标记: dmesg 第一行
