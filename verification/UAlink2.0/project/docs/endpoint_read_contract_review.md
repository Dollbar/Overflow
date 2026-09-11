# 普通 Read 完整长度实现契约复核

本轮只读核对本地 **UALink Common Specification Rev 2.0**，不修改 RTL、模型或既有契约。以下为实现释义，不复制私有规范正文。页码均为规范印刷页码；本地提取文件 `specs/private/common.txt` 的 SHA256 为 `15cd742c536e1e701a958db8a04f54666b072b8d95a72a834b0aa7d2c58e3383`。目标是普通单播 Read CMD=03 的全部合法长度与响应方式，不能把既有 single64B 子集称为完整 Read。压缩、安全、UPLI 接口及其他命令的实现状态须另列，不因扩展普通 Read 自动完成。

## 请求几何与字节语义

依据 §2.7.4、Table 2-2（pp49–52），§2.7.4.4–6、Table 2-7（p55），§2.8（pp74–75）：

- 地址保留 57 位，低两位必须为零。`S=4*(LEN+1)`，LEN 为 0..63，覆盖 4..256 byte 的 DWORD 包围区间；不能把 LEN=0 解释成零长度。
- 合法边界为 `(ADDR mod 256)+S <= 256`。该条件针对整个地址/长度区间，不能因为首尾 BE 为零而放宽跨界条件。64 个 DWORD 起点 × 64 个 LEN 中有 2080 个合法、2016 个非法组合。
- `N=ceil(((ADDR mod 64)+S)/64)`，范围 1..4。Beat 0 对应 `BASE=ADDR & ~63`，Beat k 的 lane b 对应地址 `BASE+64*k+b`。地址低六位不为零时，不得把首个有效字节压到 lane 0。
- ATTR[3:0] 是首 DWORD 的四个 byte enable；LEN>0 时 ATTR[7:4] 是末 DWORD 的四个 byte enable。LEN=0 **完全忽略 ATTR 高四位**，不能将两个 nibble 相与。中间 DWORD 的全部字节有效。
- 对地址 A，若不在 `[ADDR,ADDR+S)` 则无效；若属于首 DWORD，取 ATTR[A mod 4]；否则若属于末 DWORD，取 ATTR[4+(A mod 4)]；其余有效。这一分支顺序同时处理 LEN=0。
- 规范未要求这些 BE 非零或连续，不能自行拒绝稀疏/全零 nibble。LEN=0、低 nibble=0 仍有一个结构上的响应 Beat；LEN>=2 时即使 ATTR=0，中间 DWORD 仍有效，不能把 ATTR=0 一概解释为无数据访问。
- 被 ATTR 屏蔽或超出区间的返回 lane 无效，Originator 必须忽略；这些 byte 仍参与链路/UPLI 数据保护计算。规范不要求无效 lane 恒零，测试必须扰动它们以防全字比较误拒绝。实现可在应用输出处规范化为零，但这是本地 API 选择。

Read 请求的 NUMBEATS 为零，不能填返回 N-1；返回 Beat 数由地址和长度计算。§5.9.1、Table 5-29（p137）中普通请求仍为 128 bit：FTYPE[127:124]=1、CMD[123:118]=3、VC[117:116]、ASI[115:114]、TAG[113:103]、POOL[102]、ATTR[101:94]、LEN[93:88]、METADATA[87:80]、ADDR[79:25]=地址[56:2]、SRC[24:15]、DST[14:5]、CLOAD[4]、CWAY[3:2]、NUMBEATS[1:0]。CLOAD=0 时 CWAY 无效。ASI 和 metadata 为实现定义信息，应完整传给后端；固定零限制属于旧实现子集。TL POOL 与 UPLI POOL 信用含义独立，不能直接混同。

## 响应方式、状态与退休

依据 §2.7.5、Table 2-15（pp62–64），§2.7.5.1–3、Table 2-16（pp64–65），§2.7.8（pp71–72），§2.8（pp74–75）：

| 方式 | 传输规则 | 接收必须检查 |
|---|---|---|
| Multi-Beat | 同一事务的 N 个 Beat 按 OFFSET 0..N-1 顺序连续返回；UPLI NumBeats=N-1 对各 Beat 相同，最后 Beat 才 Last | 不能遗漏、重复或跨事务挪用 Data；一个 TL Header 对应 2*N 个 Data 半 Flit |
| Single-Beat | 每个响应 Header 对应一个 64B Beat，NumBeats/LEN=0；OFFSET 可按任意顺序到达，允许间隔和其他事务交织 | 每 Tag 收齐全部 N 个不同 OFFSET；最后到达的 Beat 才 LAST，不以 OFFSET==N-1 判终止 |

两种模式可由 Completer按事务选择；一 Beat 请求时二者相同。规范未授权将一个普通请求拆成任意的“2 Beat burst + 2 Beat burst”，也未授权中途混用两种模式。发送方最直接的实现可以统一选 Single-Beat，仍支持全部长度；完整普通 Read 接收方应同时理解 Multi-Beat 和 Single-Beat，不把乱序单 Beat 当非法。

普通 Read 合法状态为 0=OKAY、2=TARGET ABORT、3=DECODE ERROR、6=PROTECTION VIOLATION、8=CMPTO。14 是特定 INC 的混合结果，不属于普通单播 Read；其余保留值不得当普通成功或错误完成。整个事务的各响应 Beat 必须状态相同，即使按 Single-Beat 分别传输也不能逐 Beat 改状态。

**任何非零合法错误状态仍必须返回全部 N 个 Beat并结束。** 没有可用数据时可制造数据，规范建议全 FF；该图样不是接收合法性条件。Originator 不得缓存错误返回的数据或据此改变成功缓存状态。不能在第一条错误 Header、第一 Beat 或后端 ready 时提前释放 Tag；错误并不缩短 TL Data tenure。

DataError/poison 与 STATUS 独立。DataError 可逐 Beat 不同，用于数据完整性错误；正常的地址/权限/超时错误本身不要求 DataError=1。§5.3（pp114–115）要求损坏标识随对应 Data Half-Flit 传递到最终接收者。完整实现应保留逐 Beat poison，或明确声明尚未实现该能力；全局 fail-stop 拒绝所有 DataError 不是完整 poison 支持。两半组成一个 Beat 时，任一半损坏都必须影响该 Beat，不能被下一 Header 的状态覆盖。

§2.7.4.2（p52）禁止在最后响应 Beat 收到前重用 Tag；Table 2-2（p49）规定同端口的所有命令共享 Tag 空间。实现应保存 `(port,tag,kind)` 所有权、已实际发出标记、N、原地址/BE、已收 bitmap、统一 status、完整数据及 poison。只在合法最后 Beat 到达且 bitmap 恰好覆盖全部 N 位后标记事务完成。提前 LAST、重复/越界 OFFSET、漏 LAST、跨 kind、未知/未发送 Tag、错误目的 ID、状态不一致不得产生成功退休。响应 SRC 是 debug 信息（p62、Table 5-30），不能用于功能身份匹配。

应用反压期间可继续保留已完成槽，等应用握手才释放 Tag；这比规范最早允许重用时刻更保守，合法且便于保证稳定输出。请求接纳时应预约足够结果容量，使响应接收不依赖对端处理另一事务（§2.7.8 p71）。不同 Tag 的响应可重排；非严格模式的 Read/Write 响应之间也无顺序保证（§2.7.9 pp72–73）。不能用全局请求 FIFO 顺序代替响应 Tag 匹配。当前共享后端串行派发可以保留，但它不是协议强制的唯一微架构。

## 普通 TL Response 编码与一个待确认点

§5.9.2、Table 5-30（pp138–139）：FTYPE[63:60]=2、VC[59:58]、TAG[57:47]、POOL[46]、LEN[45:44]、OFFSET[43:42]、STATUS[41:38]、RD_WR[37]=1、LAST[36]、SRC[35:26]、DST[25:16]、RSPTYPE[15:14]=0，SPARE[13:0] 发零。DST 是原请求 SRC；响应 SRC 可取原请求 DST，仅供调试。普通 Read Response 每 Beat 都有完整 64B Data，不附 Write 区域 BE 半 Flit。

Single-Beat Header：LEN=0，OFFSET 为相对请求的 Beat 编号，LAST 为最后实际发出的 Beat。Multi-Beat Header：LEN=N-1；OFFSET 对该模式无效，发送建议零，接收不能以非零无效 OFFSET 拒绝合法数据。TL 按 burst 长度重建 UPLI OFFSET。

**待确认：未压缩 Multi-Beat Header 的 LAST 归约。** Table 5-30 只描述携带 UPLI Last，未明确把一个 burst 的首 Beat Last=0 还是末 Beat Last=1 放到唯一 Header；§2.7.8 已明确 UPLI 末 Beat Last，Table 5-12（pp113–114）的布局示例没有给该位值。不能把未经确认的 0/1 约定写成规范必需检查。直接可行的发送选择是 Single-Beat；接收 Multi-Beat 时按 LEN 重建最后 Beat，避免把此未明确定义的 Header 位作为额外拒绝条件，并把该解释列入后续原文澄清项。该点不允许据此放宽 Single-Beat 的 LAST 完整性检查。

§5.9.1/2 允许使用未压缩形式表达所有合法请求/响应，因此完整普通 Read 不要求为了长度扩展而新增压缩发送；接收压缩及地址 cache 仍需按其独立能力边界实现，不能把未实现压缩算作整个 TL 完成。

## 当前实现差距与最直接落地顺序

| 当前模块 | 已核对差距 | 必须衔接的改动 |
|---|---|---|
| `endpoint_read_encode` | 仅 64B 对齐、LEN15、ATTR FF、零 ASI/metadata | 全几何检查与任意 ATTR；保留完整字段和 Read NUMBEATS=0 |
| `endpoint_response_encode` | 仅状态0/3、LEN0/OFFSET0/LAST1 | 五状态；Single-Beat 任意合法 OFFSET/LAST；Multi-Beat 描述符边界明确 |
| `endpoint_read_originator` / `endpoint_request_formatter` / `endpoint_tag_table` | 共享 Tag 已存在，但每槽仅 512b，无请求 N/BE 与 seen bitmap，单响应即 done | 预约全事务结果、跨 Beat 聚合与逐 Tag 状态/poison；保留 Write kind 和原实际发送边界 |
| `endpoint_receive_transactions` / `endpoint_response_assembler` | 两种 WRITE_ENABLE 分支均有旧 Read profile；assembler 每两个半字就弹出一个 Header | 按 Header LEN 保存 2..8 半字 tenure，逐 Beat 标号；请求 Read 放开全几何，Read Response 放开五状态和分片；仍整字预检、按真实 Data owner 分配 |
| `endpoint_read_completer` | 请求仅固定64B，后端一次512b，结果仅0/3，每请求一 Header 两半字 | 保存完整请求，后端真实完成携带完整 N Beat数据或明确的有序结果流；回包序列化全部 Beat，错误同样全部发送 |
| `endpoint_transaction_core` / `ualink_endpoint_top` | 后端 Read result 和应用完成均只有512b；dispatch合法结果检查沿用0/3 | 扩展至完整事务数据/有效字节/poison或明确流式接口；真实结果完成与逐 Beat应用接纳分离，旧默认端口兼容须显式设计 |

现有 `tl_control_tenure` 已按未压缩 Response LEN 计算 `2*(LEN+1)` 个 Data 半 Flit；不能只修改 Endpoint Header 编码而仍让 receiver 每两个半字换 owner。组装队列在早先 Header 尚未收完 Data 时必须保留所属 Header；Control 中的新 Read/Write 请求及 Response 不能窃取旧 burst 的尾 Data。实际 TL/DL 是否在全部混排情况下维持这一计数，需要新增真实路径向量证明，不由此次静态阅读声明通过。

建议先固定接口：若继续采用“一次接纳完整结果”，后端和应用提供 2048-bit 数据、N、256-bit 有效字节 mask 及逐 Beat poison；数据按相对 BASE 的四个自然对齐 Beat 排列，不进行有效字节压缩。其 mask 的 bit0 对应 BASE，与 Write 的整个 256B 区域 BE 原点可能不同，命名和测试必须区分。其次独立模型/字节 oracle先覆盖全几何与 ATTR；再实现 Tag 聚合、completer、receiver；最后连 core/top 跑双向 Read/Write 后端因果、实际 TL/DL 和恢复测试。发送先统一 Single-Beat 是完整长度实现选择，不能作为接收不支持 Multi-Beat 的理由。

## 必须保留的独立向量

1. 全部 4096 起点/LEN 判定；每个合法几何计算 N 和有效 lane。高地址 bit56、高 Tag bit10、高 ID bit9，边界 252/LEN0 合法、252/LEN1 非法、0/LEN63 合法。
2. LEN0 遍历全部 ATTR，固定低 nibble 后改变高 nibble不改变有效字节；LEN1 分离首末 nibble；LEN>=2 验证中间 DWORD。首末稀疏、全零低 BE、无效 lane 随机值不得污染应用数据。
3. 地址60/LEN1：两 Beat，仅 lane60..63 与 lane0..3；先 OFFSET1/LAST0，再 OFFSET0/LAST1 应合法完成。四 Beat 全排列、跨 Tag 交织，以及早 LAST、重复/缺失/OOB OFFSET 和状态翻转均有独立断言。
4. Multi-Beat LEN1/2/3 的 4/6/8 个半 Flit、Control/Data 跨字、旧尾与新 Header 同字、FC/MSG 插空、不同事务回压；每半数据用不同值防交换、丢失和重复。
5. 五状态×N1..4；错误第一 Beat后不得完成，完整错误传输后只报错误完成。制造数据全零/全FF均可，DataError独立；第一个/最后一个 Data 半字 poison 的归属必须正确。
6. 请求握手、真实 Header 发出、后端接纳、真实执行结果、最后响应 Beat与应用退休分别计数；全事务结束前同端口 Read/Write 重用 Tag必须拒绝。结果反压、容量满、统一在途 reset 不得让旧 Beat写入新Tag。

没有进行 RTL 修改、模型生成、仿真或形式证明。本文件结论为规范契约与静态差距，后续测试应在冻结源码上建立新的红/绿证据。
