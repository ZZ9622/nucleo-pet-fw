> App 当前默认蓝牙直连，见 [蓝牙直连指南](BLUETOOTH_INTEGRATION_zh.md)。本文保留 USB＋Mac 调试通道说明。

# Pomi · USB＋Mac 真实手动往返

2026-11-01：已实现并使用 NUCLEO-F401RE 实物验证。Mac 使用 Python 3 标准库，App 使用 Xcode 原生 iOS 工程。

## 启动

1. 按原接线连接 OLED；USB 连接板上 CN1/ST-LINK 和 Mac，无需额外串口模块。
2. 在仓库运行 `make build`、`make flash`。首次升级旧固件会初始化新格式的宠物；后续正常烧录保留预留的存档扇区。升级前建议备份完整 Flash。
3. 查看串口和 Mac 名称：

```sh
ls /dev/cu.usbmodem*
scutil --get LocalHostName
```

4. 在同一个终端设置私人口令并启动桥接（替换串口名称）：

```sh
export PET_BRIDGE_TOKEN="自己设置的私人口令"
python3 tools/serial_bridge.py --port /dev/cu.usbmodem1103 --bind 0.0.0.0
```

5. Xcode 打开 `ios/NucleoPet.xcodeproj`，运行 NucleoPet。App 的“挂件”页填写 `你的Mac名称.local` 和同一口令，点击“连接真实挂件”。真实 iPhone 需与 Mac 在同一局域网并允许本地网络访问。口令仅保存在 App 本次运行内，重开后需重填。
6. 小屋点“接方方来小屋”→“出发吧”：OLED 显示门和 VISITING PHONE，板上照顾与重置暂停。App 可互动。
7. 点“送它回随身挂件”→“出发吧”：OLED 恢复小猫，保留手机更新后的完整属性、睡眠与内部计时。

桥接默认仅监听本机；`--bind 0.0.0.0` 供同一网络的手机连接。开发 HTTP 不加密，只用于可信局域网，不做公网映射。串口名称改变后需重启桥接。

## 中断恢复与保存

交接中断时保留原手机 App 存档，恢复 USB 和桥接，在小屋点“继续旅程”。真实交接没有撤销按钮，超时不会擅自恢复任一端的活动状态。不要删除 App、清空板上 Flash 或用另一台手机重新创建宠物来恢复交接。

板端稳定 petID 来自 STM32 UID。所有权与交接编号持久保存；Flash 扇区 6/7（0x08040000–0x0807ffff）为追加日志，CRC 与最后提交标记检测不完整写入，轮换时保留上一扇区。链接脚本将程序区限制为前 256 KiB。普通操作后保存，板上运行每 5 分钟保存；意外断电可能丢失最近检查点后的计时。断电期间不补算时间，没有 RTC。Flash 擦除可能造成短暂通信停顿，桥接会重试同一请求。

App 的真实存档 `physical-session.json` 与体验存档分开，原子保存完整状态和待交接记录。仅手机拥有且没有交接时才推进手机计时。返回前冻结快照、保存释放记录，再允许板端激活。新手机不能接管已经在另一台手机的宠物；当前没有存档丢失后的自动恢复功能。

## 协议与实现

USART2 PA2/PA3，经板载 ST-LINK VCP；**115200、8N1、协议 v2**，不兼容旧版 9600/问号协议。收发使用中断缓冲，CRC32 校验整帧。

请求：`!requestID|COMMAND|petID|transferID|baseRevision|stateWords|crc32\n`。三个 ID 均为 32 位十六进制字符；stateWords 为 14 个逗号分隔的无符号十进制数。响应为 JSON、`|`、八位 CRC32 和换行。CRC 覆盖最后一个分隔符之前的原始字节。完整状态次序与 `pet_state_encode` 一致。

所有 HTTP 接口要求 `Authorization: Bearer <口令>`：

| 接口 | 用途 |
| --- | --- |
| GET /device | 新鲜的完整身份、所有权、版本及状态 |
| GET /state | 兼容旧读取页面的属性摘要，按需查询 |
| POST /handoff/take/prepare | 板端冻结并持久保存提供给手机的快照 |
| POST /handoff/take/commit | 板端确认手机所有权，版本加一 |
| POST /handoff/return/stage | 板端持久保存手机返回快照，尚不激活 |
| POST /handoff/return/commit | 板端激活并确认，版本加一 |

POST JSON 包含 petID、transferID、revision，return/stage 另含 state。重复同一事务可重试；错误身份、旧版本、同编号不同返回载荷会拒绝。phase：0 板端、1 接入待确认、2 手机、3 返回待确认、4 存储锁定。

## 验证记录

- `make test`：原有六组 C 测试与新增交接日志测试通过，覆盖完整往返、重复请求、错误编号、28 个模拟写入中断位置、重启和扇区轮换。
- Swift 17 项领域测试通过，包含真实会话持久化、单端活动和返回确认约束。
- 固件交叉编译、烧录校验通过；Flash 11260 B，静态 RAM 5708 B。
- 真实 ST-LINK／STM32：双向 prepare/commit、完整载荷返回、重复确认、错误编号拒绝及手机所有权期间板子重启保持离开状态通过。
- iPhone 17／iOS 27.2 模拟器连接真实板子：接入、玩耍、返回成功。板子读回心情 100、精力 56，与 App 更新后结果一致；用户确认接入后 OLED 小猫消失、显示门和提示。
- 本次没有完成实体 iPhone 签名安装与局域网权限验收，也未做真实断电写入故障或长期 Flash 寿命测试；模拟写入中断测试不能替代电源故障测试。

本次实物日志与升级前完整 Flash 备份在本机忽略目录 `build/handoff-test/`，不上传桥接口令或固件备份。
