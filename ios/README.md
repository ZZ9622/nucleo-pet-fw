# 方方的小屋 · Nucleo Pet iOS

原生 iPhone App 原型，使用 **SwiftUI + Swift + 共享 C 宠物核心**，最低部署版本 iOS 17。
产品概念是同一只宠物在随身挂件与手机小屋之间往返，带着相同的身份、心情、精力和睡眠状态。

已实现 USB＋Mac 桥接的真实手动往返。连接“真实挂件”后，小屋使用板上的稳定身份与完整状态；未连接时保留离线体验。
运行、恢复和限制见 [USB 双向接入指南](../docs/USB_INTEGRATION_zh.md)。

## 界面与启动流程

采用蓝白像素界面、阶梯边框、方形按钮及原固件像素小猫。
每次启动先进入连接设置，填写 Mac 的 `.local` 地址和桥接口令；读取并验证真实设备记录成功后，自动进入主页。连接失败会保留在连接页。
“挂件 → 连接设置”可重新打开连接页。已保存的真实宠物记录不会因为进入设置而清空。

Debug 开发版提供“无硬件开发预览”，可在没有板子时使用独立体验存档；此入口不修改真实挂件存档，Release 版不显示。它是明确的预览入口，不代表真实连接成功。

本轮验证：iPhone 模拟器构建及 4 项界面测试通过（启动连接页、失败时停留、开发预览、往返互动及重开恢复）；17 项领域测试通过。板子已不在本机，本轮未重新进行实物连接验收。

## 在 Mac 上开发

使用 **Xcode** 打开本目录下的 **`NucleoPet.xcodeproj`**。
这是 App 工程入口；`Package.swift` 用于共享代码和测试，不是 iPhone App 的运行入口。

1. 安装与你的 macOS 兼容的 Xcode，首次启动时完成组件安装。
2. 在 Xcode 的 **Settings → Components** 中安装 iOS 平台和一个 iPhone 模拟器运行时。
   部分旧版 Xcode 将对应页面称为 Platforms。
3. 打开 `NucleoPet.xcodeproj`，顶部 Scheme 选择 **NucleoPet**。
4. 运行目标选择一个已安装的 **iPhone 模拟器**，按 **⌘R**。
5. 若使用真实 iPhone，在 Target → Signing & Capabilities 中选择你自己的 Team；
   按需要修改 Bundle Identifier，连接手机并完成开发信任与签名设置。

参考：[Apple Xcode 系统要求](https://developer.apple.com/xcode/system-requirements/)、
[安装 Xcode 组件](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)。

### 本机环境记录（2026-11-01）

- 当前为 macOS 26.5.1、Xcode 27.2；旧版 Xcode 16.0 的启动兼容问题已解决。
- 已安装可用的 iOS 27.2 模拟器运行时（24B8117），使用 iPhone 17 验证。
- 已在新版 Xcode 中打开本工程，iPhone 目标构建通过。
- 命令行的 active developer directory 仍指向 Command Line Tools。
  下方命令用临时 `DEVELOPER_DIR` 指定 Xcode，不修改电脑的全局开发工具设置。

## 已实现的原型内容

- **小屋**：房间场景、原固件方块猫、心情和精力、摸摸和玩耍；右上角叶子菜单提供喂食和睡眠／唤醒。
- **足迹**：初次相遇、互动和往返记录。
- **挂件**：模拟设备、宠物所在位置、体验编号、真实连接说明。
- **往返**：接到手机、送回挂件、旅途动画、模拟中断、继续或撤销模拟旅程。
- **本地保存**：原子写入；保留宠物身份、完整核心状态、位置、待完成旅程和记录。
  无法读取的旧文件会保留，需主动选择备份后重建。
- **单一活动位置**：宠物在挂件时不能在手机照顾；交接未完成时禁止互动。

体验路径：**小屋 → 接方方来小屋 → 出发吧 → 去小屋看看 → 摸摸／玩耍 → 送它回随身挂件**。
可在挂件页开启“下次传送时模拟中断”，验证中断恢复。

本版不包含真实蓝牙配对、云端、账号、语音对话或后台自动跨设备迁移。
真实往返由独立的 PhysicalSession 管理，使用双端持久化与确认；体验模拟交接仅用于离线演示。

## 与固件保持一致

共享 C 文件来自本仓库，与固件源码同步：

- `src/pet.c`、`include/pet.h`
- `src/pet_animation.c`、`include/pet_animation.h`
- `src/pet_view.c`、`include/pet_view.h`

这六个文件保存在 `Sources/CPetCore/`，与当前仓库保持一致；本次新增离开/交接显示标记，养成规则保持不变。
手机场景中的猫由原 128×64 像素缓冲裁切放大绘制，而不是重新画的一种猫。

沿用当前固件规则：初始心情 75、精力 80；清醒每小时各减 1；睡眠每分钟恢复 1 精力。
喂食 +30 精力，摸摸 +10 心情，玩耍 +20 心情、−12 精力。
精力不高于 10 持续约 3 秒会入睡；睡眠时普通照顾无效。
连续 24 小时未喂食会瘫软，喂食可救助并唤醒。
当前固件未实现互动冷却或低精力拒绝玩耍，本 App 也没有擅自增加。

App 的离线计时使用本机时间，在启动和回到前台时补算。真实固件当前只按持续通电时间计时，
板端已有 Flash 检查点存档；断电期间不计时。交接期间暂停计时，手机拥有时按手机经过时间推进。
迁移规则与后续实物接入要求见 [HANDOFF.md](docs/HANDOFF.md)。

## 目录

| 路径 | 用途 |
| --- | --- |
| `NucleoPet.xcodeproj` | Xcode iPhone App 工程 |
| `App/` | SwiftUI 页面、像素场景与 App 状态管理 |
| `Sources/CPetCore/` | 固定版本的原固件 C 逻辑和绘制 |
| `Sources/PetDomain/` | 完整状态映射、迁移状态机、存档 |
| `Tests/PetDomainTests/` | 规则兼容、迁移与存档测试 |
| `UITests/` | iPhone 模拟器上的往返、互动、中断恢复和照顾菜单测试 |
| `tools/generate_project.py` | 重新生成 Xcode 工程和代码绘制的图标 |

## 验证与开发命令

在本目录运行：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --scratch-path build/package
```

iPhone 工程构建（需要可用的 iOS 平台组件）：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project NucleoPet.xcodeproj -scheme NucleoPet \
  -destination 'generic/platform=iOS' -derivedDataPath build/ios \
  CODE_SIGNING_ALLOWED=NO build
```

模拟器界面测试，也可以在 Xcode 中按 **⌘U**：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project NucleoPet.xcodeproj -scheme NucleoPet \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath build/simulator -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

界面测试使用独立的体验存档，不覆盖正常 App 的记录；测试期间暂停循环动画以便稳定操作。
这些测试开关仅在 Debug 构建中启用。

另有一个在 Mac 上编译相同 SwiftUI 页面的辅助预览：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift run --scratch-path build/package PetPreview
```

Mac 辅助预览不等于 iPhone 真机或模拟器验收。

### 当前验证状态

- 14 项本机测试已通过：属性规则、睡眠、24 小时瘫软救助、自动入睡、往返完整状态、
  重复交接、错误回执、交接中禁止互动、存档后恢复旅程、取消模拟旅程、时钟回拨、
  位置限制、损坏文件备份、原像素绘制。
- SwiftUI 页面和共享核心已通过 Mac 与 iPhone 目标编译；Xcode 工程文件语法检查通过。
- iPhone 17 / iOS 27.2 上 3 项界面自动化测试全部通过：完整往返及属性保留、
  中断后重开 App 并继续旅程、睡眠／唤醒和喂食菜单。
- 已检查真实模拟器截图，并修正首页互动按钮首屏布局、返回按钮的触摸区域和往返目的地提示。
- 尚未进行真实手机和真实挂件联调；这仍是离线体验版。
- 本目录为仓库中的 iPhone App 源码，固件在仓库根目录，均可随仓库一起下载。

### 模拟器截图

- [挂件中的方方](docs/screenshots/01-device-residence.png)
- [手机小屋与互动](docs/screenshots/02-phone-room.png)
- [一起走过的足迹](docs/screenshots/03-journal.png)
- [旅途中断](docs/screenshots/04-interrupted-trip.png)
- [重开 App 后继续到达](docs/screenshots/05-resumed-trip.png)
