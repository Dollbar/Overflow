# 两端实际 TL/DL 数字接口集成审查

日期：2026-09-11。证据层级为 `integrated_rtl`，这是一份可执行的跨层通道集成测试，不是完整 Endpoint IP、UPLI 事务闭环或 G2 退出结论。生产 RTL 未修改。

## 实际连接

`verification/endpoint_link/run.py` 生成两份以下真实组合，并用显式传入的授权 KD28 同步 SRAM 模型运行 Icarus：

```text
独立预生成 Request/Response 源
  → tl_tx_prepared（prepared partition + buffered SRAM + 两类打包）
  → tl_credit_admitted_port（唯一发送信用/tenure账本）
  ↔ dl_replay_data_port（真实重放控制、头、收发器及SRAM）
  ↔ 有限延迟/丢槽/CRC-status注错的测试链路
  ↔ 对端 dl_replay_data_port
  → 对端 tl_credit_admitted_port + tl_receive_credit 的实际600-bit SRAM
  → 独立接收消费者退休 → 实际FC发布器 → 对端TL/DL反向发送
```

发送源使用当前生产 `tl_tx_prepared`，不是另外重建旧 buffered 调度器。每类源组的捕获确认推进上游索引，Data 使用实际部分入队数量；最终发送消费与上游捕获是不同事件。

测试适配器每个 DL 不透明槽保存 `{6'b0, M[1:0], TL[511:0]}` 共 520 bits。DL 预约返回完整注册头/数据，两个方向各有固定延迟的寄存链路。此格式仅属于本地测试接口，**不是标准 640-byte DL flit 格式**，不能当作 TL/DL framing 实现。测试使用单拍组边界；没有实例化数字 RS、FEC 或物理通道。

`dl_replay_data_port.o_payload_accept` 是唯一正常发送提交：同时推进 TL 账本与准备发送源。重放从 DL SRAM 返回，不再次扣 TL 信用。入站只有 `o_rx_payload_accept` 完成 DL 检查/去重后，才共同推进 TL 信用端口和接收 SRAM。测试链路不增加旁路 TL ready；有限背压通过停止预约和停止应用退休施加，随后检查完整排空。

## 独立检查与证据

`check.py` 从实际 trace 独立比较原始输入 fixture，不使用 RTL 输出的分类/释放向量作为期望值：

- 源 Control 全位及 Data 半 Flit 的类别、顺序、实际消费数量。
- 9-bit 非零 DL 序号独立递增，包括 511→1；每个正常注册 SRAM 输出与此前提交对应，所有重放序号的数据与此前原始记录完全相同。
- 每个入站去重后的完整 520-bit TL 记录与对端正常提交队列完全相等，且恰好交付一次。
- 既有独立 Python `Context` / `ReceiveContext` 语义模型重建 tenure、类别及释放量，对照实际 600-bit SRAM 退休字和每拍占用数。
- FC 不先于实际 SRAM 退休发布，完整初始化信用先于唯一完成消息；终点的逻辑归还、实际可用/总信用、TL tenure、接收 SRAM 和 DL 未确认/重放队列全部排空。

Python 检查使用显式异常，不依赖可被 `python -O` 移除的 `assert`。最终7个正向case已从 `/tmp` 用 `python -O` 独立复审，退出均为0且 `audit.json` 逐字节一致；结果保存于 `retained/optimized_audit.json`。参考模型独立于 RTL 实现，但仍为本项目自研模型；这不是第三方互操作或联盟一致性认证。

最终完整矩阵：`build/verification/endpoint_link/retained/summary.json`。7 个正向配置、4 个实际接线故障均达到各自预期。下表配置中 WIDTH=8、Header depth=2、每个 Data bank depth=3、接收 FIFO depth=40、20 个逻辑信用槽各初始1；除 wrap 每端每类160组外，每端每类均24组。

| 配置 | DL depth / delay | Auth / shared | 周期 | 唯一TL记录 | SRAM退休字 | DL重放 |
|---|---:|---:|---:|---:|---:|---:|
| clean | 3 / 3 | 0 / 0 | 418 | 206 | 176 | 0 |
| recovery | 3 / 3 | 0 / 0 | 419 | 206 | 176 | 10 |
| minimum | 1 / 1 | 0 / 0 | 518 | 202 | 178 | 4 |
| shared | 3 / 3 | 0 / 1 | 419 | 206 | 176 | 10 |
| auth | 5 / 5 | 1 / 0 | 483 | 285 | 192 | 14 |
| auth_shared | 5 / 3 | 1 / 1 | 397 | 287 | 192 | 14 |
| wrap | 5 / 7 | 0 / 0 | 2243 | 1294 | 1223 | 14 |

合计 4,897 周期，2,686 个唯一 TL 记录全部交付，2,313 次 SRAM 退休，66 次 DL 重放，1,159 次 FC/初始化完成源转移；共施加12次 CRC-status failure及12次丢槽，两个方向各跨一次非零序号环。周期是本测试的离散时钟计数；10ns 测试时钟不代表最终目标频率、带宽或物理延迟。Auth=1仅验证认证标签分类/储存，标签fixture为零，没有密码学认证。

| 实际故障 | 预期检出结果 |
|---|---|
| 重放 DATA 到接收链路的 bit300 翻转 | RTL仍排空，独立端到端对照在 side1/cycle57 失败 |
| 发送源在预约而非 DL payload_accept 时消费 | RTL连接原子性断言在 cycle7 失败 |
| CRC拒绝/未去重的线上payload旁路进入TL信用端口 | 入站共同接纳检查在 cycle59 失败 |
| 进入接收SRAM的 DATA bit300 翻转 | RTL仍排空，独立600-bit退休字对照在 side1/cycle151 失败 |

这些故障实际改变测试实例之间的连线，并重新编译执行；不是修改日志后宣称检出。首次开发阶段另有重放控制字段破坏触发 RTL fatal，最终故障矩阵改为 DATA 位破坏，确保独立全载荷检查器也受到实际挑战。

## 复跑与产物

从任意目录调用绝对脚本路径，或从工程根运行：

```bash
python3 verification/endpoint_link/run_matrix.py --kd28-root /path/to/authorized/OverFlow --label my_endpoint_run
python3 verification/endpoint_link/run.py --kd28-root /path/to/authorized/OverFlow --label my_single_run --depth 5 --delay 7 --count 160 --inject
python3 -O verification/endpoint_link/check.py build/verification/endpoint_link/my_single_run
```

`--kd28-root` 只定位显式外部依赖，不绑定相邻工程。`--label` 必须是新目录名，已有证据拒绝覆盖。每个case保存 fixture、完整生成TB、编译/运行/审计日志、原始trace、Icarus/vvp版本、实际命令、源码/参考模型/外部SRAM校验值及产物校验值；正常场景生成 `audit.json`，总矩阵生成 `summary.json`。故障case保留预期非零退出，矩阵只在编译成功且检出指定诊断时计为通过。

下一步先完成真实接收事务与回应接口，再把该测试记录适配器替换为规范化 TL/DL 打包接收接口。

## 仍缺少的端点边界

当前 Request/Response 是两侧**独立预生成流**；Response 不是收到 Read 后由完整 completer 生成，也没有请求发起方的 Tag/BeatOffset/Last 关联与完成退休。fixture只覆盖已明确的单Beat WriteFull及带Data响应的准备好字段/tenure，不覆盖全部指令、地址语义、超容量事务和每VC调度。

推进最小真实 Read→Response 闭环所需接口为：

1. `tl_receive_credit` 的退休记录目前仍是完整Flit、分类和释放向量。需要真实 Control 字段提取及跨半Flit Data/BE组装，按已确认字段输出单笔本地事务及捕获握手；不能直接把一次FIFO字退休当作整笔事务完成。
2. 需要连接可背压的本地内存/UPLI请求执行器。其应接收来源路由/事务关联信息、已解析命令和长度，返回明确的数据/状态完成事件。当前没有这层实际模块契约和读请求到执行返回的组合。
3. 需要响应格式化器将真实完成事件转换成 `tl_tx_prepared` 的 Response源组及Data源流，并保留Tag、BeatOffset/Last和适用错误状态；需要发起侧 outstanding 关联/完成检查器，不能靠固定源fixture代替。
4. 需要规范化 TL↔DL 多Flit封装、M侧带映射和接收解包，随后接 CRC、完整 DL 控制/Basic/UART、RS/PCS/FEC。CRC位序 A19仍开放；本测试只输入明确的CRC状态，未新增CRC算法或推定其线顺序。
5. 仍需跨层 Link Down/reset/迟到响应恢复、控制消息优先级、watchdog、CDC/RDC、多station、完整安全/INC/管理，以及Endpoint/Switch生产顶层与签核。当前所有模块共用一次初始化时期，未验证链路独立复位，不以全局复位替代协议恢复。

上述接口需要按正式规范/现有冻结契约展开，不能为快速形成示例而猜测未决字段。本阶段没有改变最终双 IP 完整交付范围。
