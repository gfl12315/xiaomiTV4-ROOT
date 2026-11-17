# U 盘保险绳使用说明

> 适用机型: 小米电视4 (L55M5-EC / txl_xmen 平台)
> 通道依据: 本机 U-Boot env `recovery_from_udisk`(fatload usb 0 aml_autoscript → autoscr) + `switch_bootmode`(irdetect 触发 update) —— 全部来自本机 env 分区实测解析
> 格式依据: 本机 U-Boot 源码 `common/cmd_source.c` + 外部真实 mkimage 产物交叉验证(hcrc/dcrc 复算全一致)

## U 盘文件清单(FAT32 单分区, 根目录平铺)

| 文件 | 作用 |
|---|---|
| `aml_autoscript` | U-Boot 脚本镜像(当前= test 无害验证版, 可换 rescue/install 版) |
| `twrp.img` | TWRP 镜像(autoscript 里 fatload 用) |
| `xmen.recovery` | 同 TWRP(本机 env 原生识别名) |
| `recovery.img` | 同 TWRP(部分固件版本识别名) |

四份脚本镜像说明(`scripts/build_autoscript.py --demo` 重新生成):

| 版本 | 行为 | 风险 |
|---|---|---|
| `test_autoscript` | 写入 env 标记 `usb_rescue_test` 并重启 | 零风险(可回读 env 分区闭环验证) |
| `rescue_autoscript` | 从 U 盘引导 TWRP, **不写任何分区** | 零风险 |
| `install_autoscript` | 把 U 盘 twrp.img 写入 recovery 分区再引导 | 低(有 backup/recovery.img 原厂备份) |
| `rescue_boot_autoscript` | 极限救援: 写 boot 分区(需 U 盘放 boot_rescue.img)+引导 TWRP | 中(需对应镜像, boot 有官方备份) |

## 触发方式(按无电脑程度排序)

1. **已 root**: `adb shell reboot update` → 重启自动进 update 流程 → U-Boot 读 U 盘执行
2. **未 root 但能开机**: 开 ADB 后同上(此路径同时是 LPE 提权→root 的前置)
3. **系统坏了 ADB 不通**: 电视断电 → 冷启动瞬间按遥控器任意键(irdetect 触发) → update 流程
4. **纯 TWRP 通道**: 按住遥控器确认键通电 → 直接进 recovery 分区的 TWRP(不依赖 U 盘)

## 验证闭环(test 版)

1. U 盘插电视 → `adb shell reboot update`
2. 电视重启 → U-Boot 执行脚本 → 自动重启回系统
3. `adb shell su -c 'dd if=/dev/block/env bs=1 skip=8 count=64'` → 看到 `usb_rescue_test=ok_` 即证明 autoscr 全链路通

## 风险控制

- 脚本**不含 defenv / env default -a**(外部案例警告: 会清空 env 导致引导异常)
- 写分区只写 recovery/boot, 原厂备份齐全(backup/ 目录 13 分区全镜像 + 电视内 /sdcard/boot_stock.img)
- U-Boot 阶段的 U 盘读取只认 FAT32, 建议 8-32GB 普通品牌盘, 插电视 USB 2.0 口
- 一次只插一个 U 盘(fatload usb 0 只枚举第一个设备)

## 制作工具

```
python scripts/build_autoscript.py --demo --outdir 输出目录     # 生成全部脚本镜像+明文
python scripts/build_autoscript.py --text 自定义.txt --out aml_autoscript
```
格式自检内置: magic/hcrc(整头CRC)/dcrc(数据CRC)/type=SCRIPT/数据区[BE32长度+BE32终止+文本] 逐项复算。
