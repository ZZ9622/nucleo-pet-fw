# NUCLEO-F401RE electronic pet — firmware bring-up

This is a small, bare-metal C firmware starter for an ST **NUCLEO-F401RE**. Its
first job is to prove the complete build → ST-LINK → Flash → run path without a
screen. The second job is to establish a pet core that will not need rewriting
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
| Wait about 6 s without care | Becomes needy | 250 ms on, 750 ms off |
| Wait longer | Becomes critical | Fast flashing |
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

## 首次烧录与运行（NUCLEO-F401RE）

1. 用 **USB-A 转 Mini-B 数据线**把电脑连接到开发板的 **CN1 / ST-LINK USB** 接口。
   不要接 USB 转串口模块；本项目通过板载 ST-LINK 烧录。
2. 在本项目目录执行 `make probe`。只有它能识别到 ST-LINK 后，才继续下一步。
3. 执行 `make build` 编译固件；生成的烧录文件位于
   `build/nucleo-f401re/pet.hex`。
4. 执行 `make flash`。该命令会写入、校验固件并自动复位开发板。
5. 复位后，板载绿色 **LD2** 会快速闪两次，随后开始双脉冲心跳，表示电子宠物正在运行。
   当前第一版没有屏幕，LED 就是状态界面：短按 B1 是喂养/照顾，长按约 1.2 秒后松开可睡眠或唤醒。

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

`src/pet.c` owns the persistent game rules: satiety, energy, joy, hygiene,
health, level, XP, coins, life stage, and sleep. It knows nothing about LEDs,
GPIO, display pixels, or a particular minigame.

Future games submit a score through `PET_CMD_SUBMIT_GAME_RESULT`; the pet core
decides XP, coins, joy, and energy changes. This prevents each game from
silently changing the pet balance or storage format.

`src/display_null.c` is an intentionally empty screen backend. A future
`ssd1306_i2c.c` or `st7789_spi.c` can implement the same `display.h` interface
without changing `pet.c`.

### Pin planning for a future screen

PA5 is also Arduino D13 / `SPI1_SCK`. A common SPI display on SPI1 will make
LD2 flicker, so it is not a good permanent combination. An I2C OLED on PB8/PB9
or an SPI display using SPI2 are better options if the board LED remains useful
for diagnostics.

For persistent saves, do not write a raw C struct to Flash every second. Add a
versioned, checksummed save record and only save on meaningful events, or use
external EEPROM/FRAM later.
