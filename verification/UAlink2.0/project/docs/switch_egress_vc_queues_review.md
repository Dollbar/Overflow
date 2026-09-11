# Switch egress VC queues candidate review

候选 switch_egress_vc_queues 已完成“按出口/Request-Response/VC独立容量的有界真实packet缓存”职责，可建议库存从 planned 晋升为此范围的 existing_partial。尚未修改生产、库存或top。RTL SHA-256 `50a67eb3a04ee83c7a2efe1236c7f7727853411bc63e6390dfb04603aa1245f3`。

资源分区定义见 contract.md（可安装为 docs/switch_egress_vc_queues_contract.md）：slot=(response*VCS+vc)*PORTS+egress。每domain实际组合一份 switch_credit_reservation 和 switch_egress_packet_queue；后者复用真实 upli_receive_fifo。每slot独立CAPACITIES，Request不能消耗Response或其它VC。当前库存仅有planned shell，不存在可复用的VC缓存实现；本候选复用已冻结packet helper，未复制其容量/预取状态机。

每source跨全部域只允许一个body owner。首部实际接纳同时取得对应域整packet预约及queue descriptor；保存domain/egress，随后body忽略当前候选route/VC/类别变化。只有最后body真实写接纳才释放source写owner；这不释放packet容量，容量仍等到完整packet最后word实际输出握手才归还。Token由实际queue保存并逐body核查，输出的完整word/token/last受独立oracle检查。所有slot输出独立，物理出口合并和跨域调度由未来scheduler承担。

非法route/VC/零或超额units当拍拒绝，可以合法重试。无owner body拒绝并阻止同沿首部扣账；错误token或非法body使source和相应queue sticky阻断至共同同步reset。错误沿已提交旧队首仍按实际握手退休，不制造release/grant组合环。正常backpressure、未写完owner和输入气泡不error；其他来源/分区可以继续工作。一个source尚欠Request body时自身Response也受该owner阻断，这是明确接口约束，不声称端到端无死锁。

TDD证据 red/：实现前最终typed接口驱动实际旧壳，compile exit7，属于接口不具备的RED；另保存旧壳能力回放compile0/run1、VC_QUEUE_PLANNED_CAPABILITY_MISSING。不是把接口编译失败当功能失败。首轮P1通过，P2发现多个always块对packed输出做组合读改造成零时间仿真停滞；已改为每source局部组合临时量和单一连续驱动。first/保留被中止进程/源码与诊断，不计通过。随后所有leaf与组合static真实通过。

验证器只读取公开接口日志，使用独立Python每slot deque、整单位账本、独立RR轮转与每source owner模型。实际接纳body完整值保存为输出期望，不调用刺激模式函数求期望，也不读DUT内部FIFO/owner指针。按所有启用slot都有接纳来要求覆盖，避免seq与route相关导致只覆盖部分VC×出口。TB负沿驱动/正沿记录，源进度用NBA，不用同沿组合反馈计算期望。

frozen/frozen_optimized及隔离可安装布局portable/portable_optimized均通过，所有相同case逐周期trace/coverage相同。正常3配置各2300周期，合计6900；6类非法输入另13800周期。所有40个启用slot都有实际packet，2个零容量slot不接纳。

| P/VCS/data bits | enabled slots | headers | body words | retired packets | returned units | reset canceled | Response while Request full | other VC while VC0 full |
|---|---|---|---|---|---|---|---|---|
| 1/1/8 | 2/2 | 290 | 438 | 288 | 435 | 2 | 82 | 0 |
| 2/2/33 | 7/8 | 499 | 1016 | 495 | 1012 | 4 | 62 | 16 |
| 4/4/544 | 31/32 | 1445 | 3239 | 1437 | 3220 | 8 | 113 | 154 |

正常共2234个header、4693个body word；2220个packet实际退休，14个在reset取消。Request满时257次Response接纳，VC0满时170次其它VC接纳；每个source未完成body时新header持续受阻，当前header噪声不改变已有body目的。已退休但其packet后来被reset取消的中间word不计完整packet release，这是预期整包记账语义。

非法输入六项分别为错误token、非法VC、无owner body、零route、零units、超额units，检测/阻断/重试或reset后恢复均满足独立模型。五项真实RTL变异compile0/run0后被checker拒绝：Req/Rsp域别名cycle3、body使用当前域351、首body错误释放source owner5、payload bit7、所有域误接域0ready188。这是定向检错能力，非形式完备性或认证。

静态P1/V1、P2/V2、P4/V4每项g2001、严格Verilator -Wall、Yosys proc/flatten/opt/memory_map/opt/check -assert共9项通过；静态DATA_WIDTH=33，功能包含8/33/544。技能审计0 errors/17 advisory warnings。容量实测0..5（具体配置见summary），未遍历所有参数组合或进行大容量/PPA/STA分析。packet helper的实际同步存储数组不是本轮新增SRAM宏声明。

依赖必须随安装核对：switch_credit_reservation、switch_egress_packet_queue、upli_receive_fifo的SHA见freeze.json。库存直接依赖建议改为前两者，FIFO是packet helper的实际传递依赖；旧upli_receive_storage占位依赖不能用于声称已接KD28。本候选不提供物理egress scheduler、标准TL分类/重打包、credit协议映射、管理配置、CDC、独立LinkDown或完整Switch互操作。

开发执行 `python3 build/development/switch_egress_vc_queues/run.py --label NEW --faults`。安装布局执行 `python3 verification/ip_tops/run_switch_egress_vc_queues.py --label NEW --faults`，输出 build/verification/ip_tops/switch_egress_vc_queues/NEW。release/包含新RTL、portable runner/TB/reference及契约/review；不自动复制到生产，packet helper另需从其冻结release安装。下一步是root审查后更新准确库存接口/依赖，再单独接物理出口scheduler与真实packet分类。
