# Pomi 双主控原型 · 接线建模基线

状态：已结合 2026-11-08 提供的五张实物照片、代码和历史联调记录整理。可见整体模块与布局；遮挡端点未逐根确认。不是完整电路仿真、尺寸模型或生产设计。

下载本文件夹后用浏览器打开 [index.html](index.html) 查看交互接线模型及原图；GitHub 页面不执行交互 HTML，可直接查看 [接线图 SVG](wiring-model.svg)。原始照片保存在 photos/，SHA-256 见 photos-manifest.json。

## 元件
- STM32 NUCLEO-F401RE
- Olimex ESP32-C3-DevKit-Lipo
- SSD1306 128×64 I²C OLED 模块
- LIS3DH Qwiic 加速度模块
- 四个常开按键及面包板
- 两路 USB 供电（当前开发方式）

## 网络表
| 网络 | STM32 | 外设 |
|---|---|---|
| I²C SCL | PB8 / D15 | OLED SCL、LIS3DH SCL |
| I²C SDA | PB9 / D14 | OLED SDA、LIS3DH SDA |
| 传感器与屏幕供电 | 3V3 | OLED VCC、LIS3DH VCC |
| 公共地 | GND | OLED、LIS3DH、Olimex GND，四个按键公共端 |
| 喂食键 | PA0 / A0 | 常开按键另一端 |
| 抚摸键 | PA1 / A1 | 常开按键另一端 |
| 睡眠键 | PA4 / A2 | 常开按键另一端 |
| 玩耍键 | PB0 / A3 | 常开按键另一端 |
| STM32 → BLE | PA9 / D8 / USART1 TX | Olimex GPIO4 / RX |
| BLE → STM32 | PA10 / D2 / USART1 RX | Olimex GPIO5 / TX |

按键使用内部上拉，按下接地；不要接到 A4/A5，以免与 OLED I²C 冲突。
OLED 地址由固件探测 0x3C/0x3D；LIS3DH 曾实测为 0x19，固件支持 0x18/0x19。
两块板分别 USB 供电时保留共地，不增加两块板电源输出之间的连接。

## 实物核对状态
- 照片可见 NUCLEO MB1136 rev C、Olimex 红色开发板、OLED、400 孔面包板和四个按键。
- 传感器小板可见双 Qwiic 接口和连接线，芯片完整型号未能从照片辨认；LIS3DH 依据原购买记录与历史 WHO_AM_I 测试。
- 照片可见两板 USB 供电，未见已连接的独立电池。
- OLED 位于面包板上部，四键位于下部，NUCLEO 在左侧，Olimex 位于右下侧，传感器在外侧。
- 多条线交叠，无法逐根核实 Olimex GPIO4/5、传感器四线、每个按钮的孔位与公共地。网络表是已知固件所要求的接线，不等于照片端点逐根验证。
- 图中按键按功能排序，不对应照片中的上下顺序；图中颜色用于区分网络，不表示真实线色。
- 外壳设计仍需实测长宽、安装孔、最高点、线缆和插头突出量。

## Velxio 适配边界
用户已确认视频平台为 Velxio。官方列表有 ESP32-C3、SSD1306 与按键，但未列出完全一致的 NUCLEO-F401RE、Olimex ESP32-C3-DevKit-Lipo 与 LIS3DH；STM32 系列仿真标为 PRO。
官方支持表：https://velxio.dev/docs/boards/overview/
本模型是本地交互式逻辑接线档案，不是 Velxio 项目文件，未宣称可直接导入或运行原固件。没有使用不同 MCU 或不同传感器冒充原实物。

## Qwiic 四线颜色

依据当前使用的 Qwiic 转杜邦线及此前接线记录：

| 功能 | 线色 | STM32 连接 |
|---|---|---|
| 3V3 | 红 | 3V3 |
| GND | 黑 | GND |
| SDA | 蓝 | D14 / PB9 |
| SCL | 黄 | D15 / PB8 |

颜色对应 Qwiic 这根线，不用于推断其他杜邦线的功能。
