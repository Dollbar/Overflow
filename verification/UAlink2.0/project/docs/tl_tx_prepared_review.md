# 完整源组到实际发送队列的生产集成审查

新增 `rtl/tl/tl_tx_prepared.v`：两份已验证的注册化准备器直接连接生产 `tl_tx_buffered`，完整 Request/Response 源组可以在捕获后立即释放并更新。原测试中的退休适配器已从新集成回归移除。该模块是实际发送组合，不是完整 Endpoint/Switch 顶层；完整双 IP Goal、组合顶层工艺 STA 和完整时序参考证明仍开放。

## 所有权与接口

每类输入为一个 256 位 Control 源组和八个 64 位标签。两类独立捕获，固定分别作为 Request 和 Response。Auth 开启时，生产者同时声明源组与标签有效并保持到捕获；没有标签时不发出捕获确认。Auth 关闭时不等待或消费标签有效信号。

| 事件 | 意义 |
|---|---|
| `o_source_captured` | 本沿保存整个源组及其标签；生产者可以切换到下一组 |
| `o_source_tags_taken` | Auth 模式下与源组捕获同沿释放标签，其他模式为零 |
| `o_partition_taken` | 当前完整字段分组被实际头部 FIFO 接纳 |
| `o_group_queued` | 原组的最后一个分组已经入队；可同拍捕获下一组 |
| `o_header_taken/o_tags_taken/o_data_taken/o_fc_taken` | 实际线上发送导致的队列或 FC 消费，继续沿用原发送语义 |

`o_source_captured = i_source_valid && o_source_ready`。标签准备条件同时约束外部 ready 与准备器的输入 valid，避免只改变确认而仍错误捕获。捕获不代表格式正确或已经发送：错误和单字段总容量不足仍持有源组到同步复位，并分别由 `o_prepare_error/o_prepare_shortfall` 报告。

准备器的输出分组与对应最多四个标签原子写入原有实际 SRAM 头部队列。Data/BE 和 FC 使用原有真实缓存及信用路径。配置 `auth/shared/capacity` 在初始化时期稳定；开启新时期必须复位取消持有、排队和发送上下文。新组合没有额外状态或额外捕获延迟，也没有绕过队列的数据旁路。队列拥塞仍可能降低端到端吞吐；1,308 次同拍替换不代表整个系统每周期都发送一组。

## 最终验证

| 检查 | 实测范围 |
|---|---|
| 实际双端 SRAM/信用闭环 | 32/32：WIDTH 8/16 × Auth 0/1 × shared 0/1 × link delay 1/3 × 两种队列配置 |
| 完整源组/分组/字段 | 1,536 组捕获并完整入队，5,248 个分组，6,912 个字段 |
| 完整 SingleBeat read reply | 2,304 个，保留实际 Offset/Last、VC、目的地和标签一致性审计 |
| 同拍替换 | 正常队列 660 次，最小队列 648 次，合计 1,308 次 |
| 独立捕获核验 | 115,600 条 lane 观察记录；不是 115,600 个独立时钟周期 |
| 独立源组/满队列/复位模型 | WIDTH 8–16 × Auth 0/1 × 头部深度 1/3，共 36/36、5,760 周期；每周期比较 1,064 位双类准备输出，并断言实际 FIFO 数量 |
| 真实接线故障 | 11 类 × WIDTH 8/16、Auth/shared 开启、delay 3，共 22/22 检出 |
| 真实带负载复位故障 | WIDTH 8/16 × Auth 0/1 × 深度 1/3，共 8/8，在前 40 个向量相同后于复位向量 40 检出 |
| 普通/优化 Python | 独立捕获、原始线上/队列、最终汇总审计均通过 |

捕获核验使用原独立 `PreparedPartitioner` 模型，以真实 FIFO ready、真实容量和初始化状态驱动，逐条比较源捕获、标签捕获、整组入队、分组接纳、全部 Control/标签位、字段数与游标。同时独立维护捕获与退休索引，并检查源数据只按捕获索引推进。模型源码保持前阶段不变。实际线上/存储/信用检查使用另一个既有 trace 审计入口，两者结论分开成立。

单位场景包含缺标签、捕获后的持续输入变化、满队列保持、无事务字段的非法组、零总容量和仍有持有/排队工作的复位。Data 和 FC 的实际消费由完整双端测试覆盖；单位测试故意关闭线上消费来建立可独立计算的满队列与复位期望，不宣称该单位模型覆盖整个发送器。

11 类接线故障分别为：忽略源标签有效、Response 接成 Request、队列满时仍推进、把源 ready 接到退休、源组类别交换、八标签类别交换、实际 FIFO 误接实时源 Control、标签在分组入队时错误确认、FIFO 误接实时源标签、Data 类别交换、屏蔽 FC。每个故障都重新编译真实 wrapper，使用与正常运行相同的独立源文件和测试台，仅重定向结果路径；编译失败和工具超时不算检出。屏蔽 FC 由实际测试台的持续前进时限断言检出，不是仿真工具被超时杀死。

## 编码与结构

严格 Verilog-2001 lint 在 WIDTH 8/16 均通过。仅沿用针对外部 SRAM 多模块文件的 `DECLFILENAME` 豁免；没有豁免新 RTL 的警告。

Yosys 普通结构综合得到 6,254/6,574 位真实 FF 和各 64 个 SRAM 黑盒实例。逐个核对全部 FF 与 SRAM 读/写时钟连接到原始 `i_clk`，触发器类型均为上升沿、同步控制，无锁存器。此项是 RTL 状态/时钟结构检查，尚无真实 SRAM 时序库或新组合顶层工艺签核结论。

完整 11 文件自有 RTL 依赖层级的技能 artifact 检查为零错误、122 条建议。过程中发现旧 `tl_control_decode` 的连续 wire 赋值和模块注释不符合当前格式规则：分离 67 处 wire 声明/连续赋值并补齐模块注释后，实际原、新解码器在全部 256 位输入、全部 32 位原输出上通过无假设组合 SAT。所有最终单位、双端、负例及结构检查都在修正后的当前依赖上重跑。该依赖格式变更不作为新增功能，也不把旧源码绑定的 STA 报告重新标成当前组合顶层结果。

初次仅提交 wrapper 给技能检查时，它要求在当前 artifact 中看到时钟与复位实现；加入实际依赖后，又遇到工具按文件顺序识别首个顶层的问题。最终 artifact 按 `design/` 与 `support/` 组织，声明全部文件，保留原时钟/流水线要求并检查真实层级。先前配置错误、旧格式违规、缺少模块的红灯运行和实际故障均留存，没有加入无功能寄存器来满足检查器。

## 复跑和证据

生产入口：

```sh
make prepared-tx-smoke KD28_ROOT=/authorized/sram/repository
```

输出包括 `build/verification/tl_tx_prepared/smoke` 的八个源组/队列场景，以及 `tl_control_partition/prepared_top_smoke` 的一组实际双端与捕获审计。完整矩阵使用如下入口，标签不能覆盖已有记录：

```sh
python3 verification/tl_tx_prepared/run_unit.py --kd28-root "$KD28_ROOT" --label unit_final --widths 8 9 10 11 12 13 14 15 16
python3 verification/tl_control_partition/run_peers.py --integrated --kd28-root "$KD28_ROOT" --label prepared_top_final_peers
python3 verification/tl_control_partition/run_peers.py --integrated --kd28-root "$KD28_ROOT" --label prepared_top_final_minimum --header-depth 1 --bank-depth 1
python3 verification/tl_tx_prepared/check_capture.py --labels prepared_top_final_peers prepared_top_final_minimum
python3 verification/tl_control_partition/check_evidence.py --peers-only --peers-label prepared_top_final_peers --minimum-label prepared_top_final_minimum --output-label prepared_top_final_wire_evidence
python3 verification/tl_tx_prepared/run_faults.py --peers-label prepared_top_final_peers --label faults_final
python3 verification/tl_tx_prepared/run_structure.py --kd28-root "$KD28_ROOT" --label structure_final
python3 verification/tl_tx_prepared/check_evidence.py
python3 -O verification/tl_tx_prepared/check_evidence.py
```

固定标签汇总审计还需要本阶段保留的解码器 SAT、复位负例、完整 artifact 和优化 Python 线上报告。使用新的隔离导出及新标签重跑时，按这些输入关系调整相应审计入口。各脚本 docstring 给出执行方式、输出位置与下一步；`KD28_ROOT` 必须是已授权模型仓库根目录。

干净导出的 `make test rtl-smoke prepared-tx-smoke` 已通过，普通非文档源文件与当前工作区对应核验。主证据为 `build/verification/tl_tx_prepared/evidence.json`；源/工具/测试及失败记录由该目录的 `manifest.json` 绑定本地提交。私有 SRAM、工艺库和规范继续在授权的外部位置，只清理终止任务的波形与编译缓存。

下一步对生产发送组合建立完整时序参考/组合证明，并开始实际标准单元映射与顶层 STA；SRAM 的真实工艺时序和明确标为抽象的接口时序必须分别处理。继续把发送组合接到最终 UPLI/信用/DL/TL 端口及 Endpoint/Switch 顶层，随后覆盖其余数字 PHY、INC、安全和管理范围。所有这些仍是完整 Goal 的交付要求。
