# Endpoint 接收事务组装契约审查

结论：当前接收栈提供足够的真实 payload、类别及释放元数据，可实现未认证、未压缩、单 64B Read/Read Response 接收子集。必须保留完整记录、按字段顺序保存响应描述符，并跨记录组装 Data。新 Control 与旧响应最后半字同字出现是正常序列；普通 Message 与 Poison 对 Data 序列的作用不同，不能混用。

本次只读 RTL/规范与既有接口说明，仅新增本文；不以旧 fixture 推断协议，不运行 STA 或大规模证明。此文是编码前契约审查，不是新 receiver 的功能通过报告。

## 依据

直接读取 Common 2.0 本地正文 `specs/private/common.txt`，SHA256 为 `15cd742c536e1e701a958db8a04f54666b072b8d95a72a834b0aa7d2c58e3383`。语义来源为 §5.1.1、Tables 5-1/2（半 Flit 和自然对齐），§5.1.2、Tables 5-3/4（Message），§5.3（Poison），§5.7（打包约束），§5.8、Tables 5-27/28（类型），§5.9.1/2、Tables 5-29/30（未压缩字段）。本文只记录工程解释，不复制规范表格。

实际连接核对覆盖 `tl_receive_credit`、`tl_receive_storage`、`tl_receive_context`、`tl_sequence`、`tl_full_flit`、`tl_content`、`tl_atomic_admission`、`tl_packing_budget`、`tl_control_decode`、`tl_control_tenure` 与 `ualink_endpoint_top`。

## 保存记录与握手

`tl_receive_storage.write_word` 的实际布局为：

```text
[599:520] releases[79:0]
[519:517] upper class
[516:514] lower class
[513:512] msg[1:0]
[511:256] upper half
[255:0]   lower half
```

所以 receiver 输入 `classes[2:0]` 对应 lower，`classes[5:3]` 对应 upper；先处理 lower，再处理 upper。`msg[0]`、`msg[1]` 分别是两个半字的 Message 标志，类型取各半最低字节 `[7:0]`、`[263:256]`。msg 不是事务类别，也不是 Data 有效位。

`tl_receive_credit.o_read_valid = storage_valid && release_ready`，底层 read_ready 同时受发布器 release_ready 门控。因此 top `o_read_valid && i_read_ready` 正好是保存字退休与真实信用归还接纳事件。receiver 必须在该事件原子保存全部 600 位，不能先接收 payload 后补取元数据。退役后不再依赖源总线保持。单个 holding 满时撤销 ready；下游有效但未接纳的描述符和完整响应必须保持稳定。

releases 是 20 个四位计数槽，属于资源归还，不包含 Tag 或地址。依次为 Request CMD、Response CMD、Request Data、Response Data 四组，每组为 Pool、VC0..VC3。本 profile 的 Read CMD 是 slot1；Response 最后一半 Data 所在记录通常同时含 slot6 的 CMD 和 slot16 的 Data 归还；同字多字段会累计。它已经交给真实 publisher，receiver 不得再造一次释放，也不能据此推断哪条 Tag 完成。

`o_store` 仅保存事务需求或 Data/BE/Poison 内容，纯 FC/NOP/普通 Message 可以不进 SRAM。退休记录不是每个线上 Flit 的完整日志，不能以“收到一条记录”重新推进线上打包预算；分类应消费保存的实际 classes，所有权由本地已解析事务维持。

## 类别与消费动作

以下 3 位数值是当前 RTL 的内部编码，不是新增标准线字段。

| class | 含义 | 单 64B Read receiver 的动作 |
|---:|---|---|
| 0 | Control | 只允许 lower；按实际字段起点解析 |
| 1 | Data | 消耗最早未完成响应的一个 256 位半字 |
| 2 | Byte Enable | 本子集不支持；锁存诊断并停止继续归属 |
| 3 | Mandatory NOP | 无事务、无 Data 消费；整个半字应为零 |
| 4 | 普通 Message | msg 必须为 1，当前只支持 type 0/1；不消费 Data |
| 5 | Poisoned Data | msg=1、type=0x20；实际替换并消费 Data，不能当空隙跳过 |
| 6 | AuthTags | 本子集不支持；在暴露该字请求前阻断 |
| 7 | 非法/无有效分类 | 有效记录中出现时阻断 |

非 Message 类别的 msg 应为 0。当前上游已检查 mandatory NOP 内容、消息类型与 Poison 成对；局部接口的错误注入可再次检查这些约束，但不能把上游已保证条件误写为 receiver 新创造的协议规则。

Poison 对应一个 64B Beat 的两个半字，可能跨物理 Flit且中间插普通 Message。其余 31 字节未定义，不应拿来构造成功数据。首版若无 DataError typed 输出，可以在 class5 锁存 `o_fatal`、抑制尚未完成响应并停流至统一复位；这是本地不支持策略，不是对规范合法 Poison 的通用接收实现。不能跳过它后将下一条响应的数据拼到上一条 Tag。

## 字段起点、profile 与顺序

Control 的 sector0 是最低 32 位。`tl_control_decode.o_field_starts` 包含 FC/NOP 起点，事务必须结合 `o_request_starts/o_response_starts` 与完整 FTYPE 检查。未压缩请求起点只能是 sector0/4，FTYPE 位于其第四个 sector 的高四位；响应起点只能是 sector0/2/4/6，FTYPE 位于第二个 sector 的高四位。不能读起点 sector 高四位就决定整个字段长度，也不能把请求 payload 内看似 FTYPE 的位解析为新字段。

FTYPE0 是 FC/NOP，允许非零信用信息，不能要求每个这种 sector 全零。FTYPE1/CMD3 是本次 Read；FTYPE2 且 RD_WR=1 是候选 Read Response。压缩请求/响应、Write、Atomic 等即使结构和 tenure 合法，也不属于本次支持子集。不得忽略其 header 后继续消费 Data。

Read 需要检查 CMD3、VC0、POOL0、ASI0、LEN15、ATTR FF、metadata0、完整地址 64B 对齐，并输出完整 Tag11、SRC10、DST10、ADDR57（线上 55 位地址补低两位零）。CLOAD1 涉及地址缓存，本阶段应报告未支持；CLOAD0 时 CWAY 没有有效语义，接收时忽略其值合理。Read NUMBEATS 对 CMD[5]=0 不描述响应长度；若首版要求它为零，应标明局部 profile 限制，不能宣称所有非零值都是标准非法。

Response 需要检查 VC0、POOL0、LEN0、OFFSET0、STATUS0/3、RD_WR1、LAST1、RSPTYPE0，保留完整 Tag/SRC/DST。SPARE[13:0] 未分配，不能从发送器恒零策略推导接收时必须零；SRC 只保留给调试，活跃 Tag 和本地 DST 的匹配属于 originator。`tl_control_tenure` 的 RD_WR0 响应会合法产生零 Data，故仅靠它不能识别本次 profile。

Data 按所属 Control 的数据字段起点从低到高排列，没有自己的 Tag/VC/POOL。第一半写到响应 `[255:0]`，第二半写 `[511:256]`；完成值为 `{second, first}`，与两个半字到达时分别在物理 lower 还是 upper 无关。STATUS3 不减少 Data 需求，也不等于 Poison。

当旧 tenure 仅剩一个半字时，下一记录 lower 可以包含新的 Control，upper 则承载旧 tenure 的最后半字。应先在旧描述符之后追加新响应，再将 upper 分给最早待完成描述符；绝不能先用新 Control 重置 pending 响应。新 Control 的零 Data Read 不影响旧响应组装。

## 可立即实现的有限状态与接口

推荐输入为 `i_valid/i_flit[511:0]/i_msg[1:0]/i_classes[5:0]/i_releases[79:0]` 与 `o_ready`，时钟/复位同 top。typed 输出为带 ready/valid 的请求描述符和带 ready/valid 的完整 512 位响应；请求保留地址及 profile 字段，响应保留 Tag/SRC/DST/status/offset/last/num_beats，另输出 sticky fatal 与明确诊断原因。可选捕获/释放向量观察只用于审计，不产生第二次信用事件。

最小控制可分 `EMPTY → CHECK → LOWER → UPPER → EMPTY`，错误进入 `FAULT`，输出寄存器及响应 FIFO 独立持有：

1. EMPTY 的输入握手保存整字。CHECK 预检查两个类别、msg、结构与本字所有事务 profile，再允许本字任何请求/响应对外可见。这样不会先发 lower 的有效请求，再发现 upper 的不支持认证或本字后部的未知字段。
2. LOWER 遇 Control，以递增 sector 游标处理字段；无数据 Read 送请求保持寄存器，Response 按顺序追加 FIFO。普通 Message 不推进 Data。合法 Data 则服务 FIFO 队首。
3. UPPER 同样处理 Data/NOP/Message，但不允许新非 NOP Control。一个 Data 事件只推进半字标志一次；完成输出占用时停在当前事件，不重复消费、不覆盖输出。
4. 两半及全部 Control 字段均已有本地所有者后清 holding。FIFO 队首可跨多个记录保持半字状态。FAULT 清除或隔离未发布结果，停止新输入和新事务输出，统一复位恢复；不能仅清 pending 然后继续同一线上流。

响应描述符不能只有一个槽。全 256 位 Control 可放四个未压缩响应，旧响应还可能有最后半字等待，所以“先追加全部新 header，再处理 upper”调度需要容纳五个描述符，简单深度8可用。若只有四槽，必须设计能先处理旧 upper 或分阶段保留未入队字段的调度；否则 FIFO 满会阻止处理负责释放旧槽的同字 upper，形成永久自锁。完成输出占用时也必须纳入容量预检查。

单 holding 顺序发请求会产生请求对响应的队头阻塞。若请求下游保证最终 ready，局部可有界排空；真实双向闭环则需预留 completer 请求容量，或将同字请求/响应独立暂存，避免请求服务等待返回响应、响应却被请求背压堵住的循环。局部背压测试不能替代这项端到端资源论证。

## 必须独立构造的定向向量

使用不同 Tag、非对称 SRC/DST、高地址及不同 Data 半字；期望按规范位位置人工构造，不通过待测编码器往返生成全部 oracle。

| 场景 | 预期检查 |
|---|---|
| 两个 Read 分别位于 sector0/4 | 两次请求、顺序正确、完整地址/Tag；payload 伪 FTYPE 不另生字段 |
| 单 Response 分别位于 sector0/2/4/6，FC 穿插 | 四种合法定位；FC 非零不产生请求/响应 |
| 四 Response 同一 Control | 四个独立完整结果，数据按低起点到高起点归属 |
| `lower=RspA, upper=A0`；下一字 `lower=Req0+Req1, upper=A1` | 新请求与旧响应均保留，A1 仍归 A；至少对每个输出施加停顿 |
| A 仅剩最后半字；下一 lower 含四个新 Response | 最大五描述符场景，无覆盖、无内部容量自锁 |
| Data/Data 物理两半及跨字组合 | `{second,first}` 正确，完整512位无交换；Data 位型像 header 也不重译码 |
| type0/1 Message 插在两 Data 之间，或 lower MSG+upper 旧尾 | Message 不消耗半字，最终仍只完成一次 |
| STATUS3 普通 Data 与成对 Poison 分开测试 | 前者完整收齐并保留错误状态；后者不得完成成功结果 |
| 压缩/Write/非法 profile 后接合法 Response Data | 首次未支持即停流，后续数据不会错配到旧或新 Tag |
| 合法 lower 请求+upper AuthTags/Poison，或后部不支持字段 | 预检查阻止本字部分事务先对外发布 |
| 无响应描述符的 Data、类别/msg 不一致、upper class0、非零 mandatory NOP | 明确诊断并停止，不静默忽略 |
| holding/req/rsp 任意有限停顿与同步复位 | 输入仅捕获一次、源退休一次；输出稳态、无重复、复位无残留半字完成 |
| 非零 Response SPARE、CLOAD0 且非零 CWAY | 不凭发送端常量策略误报标准非法；采用更窄本地限制时明确标注 |

至少注入一次实际半字交换、错 header 出队或提前完成、字段高位截断、重复退休/消费故障，要求独立数据与事件检查失败。接入真实 `tl_receive_credit/storage` 后还应监视 `retired == release_taken == receiver_capture`，并以非零且各不相同的真实 release 元数据验证整字保存，没有伪造或重复信用归还。
