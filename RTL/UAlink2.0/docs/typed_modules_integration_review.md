# 首批 typed 模块独立集成审查

审查结论：三个新实现与库存、角色聚合和当前调用关系一致；在已声明的输入契约内，未发现阻止本次局部功能增量发布的 RTL 缺陷。编码器尚未接成真实 Read 因果事务，pending 位清零不能解释为事务功能完成。审查未修改生产 RTL、库存或聚合文件，没有重跑 SRAM 大规模证明，也不提供工艺 PPA 结论。

## 源码、库存与位图

核查对象为两个 Endpoint 编码器、Switch lookup、提取前后的 `ualink_switch_top`、生成器与结构检查器，以及字段/lookup/Switch 测试入口。已阅读 [字段实现评审](endpoint_fields_review.md)、[独立字段规范审计](endpoint_fields_audit.md)、[查表实现评审](switch_route_lookup_review.md)、[骨架生命周期](ip_scaffold_interface.md) 和 [增量证据说明](typed_modules_progress.md)。

| 模块 | 保留槽位 | 当前功能连接 | 审查范围 |
|---|---|---|---|
| `endpoint_read_encode` | Endpoint 11 | 尚无生产父模块 | 单 64B Read 组合字段生成 |
| `endpoint_response_encode` | Endpoint 12 | 尚无生产父模块 | status 0/3 普通单 beat Read Response 组合字段生成 |
| `switch_route_lookup` | Switch 53 | `ualink_switch_top.u_route_lookup` | 完整 10 位 ID、唯一 enabled 目标匹配 |

当前库存为 202 项：60 `existing_partial`，142 `planned`。三个晋升项都保留原 `feature_slots`，typed 接口未接到旧 generic-service 端口；两个编码器的 `actual_integration_parents=[]` 与现实一致。lookup 对动态路由、vPod 和 INC 的缺口另有明确说明，不能把库存中的未来职责当成本次已实现接口。

结构证据 `build/verification/ip_structure/typed_modules/evidence.json` 对应当前库存哈希，记录 202 个实际声明、142 个壳；Endpoint 107 个壳实例，位图 `00001fffffffffffffffffffffffe7ff`；Switch 126 个壳实例，位图 `7fffffffffffffffffdfffffffffffff`。本次重新计算其中 204 个 RTL/聚合源哈希，全部一致。该证据明确 `functional_completion=false`。

位图中置位表示未实现壳仍存在，清零只表示该壳晋升或该位未分配。当前仍是部分实现的模块会有零位，因此软件或文档不能用 `pending==0` 推导完整协议能力。生成器与检查器都对所有携带槽位的库存项检查唯一性，包括晋升后的 `existing_partial`；保留历史槽位仍依赖库存审查，脚本没有独立历史分配数据库。

## Switch 提取的行为边界

提取只替换组合目标译码与资格判断；owner、locked、round-robin 的时序更新没有改变。唯一 enabled 匹配时，新矩阵位等价于旧 `match_count==1 && destination==egress`。首次有效 beat 被反压仍锁 owner，只有实际末拍握手才释放；valid 气泡保留 owner。

lookup 的 `o_match` 不受 valid 门控，这是保持已锁源在气泡中仍获得 ready 的必要细节。`o_error` 仍只对有效输入报告无匹配或重复匹配。已有契约要求路由配置在运行期间稳定，且整个包（含气泡）保持相同 dst；在这个契约下未发现提取导致的停顿或锁定变化。

不能扩大成任意输入逐位等价：若已锁源在 valid=0 时违规把 dst 改成存在多个 enabled 匹配的值，旧代码的 valid 门控 error 为零且 destination 取最后匹配项，新代码则把歧义匹配整行清零；ready 或无效 data/last 可以不同。这不是合法输入契约内的回归，但应保留该限制。

读取实际 `switch_route_lookup_integrated` 结果：2/3/4 端口正常配置分别交付 1086/1566/2024 beat，编译及仿真返回 0；真实路由连接故障和移除 owner 锁定故障均编译成功、由仿真检查检出。203 项支持源哈希与当前文件一致，顶层哈希亦匹配。独立 lookup 测试采用 Python 目标 ID 到 enabled 目的列表的字典 oracle，RTL 使用位向量唯一置位判断；1..5 端口合计 13044 次全矩阵检查与两个实际注错提供局部独立可检错证据。

`route_lookup_equivalence` 的 2/3/4 端口尝试均以 timeout 结束，状态为 not_proven；本审查直接读取了 2/3 端口超时日志，4 端口最终状态由 root 汇总确认。它们没有提供通过证明，也没有给出行为反例。本次结论依据静态条件核对和上述功能回归，不把这些超时计为形式通过。

## 编码器 profile 与 oracle 独立性

Read 保留 Tag 11 位、ID 10 位与地址 57 位，编码 `address[56:2]`，并额外限制低 6 位对齐、length=15、attr=FF、VC/pool/ASI/metadata=0。完整地址是否落在测试内存映射中应由执行层判断，不能在编码器截低位。

Response 限 status 0/3、num_beats=0、offset=0、last=1、VC/pool=0，RD_WR=1、RSPTYPE=0。调用者必须显式提供由请求交换得到的 src/dst 和关联 Tag；编码器不会偷偷交换输入。普通 status=3 仍要求完整两个 Data 半 Flit，不等于 DataError/Poison。无效输入输出全零，有效非法 profile 输出 error=1、valid=0、Control=0。

字段定位已对照 Common 2.0 Table 5-29/30；Read 无 OrigData 与 Response Data 需求另对应 Table 2-12、Table 2-16 及 §2.7.5.1，详细源定位保留在字段审计中。`run_fields.py` 的 oracle 不调用模型 encode/decode，不从生产 RTL 或契约位段自动生成期望：它采用六个固定原始 hex、各完整 Tag/ID 位和地址 bit 6..56 的独立位注入，以及有限 profile 非法值遍历。全 256 位 Control 与 valid/error 一起检查，避免仅检查译码后少数字段。

TB 实例化实际 `tl_control_decode`、`tl_control_tenure`，分别检查字段起点、请求/响应计数、Data/BE tenure。Read 是零 Data，合法及 status=3 Response 都是两个 Data 半 Flit；零 Control 是合法 NOP，不应被误记为实际事务。实际 tenure 消费器漏计 Response Data 的注错在编码器全位输出正确时仍被 `TL_CONSUMER` 检出，说明测试并非只验证双方往返一致。

本次先核对 `fields_final` 的 55 项源/产物哈希与 `fields_optimized` 的 15 项哈希，均无差异。随后 root 仅删除运行器尾随空格，RTL 未变；最终以 `typed_final_fields` 为准，重新核对其 55 项源/产物哈希均一致，1345 条正向通过、五项实际故障被明确断言检出，编译失败不计检出。局限是未穷举所有字段笛卡尔积、不定义 X/Z profile，且 Control 的 Data 描述符正确并不证明真实 Data 已发送或已收到。

## 可发布的生命周期回归

已将原忽略目录中的测试迁入 `verification/tools/test_ip_scaffold_lifecycle.py`，根目录改为从该源文件位置解析。测试的库存、typed 叶和聚合均在自动清理的临时目录中，没有修改真实库存或聚合。

```sh
python3 verification/tools/test_ip_scaffold_lifecycle.py -v
python3 -O /absolute/repo/verification/tools/test_ip_scaffold_lifecycle.py -v
```

本次两种方式各 8/8 通过，第二条从 `/tmp` 执行。输出为 unittest 结果；临时产物自动删除。覆盖变化叶拒绝覆盖、默认拒绝变化聚合、显式刷新双角色且保持 typed 叶、晋升槽位复用拒绝、无标识聚合拒绝、只读/刷新互斥，以及 CLI 刷新与只读无写入。成功晋升副本也经过独立结构检查和 Yosys 骨架行为检查。后续晋升先审核库存，再显式刷新聚合并使用新标签保存结构证据。

## 下一步最小因果 Read 路径

按既有计划优先实现 `endpoint_receive_transactions`、`endpoint_read_originator`、`endpoint_read_completer`，复用两个编码器和真实 Endpoint TL/DL。必要的 Tag 表、响应组装及内存握手应有明确所有者；未独立实现的库存壳继续保留准确状态。

接收侧须原子保留 600 位记录，处理任意合法字段起点、同字 Control/Data 和跨字两半数据，只在本地保存完整内容后退休原字一次。Originator 先保留完整 Tag/结果容量，sent 跟随实际 TL header 接纳；匹配完整 Tag/DST、收齐数据后完成，应用退休后释放。Completer 只能由实际请求发起完整 57 位地址内存访问，收到内存结果后生成交换 ID/匹配 Tag 的响应，保持到 Header 和两半 Data 全部接纳；status=3 也必须提供完整 Data tenure。

最小闭环测试必须断开预生成 Response fixture，以独立内存 BFM 和请求→执行→结果→响应→完成事件链核查双向四 Tag、有限背压、未知/重复 Tag、高地址错误及重放不重复执行/完成。当前编码器和 top 传输证据尚未证明这条因果关系；继续功能衔接即可，无需扩大到 PPA。
