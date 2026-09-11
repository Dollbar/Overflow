# UALink 仿真模型与 VIP

`vip/ualink_memory_vip.sv` 是实际可复用的四槽内存服务 BFM，已由双 Endpoint→Switch→Endpoint 因果事务回归实例化。它只实现当前 single64B Read 的局部内存接口；不生成 Response Header，也不是完整 UALink 线协议 VIP、生产内存控制器或一致性模型。生产可综合设计仍放在 `rtl/`。

源工程的公共测试包为 `verification/pkg/ualink_test_pkg.sv`。包提供八个稀疏完整 Tag、测试地址及反向查找函数，以及局部测试内存的数据生成函数 `memory_word`。这些是可复用测试 fixture，不是新增规范编码。

## 内存服务接口与独立检查边界

VIP 接收完整 `read_valid/read_ready`、slot[1:0]、address[56:0]、length[5:0]、attr[7:0]、ASI[1:0]、metadata[7:0]；只支持地址低 6 位为零、length=15、attr=FF、ASI/metadata=0。它独立拥有四槽 pending、地址和到期时间，在真正接纳内存请求后才安排结果。当前 4 KiB 测试映射之外返回 status=3、完整零数据，不截断 57 位地址。

结果接口为 `result_valid/result_ready`、slot、data[511:0]、status[3:0]。结果选中后保存到独立 holding，直到实际握手才释放对应槽；新的到期结果不能替换被背压的输出。参数 SIDE 选择本地数据模式，MIN_LATENCY/SLOT_LATENCY_STEP 控制延迟，READY_PERIOD/READY_STALL_PHASE 控制请求端周期性停顿。时序参数为测试模型选择，时钟周期数从同步低有效复位后独立计数。

TB 不访问 VIP 内部 pending/due/地址阵列。`transactions_tb.sv` 保留独立的公开握手账本：实际内存请求记录 slot→完整地址和接纳周期，实际结果检查此前接纳、唯一性、状态及全部 512 位数据；任何首次 `complete_valid` 均要求更早周期的对侧内存结果。最终期望仍是 TB 内原有 16 个冻结 512 位 literal，未移动进包，也不调用 VIP 的数据函数。

## 独立工程运行

从 UALink 源工程根运行；Icarus `iverilog` 和 `vvp` 必须在 PATH。包必须先于 VIP 和 TB 编译，运行器使用实际顺序：公共 package → memory VIP → 生产 RTL/获授权 SRAM 模型 → TB。

```sh
python3 verification/endpoint_transaction/run_transactions.py --vip-selftest --label memory_vip_new

KD28_ROOT=/path/to/authorized/Overflow
python3 verification/endpoint_transaction/run_transactions.py --kd28-root "$KD28_ROOT" --label causal_vip_new
python3 verification/endpoint_transaction/run_transactions.py --kd28-root "$KD28_ROOT" --label causal_vip_recovery_new --inject
python3 verification/endpoint_transaction/run_transactions.py --kd28-root "$KD28_ROOT" --label causal_vip_minimum_new --inject --bank-depth 1
python3 verification/endpoint_transaction/run_transactions.py --kd28-root "$KD28_ROOT" --label causal_vip_data_fault_new --fault data_half
python3 verification/endpoint_transaction/run_transactions.py --kd28-root "$KD28_ROOT" --label causal_vip_retirement_fault_new --fault retirement
python3 verification/endpoint_transaction/run_transactions.py --kd28-root "$KD28_ROOT" --label causal_vip_tag_fault_new --fault tag_high
```

VIP 自测不依赖 KD28；实际双端集成必须显式传入授权外部依赖，运行器核对 `third_party/kd28_dependency.json` 的源校验值。每个 label 必须是新目录。结果位于 `build/verification/endpoint_transaction/<label>/`，包含 `result.json`、实际 TB、RTL 与支持文件快照、编译/仿真日志。package/VIP 快照位于 `support/`，源清单用 `source_order` 和 `snapshot_sources` 明确记录编译顺序及原文件→快照映射；所有源和产物均保存 SHA256。

提取前两源与原成功证据保存在 `vip_extract_before`。提取后 `vip_extract_final`、`vip_extract_final_recovery`、`vip_extract_final_minimum` 均完成 16 请求/16 完成，合计 48/48；恢复例各有双向 4+4 次重放。`vip_extract_final_data_fault`、`vip_extract_final_retirement_fault`、`vip_extract_final_tag_fault` 均成功编译后由独立检查失败，预期故障检出通过。`vip_extract_final_selftest` 在 66 周期完成 5 次内存请求、4 次结果及 1 次复位取消，并检查四槽同时占用及结果背压保持。所有七例的源、产物哈希与 package/VIP/TB 编译顺序已重新核对。

## Overflow 发布树中的运行位置

发布映射由工程发布流程负责，当前源工程仍使用上述独立目录。Overflow 发布树的设计放在小写 `rtl`；测试与公共包位于 `verification/UAlink2.0/` 和 `verification/UAlink2.0/pkg/`，VIP 位于 `simulator/UAlink2.0/vip/`。从 VIP 目录看，公共包的相对位置为 `../../../verification/UAlink2.0/pkg/`；独立源工程从 `simulator/` 看包的位置为 `../verification/pkg/`。

在 Overflow 根目录开始，使用发布工程入口和现有根 Library 模型：

```sh
cd verification/UAlink2.0/project
KD28_ROOT=../../..
python3 verification/endpoint_transaction/run_transactions.py --vip-selftest --label published_memory_vip_new
python3 verification/endpoint_transaction/run_transactions.py --kd28-root "$KD28_ROOT" --label published_causal_vip_new --inject
```

下一步按新 label 查看公开握手和固定期望的检查结果，再扩展具体服务 profile。此轮只在独立源工程实测；本说明中的 Overflow 命令由发布集成任务验证，不据此宣称已经在目标发布树运行。
