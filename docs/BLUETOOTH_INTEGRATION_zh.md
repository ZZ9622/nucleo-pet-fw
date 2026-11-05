# Pomi · 蓝牙直连

2026-11-05：已使用当前连接的 STM32 NUCLEO-F401RE 与 Olimex ESP32-C3 模块完成 BLE 实物往返。Mac 只用于开发、烧录与本次蓝牙测试，不再作为手机通信桥接服务器。

## 已验证接线

两块板子开发时分别通过 USB 供电，信号使用 3.3V 电平，必须共地。

| STM32 NUCLEO-F401RE | ESP32-C3 | 方向 |
| --- | --- | --- |
| D8 / PA9 / USART1 TX | GPIO4 / UART RX | 板子 → 模块 |
| D2 / PA10 / USART1 RX | GPIO5 / UART TX | 模块 → 板子 |
| GND | GND | 共地 |

三根线缺一不可。仅 D8→GPIO4 可以做单向遥测，无法完成手机交接命令。D2 不是 A2，GPIO5 不是 5V。断电后接线；蓝牙模块不要使用 USB 信号所在的 GPIO18/19 作为 UART 引脚。

板端保留 USART2 PA2/PA3 的 ST-LINK USB 调试接口。USART1 与 USART2 各有独立中断缓冲，承载同一份 v2 宠物交接协议与同一份 Flash 存档。

## 烧录

修改前先备份两块板子的完整 Flash；普通更新 STM32 时只烧程序区，不擦除扇区 6/7 的宠物存档。

STM32 依旧运行仓库根目录的 `make build`、`make test`、`make flash`。

模块固件源码：`firmware/pomi_ble_bridge/pomi_ble_bridge.ino`。使用 Arduino CLI 和 ESP32 core 3.3.12：

```sh
brew install arduino-cli
arduino-cli core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core install esp32:esp32@3.3.12 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli compile --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc --build-path build/esp32c3 firmware/pomi_ble_bridge
arduino-cli upload --fqbn esp32:esp32:esp32c3:CDCOnBoot=cdc --port /dev/cu.usbmodem1101 --input-dir build/esp32c3 firmware/pomi_ble_bridge
```

串口名称以本机检测结果为准。GPIO4/5 是本次实物验证的连接；其他接线可用编译宏 `POMI_UART_RX` / `POMI_UART_TX` 明确配置，不能只按模块品牌猜测引脚。

## App 操作

1. 用 Xcode 打开 `ios/NucleoPet.xcodeproj`，运行到实体 iPhone，允许蓝牙访问。
2. App 默认进入蓝牙连接页，点“搜索附近挂件”。
3. 选择广播名称 Pomi 的设备。App 检查可写、通知服务，并读取/校验完整宠物记录后进入小屋。
4. “接到小屋”后，OLED 小猫消失、显示 VISITING PHONE，板上互动暂停；手机可互动。
5. 送回挂件后，OLED 恢复小猫，保留手机更新后的完整状态。

iPhone 模拟器可验证界面、领域逻辑和动作调试台，不能代替实体 iPhone 的无线 BLE 验收。本次已使用同源 SwiftUI/Core Bluetooth 代码的 Mac 原生测试版完成真实连接、互动与往返；实体 iPhone 的签名、权限与无线连接仍需在真机验收。

“USB 经 Mac”是可选的调试通道；正常蓝牙连接不需要 Mac 地址、HTTP 服务器或桥接口令。

## 中断与所有权

蓝牙断开会显示重新连接入口。手机拥有宠物时可继续本地互动并保存；交接未完成时双方保持冻结，重新连接后继续同一段旅程。超时不撤销、重试不新建宠物。

收到更高版本的板上记录时，仅“本地记录仍归板子、没有待交接、板子也处于活动所有权”的旧快照可以刷新。不会用板端记录覆盖手机正在拥有的宠物，也不会接受版本回退。

## BLE 与 UART 协议

- 服务 UUID：`A27C38E1-9447-454A-898F-F1B8719391E3`
- 双向特征 UUID：`87A0909E-5440-4883-A0B9-5FB589496AD8`
- 特征属性：Read + Write（有响应）+ Notify。
- UART：115200、8N1；BLE 原样承载 v2 的 CRC32 行帧，不只传心情/精力摘要。
- App 按协商写入长度分包，串行等待写入确认；模块以 20 字节通知分包回复，兼容默认 ATT MTU。
- 双端验证完整帧、请求编号、宠物身份、交接编号和版本。模块只负责转发，不自行养宠或改变属性。
- 模块只在 BLE 完整有效请求到达时访问 STM32，不再用旧的单向属性推送固件。
- 模块断开会丢弃旧连接排队数据；重新广播。客户端请求重试沿用同一帧编号和交接事务。

当前为开发原型的近距离 BLE 服务，尚无产品级配对认证、绑定白名单或加密策略；量产前需要补齐设备授权与安全设计。没有加入后台持续连接或自动跨设备迁移。

## 本次验证

- 7 组 C 测试通过；双 UART 固件 11408 B Flash、10356 B 静态 RAM，烧录读回校验通过。
- ESP32-C3 双向桥接固件编译、烧录校验通过；旧固件和 STM32 完整 Flash 已在本机独立备份，不上传仓库。
- Swift 28 项领域测试通过，包括 CRC、错帧/错编号、通知分片、超长帧恢复、完整状态和所有权保护。
- iPhone 模拟器 2 项连接界面测试通过：蓝牙默认入口、USB 可选入口及失败时停留/恢复。
- 真实 BLE 协议：完整读取、双向 prepare/commit、重复确认、错误事务和过期事务拒绝、离开期间 STM32 重启保持冻结均通过。
- App 同源原生 Mac 版：真实 BLE 搜索、连接后进入主页、两轮互动往返通过。最终 App 与板端均为心情 100、精力 50、经验 35、交接版本 10。
- 用户确认 OLED 接入后小猫消失、返回后小猫恢复且数值正确。

本机测试产物和备份放在仓库外的 `ble-work/` 工作目录。通信测试使用 Mac 自身 BLE，无 USB/HTTP 网络桥接服务器参与实际宠物数据链路。
