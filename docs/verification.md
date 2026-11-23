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
- 文件输入限 16 MiB。库输入限 8,388,608 个 UTF-16 代码单元、250,000 个 XML 元素及 250,000 个展开实例。单个局部名称限 256 个 UTF-16 代码单元，限定路径限 4,096 个，数值文本限 128 个。声明索引和展开阶段各有 8,388,608 个 UTF-16 代码单元的累计名称预算，展开阶段同时计算寄存器别名。继承合并累计最多处理 1,000,000 个子项，直接继承会复用已有子项列表。
- CLI 回归测试检查损坏的 XML、非法 UTF-8、超限文件、目录、控制字符诊断和 Linux 命名管道。
- XML 解析前检查单个标签最多 128 个属性、65,536 个 UTF-16 代码单元，限制依赖逐项检查重复属性时的工作量。回归覆盖属性数和标签长度的临界值、单双引号内的等号与大于号、Unicode 长度，以及注释、处理指令和 CDATA 中的同名文本。
- 位宽回归覆盖 8、63、64 位边界、复位掩码与写约束范围、继承后的属性和位域约束覆盖。位域及寄存器的只读、只写、写一次视图分别检查读写冲突，新增同类视图仍会报告重叠。
- 合法输入回归覆盖含小数点和 Unicode 的设备名称，以及接近 `UInt64` 上界的数字范围型 `dimIndex`。数组索引用于实例名称，元素个数和地址步长分别校验，超长范围、逆序及数值溢出会返回解析错误。

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

本地验证的工具链为 `moonc v0.10.15`。Linux CI 安装官方稳定版并记录版本，覆盖四个核心后端及 Node.js CLI，运行场景示例并生成源码包。
