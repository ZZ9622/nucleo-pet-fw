# 新 Mac 烧录指南：Little Wanderer / NUCLEO-F401RE

这份指南用于在另一台 Mac 上下载项目、编译固件并烧录到 NUCLEO-F401RE。
只烧录开发板时不需要安装完整 Xcode、STM32CubeIDE、Arduino IDE 或蓝牙模块。

## 1. 准备硬件

- NUCLEO-F401RE 开发板（确认板上型号）。
- 一根 **Mini-USB / Mini-B 数据线**，连接板上 **CN1 / ST-LINK** 接口；不是 Micro-USB。只能充电的线不行。
- Mac 只有 USB-C 时，准备支持数据传输的转接器或合适的数据线。
- OLED 和四按键可以暂时不接，先确认能识别和烧录开发板。

## 2. 需要下载哪些软件

| 软件 | 用途 | 怎么安装 |
|---|---|---|
| Xcode Command Line Tools | 提供 Git、Make 和 Mac 本机 C 编译器 | `xcode-select --install` |
| Homebrew | 安装下面三个工具 | 从 [brew.sh](https://brew.sh/) 按官方步骤安装 |
| CMake（项目要求 ≥3.20） | 配置编译 | `brew install cmake` |
| Arm GNU 编译器 | 把 C 代码编译成 STM32 固件 | `brew install arm-none-eabi-gcc` |
| OpenOCD | 通过板载 ST-LINK 烧录 | `brew install open-ocd` |

这里 **Homebrew 的软件包名是 `open-ocd`，安装后的命令名是 `openocd`**。
本流程直接使用 OpenOCD，无需另外下载 Windows 的 ST-LINK USB 驱动。
工具来源：[Homebrew 安装说明](https://docs.brew.sh/Installation)、[CMake](https://formulae.brew.sh/formula/cmake)、[Arm 编译器](https://formulae.brew.sh/formula/arm-none-eabi-gcc)、[OpenOCD](https://formulae.brew.sh/formula/open-ocd)。

## 3. 安装工具（只需做一次）

打开 Mac 的“终端”（用 Spotlight 搜索 Terminal / 终端）。下面命令逐段执行；前一步成功再继续。

先输入：

```sh
xcode-select --install
```

按弹窗完成安装，再继续。若提示已经安装，可直接下一步。

打开 [Homebrew 官网](https://brew.sh/)，复制官网提供的安装命令执行。
安装时可能要求输入 Mac 登录密码；终端输入密码时不显示字符是正常现象。
**安装结束后，按终端里 `Next steps` 提示配置 Homebrew 的 PATH，再重新打开终端。**
Apple Silicon 与 Intel Mac 的安装路径可能不同，不要盲目复制另一台电脑的路径。

确认 Homebrew 可用并安装工具：

```sh
brew --version
brew install cmake arm-none-eabi-gcc open-ocd
```

安装完成后逐项检查：

```sh
git --version
make --version
cc --version
cmake --version
arm-none-eabi-gcc --version
arm-none-eabi-objcopy --version
arm-none-eabi-size --version
openocd --version
```

这些命令应显示版本，不应出现 `command not found`。
老版本 macOS 或 Intel Mac 的 Homebrew 支持程度以官方安装说明为准；安装失败时保留完整报错。

## 4. 下载代码

推荐重新从 GitHub 下载，避免把另一台 Mac 的编译缓存一起拷过来：

```sh
mkdir -p ~/Documents/LittleWanderer
cd ~/Documents/LittleWanderer
git clone https://github.com/ZZ9622/nucleo-pet-fw.git
cd nucleo-pet-fw
git rev-parse --short HEAD
```

最后一行显示当前版本号，出问题时可发给项目维护者。
如果仓库变为私有，需要先获得访问权限，不能把账号密码或访问令牌写进命令发给别人。

已有仓库且没有本地改动时，进入原目录更新即可：

```sh
git status --short
git pull --ff-only
```

如果有本地改动或更新失败，先保留改动和报错，不要直接清空文件。

## 5. 先测试、编译，不连接板子也能做

确保终端位于仓库根目录，这里应能看到 `Makefile`、`src`、`include`：

```sh
make test
make build
```

- `make test` 应完成 6 组 Mac 本机测试。
- `make build` 成功后会生成 `build/nucleo-f401re/pet.elf`、`pet.bin`、`pet.hex`。
- 后续 `make flash` 会自动使用本机编译的 `pet.elf`，不用手动选择固件文件。

若复制过别人的整个工程，遇到 `CMakeCache.txt` 路径不匹配，在仓库根目录执行：

```sh
make clean
make build
```

`make clean` 会删除生成的 `build/` 目录；先确认没有把个人文件放在里面。它不删除 `src/` 源码。

## 6. 连接开发板，再烧录

1. 外接线路不确定时先断电并移除面包板、OLED 和按钮，只保留开发板。
2. 保留原厂 CN2 跳帽，不随意改动焊桥。
3. 用数据线连接开发板 **CN1 / ST-LINK** 与 Mac。
4. 如果 macOS 提示是否允许 USB 配件连接，选择允许。
5. 关闭可能占用 ST-LINK 的其他烧录或调试软件。

在仓库根目录输入：

```sh
make probe
```

这是只读检测，不会烧录。输出应识别到 ST-LINK 和 STM32 Cortex-M4 目标，不能以 `Error: open failed` 结束。
**确认连接的是准备烧录的 NUCLEO-F401RE 后**再执行：

```sh
make flash
```

这一步会写入固件、校验并复位开发板，原有运行状态会丢失。
等待终端报告烧录及校验成功、正常退出；过程中不要拔线。

## 7. 验证宠物运行

仅接开发板时，先观察绿色 LD2 启动闪烁。
需要看小猫时，断电后再按下面接线接 OLED，完成后重新上电：

| OLED 丝印 | 开发板 |
|---|---|
| VCC / VDD | 3V3 |
| GND | GND |
| SCL / SCK | PB8 / D15 |
| SDA | PB9 / D14 |

屏幕应为 **SSD1306，128×64，I2C**。按模块丝印接线，不按插针左右顺序猜。
上电后约 2.5 秒棋盘图案，再出现小猫及 Happiness / Energy。

- B1 短按后松开：喂食。
- B1 按住 1.2–5 秒后松开：睡眠 / 唤醒。
- B1 按住至少 5 秒后松开：重置宠物。
- 闲置 30 秒熄屏，首次按键只亮屏，再按才执行动作。

外接四键按 [WIRING_zh.md](../WIRING_zh.md) 接 A0/PA0、A1/PA1、A2/PA4、A3/PB0，各自另一端接 GND。
**A2 不是 PA2；不要把四键接到 A4/A5，以免与 OLED I2C 冲突。**

## 8. 常见问题

| 现象 | 处理顺序 |
|---|---|
| `brew: command not found` | 完成 Homebrew 安装后的 `Next steps`，重新打开终端 |
| `arm-none-eabi-gcc` 或 `openocd` 找不到 | 确认对应包安装成功、终端能显示工具版本 |
| `make: No targets specified and no makefile found` | 终端不在仓库根目录，先 `cd` 到 `nucleo-pet-fw` |
| `make probe` 报 `open failed` | 确认 CN1 → 换数据线 → 换 USB 口/转接器 → 移除外接电路 → 关闭其他调试软件 |
| 能看到 ST-LINK，但无法识别 STM32 | 断电检查 CN2 原厂跳帽及板子连接，不改调试引脚或焊桥，保留完整日志 |
| 灯亮但 Mac 不识别 | 灯亮只能证明供电；打开“系统信息 → USB”检查是否出现 ST-LINK |
| 没有 `/dev/cu.usbmodem*` | 烧录以 `make probe` 为准；串口是后续通信检查，不是唯一的烧录检测方式 |
| 烧录成功但 OLED 不亮 | 先按一次键排除熄屏，再断电检查供电、共地、SCL/SDA 和 SSD1306 型号 |
| OLED 工作但四键异常 | 按 WIRING 指南检查按钮内部常通两组脚与面包板连接 |

需要求助时发：Mac 芯片和 macOS 版本、`git rev-parse --short HEAD`、失败命令及完整终端输出；接线问题另附清晰照片。不要只发最后一行报错。

## 9. 哪些是可选下载

- **仅烧录和运行 OLED 宠物**：上面的命令行工具就够了。
- **运行 iPhone App**：另装兼容 macOS 的完整 Xcode，在 `ios/NucleoPet.xcodeproj` 运行；真机还需设置签名 Team。
- **尝试 USB → Mac → App 真实属性读取**：另需 Python 3（`python3 --version` 检查，没有时 `brew install python`），按 [USB 接入指南](USB_INTEGRATION_zh.md) 启动桥接。脚本不需要额外 pip 包。

烧录成功不代表 App 已连接。当前 USB 接入只读真实属性；召唤和返回仍为模拟，真实迁移尚待实现。
