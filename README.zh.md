# OpenJoystickDriver

[English](README.md) | 简体中文

[![GitHub 仓库星标数](https://img.shields.io/github/stars/xsyetopz/OpenJoystickDriver?style=social)](https://github.com/xsyetopz/OpenJoystickDriver/stargazers)
[![许可证](https://img.shields.io/github/license/xsyetopz/OpenJoystickDriver)](LICENSE)
[![Swift](https://img.shields.io/badge/Swift-Package-orange)](Package.swift)
[![macOS](https://img.shields.io/badge/platform-macOS-lightgrey)](README.md)

OpenJoystickDriver 是一个 macOS 用户空间游戏手柄驱动程序。其签名 app bundle 承载控制器运行时。同一个可执行文件还提供底层 CLI，用于设置、控制和诊断。

如果控制器能在 OpenJoystickDriver 中工作，但无法在游戏、模拟器、SDL app 或原生 macOS app 中使用，请使用它。

<p>
  <a href="#quickstart">快速开始</a> ·
  <a href="#install-update-or-remove">安装 / 移除</a> ·
  <a href="docs/user/compatibility.md">兼容性</a> ·
  <a href="#choose-a-compatibility-identity">选择兼容性身份</a> ·
  <a href="#troubleshooting">故障排查</a> ·
  <a href="CONTRIBUTING.md">参与贡献</a> ·
  <a href="https://github.com/xsyetopz/OpenJoystickDriver/stargazers">加星</a>
</p>

## 为什么选择 OpenJoystickDriver

OpenJoystickDriver 会把物理控制器输入规范化为 app 能理解的虚拟控制器输出。它为 SDL、Apple GameController、Generic HID 和实验性的 Xbox HID 目标提供兼容模式，并把常用诊断和检查整合到由本仓库控制的一套工作流中。

## 状态

当前后端、输出模式和设备支持状态请参阅 [docs/user/compatibility.md](docs/user/compatibility.md)。

兼容模式不需要 DriverKit。生成的 SwifterKit system extension 是一个由供应商定义的完整性 relay，用于自检和诊断。它有意不发布第二个面向用户的游戏手柄。自检会读取已签名 host entitlement。对于拥有 entitlement 的 host，必须完成 relay delivery；缺少 entitlement 时，它会被报告为可选且无法得出结论。

## 快速开始

1. 将 `OpenJoystickDriver.app` 拖到 `/Applications`。
2. 打开 `OpenJoystickDriver.app`。
3. 此 app 特意不提供可见 UI。请使用下方已安装 bundle 中的命令启动并检查它。
4. macOS 提示时，为 OpenJoystickDriver 授予 **输入监控** 和 **辅助功能** 权限。
5. 连接受支持的控制器。
6. 从 CLI 运行 `controller state` 或 `controller watch`，确认按键和摇杆输入。

现在，目标 app 应该能看到一个兼容的虚拟控制器。

## 安装、更新或移除

OpenJoystickDriver 在 `/Applications` 中只有一个 app bundle：

```bash
/Applications/OpenJoystickDriver.app
```

主应用程序的可执行文件也承载进程内运行时。没有嵌套的辅助应用程序，也没有第二个隐私身份。

请使用已安装的可执行文件进行设置和诊断：

| 操作 | 命令 |
| --- | --- |
| 检查服务状态 | `/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless status` |
| 禁用登录时打开 | `/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless app login disable` |

要彻底卸载 OpenJoystickDriver：

1. 使用以下命令禁用登录项：

   ```bash
   /Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless app login disable
   ```

2. 退出 OpenJoystickDriver。
3. 删除 `/Applications/OpenJoystickDriver.app`。
4. 可选：在系统设置的 **输入监控** 和 **辅助功能** 中移除 OpenJoystickDriver。

## 选择兼容性身份

| 你要运行的内容 | 推荐选项 | 原因 |
| --- | --- | --- |
| 大多数游戏、Steam、模拟器、SDL app | Compatibility + `SDL 2/3` | 提供稳定的 app 侧身份和映射。 |
| 使用 `GCController` 的原生 macOS app | Compatibility + `Apple GameController` | 面向 GameController.framework 使用方。 |
| 检查 HID descriptor 的 app | Compatibility + `Generic HID` | 提供由 descriptor 驱动的 HID 接口。 |
| 需要 Microsoft HID 的挑剔 app | Compatibility + `Xbox 360 HID` 或 `Xbox One HID` | 用于定向测试的实验性伪装身份。 |

使用已安装 app bundle 时，对应的 CLI 命令如下：

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless compat set sdl2-3
```

## 故障排查

| 症状 | 处理方法 |
| --- | --- |
| 运行时已断开连接 | 启动已安装的 app，然后检查 `--headless status`。 |
| SDL 看到 0 个控制器 | 确保已授予输入监控和辅助功能权限，然后重启 host 并重新测试。 |
| DriverKit relay 安装失败 | 兼容性输出仍可工作。`--headless test` 会测试 Compatibility；当签名 host 没有 relay 访问权限时，会将 relay 诊断报告为可选。 |

实用诊断命令：

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd test parsers-macos14
./scripts/ojd diagnose backends --seconds 5
./scripts/ojd diagnose gamecontroller --seconds 5
./.build/debug/OpenJoystickDriver --headless diagnose catalog --json
./.build/debug/OpenJoystickDriver --headless diagnose runtime --seconds 300 --json
./.build/debug/OpenJoystickDriver --headless controller state --json
./.build/debug/OpenJoystickDriver --headless controller watch --seconds 10 --interval-ms 16
./.build/debug/OpenJoystickDriver --headless controller packets --limit 50
./.build/debug/OpenJoystickDriver --headless app logs show --stream both --lines 100
./.build/debug/OpenJoystickDriver --headless update check
./scripts/ojd diagnose sdl3 --seconds 10
```

连接相同型号的控制器时，请运行 `controller output list`，并把它的不透明 selector 作为 `--device <id>` 传给 `input` 或 `controller output`。这样会定位到 Input 诊断所使用的同一个运行时设备身份，而不是随意选择 VID/PID 匹配的设备。

关于 soak verdict、high-water limit 和 foreground-consumer polling leak regression probe，请参阅 [应用服务运行时健康状态](docs/development/application-service-health.md)。
关于有界系统工具执行和关闭保证，请参阅 [应用响应能力](docs/development/application-responsiveness.md)。
关于共享运行时边界，请参阅 [CLI 和应用程序运行时](docs/development/cli-and-runtime.md)。

已安装 app bundle 中的命令：

```bash
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless status
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless controller list
/Applications/OpenJoystickDriver.app/Contents/MacOS/OpenJoystickDriver --headless diagnose report
```

## 开发

修改 parser、record 和测试不需要签名：

```bash
brew install libusb
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd test parsers-macos14
./scripts/ojd check driverkit
swift build
```

涉及应用程序、生成的 DriverKit relay、签名和 notarization 的工作，请从这里开始：

- [签名资源和 Apple Developer portal 设置](docs/development/signing.md)
- [scripts/README.md](scripts/README.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [docs/development/architecture.md](docs/development/architecture.md)

## 参与贡献

适合贡献的方向：

- 改进控制器 parser 和 record
- 兼容层测试和诊断
- 受支持设备、兼容性身份和故障排查文档
- 针对游戏、模拟器、SDL app 和原生 macOS app 的可复现报告

提交涉及 parser/record 的 PR 前，请运行：

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd test parsers-macos14
swift build
```

仓库要求请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。

## AI 和编码代理

编辑前请阅读这些文件：

1. [README.md](README.md) -- 产品意图和用户工作流。
2. [scripts/README.md](scripts/README.md) -- 仓库命令接口。
3. [CONTRIBUTING.md](CONTRIBUTING.md) -- PR 要求。
4. [docs/development/architecture.md](docs/development/architecture.md) -- 应用程序、DriverKit 和兼容性边界。
5. [docs/user/compatibility.md](docs/user/compatibility.md) -- 支持状态和输出模式行为。

修改 parser/record 时的最低检查要求：

```bash
./scripts/ojd catalog regenerate --check
./scripts/ojd check profiles
./scripts/ojd test parsers-macos14
swift build
```

## Star 历史

<a href="https://www.star-history.com/?repos=xsyetopz%2FOpenJoystickDriver&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&legend=top-left" />
   <img alt="Star 历史图表" src="https://api.star-history.com/chart?repos=xsyetopz/OpenJoystickDriver&type=date&legend=top-left" />
 </picture>
</a>

## 许可证

[MIT](LICENSE)
