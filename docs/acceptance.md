# MoonSVD 终验自查

以下按本届验收指南的九项要求核对，发布版本为 `0.2.9`。

| 验收项 | 实现与验证证据 |
| --- | --- |
| 1. 主要语言及编译器 | 语义解析、继承和数组展开、校验、查询、比较、JSON 输出均由 MoonBit 实现。已使用 `moonc v0.10.22` 验证，CI 检查最低版本 `0.10.16`。 |
| 2. 公开仓库与提交 | [TAIminif/MoonSVD](https://github.com/TAIminif/MoonSVD) 公开可访问，默认分支为 `main`；[提交历史](https://github.com/TAIminif/MoonSVD/commits/main/)保留功能开发和修复记录。 |
| 3. 源码与核心功能 | 根包按 XML、数值、继承、数组、模型、查询、校验和比较组织；`bridge/` 提供 JS 接口，`bin/` 提供文件宿主。支持范围及限额见 [README](../README.md#支持范围)。 |
| 4. README 与复现 | README 包含目标、工具链最低版本、Git 克隆、构建、CLI 调用、Mooncakes 安装、包引用和输出说明。 |
| 5. 持续集成 | [CI 配置](../.github/workflows/ci.yml)覆盖格式、编译器版本、检查、构建、测试、运行示例、CLI、外部样本及源码打包；运行结果见 [GitHub Actions](https://github.com/TAIminif/MoonSVD/actions/workflows/ci.yml)。 |
| 6. 可运行示例 | `moon run examples/inspect` 输出 `TIMER.CTRL @ 40000004, EN=1`；另有文件查询、错误校验和版本差异样例。 |
| 7. 核心测试 | 47 项核心测试在 wasm-gc、wasm、js、native 四个后端通过，覆盖继承、数组、边界、别名、校验、差异、JSON 和 XML 声明。CLI 脚本独立核对退出码及六份固定哈希厂商样本。 |
| 8. Mooncakes 发布 | [guoqi/moonsvd@0.2.9](https://mooncakes.io/docs/guoqi/moonsvd@0.2.9) 已公开发布，已在独立项目中从注册表安装，并在三个后端运行公开 API。源码地址指向本 GitHub 仓库。 |
| 9. 开源许可证 | 根 [LICENSE](../LICENSE) 为 Apache-2.0。通用 XML 依赖及其传递依赖声明 Apache-2.0；原创样例随项目分发，厂商样本按来源链接和固定哈希获取，仓库不打包重分发这些样本。 |

复现命令、样本许可来源、资源限额与发布验证详见[验证说明](verification.md)。RP2350 原样本包含四处继承的复位掩码超出位宽，脚本逐项核对其预期诊断；不应将这些原文件问题视作零诊断样本。

当前声明范围为寄存器布局、位域元数据与读写行为。完整 XSD 合规性、枚举值定义、中断说明、地址块权限和厂商扩展不在本版本承诺范围内。
