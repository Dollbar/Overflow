# 本地 Isolation dummy 完成生成与账本集成

本候选真实实例化 `ras_originator_isolation` 与新增 `ras_dummy_completion`，由 `ras_isolation_completion` 连成一条本地应用完成路径。隔离请求接纳、实际响应 Beat 消费、账本销账分别发生于不同握手边界。没有修改生产 RTL、库存或系统顶层。

依据 Common 2.0 §3.1.3 的 Originator Isolation 责任及上一阶段冻结账本契约：隔离期间为真实响应义务生成 CMPTO，迟到正常完成不能消除 dummy 责任，信用规则仍由既有所有者执行。本候选只释义这些责任；本地 epoch 和管理恢复资格是保守实现契约。它不是 native UPLI/TL 发送器：没有构造 Src/Dst/Auth/VC/Pool、线格式 Header、TDM 或信用握手。

## 生成器契约

`ras_dummy_completion` 的参数 `EPOCH_WIDTH=8` 支持 2..16。时钟上升沿、同步低有效 reset。输入 `i_request_valid/o_request_ready` 接收原 slot2、port2、epoch、Tag11、read、beats3、status4。只接受 status=8，Read 1..4 Beat，Write 必须 1。非法描述符 ready=0、error=1；忙状态不覆盖既有请求。该叶模块不再检查端口对应某个 PORTS 范围，集成中的冻结账本已负责可信端口资格。

每个响应通过 `o_response_valid/i_response_ready` 向**本地应用完成消费者**交接，字段如下：

| 字段 | 行为 |
|---|---|
| slot、port、epoch、Tag | 保存原始完整身份，贯穿所有响应 Beat；反压时不变。 |
| read | 1 表示本 Beat 有完整 512 位 Data 义务；0 是 Write 无 Data 完成。 |
| num、offset、last | 使用单 Beat 响应描述模式，num=0；Read offset 从 0 到 beats−1，只有最终 Beat last=1；Write offset=0、last=1。 |
| status | 每一 Beat 均为 CMPTO=8。 |
| data[511:0] | 明确选择错误 Read 数据全零策略，实际完整驱动全部 512 位。Write 的该总线为零且没有数据义务。 |

生成器只有三个状态：空闲接纳一个描述符；逐 Beat 输出真实本地响应；最后一拍**实际握手之后**保持 `o_done_valid`。done 还携带原 slot/epoch，直到 `i_done_ready` 才回空闲。`o_busy` 在 done 被反压期间仍为 1。请求接纳不能触发 done，普通响应 valid 也不能代替响应握手；reset 可取消当前历史，但外部所有者需要同步处理其事务责任。

该接口的 ready 必须来自真正接收完整 Beat 的消费者，不能直接连空间预约或候选有效。接口允许消费权交接，但不证明未经接入的应用已经执行副作用。Read data 和其状态/身份同一次握手，未引入独立 Data 半 Flit 的可能错配。

## 集成契约

`ras_isolation_completion` 参数与冻结账本一致：PORTS=1/2/4，CAPACITY=1..4，IS_SWITCH=0/1，EPOCH_WIDTH=2..16，默认 1/4/0/8。0 为 Endpoint Accelerator Originator 全角色端口隔离；1 为 Switch Originator 逐端口隔离。真实层级中恰好一个账本和一个生成器，不再维护第二套 pending/count/Isolation/epoch。

登记、可信正常完成、LinkDown/Isolation、连接/init/外部 Drop、quiescent 及恢复输入全部直接接冻结账本。生成器 request_ready 仅接账本 dummy 请求握手。账本的 dummy_done 仅来自生成器在全部响应实际消费后的完成状态，不能由 request_accepted 或最后候选 valid 代替。公共 `o_dummy_request_accepted`、`o_dummy_busy`、`o_dummy_done_*` 供观察真实边界。

`o_normal_retire = i_complete_valid && o_complete_ready && !o_complete_discard`。同沿 Isolation/LinkDown 优先于真实正常完成；隔离后正常完成被消费、标记 discard，不销 pending，不传为 normal_retire。这里过滤的是**可信完成通知**，不是尚未接入的 native RX Response/Data payload；实际 RX 路由与 Tag 所有者仍需接入此决策。

恢复沿继续要求账本全部空、外部 quiescent、全实例 link_up/init、外部 Drop 清零、无同时登记/完成事件，并精确递增 epoch。最后响应握手当沿、其后的 done 当沿均不能提前恢复。epoch 达最大值后拒绝回绕，仍保持 Isolation。Switch 的恢复仍是保守全实例 epoch 边界，不是逐端口独立恢复。LinkDown→Isolation 是原候选明确采用的本地策略。

## 验证、证据与复跑

独立 Python 字典义务模型和应用响应事件模型不读取 DUT 内部；SV 下降沿施加向量并比较全部公开位，上升沿提交。先保留缺少集成模块及缺少生成器的两个真实 elaboration RED。正常/-O 的完整矩阵均为 PORTS1/2/4 × CAPACITY1/2/3/4 × IS_SWITCH0/1 的 24 个真实集成配置，加独立生成器单元。单元额外覆盖非法描述符、全部 Read Beat 数、Write、请求和响应反压、done 反压、请求被反压时字段变化、在途 reset。

最终 `release` 与 `release_optimized` 每次 25 个正常配置共 26,512 时隙，其中 24 个集成配置 25,452 时隙：2,393 登记、80 正常完成、2,262 dummy 请求、5,368 个 Read Beat、72 个 Write 完成、2,191 次实际 dummy_done、3,795 次迟到/未知完成丢弃观察；122 义务在明确共同 reset 时取消。独立生成器另 1,060 时隙、129 次 done 反压观察。普通/-O 向量逐字节一致。

11 项真实源码/接线注错要求 compile=0、runtime=1 且出现 `DUMMY_CHECK`：第一拍提前 done、无 ready 也推进、Tag 高位丢失、Offset 错步进、Last 提前、epoch 丢失、port 接零、request 直接当 done、迟到正常完成误退休、实际 Data 错位值、done 忽略反压。故障没有替换 golden，也没有以 compile 失败充当故障检出。

每个正常配置均执行 Icarus `-g2001`、Verilator `--language 1364-2001 -Wall`（无豁免）、Yosys `proc; opt; memory_map; check -assert`。另从 `/tmp` 实际运行默认 8 位 epoch 的生成器及 4端口/4槽/Switch 集成，达到最大 epoch 后拒绝回绕；8 个非法参数展开均失败。

技能 artifact gate：生成器 69 行零问题；完整三模块原文按顶层在前拼接的审核 bundle 260 行零问题。最初把纯层级 wrapper 当独立时序叶模块出现 clock/reset 适用性误报，及模块目的注释检查失败，原结果保留；仅补模块说明注释后以真实完整层级复核，未伪造 wrapper 自身时序，也未豁免实际 lint。整个 skill 自测脚本会写出隔离目录，本轮未执行，不声称整个 skill 自测通过。

最终源码测试命令（仓库根）：

```sh
python3 -B build/development/ras_isolation_completion/release/verification/ras/run_dummy.py --label release --faults
python3 -B -O build/development/ras_isolation_completion/release/verification/ras/run_dummy.py --label release_optimized --faults
python3 -B build/development/ras_isolation_completion/release/verification/ras/run_dummy.py --label release_epoch --case 4 4 1 --epoch-width 8
```

这些标签保留证据不能覆盖。再次运行使用新 label。精确时隙数、真实响应/销账计数、工具命令和返回码、源文件与所有产物 SHA 在 `freeze.json` 和每个 `result.json` 中；`first/frozen/final` 等较早标签按各自源码和测试快照保留，不冒充最终冻结哈希。

可安装副本：`release/rtl/ras/{ras_dummy_completion.v,ras_isolation_completion.v}`，`release/verification/ras/{run_dummy.py,dummy_tb.sv,dummy_reference.py}` 和本文。还附带字节不变的上一阶段依赖 `release/rtl/ras/ras_originator_isolation.v`（SHA `0eff06a6996741141a1e54ce637108de0859cb9d0e01d5f34a6bcbd752ddeb67`）；不能与同名旧壳同时编译。安装后的 runner 只从 `ROOT/rtl/ras` 读取实际源码，ROOT 是 `Path(__file__).resolve().parents[2]`，可用 `--ledger` 显式指定账本副本。

```sh
python3 -B verification/ras/run_dummy.py --label REVIEW_NEW --faults
```

输出为 `ROOT/build/verification/ras/dummy/LABEL` 内源码快照、完整向量、编译/运行/静态日志、映射网表、结果 JSON。可以从任意 cwd 使用入口绝对路径；不需要 development 目录、私有规范或 PDK 才能复跑。

## 尚缺的系统接入

本轮“真实集成”仅指候选账本→生成器→本地应用握手的实际三模块层级。尚未接 Endpoint/Switch 顶层、应用 normal/dummy 完成仲裁、真实 Tag 分配/释放、native RX payload 过滤、UPLI 信用、停止在途 burst、管理恢复协议或物理 Link 恢复。

外部事务所有者仍须保证登记与请求接纳原子一致，并过滤同 epoch 槽复用后的旧完成别名；当前完成身份只有 slot+epoch，不是完整防重放 token。共同 reset 必须清除旧系统事件，epoch 不是跨 reset 持久化状态。生成器自己不认证 Tag/源端，也不执行软件恢复。没有生成 Drop，没有把握手预约说成完成，没有证明 full IP、STA、互操作或认证。
