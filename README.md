# MoonSVD

[![CI](https://github.com/TAIminif/MoonSVD/actions/workflows/ci.yml/badge.svg)](https://github.com/TAIminif/MoonSVD/actions/workflows/ci.yml)

MoonSVD 是 MoonBit 实现的 Arm CMSIS-SVD 寄存器描述库和命令行工具。它把厂商设备包中的 SVD 文件展开为可查询的寄存器、位域和地址，用于固件开发、调试工具接入和器件包更新审查。

## 快速运行

安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)及 Node.js 22 或更新版本。在仓库根目录运行以下命令。依赖从 Mooncakes 获取，CLI 无需安装 npm 依赖。

```sh
moon update
moon build --target js --release
node bin/moonsvd.mjs inspect fixtures/timer-v1.svd
node bin/moonsvd.mjs lookup fixtures/timer-v1.svd 'TIMER1.CAPTURE[1]'
node bin/moonsvd.mjs check fixtures/timer-v1.svd
node bin/moonsvd.mjs diff fixtures/timer-v1.svd fixtures/timer-v2.svd
node bin/moonsvd.mjs diff fixtures/status-v1.svd fixtures/status-v2.svd
```

- 查看寄存器。样例查询得到 `TIMER1.CAPTURE[1]`，地址 `0x40000114`，权限为只读。
- 审查版本。版本对比报告两个定时器各自新增的 `EVENTS`，以及 `CTRL` 的复位值和位域变化。
- 检查读写行为。状态寄存器样例的地址和位宽相同，`diff` 仍会报告寄存器读操作的副作用、`PENDING` 的写入行为及 `LEVEL` 的可写范围变化。
- 检查器件包。对 `fixtures/bad-field.svd` 运行 `check`，会定位 `TIMER.CTRL.BAD` 超出寄存器位宽。
- 检查数值范围。对 `fixtures/bad-widths.svd` 运行 `check`，会报告复位掩码、寄存器写入范围及位域写入范围超出位宽，返回退出码 1。

命令输出 JSON。退出码 0 表示查询成功、未发现问题或无差异，1 表示发现问题、差异或查无该寄存器，2 表示调用、IO 或解析错误。地址、复位值和掩码用十六进制字符串输出，位偏移和位宽用十进制字符串输出，以保持 64 位精度。

寄存器及位域的 JSON 包含 `readAction`、`modifiedWriteValues` 和 `writeConstraint`，缺省时用 `null`。`fieldChanges` 按位域名称列出同一个寄存器内的新增、删除及属性变化。整个寄存器新增或删除时，对应的寄存器快照已包含所有位域。

## MoonBit API

可将仓库源码作为 MoonBit 工作区依赖使用。根包导出 `parse` 和 `Device`。接口调用示例见 [examples/inspect](examples/inspect/main.mbt)。

```sh
moon run examples/inspect
```

示例输出 `TIMER.CTRL @ 40000004, EN=1`。

## 支持范围

- 以字节寻址的 CMSIS-SVD XML，解析外设、嵌套寄存器组、寄存器和位域。支持外设／组／寄存器／位域的 `derivedFrom` 引用、`dim` 数组，以及设备到寄存器的属性默认值。
- 设备名称按文本读取，支持含小数点的版本号和 Unicode 名称。数字范围型 `dimIndex` 保留 64 位精度，数组数量限额按元素个数计算。
- 支持三种位域范围写法。提供按路径和起始地址查询、位域提取，以及寄存器地址、位宽、访问权限、复位信息、别名和位域布局的语义比较。
- 寄存器位宽优先取显式声明和继承的 `size`，缺省时使用设备 `width`，支持 1 至 64 位的有效寄存器位宽。兼容 Nordic nrfx 中 `writeonce` 和 `read-writeonce`，输出采用 CMSIS-SVD 的标准拼写。
- 读取并比较寄存器和位域的 `readAction`、`modifiedWriteValues`、`writeConstraint`。写约束支持按读值写入、使用枚举值和数值范围，寄存器约束可作为位域默认值。
- 校验字段越界和重叠、复位值与复位掩码位宽、写约束的取值范围、同一外设内的寄存器重叠及寄存器别名。位域和寄存器按读、写访问分别检查重叠，支持只读与只写或写一次视图共享位置。解析错误包含源行列，校验结果包含来源行和完整路径。
- CLI 读取 UTF-8、最多 16 MiB 的常规文件。库在解析 XML 前禁用 DTD，限制单个标签最多 128 个属性、65,536 个 UTF-16 代码单元，限制 XML 层级和继承链各最多 64 层，并限制展开实例的数量、名称大小和继承合并的工作量。超出限额的输入会得到明确的解析错误。详见[验证说明](docs/verification.md)。
- 当前覆盖寄存器布局和声明的读写行为，枚举值定义、中断说明、外设地址块权限和厂商扩展仍在范围之外。完整 XSD 合规性可用独立工具核查。CLI 的文件宿主是 Node.js，解析、校验、比较和结构化输出均由 MoonBit 完成。

## 测试与来源

```sh
moon check --deny-warn
moon test --deny-warn
moon build --target js --release
python scripts/verify_cli.py
python scripts/verify_cli.py --official
```

默认脚本验证仓库内的原创样例。带 `--official` 时，脚本核对 Arm、STM32、Nordic 和 Raspberry Pi 共六份文件的 SHA-256，用 Python XML 读取结果独立核对选定的寄存器地址、复位值、访问权限及位域。来源、版本及复现细节见 [验证说明](docs/verification.md)。

RP2350 样本中的四个 16 位寄存器继承了 32 位复位掩码。`check` 报告四条 `reset-mask-width` 诊断并返回退出码 1，验证脚本逐项核对这些预期结果。

源代码采用 [Apache-2.0](LICENSE)。项目以 [Open-CMSIS-SVD 规范](https://open-cmsis-pack.github.io/svd-spec/main/index.html)为依据，复用 [Milky2018/xml](https://github.com/moonbit-community/xml-mbt) 作为通用 XML 解析依赖。
