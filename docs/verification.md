# 验证与来源

使用 MoonBit 自带的测试覆盖 XML 读取、数值和边界检查、寄存器继承和数组、位域和地址冲突、查找、稳定差异和精确 JSON 输出。JavaScript 命令行集成测试对实际文件和进程退出码做断言。

```sh
moon test --target wasm-gc --deny-warn
moon test --target wasm --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
moon build --target js --release
python scripts/verify_cli.py --official
```

## 异常输入

- 回归测试覆盖 DTD 在进入 XML 解析前被拒绝、注释与 CDATA 中的同名文本仍可读取，以及两种声明顺序下 64 层继承成功、65 层失败。
- XML 声明位置在解析事件之前校验，覆盖有无 BOM、重复声明之间的 CRLF、声明前的空白、注释和处理指令，并核对错误行列号。合法的 BOM 和单次声明、`xml-stylesheet` / `xml-model` 指令及 CDATA、注释内的同名文本保持可读；CLI 使用 Python ElementTree 独立确认重复声明非法并检查退出码 2。依据 [XML 1.0 文档序言规则](https://www.w3.org/TR/xml/#sec-prolog-dtd)。
- 文件输入限 16 MiB。库输入限 8,388,608 个 UTF-16 代码单元、250,000 个 XML 元素及 250,000 个展开实例。单个局部名称限 256 个 UTF-16 代码单元，限定路径限 4,096 个，数值文本限 128 个。声明索引和展开阶段各有 8,388,608 个 UTF-16 代码单元的累计名称预算，展开阶段同时计算寄存器别名。继承合并累计最多处理 1,000,000 个子项，直接继承会复用已有子项列表。
- 外设、寄存器组和寄存器的展开层级最多 32 层。语义校验同时跟踪最多 128 个重叠寄存器，超过时报告 `overlap-density`，CLI `check` 返回 1。
- CLI 回归测试检查损坏的 XML、非法 UTF-8、超限文件、目录、控制字符诊断和 Linux 命名管道。
- `at` 命令回归覆盖十进制与整数前缀、下划线、128 字符边界、非法数字和溢出。以两个相邻的 UInt64 最大地址核对数组实例，确认不会因 JavaScript 数字转换而合并地址，并返回同地址的全部别名。六份厂商样本按 Python 独立计算的地址核对查询结果。
- XML 解析前检查单个标签最多 128 个属性、65,536 个 UTF-16 代码单元，限制依赖逐项检查重复属性时的工作量。回归覆盖属性数和标签长度的临界值、单双引号内的等号与大于号、Unicode 长度，以及注释、处理指令和 CDATA 中的同名文本。
- 位宽回归覆盖 8、63、64 位边界、复位掩码与写约束范围、继承后的属性和位域约束覆盖。位域及寄存器的只读、只写、写一次视图分别检查读写冲突，新增同类视图仍会报告重叠。
- 合法输入回归覆盖含小数点和 Unicode 的设备名称，以及接近 `UInt64` 上界的数字范围型 `dimIndex`。数组索引用于实例名称，元素个数和地址步长分别校验，超长范围、逆序及数值溢出会返回解析错误。
- 别名回归覆盖正反两种声明顺序的连续引用、循环与悬空引用的依赖者、跨地址引用，以及短名与完整路径之间的语义比较。CLI 同时验证合法链返回 0、循环链返回 1、等价路径比较无差异。
- 组合别名回归覆盖两组 `alternateGroup` 由显式引用连接的情况，以及正反声明顺序。循环引用和跨地址引用会独立报错，别名组也按作用域、地址及存储宽度区分。

## 可复现的文件样本

- `fixtures/` 中的文件为本项目编写，并随项目许可证分发。检索、错误校验和版本比较可完全离线运行。两个 `status-*.svd` 使用相同的寄存器地址与位宽，独立检查 CLI 是否报告读副作用、位域写入方式及写入范围的变化。
- Arm `ARM_Example.svd` 来自 CMSIS 5.9.0 示例，带有文件内的版权和许可说明。样本解析出 33 个寄存器，核对 `TIMER0.RELOAD[3]` 的地址与复位值，并检查同地址的两个读写视图。 [原始示例](https://github.com/ARM-software/CMSIS_5/blob/5.9.0/CMSIS/Utilities/ARM_Example.svd)
- STM32F407 文件来自 CMSIS-SVD Data 的固定提交。样本解析出 1,540 个寄存器，核对 `RCC.CR` 的地址与复位值及 `PLLI2SRDY` 位域位置。 [固定样本](https://github.com/cmsis-svd/cmsis-svd-data/blob/c65f8551e57c770344d229dcaa0bf838fa29aff4/data/STMicro/STM32F407.svd)
- Nordic nrfx v3.14.0 的 `nrf52840.svd` 和 `nrf5340_application.svd` 分别解析出 2,332 和 9,956 个寄存器。查询 `APPROTECT.FORCEPROTECT`、`CC_HOST_RGF.HOST_IOT_KDR1` 和 `CACHE_S.DEBUGLOCK`，核对两种写一次权限拼写与位域继承。 [nRF52840](https://github.com/nordicsemi/nrfx/blob/v3.14.0/mdk/nrf52840.svd) · [nRF5340](https://github.com/nordicsemi/nrfx/blob/v3.14.0/mdk/nrf5340_application.svd)
- Raspberry Pi Pico SDK 2.2.0 的 RP2040 和 RP2350 分别解析出 1,182 和 3,029 个寄存器。查询两份文件的 `RESETS.RESET`，核对地址、复位值及 `USBCTRL` 位域。 [RP2040](https://github.com/raspberrypi/pico-sdk/blob/2.2.0/src/rp2040/hardware_regs/RP2040.svd) · [RP2350](https://github.com/raspberrypi/pico-sdk/blob/2.2.0/src/rp2350/hardware_regs/RP2350.svd)
- RP2350 的 `OTP_DATA.BOOTSEL_LED_CFG`、`BOOTSEL_PLL_CFG`、`BOOTSEL_XOSC_CFG` 和 `FLASH_DEVINFO` 声明为 16 位，继承的复位掩码为 `0xffffffff`。`check` 返回 1，输出这四个路径的 `reset-mask-width`。脚本以固定哈希原文件独立核对这些寄存器的位宽、掩码和完整诊断列表，另外五个样本的 `check` 返回 0。这些检查验证 MoonSVD 的寄存器语义处理范围，完整 XSD 合规性可用专用工具核查。
- 外部样本由验证脚本下载，按脚本所列 SHA-256 核对，仓库保留引用和验证方法。用 `--reference-dir` 指定本地目录可复用已下载样本。
- `Milky2018/xml@0.4.1` 采用 Apache-2.0，通过 MoonBit 模块依赖获取。Python 对照使用标准库的 XML 和 SHA-256 实现。 [XML 包](https://mooncakes.io/docs/Milky2018/xml@0.4.1)

## 初次准备

项目要求 `moonc` 不低于 0.10.16。本地使用 `moonc v0.10.22` 完成检查、测试、JS 构建、示例、CLI 和源码打包。Linux CI 安装官方稳定版，校验并记录编译器版本，覆盖四个核心后端及 Node.js CLI。

## 发布与安装验证

版本 `guoqi/moonsvd@0.3.0` 已发布至 [Mooncakes](https://mooncakes.io/docs/guoqi/moonsvd@0.3.0)。在不引用仓库源码的独立项目中执行 `moon add guoqi/moonsvd@0.3.0`，从注册表下载依赖，在 wasm-gc、wasm、js 三个后端完成检查和运行。验证解析、路径查询、地址查询、位域解码、校验和自比较，示例输出 `TIMER.CTRL @ 40000004, EN=1`。

安装包中的 32 份 MoonBit 源码、接口、包配置及 CLI 文件与 [v0.3.0 发布源码](https://github.com/TAIminif/MoonSVD/tree/v0.3.0) 一致（文本换行统一后比较），根许可证也一致。README 提供了相同的安装命令，包元数据中的源码地址为 `https://github.com/TAIminif/MoonSVD`。
