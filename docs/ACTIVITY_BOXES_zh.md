# Pomi 活动盒子：六盒版本与保留的测试版

## 当前方案

| 配置 | 刷新时间（服务时区） | 每盒新增有效活动 | 上限 |
|---|---|---|---|
| `daily6` 新版 | 每天08:00 | 1、3、5、8、12、15分钟 | 6盒 |
| `test30` 原测试版 | 保持原来的零点刷新 | 固定30秒 | 3盒 |
| `fixed600` 原固定版 | 零点刷新 | 固定10分钟 | 3盒 |

新版总活动门槛为1、4、9、17、29、44分钟。不是“累计到第3分钟”就领第二盒，而是拿到第一盒后再活动3分钟。服务器默认时区为Europe/Stockholm，可用 `--timezone` 指定；每天8点按当地钟表时间计算，夏令时切换时周期可能为23或25小时。8点之前的活动归属前一周期，不限制凌晨活动。

有效活动沿用LIS3DH当前算法，不是GPS出门识别或精确步数。只有宠物在挂件上、没有交接/存储故障时累计，睡眠不妨碍携带活动。状态“晃动”的显示保持时间不会额外算作持续活动，奖励计时与传感器的有效活动窗口一致。

## 持久进度和8点刷新

每新增一整秒持久写入journal v5；App只显示已保存的整秒。断电可能舍弃未满1秒的采样，不回退已显示进度。达标时扣除本阶段秒数并增加奖励计数，原子写入。达到当期上限后不再囤积额外时间。

8点刷新时：先将旧期未入库的盒子补齐，再确认新周期；已获得的盒子不清空。未用于换盒子的活动秒数结转到新周期，并按新周期阶梯扣除。例如上一周期还剩179秒未消费，新周期会用60秒换第一盒，剩119秒用于第二阶段。这可能在重连时直接带来盒子，但不会再次使用已换过盒子的活动时间。

当前挂件没有断电走时时钟。首次需连小屋服务确认日期才能启用奖励；之后可离线累计并断电保存。离线跨8点不会自行重置额度，保持最后确认周期，重连后再结算并刷新。这是保守规则，避免改手机时间或重启刷额度。

可靠计时通常指RTC实时时钟在主电源断开后仍有后备供电，可持续记录日历。加速度计不是时钟；仅靠上电计时无法知道断电多久。RTC也只解决时间，不会把断电时间算成活动。

## 构建新版（默认daily6）

```sh
git pull --ff-only origin main
cmake -S . -B build/daily6 \
  -DCMAKE_TOOLCHAIN_FILE=cmake/arm-none-eabi-gcc.cmake \
  -DPOMI_ACTIVITY_PROFILE=daily6 -DPOMI_ACTIVITY_SECONDS=600
cmake --build build/daily6
openocd -f openocd/nucleo-f401re.cfg \
  -c "program build/daily6/pet.hex verify reset exit"
```

烧录前让宠物回到挂件、完成物品待办。不要mass erase；程序HEX不覆盖存档扇区6/7。v5可读取v2/v3/v4存档，不要刷回不识别v5的旧固件。ESP32透传桥不需升级。

新版服务使用原数据库和原地址，先停止原服务、备份DB，再启动：

```sh
python3 server/pomi_server.py --db /你的原数据库路径/pomi.sqlite \
  --host 0.0.0.0 --port 8787 --activity-profile daily6 --timezone Europe/Stockholm
```

不要新建数据库冒充升级，不要删App身份。不要同时运行不同版本的服务写同一个数据库。本轮开发没有自动替换用户正在运行的30秒测试服务，也没有自动安装新版App到iPhone。

## 保留原30秒测试版本

原命令继续有效，不会因为新增daily6而变成六盒：

```sh
cmake -S . -B build/activity-test \
  -DCMAKE_TOOLCHAIN_FILE=cmake/arm-none-eabi-gcc.cmake \
  -DPOMI_ACTIVITY_SECONDS=30
cmake --build build/activity-test
openocd -f openocd/nucleo-f401re.cfg \
  -c "program build/activity-test/pet.hex verify reset exit"
```

```sh
python3 server/pomi_server.py --db /你的原数据库路径/pomi.sqlite \
  --host 0.0.0.0 --port 8787 --development --activity-seconds 30
```

也可用 `--activity-profile test30`。旧600秒方案使用固件 `-DPOMI_ACTIVITY_PROFILE=fixed -DPOMI_ACTIVITY_SECONDS=600`、服务 `--activity-profile fixed600`。不要同时传相互矛盾的配置参数。

## 切换配置不会重新领取额度

挂件报告当前保存的profile和固件目标profile。服务先核对旧计数，再发迁移回执；挂件收到匹配的确认后才切换。旧v4没有profile字段时，会结合服务已有记录迁移，保留旧进度和计数。

旧测试期已领3盒，切到六盒版不会额外送6盒：新周期先计入已领3盒，从第4阶段继续。下一次8点刷新才恢复完整新周期。切回三盒版时视为达到三盒上限，再切回六盒版也不会打开已经用过的额度。先把旧版所有奖励同步完，再同步升级固件、App和服务。

新App兼容旧版30秒固件和旧服务；新版六盒功能需要新固件、App和服务匹配。配置不匹配时停止发放并显示提示，不自动清空数据。

## 自动同步与幂等

STATUS可选activity字段包含周期、整秒进度、当前目标、已得数、当前profile、固件目标profile和上限。App自动转发累计回执。服务使用SQLite事务，以 `(petID, profile, day)` 核对累计已领数，只发差额。迁移时继承已经消耗的额度，不能靠来回换配置重复领。挂件仍与一个仓库绑定。

新ACTIVITY_SYNC有6个载荷字段：新周期、旧周期、旧已得数、目标profile、旧profile、继承数量；保留旧3字段协议用于原测试固件。回执/断网请求均可重试。CRC仅检查传输错误，量产防作弊仍需签名凭证。

## 实物验收

- 先确认App显示“每天08:00刷新 · 最多6盒”和当前阶段分钟数。
- 在没有旧期额度结转的新周期测试：1分钟得第1盒，再3分钟得第2盒，再5、8、12、15分钟依次得第3至6盒。以已保存有效秒数为准，达到6盒后继续活动不发第7个。
- 途中记下已保存秒数，断电重连不回退；断连后达标，重连只补一次。
- 多次同步、重开App、服务重启，不重复发放。
- 8点刷新、夏令时和迁移已有自动化覆盖；真实时钟验收按服务配置时间自然经过，不改手机时间。

`make test`测试fixed600、test30、daily6三种固件状态机，每种覆盖44个写入中断点；服务测试覆盖8点边界、午夜不刷新、夏令时、六盒上限、并发领取、迁移丢包和往返切换；Swift测试覆盖阶段、旧协议兼容与迁移回执。实物结果需单独记录，自动化通过不代表新增版本已烧录验收。
