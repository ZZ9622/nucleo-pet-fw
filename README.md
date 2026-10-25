# Nucleo Pet — STM32 电子宠物

基于 **NUCLEO-F401RE** 和 **SSD1306 OLED** 的电子宠物固件，使用裸机 C 编写。
当前阶段为 **Demo 0.1**：已完成实物连接、固件烧录，并确认在开发板上正常运行。

本 README 记录当前硬件范围、已实现功能和 **macOS** 开发流程。

## 适用范围与接线

| 项目 | 当前配置 |
| --- | --- |
| 开发板 | ST NUCLEO-F401RE（STM32F401RE） |
| 屏幕 | Joy-IT SBC-OLED01，SSD1306，128×64，四针 I²C |
| 操作输入 | 板载蓝色 B1 USER 按键（PC13） |
| 状态指示 | 板载绿色 LD2（PA5） |
| 烧录与调试 | 板载 ST-LINK/V2-1，通过 CN1 USB 接口连接 Mac |
| 开发环境 | macOS、CMake、Arm GNU 编译器、OpenOCD |

当前屏幕驱动按 SSD1306 编写，不适用于 SH1106（如 SBC-OLED01.3）。
其他开发板、屏幕控制器或引脚配置需要调整代码后使用。

### OLED 接线

断电后按模块上的引脚文字连接：

| OLED | NUCLEO-F401RE |
| --- | --- |
| GND | GND |
| VCC / VDD | 3V3 |
| SCL / SCK | PB8，Arduino D15 / SCL |
| SDA | PB9，Arduino D14 / SDA |

驱动固定使用 PB8/PB9，I²C1 速率为 100 kHz，自动依次尝试七位地址 `0x3C`、`0x3D`。
SCL、SDA 需要上拉到 **3.3V**；若模块没有自带上拉，可各接一只约 4.7 kΩ 电阻到 3V3。

使用 **USB-A 转 Mini-B 数据线**连接 Mac 与开发板的 **CN1 / ST-LINK USB**；
Mac 只有 USB-C 接口时，可使用支持数据传输的转接器。
保留 CN2 原厂跳帽，PA13/PA14 留给 SWD 调试，无需另接 USB 转串口模块。

## 当前功能

### 屏幕与动画

- 启动时显示约 2.5 秒棋盘测试图案，随后进入小猫状态界面。
- 小猫支持眨眼、轻微起伏、摆尾；睡眠时闭眼并显示 Z，严重缺乏照顾时闪烁感叹号。
- 顶部显示状态 `CONTENT / HAPPY / NEEDY / HELP / SLEEP` 和等级 `LV`。
- 右侧显示饱食度 `FOOD`、体力 `ENERGY`、心情 `JOY`、清洁度 `CLEAN`、
  健康值 `HEALTH`，数值范围为 0–100，并配有状态条。
- 界面使用内置英文小字体。

### 按键操作

所有操作都在 **松开 B1 后**触发：

| 操作 | 功能 |
| --- | --- |
| 短按，不足 1.2 秒 | 喂食（清醒时有效） |
| 按住至少 1.2 秒、不足 5 秒后松开 | 睡眠 / 唤醒 |
| 按住至少 5 秒后松开 | 重置宠物属性 |

按键已做消抖，极短的触碰会被忽略。屏幕底部的 `2S SLEEP` 是操作提示，
实际睡眠切换阈值为 1.2 秒。

### 宠物状态与 LED

宠物状态每秒推进一次。当前使用加速演示规则 `PET_RULES_DEMO`，
便于短时间观察属性变化；这不是按真实生活节奏设计的长期养成参数。
喂食可改善饱食度、获得经验，达到经验阈值后升级；睡眠可恢复体力，缺乏照顾会使状态变差。

绿色 LD2 同步提供反馈：启动或重置时闪两次，喂食后快闪四次，
日常状态为双脉冲心跳，需要照顾时周期闪烁，严重状态快闪，睡眠时为慢速心跳。

### 当前边界

- 实物按键目前只接入喂食、睡眠 / 唤醒和重置。
- 宠物核心已有玩耍、清洁、用药、小游戏结果奖励等命令逻辑，以及经验、金币和成长阶段数据；
  当前没有对应操作菜单或可玩的小游戏，界面也未展示全部数据。
- 尚未实现存档，断电或开发板复位后会重新初始化宠物。
- 尚未接入声音、传感器或联网功能。

## macOS 开发与烧录

### 1. 安装工具

需要 Xcode Command Line Tools（提供本机 C 编译器、Git 和 Make）。
若尚未安装：

```sh
xcode-select --install
```

安装 [Homebrew](https://brew.sh/) 后，安装项目工具：

```sh
brew install cmake arm-none-eabi-gcc open-ocd
```

项目要求 CMake 3.20 或更高版本，不依赖 STM32CubeIDE 或 HAL。
工具包说明：[CMake](https://formulae.brew.sh/formula/cmake)、
[Arm 编译器](https://formulae.brew.sh/formula/arm-none-eabi-gcc)、
[OpenOCD](https://formulae.brew.sh/formula/open-ocd)。

### 2. 获取项目

```sh
git clone https://github.com/ZZ9622/nucleo-pet-fw.git
cd nucleo-pet-fw
```

已有仓库时，直接进入项目目录即可。

### 3. 测试、编译与烧录

连接 CN1 后，在项目根目录依次运行：

```sh
make test       # 在 Mac 上运行宠物规则和界面绘制测试
make build      # 编译 STM32 固件
make probe      # 检查 ST-LINK 和 STM32 连接，不写入 Flash
make flash      # 写入、校验固件并自动复位
```

确认 `make probe` 成功识别开发板后再执行 `make flash`。
编译产物位于 `build/nucleo-f401re/`，包括 `pet.elf`、`pet.bin` 和 `pet.hex`。
`make test` 和 `make build` 无需连接开发板；本机测试覆盖宠物规则和部分界面绘制行为，
不替代实物验证。

烧录完成后，LD2 应先闪两次，OLED 显示棋盘图案后进入小猫界面；
可通过短按 B1 验证喂食，通过长按后松开验证睡眠 / 唤醒。

## 常见问题

| 现象 | 检查方式 |
| --- | --- |
| 无法识别 ST-LINK | 检查是否使用数据线、是否接在 CN1、转接器是否支持数据传输，以及开发板是否通电 |
| LED 正常但屏幕不亮 | 检查 3V3、共地、SCL/SDA 接线、上拉及焊接；确认屏幕控制器为 SSD1306 |
| 移动项目后 CMake 报路径错误 | 执行 `make clean` 清除生成的 `build/` 目录，再执行 `make build` |
| 安装 OpenOCD 后仍提示未找到 | 确认终端能运行 `openocd --version`，然后执行 `make clean`、`make build` 重新配置 |

屏幕通信出错后，驱动约每秒重试初始化；单次 I²C 事务有超时限制。
若总线卡住，可断电检查接线后重新上电。
调试时可查看 `oled_status`：`0` 等待上电、`1` 无应答或总线故障、
`2` 棋盘测试、`3` 宠物画面。

## 代码结构

| 路径 | 职责 |
| --- | --- |
| `src/main.c` | 主循环、按键命令与各模块调度 |
| `src/pet.c`、`include/pet.h` | 宠物属性、状态变化与命令规则 |
| `src/pet_view.c` | 小猫动画、文字和状态条绘制 |
| `src/display_ssd1306.c` | OLED 初始化、I²C 通信与帧缓冲传输 |
| `src/board.c`、`src/button.c`、`src/led.c` | 板级初始化、按键消抖、LED 状态反馈 |
| `tests/` | 在 Mac 上运行的宠物规则与界面绘制测试 |
| `cmake/`、`linker/`、`openocd/` | 交叉编译、内存布局与烧录配置 |

## 开发记录

- **2026-10-25 · Demo 0.1**：完成 STM32 NUCLEO-F401RE 与 OLED 的初步物理连接，
  完成首代电子宠物 Demo 烧录并确认实物正常运行；实现小猫动画、属性显示、
  喂食、睡眠 / 唤醒、重置及 LED 状态反馈。
