# UPLI OrigData 原生发送执行契约

依据 Common Rev 2.0 §2.5、§2.6、§2.7.7/Table 2-21、§2.7.7.1、§2.7.8、§3.1.1；私有原文仅在授权目录读取，不随实现发布。当前候选在 `build/development/upli_orig_data_channel/`，不改生产 RTL、库存或 top。

## 唯一调度与连接边界

Request 与 OrigData 共用一个实际 `upli_burst_sender`，复用其两个 `upli_credit_bank` 和一个 `upli_burst_control`。两 typed channel 不另建信用银行、TDM 相位或 burst 预约。有效端口数为 1、2、4；两通道共同相位由第一次 Request 确定，之后每周期轮转。第一 Data 与对应 Request 同拍，其余 Data 在同端口连续 TDM 时隙递增 Offset，最后一拍 Last=1。相同端口的数据事务不能覆盖未完成尾部；Read 可以与既有尾部重叠。

本地候选在接受前提供全部一至四拍 `data[2047:0]`、`byte_enable[255:0]` 和 `error[3:0]`，各字段最低部分对应相对 Beat0。这里 ByteEn 是依次发送的四组64字节使能；由自然地址区域生成它的上游必须完成正确的 Beat 对齐，不能直接假定是任意 Write 区域 BE。sender 收齐声明数据且沿前 Request 信用及全 burst 所需 Data VC/Pool 信用足够才接受；每个实际发出 Beat 分别扣除信用，未发尾部由所有权保留。信用返回的 Num 编码表示一至四，四端口返回可并行且不受 TDM 限制，当拍归还不能旁路到当拍发送。初始化 Done 需连续多于一次采样，信用余额和确认均为已注册状态。

`upli_connection_side` 负责真实请求/应答握手；信用返回方向使用已建立的接收连接，发出 Beat 使用双向握手共同成立条件。`i_ready` 在该连接模块是初始接收能力，不是 Native OrigData 逐 Beat ready。建立连接后不能以 ready 撤销已作承诺。正常运行期间断链/隔离处理不由 typed leaf 发明；共用 reset 及完整隔离状态机是整合层责任。

## 冻结 typed leaf

`upli_orig_data_channel` 是组合发送层，无时钟、复位、ready 或内部状态。上游必须提供已由共同 sender 判定的实际发送事件；此层不再次门控有效，也不重排或修饰数据。输入如下，输出对应 `o_orig_data_*`：

| 输入 | 位数 | 输出 |
|---|---:|---|
| `i_valid` | 1 | `o_orig_data_valid` |
| `i_port_id` | 2 | `o_orig_data_port_id` |
| `i_data` | 512 | `o_orig_data` |
| `i_byte_en` | 64 | `o_orig_data_byte_en` |
| `i_offset` | 2 | `o_orig_data_offset` |
| `i_last` / `i_error` | 各1 | `o_orig_data_last` / `o_orig_data_error` |
| `i_vc` / `i_pool` | 2 / 1 | `o_orig_data_vc` / `o_orig_data_pool` |

附加输出 `o_orig_data_valid_parity[0]`、`o_orig_data_parity[7:0]`、`o_orig_data_byte_en_parity[0]`、`o_orig_data_fields_parity[0]`。全部原生字段原样保留，valid=0 时仍透传字段；接收方只有 Valid parity 每周期检查，其余保护组在 valid=1 检查。

每个 Data parity[i] 覆盖 data[64*i +:64]，包括 BE=0 的所有数据字节。BE parity 独立保护64位 ByteEn；字段 parity 覆盖 Last/Error/Offset/PortID/VC/Pool 共9位。共同 parity 模块若采用打包 controls，则 Last[0]、Error[1]、Offset[3:2]、PortID[5:4]、VC[7:6]、Pool[8]。Table 2-21 的 ByteEnParity 描述存在自引用字样；这里依据 §3.1.1 明确的独立 ByteEn 保护要求，并与既有 `model/ualink/upli_parity.py` 一致解释为 ByteEn 的偶校验，而非复制表述错误。

已有 `OrigDataError` 全程保留，不把 poison 当成本地发送失败。此 TX leaf 不承担入站 parity 检查、poison 注入、credit parity 错误处理或隔离/RAS 状态机；这些必须在具备明确保护重叠边界的接收路径实施，不能仅在发送出口重新计算 parity 就宣称端到端保护完成。

## 独立验证与交付范围

候选入口 `python3 build/development/upli_orig_data_channel/run.py --label <fresh_label> --integration`，产物在同目录 `evidence/<fresh_label>/`，拒绝覆盖 label。测试先用旧 production shell 观察真实展开失败；随后完整字段向量检查所有512位数据（包括零 BE 与无效周期）、64位 BE、全部512种控制及随机值，期望 parity 通过 Python population-count 构造，不调用 RTL/model parity helper。

实际 sender 集成测试将输出先经过本候选，再进入既有完整事件 oracle 和按真实接受记录的独立历史队列；覆盖1/2/4端口、全部一至四拍声明及逐拍 Pool 计划、完整数据/BE/Error、信用不足与同拍返回不旁路、初始化/连接阻断、Read overlay、TDM、随机变化和未完成 burst reset。该集成复用既有独立 Python burst oracle，不能把它与原 burst 回归累计为独立规范认证。新增 parity 逐bit检查独立于 oracle。

本模块提供原生 OrigData 发送字段与保护码，不实现新站级协议栈，不接管共享 sender 的 burst 状态，也未完成原生 Read/Write Response 两方向、完整断链/隔离、安全认证、STA 或联盟互操作。下一步由总装层把唯一 sender 的 Request/OrigData 输出分别连接两个 typed leaf，并统一 parity 复用。


## 本次候选实际证据

最终 RTL SHA-256：`36bce7856ddea52b0e76090e3ae1d166dac64bda4bf9706068f358b83c3eb530`。`evidence/release_final/` 是最终源码全宽与实际 sender 集成结果；`release_fault_data_msb`、`release_fault_masked_parity`、`release_fault_poison` 分别保留复制源码的最高数据位翻转、错误按 BE 掩蔽数据校验、poison 清零故障。每个故障均先正常编译，随后真实仿真以返回码1触发 `ORIG_COMPARE`，不把编译失败当注错检出。

| PORTS | 实际检查周期 | Request | Data / journal | Read overlay |
|---:|---:|---:|---:|---:|
| 1 | 4507 | 698 | 1402 | 198 |
| 2 | 9279 | 1764 | 2022 | 1097 |
| 4 | 22076 | 3276 | 3437 | 2191 |

另有3688个独立全字段/校验向量。Icarus `-g2001` 展开、Yosys `memory_map; check -assert`、Verilator `-Wall` 无豁免均通过；此组合模块不含存储或锁存器。运行命令、耗时、精确计数和源码/产物哈希由各 label 的 `result.json` 保存。

`evidence/old_shell_red` 是原占位壳缺失实际端口的真实展开失败；`initial_green` 保留首轮数据比较通过但 TB 文件结束判定失败的记录。新副本 TB 明确消费尾换行，并由 runner 再核对准确向量行数后通过，不改原生产验证器，不将旧失败改绿。

技能 `validate_verilog_artifacts` 在 `evidence/skill_final/` 使用实际无时钟/复位的组合接口契约检查，结果0错误、0警告，45行RTL代码均满足逐行语义注释。首轮技能配置误用默认时钟/复位以及将 spec 放入 RTL 目录的失败也保留。`validate_verilog_skill.py` 整技能自测因其启动清理会删除外部技能目录的 workflow-state 和缓存，超出本任务目录所有权，明确未执行，记录于 `skill_final/skill_runner_scope.json`；不能声称整技能自测通过。真实硬件功能与工具检查结果不依赖该未运行项。
