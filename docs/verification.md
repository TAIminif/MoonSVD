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

## 可复现的文件样本

- `fixtures/` 中的文件为本项目编写，并随项目许可证分发。检索、错误校验和版本比较可完全离线运行。两个 `status-*.svd` 使用相同的寄存器地址与位宽，独立检查 CLI 是否报告读副作用、位域写入方式及写入范围的变化。
- Arm `ARM_Example.svd` 来自 CMSIS 5.9.0 示例，带有文件内的版权和许可说明。样本解析出 33 个寄存器，核对 `TIMER0.RELOAD[3]` 的地址与复位值，并检查同地址的两个读写视图。 [原始示例](https://github.com/ARM-software/CMSIS_5/blob/5.9.0/CMSIS/Utilities/ARM_Example.svd)
- STM32F407 文件来自 CMSIS-SVD Data 的固定提交。样本解析出 1,540 个寄存器，核对 `RCC.CR` 的地址与复位值及 `PLLI2SRDY` 位域位置。 [固定样本](https://github.com/cmsis-svd/cmsis-svd-data/blob/c65f8551e57c770344d229dcaa0bf838fa29aff4/data/STMicro/STM32F407.svd)
- 两个外部样本均由验证脚本下载到临时目录，按脚本所列 SHA-256 核对，仓库只保留引用和验证方法。
- `Milky2018/xml@0.4.1` 采用 Apache-2.0，通过 MoonBit 模块依赖获取。Python 对照使用标准库的 XML 和 SHA-256 实现。 [XML 包](https://mooncakes.io/docs/Milky2018/xml@0.4.1)

## 初次准备

本地验证的工具链为 `moonc v0.10.15`。Linux CI 安装官方稳定版并记录版本，覆盖四个核心后端及 Node.js CLI，运行场景示例并生成源码包。
