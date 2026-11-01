# Little Wanderer：c79bad5 实际检查与 USB 接入

## 检查结论

检查的原工程：`/Users/linda/Desktop/learning/nucleo-pet-fw`，HEAD `c79bad5`。
此次实现位于当前工作区的 `nucleo-pet-fw` 副本，不自动覆盖下载目录，不自动烧录。

- 固件：C11 裸机，最小寄存器头文件，HSI/APB1 16 MHz，CMake/Make、Arm GCC、OpenOCD；没有 HAL、RTOS、UART、BLE 或 Flash 存档。
- App：iOS 17+ SwiftUI/Combine，Swift Package `PetDomain`，C 模块 `CPetCore`，JSON 本地存档。不是网页或 React Native。
- `TravelView`/`CompanionStore` 的往返确认是单进程模拟。`CompanionSession` 自建 UUID 并推进模拟状态，不能直接用作真实板子的状态副本。
- `FirmwareState` 显式映射 14 个 C 状态字段；只同步显示用 Happiness/Energy 不足以迁移宠物。
- `ios/Sources/CPetCore/` 是代码副本；修改养成规则后需保持两端一致。

## 无需加硬件的第一条链路

STM32 USART2 ↔ 板载 ST-LINK VCP ↔ CN1 USB 数据线 ↔ Mac Python 桥接 ↔ 同一 Wi-Fi 的 iPhone。
Mac 必须开机、连接开发板并运行桥接。iPhone 上的 localhost 是手机自身，不能填 localhost。

[ST UM1724 §7.10](https://www.st.com/resource/en/user_manual/DM00105823-.pdf)：默认 PA2/PA3 连接 ST-LINK USART，SB13/SB14 ON、SB62/SB63 OFF。先检查板子是否改过焊桥，不要为了此方案随意改焊桥。ST-LINK USB 并不等于 F401 固件已经配置串口。

| 功能 | 当前代码引脚 | 是否冲突 |
|---|---|---|
| OLED I2C1 | PB8 SCL、PB9 SDA | 与当前四键不冲突 |
| 喂食/抚摸/睡眠/玩耍 | PA0、PA1、PA4、PB0 | 保留 |
| 新增 USART2 | PA2 TX、PA3 RX、AF7 | 与上述接口不冲突 |
| 调试/板载键/灯 | PA13/PA14、PC13、PA5 | 保留 |

A2 是 PA4，不是 PA2。A4/A5 可能经焊桥接 PB9/PB8，不可拿它们替代四键，否则按键接地会拖住 I2C。按 WIRING_zh.md 的 A0–A3 接线。

## 本次已实现：真实属性只读链路

- `src/pet_serial.c`：9600 baud、8N1；每次收到 `?`，捕获一份当前状态，逐字节非阻塞发送 JSON 行，不阻塞等待 UART。
- 响应示例：`{"v":1,"seq":1,"energy":80,"happiness":75,"sleeping":false}`。
- `seq` 是本次启动内的响应计数，不是持久 revision，不是设备身份，不是迁移 ACK。
- `tools/serial_bridge.py`：仅依赖 Python 标准库；每秒查询，校验字段，3 秒无新帧即过期；掉线清除缓存并每秒尝试重开同一路径。端口名称改变后需重启桥接。
- `/state` 使用 Bearer 口令，只读；默认仅监听 Mac 本机。指定 `--bind 0.0.0.0` 才供同一网络的手机读取。开发用 HTTP 口令不加密，仅在可信局域网使用，不做公网映射。
- App 设备页新增独立的“真实挂件”读取区域；不覆盖模拟宠物和本地存档。每次点击读取，3 秒后隐藏结果，失败时不继续显示旧属性。没有后台自动同步。
- App 增加本地网络用途说明与仅本地 ATS 例外；参见 [Apple NSAllowsLocalNetworking](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking)。

本阶段没有远程照顾、真实召唤、返回、完整状态导入或持久 ACK。页面原有往返仍是离线演示。

## 最小运行步骤

在**这个副本目录**执行，避免误用下载目录的旧固件：

```sh
make test
make build BUILD_DIR=build/usb-bringup
make probe
# 识别到目标 NUCLEO-F401RE 后，手动烧录：
make flash BUILD_DIR=build/usb-bringup
ls /dev/cu.usbmodem*
```

USB 接板载 ST-LINK 的 CN1，使用可传数据的线。若无 usbmodem，先解决 USB 枚举；不必先买蓝牙模块。
不能用蓝牙耳机的 `/dev/cu.*` 端口代替开发板。

```sh
export PET_BRIDGE_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(24))')"
# 查看口令并手动填入 App，不把它提交进仓库：
printf '%s\n' "$PET_BRIDGE_TOKEN"
python3 tools/serial_bridge.py --port /dev/cu.usbmodem实际名称 --bind 0.0.0.0
```

1. 用完整 Xcode 打开 `ios/NucleoPet.xcodeproj`，选择自己的签名 Team，运行到 iPhone。
2. Mac 与手机连接同一可信 Wi-Fi；允许 Mac Python 接收入站连接。
3. Mac“系统设置 → 通用 → 共享”查找本地主机名（如 `Lindas-Mac.local`）。在 App 设备页填此名称与口令。
4. 点“读取真实属性”，允许 iPhone 本地网络访问；第一次授权后可能需要再点一次。
5. 在板上按键改变属性，再点读取核对。拔线后再读取应提示断开；旧结果最多显示 3 秒。
6. 模拟出发不会使真实 OLED 宠物消失，这是当前阶段的明确边界。

若只在 Mac 检查：桥接保持默认 bind，在另一个终端用带 Authorization 的 HTTP GET 请求 `http://127.0.0.1:8765/state`。

## 下一阶段：真实召唤/返回协议（设计，尚未实现）

不能在现有 `finishTransfer` 前后简单加网络请求。先补板端稳定 ID 和掉电可恢复的日志，再允许所有权变化。

### 数据和消息

- HELLO：deviceID（可基于芯片 UID）、稳定 petID（设备身份+宠物世代）、协议版本、规则版本、启动 ID。
- STATE：petID、owner、持久 revision、完整 14 字段 FirmwareState、规则版本。计时器按现有“活动所有者推进时间”的规则传递，不能两端同时按时钟衰减。
- 帧：版本、长度、消息类型、requestID、transferID、petID、expectedRevision、字段载荷、CRC32。明确大小上限、截断处理、重组超时；不发原始 C struct 内存。
- 命令 ACK：带原 requestID、执行结果、应用后的 revision；CRC 只校验传输完整性，不负责身份鉴别。
- 重复相同 ID 与载荷返回同一结果；同 ID 不同载荷报错；旧 revision 拒绝。持久去重记录在确认之前保存。

### 迁移顺序：宁可暂时冻结，不允许两个活动所有者

A 为当前主人、B 为目标；Mac 只转发，不做状态主人。

1. A 在同一事件循环停止照顾和计时，捕获完整状态，将 PREPARED(transferID, B, rev+1, state) 可靠落盘，再发 OFFER。
2. B 校验身份、版本、范围与 revision，持久化为 STAGED，仍不互动，回复 READY。
3. A 收到 READY 后持久化 RELEASED（不可自行恢复为活动主人），再发 COMMIT。
4. B 收到 COMMIT 后持久化 ACTIVE 和已完成 transferID，才启用互动，回复 COMMITTED。
5. A 收到 COMMITTED 后标记出门/清理待处理记录；OLED 显示出门，拒绝本地动作、B1 复位与计时推进。返回时 A/B 对调。

COMMITTED 丢失时 A 查询 STATUS 并重发相同 COMMIT，B 返回已保存结果；不得建立新事务或重复导入。
READY 丢失时重发同一 OFFER。任何阶段超时均进入“等待重连确认”，不能自动切回活动主人。
重连/重启先读取日志并交换 STATUS，然后继续原事务。未完成前禁用新迁移。
要撤销 PREPARED，必须和对端完成持久 ABORT 协议并确认对端从未 ACTIVE；RELEASED 后不允许本地直接撤销。
不能用当前 `cancelSimulatedTransfer` 撤销真实事务。

### 存档、时间和身份

板端需预留 Flash 区并同步修改链接脚本（当前没有预留），实现双槽/追加日志、长度/版本/序号/CRC、最后写入有效标记；不能在 UART 回调中阻塞擦除。加入掉电和磨损策略，并验证 Flash 操作期间通信停顿。ACK 必须发生在写入完成、可读回验证之后。
App 端存档需原子写入完整状态与事务记录；保存失败不回复 READY/COMMITTED，不切换居所。
板子恢复出厂应显式创建新宠物世代，旧 App 不得把旧 petID 的状态覆盖回来。
现有板端没有 RTC：初期保留“仅活动且运行时推进”的行为，明确手机端是否计入后台时间；迁移冻结时间不重复补算，避免睡眠/每日喂食计时发生跳变。

### 接入现有 App

增加独立真实设备会话与 Transport 层，通过事件进入持久状态机；隔离当前 Demo 会话。
真实设备居所时只展示板端快照，不能调用模拟 `advance` 推进这份状态。
手机取得 ACTIVE 后才复用 CPetCore 做本地照顾和计时；返回完成后立即冻结。
不能只调用当前会自行生成 UUID 的 `CompanionSession()` 创建真实绑定。

### BLE 何时值得做

只有需要离开 Mac 独立使用 iPhone 时，再增加 ESP32-C3 BLE 桥。保留同一应用协议，换传输为 GATT write/notify，处理 MTU 分片与重组；iPhone 用 Core Bluetooth。ESP32-C3 也需要烧录桥接程序，不能把裸模块当即插即用串口。
届时另选未占用的 STM32 UART 并核对复用、3.3V 和共地，避免把 ST-LINK TX 与 ESP32 TX 并接在同一个 RX 上。
本次没有实现、购买或实测 BLE 硬件。

## 验收边界

- 需要实测：按键与 OLED 正常运行时串口无乱码；App 显示真实属性；拔插重连；Mac 睡眠与 App 前后台变化。
- 真正迁移实现后：在 PREPARED/STAGED/RELEASED/ACTIVE 每个阶段分别断网、断电、杀 App、丢 ACK、重发和乱序；必须保持最多一个活动主人、同 ID 不重复执行、全字段一致。
- 软件测试和交叉编译不等于完成真机联调。

## 本次验证记录

- 原有 C 测试 6 组通过。
- 新 USB 固件交叉编译通过：Flash 7356 B，静态 RAM 1188 B，不含运行栈。
- Python 桥接测试 2 项通过：字段校验；伪串口分段帧→HTTP、401、3 秒过期与断开。该测试未连接真实板子。
- Swift Package 的 PetPreview（macOS）编译通过，含新增设备读取视图。
- Info.plist / Xcode 项目语法校验、git diff --check 通过。
- iOS 构建/UITest 未执行：本机未安装完整 Xcode；swift test 因缺少 XCTest 未通过执行，不能将原项目历史测试记录视为本次通过。
- 当前设备列表没有 /dev/cu.usbmodem*；未烧录、未做 USB 真机读取、未验证 iPhone 网络授权与 UI。
