# AutoLoot

[![Build and Release](https://github.com/mmm8091/autoloot/actions/workflows/build.yml/badge.svg)](https://github.com/mmm8091/autoloot/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/mmm8091/autoloot?include_prereleases&sort=semver)](https://github.com/mmm8091/autoloot/releases)

一个基于 AutoHotkey v2 的自动按键脚本：支持多按键、OSD 状态显示、配置持久化，并通过轻微随机化模拟更“像人”的按键节奏。

## 特性

- 多按键管理：同时启用/停用多个按键的自动点击
- 实时调速：按住目标按键时，用 `+/-` 动态调整间隔
- OSD 显示：实时展示运行状态与每个按键的间隔
- 配置持久化：自动写入 `config.ini`，下次启动自动恢复

## 快速开始

你可以选择以下任一方式运行：

1) 直接下载可执行文件（推荐）
- 进入 Releases：`https://github.com/mmm8091/autoloot/releases`
- 下载 `autoloot-v*.exe` 并运行

2) 运行脚本
- 安装 AutoHotkey v2（系统要求见下方）
- 双击运行 `autoloot.ahk`

## 使用说明

### 热键一览

| 操作 | 热键 | 说明 |
| --- | --- | --- |
| 全局暂停/恢复 | `F12` | 暂停时不会执行任何点击 |
| 单键开关 | `Ctrl` + `Alt` + `Shift` + `Key` | 为指定按键开启/关闭自动点击 |
| 调整间隔 | 按住目标按键时，按 `=` / `-` | 每次调整 `±100ms`（`=` 对应键盘上的 `+`） |
| 调整间隔（小键盘） | 按住目标按键时，按 `NumpadAdd` / `NumpadSub` | 同上 |

### 支持的 Key

- 字母键：`A-Z`
- 数字键：`0-9`
- 功能键：`F1-F12`
- 符号键：`[ ] ; ' , . / - =`

## 配置文件

脚本会在同目录下创建 `config.ini`（已加入 `.gitignore`）。格式示例：

```ini
[ActiveKeys]
a=1000
f1=250
```

- key 为小写（脚本内部会统一转换）
- value 为间隔毫秒（ms）

## 构建与发布（开发者）

- 推送 `v*` tag 会触发 GitHub Actions 自动构建并创建 Release（含 `.exe` 与 `.sha256`）。
- `workflow_dispatch` 支持手动构建并上传 artifact。

工作流配置见：`.github/workflows/build.yml`。

## 系统要求

- Windows 10/11（GitHub Actions 构建目标为 Windows）
- 运行脚本需要 AutoHotkey v2.0+

## 免责声明

本项目仅用于学习与自动化演示。请遵守目标软件/游戏的用户协议与当地法律法规；因使用本项目产生的任何后果由使用者自行承担。

## 许可证

MIT License
