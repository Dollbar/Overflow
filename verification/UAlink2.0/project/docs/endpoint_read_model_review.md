# 独立普通 Read 参考模型复核

新增 `model/ualink/endpoint_read.py`、`verification/endpoint_transaction/test_read_model.py` 和 [机器可读契约](../config/endpoint_read_contract.json)。规范依据与已知 Multi-Beat Header LAST 歧义见 [普通 Read 契约复核](endpoint_read_contract_review.md)。未修改任何 RTL 或旧模型，没有调用 RTL helper、旧事务模型或新 Write 模型计算结果。

模型覆盖普通未压缩 CMD03 的完整57位地址、11位Tag、10位ID、全部合法4..256B DWORD几何及任意ATTR/ASI/metadata；当前本地profile为VC0/VC-credit。`byte_masks` 分别返回整个256B区域mask、以请求首个自然64B Beat为原点的relative mask、N。LEN0完全忽略ATTR高nibble，中间DWORD全部使能，零BE不减少结构Beat数。请求codec按真实128位布局编解码，Read NUMBEATS必须为零；CLOAD不支持，CLOAD0时忽略无效CWAY。

`memory_read` 表示一次真实后端结果语义事件，返回不可变内存对象（执行计数加一）、N个完整自然64B响应事件及上述mask。成功原始响应保留映射内所有lane，包括被屏蔽的非零数据；每Beat的lane0仍对应其自然地址，不把请求首byte压到lane0。状态0/2/3/6/8全部返回原定N Beat，错误Data可为全零或全FF。后端按整个DWORD区间检查映射、显式错误优先于本地decode，是本地策略；它没有模拟请求接受到完成的周期时序。

`ReadResponse` 是一个重建后的Beat事件。`ReadCollector` 按(port,tag)保存请求、实际发送状态、模式、统一status、已收OFFSET和完整数据。Single-Beat允许任意OFFSET顺序和跨Tag交织，LAST仅属于最后到达的Beat；Multi-Beat要求完整N、OFFSET0..N-1、最后LAST且同port burst不交织。`decode_response_burst` 消费严格完整的TL LEN+1个Data Beat，重建Multi事件OFFSET/LAST，忽略该模式原Header的无效OFFSET及尚未澄清的LAST归约。发送codec与内存模型统一采用Single-Beat。未知、未sent、重复、越界、模式/状态改变、提前或缺LAST等事件拒绝且不改已保存状态；响应SRC仅用于调试，不参与功能身份匹配。

完成槽在应用`retire`前保持稳定并占用容量。应用输出采用明确的masked-zero策略：成功无poison时只保留relative mask内的数据；任何错误或poison均抑制整个事务应用数据/valid_mask，仍保留requested_mask、status、N和独立poison bitmap。这是保守的本地API策略，不是要求线上无效lane或错误Data恒零。reset清除模型所有权；合法重用相同Tag后无法仅靠Tag辨认陈旧响应。

复现入口：

```sh
python3 verification/endpoint_transaction/test_read_model.py --label NEW_NORMAL --faults
python3 -O verification/endpoint_transaction/test_read_model.py --label NEW_OPTIMIZED --faults
```

每个新label写入 `build/verification/endpoint_transaction/<label>/`，包含实际候选源与测试快照、日志、覆盖分母、优化级别、4个隔离变异源和子进程命令、逐文件SHA256。已存在label拒绝覆盖；诊断用显式异常与unittest断言，生产模型不依赖可被`-O`移除的assert。

| 最终证据 | 测试 | 几何/ATTR掩码对照 | 独立内存场景 | 四Beat排列 | 实际源码故障 |
|---|---:|---:|---:|---:|---:|
| `ordinary_read_model_final` | 11通过 | 532480 | 120 | 24 | 4/4检出 |
| `ordinary_read_model_optimized` | 11通过 | 532480 | 120 | 24 | 4/4检出 |

掩码分母为全部2080合法DWORD起点/LEN组合×256 ATTR；另检查全部2016非法几何，未声称非法几何也逐一遍历256 ATTR。oracle从自然字节位置枚举首/末DWORD与中间字节，模型使用独立nibble算术。数据结果另有代表场景，包含区域128/192、跨Beat、bit56、全零/稀疏/完整使能、成功与错误全N Beat。四Beat全部24排列与跨Tag、相同Tag跨port、应用保持、复位、Multi2/3/4以及非法事件原子性有独立断言。请求3个、五状态响应5个固定raw literal来自独立位段worksheet，不用模型roundtrip生成expected。

四类模型变异为LEN0错误合并高nibble、把自然lane压到请求地址、错误状态提前完成、放行重复OFFSET。两运行模式下每个变异均在独立子进程真实执行，分别产生1个断言失败、0个测试框架错误，返回1；没有伪造失败结果。初始 `ordinary_read_model_red` 中，当时的10项测试均因模型尚未实现而失败。`ordinary_read_model_initial` 保留一项测试预期错误：将高地址设为64B对齐却期待两个Beat；改为真实跨界的高地址+60后重跑通过，未修改旧证据。

冻结SHA256：

- 模型：`8a3eb318957c14597dcd34871070824396b97c6767b98b01907a83829bee576e`
- 测试：`2edb490933f5cb5bc70a114943f7c90c571f0b83419a46b49cc32105a0861c27`
- 契约：`ab582529820b3b8f7a1d32de648b8fdd172c5d86a87915ee1107b404bbfbd19e`

两套最终证据及所有变异子进程的源/产物hash逐项复核一致，Python语法和JSON解析通过。该模型不模拟完整TL/DL credit、framing、重放、coherence或共享Read/Write Tag分配，不等于RTL验证或协议认证。下一步将独立byte/事件oracle与实际Endpoint路径、接收两种响应方式和恢复场景对照。
