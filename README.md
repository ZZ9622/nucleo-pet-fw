# NUCLEO-F401RE electronic pet — firmware bring-up

This is a small, bare-metal C firmware starter for an ST **NUCLEO-F401RE**. Its
first job is to prove the complete build → ST-LINK → Flash → run path with an
SSD1306 screen. The second job is to establish a pet core that will not need rewriting
when a display, storage, sound, sensors, or minigames arrive.

## First milestone

The firmware uses only the board hardware already present:

- **LD2 / PA5** is the green status LED; high means on.
- **B1 / PC13** is the user button; it is active-low.
- The board's **ST-LINK/V2-1** is the programmer/debugger.

The initial pet behavior is deliberately visible in under a minute:

| What you do | What the pet does | LED evidence |
| --- | --- | --- |
| Power / reset | Starts its firmware | Two quick boot flashes |
| Wait normally | Needs slowly decay in demo time | Two-pulse heartbeat |
| Short press B1 | Feed / care | Four quick happy flashes |
| Hold B1 for 1.2–5 s, then release | Sleep or wake | Slow sleep heartbeat / normal status |
| No feeding for 24 hours | Collapses and needs feeding | Fast flashing |
| Feed after collapse | Recovers and starts a fresh 24-hour window | Happy flashes |
| Hold B1 for 5 s or more, then release | Reset the pet | Boot flashes, default attributes restored |

All LED patterns and button handling are non-blocking. There is no `delay()` in
the pet logic, so future display animations and minigames can run alongside it.

## Cable and board connection

Your **USB-A to Mini-B data cable** is the correct cable. Connect it from the
Mac (or a USB-C-to-A data adapter) to the Nucleo connector labelled **CN1 /
ST-LINK USB**. It carries power, SWD programming, and debugging through the
onboard ST-LINK; do not use a USB-to-TTL converter for this normal path.

Leave the factory CN2 jumpers fitted and leave `PA13`/`PA14` free: they are the
SWD debug pins. The board has to be a real NUCLEO-F401RE board for the PA5/PC13
mapping in this project to apply.

## Build and test on macOS

This project needs the ARM compiler and OpenOCD once:

```sh
brew install arm-none-eabi-gcc open-ocd
```

Then, from this directory:

```sh
make test       # Runs the pure pet-logic tests on the Mac
make probe      # Read-only: looks for the board through ST-LINK
make build      # Produces build/nucleo-f401re/pet.elf, .bin, and .hex
make flash      # Writes, verifies, and resets the STM32 through ST-LINK
```

## Windows 烧录与运行

推荐使用 **MSYS2 UCRT64** 终端，而不是直接在 PowerShell 或 `cmd` 中运行本项目的
`Makefile`：项目会使用 `make`、`mkdir -p` 和 `rm` 等 Unix 风格命令。

1. 安装 [MSYS2](https://www.msys2.org/)，按其安装器提示完成首次更新后，打开
   **MSYS2 UCRT64** 终端。
2. 在该终端中安装所需工具：

   ```sh
   pacman -Syu
   pacman -S --needed make mingw-w64-ucrt-x86_64-cmake \
     mingw-w64-ucrt-x86_64-arm-none-eabi-toolchain \
     mingw-w64-ucrt-x86_64-openocd
   ```

   这些包提供 CMake、Arm 交叉编译器和 OpenOCD。MSYS2 目前提供
   `mingw-w64-ucrt-x86_64-arm-none-eabi-toolchain` 与
   `mingw-w64-ucrt-x86_64-openocd`；也可改用官方
   [Arm GNU Toolchain](https://developer.arm.com/Tools%20and%20Software/GNU%20Toolchain)
   和 Windows 版 OpenOCD，但必须让它们的 `bin` 目录位于 `PATH` 中。
3. 克隆本仓库并进入目录：

   ```sh
   git clone https://github.com/ZZ9622/nucleo-pet-fw.git
   cd nucleo-pet-fw
   ```

4. 用 USB-A 转 Mini-B **数据线**连接电脑和开发板的 **CN1 / ST-LINK USB**，然后依次运行：

   ```sh
   make probe      # 只检测 ST-LINK 与 STM32，不写入 Flash
   make build      # 生成 build/nucleo-f401re/pet.hex
   make flash      # 写入、校验并复位开发板
   ```

   `make probe` 不能识别板子时，不要执行 `make flash`；先检查线缆是否为数据线、是否连接
   CN1、Windows 的设备管理器是否显示 ST-LINK，以及重插 USB 后再试。

### Windows 图形界面烧录（不使用 OpenOCD）

若已通过 `make build` 得到 `build/nucleo-f401re/pet.hex`，也可以安装 ST 官方的
[STM32CubeProgrammer](https://www.st.com/content/st_com/en/stm32cubeprogrammer.html)。连接
CN1 后，在程序中选择 **ST-LINK**、点击 **Connect**、打开 `pet.hex`，再执行 **Download**。
下载完成后复位开发板；绿色 LD2 先快速闪两次，再进入双脉冲心跳，即表示电子宠物正在运行。

## 首次烧录与运行（NUCLEO-F401RE）

1. 用 **USB-A 转 Mini-B 数据线**把电脑连接到开发板的 **CN1 / ST-LINK USB** 接口。
   不要接 USB 转串口模块；本项目通过板载 ST-LINK 烧录。
2. 在本项目目录执行 `make probe`。只有它能识别到 ST-LINK 后，才继续下一步。
3. 执行 `make build` 编译固件；生成的烧录文件位于
   `build/nucleo-f401re/pet.hex`。
4. 执行 `make flash`。该命令会写入、校验固件并自动复位开发板。
5. 复位后，板载绿色 **LD2** 会快速闪两次，随后开始双脉冲心跳，表示电子宠物正在运行。
   本版加入了 SBC-OLED01 屏幕，LED 仍保留状态提示：短按 B1 是喂养/照顾，长按约 1.2 秒后松开可睡眠或唤醒。

如果 `make probe` 显示无法打开 ST-LINK，请依次检查：线缆是否为数据线、是否接在 CN1、开发板是否通电，以及重新插拔 USB 后再试。

`make flash` deliberately performs a write, so run `make probe` first and make
sure the cable is attached to the correct board. A successful flash resets the
board automatically; LD2 should show the boot flashes.

The project is intentionally register-level and does not require HAL, CubeIDE,
newlib, `printf`, or dynamic allocation. That keeps the first flashing program
small and reproducible. It is still ordinary C and can later be imported into a
CubeIDE or VS Code workflow if wanted.

## Growth-friendly design

```text
button / future touch UI → semantic PetCommand → pet core → PetSnapshot
minigame result ──────────────────────────────────────────┘       ├─ LED today
                                                                    └─ screen later
```

`src/pet.c` owns the persistent game rules: happiness, energy, level, XP, coins, life stage, and sleep. It knows nothing about LEDs,
GPIO, display pixels, or a particular minigame.

Future games submit a score through `PET_CMD_SUBMIT_GAME_RESULT`; the pet core
decides XP, coins, happiness, and energy changes. This prevents each game from
silently changing the pet balance or storage format.

`src/display_ssd1306.c` implements the `display.h` interface for SBC-OLED01.
`src/display_null.c` remains available as the original no-screen backend; it is
not compiled alongside the OLED backend. The core now uses only Happiness and Energy for needs.

### Pin planning for a future screen

PA5 is also Arduino D13 / `SPI1_SCK`. A common SPI display on SPI1 will make
LD2 flicker, so it is not a good permanent combination. An I2C OLED on PB8/PB9
or an SPI display using SPI2 are better options if the board LED remains useful
for diagnostics.

For persistent saves, do not write a raw C struct to Flash every second. Add a
versioned, checksummed save record and only save on meaningful events, or use
external EEPROM/FRAM later.


## SBC-OLED01 屏幕初始化与测试

本版适用于 Joy-IT **SBC-OLED01，SSD1306，128×64，四针 I2C**，
不是 SBC-OLED01.3 的 SH1106。厂家资料：
https://www.joy-it.net/en/products/SBC-OLED01

断开供电后，按模块针脚上的文字接线，不要仅按左右顺序判断：

| OLED | NUCLEO-F401RE |
| --- | --- |
| VCC / VDD | 3V3 |
| GND | GND |
| SCL / SCK | PB8，Arduino D15 / SCL |
| SDA | PB9，Arduino D14 / SDA |

驱动固定使用上述引脚；如果目前接在别处，请改接。保持 PA5（LED）、PC13（B1）、
PA13/PA14（SWD）原接法。I2C 信号必须有上拉至 **3.3V** 的电阻；先检查模块是否
已有上拉，如果没有，可给 SCL、SDA 各接一只约 4.7kΩ 电阻到 3V3。不要上拉到 5V。

驱动保持原有 16MHz HSI 时钟，在 PB8/PB9 上配置 AF4、开漏、I2C1 100kHz。
如以后修改 APB1 时钟，必须同步修改驱动中的 CR2、CCR、TRISE。
自动依次尝试七位地址 0x3C 和 0x3D；发送时才左移一位。

```sh
cd ~/Desktop/learning/nucleo-pet-fw
make test
make build
make probe
make flash
```

`make flash` 会写入并校验 Flash，再自动复位。若已有旧的构建目录因搬迁路径导致
CMake 报错，可使用独立目录重新配置及烧录：

```sh
cmake -S . -B build/oled -G "Unix Makefiles" -DCMAKE_TOOLCHAIN_FILE=cmake/arm-none-eabi-gcc.cmake
cmake --build build/oled
openocd -f openocd/nucleo-f401re.cfg -c "init; targets; shutdown"
cmake --build build/oled --target flash
```

烧录文件：默认是 `build/nucleo-f401re/pet.hex`；独立目录是 `build/oled/pet.hex`。

预期效果：上电约 100ms 后初始化屏幕，先显示棋盘测试图案，约 2.5 秒后
切换成小猫状态界面。顶部两行显示 HAPPINESS / ENERGY（000–100）与状态条；
中央小猫眨眼、起伏、摆尾，睡眠闭眼显示 Z；侧边显示短反馈。
Feed / Pet / Play / Wake 后显示 YUMMY / LOVE YOU / THAT WAS FUN / GOOD MORNING，
约 2.5 秒后恢复状态文本；睡眠期间显示 SLEEP。

外接四键操作与接线见 [四按键接线指南](WIRING_zh.md)。不接新按键也可运行，
B1 原有短按喂食、1.2–5 秒松开睡眠/唤醒、至少 5 秒松开重置仍有效。

显示使用 1024 字节帧缓冲，每帧固定同一份状态和动画时间，避免上下部分动作不同步。
每 5ms 调度一次，每次传输 32 字节，100kHz 下正常约 3–4ms，一帧约 0.16 秒。
依然按页顺序写屏，无硬件双缓冲，可能存在轻微扫描感。
每个 I2C 事务最多等待 20ms，错误后约一秒重试初始化，不无限等待。
显示传输采用短轮询，并非完全异步；缺屏或接线错误不会阻止宠物循环运行。
调试器可查看 `oled_status`：0=等待上电，1=无应答/总线故障，2=测试图案，3=宠物画面。
若屏幕仍黑，先检查共地、3V3、电源针脚和 PB8/PB9；然后检查上拉和焊接。
总线物理卡死时可能需要断电检查接线后重新上电；本版不发送 GPIO 总线恢复脉冲。

本次可在电脑验证编译和宠物核心测试；屏幕亮度、应答地址及接线必须在实物上确认。


### 动画版本验证

`make test` 同时运行宠物规则测试和界面绘制测试（眨眼/睡眠画面变化、
绘制缓冲区边界与数值极限）。已通过交叉编译和电脑端测试，并检查了三种状态的
128×64 像素预览。动画版本仍需在实物上确认刷新效果与按键响应。

## 双属性与每日喂食

Happiness 初始 75、Energy 初始 80，范围 0–100；`is_sleeping` 独立。
清醒累计每小时两值各减 1；睡眠累计每分钟 Energy 加 1，Happiness 不减。
两种时间累计独立保留，反复切换睡眠不会跳过衰减。
Feed 增加 Energy 30，Pet 增加 Happiness 10，Play 增加 Happiness 20、消耗 Energy 12。
常规睡眠中忽略 Feed/Pet/Play，须先唤醒。

从开机或最近一次有效喂食起连续 24 小时未喂食，进入瘫软状态，Energy 归零，
猫猫趴在地上轻微呼吸，侧边 FEED ME；瘫软后暂停属性增减直至救助。此判定独立于心情与精力，睡眠也不能替代喂食。
瘫软期间仅喂食或重置有效；喂食可直接救助（即使此前正在睡眠），清除瘫软并唤醒，
Energy 恢复到 30，重开滚动 24 小时窗口。不加入死亡或不可逆惩罚。
屏幕熄灭时继续计时；首次按键仍只唤醒屏幕，再次按 Feed 才喂食。
等级、经验、金币、小游戏结果接口保留，但游戏奖励不重置喂食计时。

当前按持续通电运行时间计算，未实现 RTC/断电存档；断电、复位或 B1 重置会重新开始。
真正跨断电的每日照顾需要后续增加存档与可信实时时钟。
规则配置在 `PET_RULES_DEFAULT`；期限在 `PET_FEED_DEADLINE_S`，正式固件为 86400 秒。
测试以模拟时间推进，无需实际等待一天，也不缩短正式固件期限。

### 方块猫外观

猫猫改为参考图的实心像素轮廓：方耳、阶梯形脸颊、平底下巴，眼睛与嘴巴镂空。
单色 OLED 使用亮色身体与黑色五官，无法显示参考图中的蓝色。
HAPPY 为弯眼笑脸；CONTENT 为方眼小嘴；NEEDY 为方眼下弯嘴；
HELP 为疲惫眼睛、下弯嘴与闪烁感叹号；SLEEP 为闭眼细嘴与飘动 Z。
保留眨眼及一像素起伏，四键、属性和显示驱动不变。

## 闲置熄屏与按键唤醒

30 秒没有按钮活动后，OLED 发送 SSD1306 `0xAE` 关闭显示，并暂停像素刷新。
宠物计时、Happiness/Energy、睡眠恢复及 LED 仍运行；这不是断电，也不是 MCU STOP 模式。
四个外接按钮与板载 B1 均可在按下稳定约 25ms 后唤醒。
首次按键仅唤醒，直到所有键松开前均忽略动作（包括 B1 长按重置）；再按才执行原功能。
按住按钮不会熄屏，松开后重新计时。熄屏不改变宠物的 `is_sleeping`。
唤醒时先在暗屏中写入完整最新画面，再发送 `0xAF`，正常约 0.16 秒，避免旧画面闪现。
上电棋盘测试保留，正常闲置唤醒不重播测试图；I2C 故障重连仍保留原初始化测试。
屏幕失联时沿用超时与每秒重试；重连后服从当前熄屏请求。
等待时间可修改 `include/screen_idle.h` 中的 `SCREEN_IDLE_TIMEOUT_MS`。
调试状态 `oled_status=4` 表示闲置熄屏。

板上验收：烧录后等待 30 秒确认熄屏；任意按钮按下确认亮屏且无喂食/睡眠/重置；
松开后再按确认动作；睡眠中熄屏、唤醒屏幕后仍应是睡眠。
主机测试覆盖超时边界、计时溢出、按住不熄屏与唤醒按键吞掉动作；仍需在实物确认显示命令与时序。

## 五种基础动画

保留参考方块猫造型，`pet_animation_sample` 仅采样画面，不修改属性或游戏随机数。
- Blink：每 6 秒窗口中伪随机选一个时刻闭眼约 220ms；走动时也可眨眼。
- Walk：偶尔左右走动最多 7 像素，交替抬脚后回到中心，精力 >35 才出现。
- Happy Jump：心情 >=75、精力 >=60 时更容易随机跳跃；有效 Play 后立即播放一次约 1.2 秒跳跃。
- Yawn：精力 <=35 时周期性打哈欠，精力 <=10 时优先连续打哈欠。
- Sleeping：闭眼、小幅呼吸起伏、飘动 Z；用户可主动睡眠。

精力 <=10 连续约 3 秒自动进入睡眠，睡眠键可唤醒；若精力仍低，约 3 秒后会再次入睡，
可在此期间喂食恢复。24 小时未喂食的瘫软状态优先于睡眠，只有喂食才能救助。
动画在屏幕中央范围绘制，不遮挡指标与侧边反馈。动画本身不增减属性，睡眠状态仍按规则恢复精力。
伪随机动画采用稳定的时间散列，同一开机时间序列可复现；没有依赖硬件真随机数。
电脑端动画测试覆盖边界、双向走动、Play 跳跃、打哈欠/睡眠/瘫软优先级、自动睡眠与救助。

### 侧边反馈布局

删除底部状态栏与全宽分隔线，反馈放在宠物左侧 x=2..28，多词反馈分两行显示。
宠物活动区域向下延伸 6 像素，瘫软的地面线移到 y=61；顶部两行指标保持不变。
走动时猫猫与左侧文字保持间距，睡眠 Z 和低状态感叹号仍位于右侧。
