# UPLI Write Response sender 执行契约

按已冻结 `docs/upli_station_integration_execution.md` 的任务 A 实施，来源为 Common Rev 2.0 §2.5、§2.6、§2.7.6/Table 2-18、§2.7.8 与 §4.3。候选目录 `build/development/upli_write_response_sender/`，本轮不修改生产 RTL、公共 bank/leaf/parity 或库存。

## 冻结接口

参数依次为 `C_NUM_PORTS=1`、`C_CREDIT_WIDTH=4`、`C_DEFAULT_CAPACITY=4`（C_CREDIT_WIDTH位）、`C_CAPACITIES`（C_NUM_PORTS×5×C_CREDIT_WIDTH位，默认重复前值）、`C_INIT_COUNT_WIDTH=4`、`C_INIT_CYCLES=2`。端口数只允许1/2/4，信用位宽3..16，初始化约束沿用真实 bank。

输入：

- `i_clk`, `i_rstn`, `i_credit_connected`, `i_beats_connected`。
- `i_candidate_valid`, `i_candidate_port[1:0]`, `i_candidate_vc[1:0]`, `i_candidate_pool`, `i_candidate_payload[100:0]`。
- `i_credit_valid[3:0]`, `i_credit_pool[3:0]`, `i_credit_vc[7:0]`, `i_credit_num[7:0]`, `i_credit_init_done[3:0]`。

输出：

- `o_candidate_accepted`，与本沿实际 native `o_valid` 完全相同。
- 生产 typed leaf 同名字段：`o_valid`, `o_type_info[1:0]`, `o_tag[10:0]`, `o_status[3:0]`, `o_src[9:0]`, `o_dst[9:0]`, `o_port[1:0]`, `o_vc[1:0]`, `o_pool`, `o_auth_tag[63:0]`。
- `o_valid_parity`, `o_auth_tag_parity`, `o_control_parity`。
- `o_balances[C_NUM_PORTS*5*C_CREDIT_WIDTH-1:0]`, `o_init_confirmed[3:0]`, `o_credit_error`, `o_credit_error_sticky`, `o_tdm_known`, `o_tdm_port[1:0]`。

payload101 固定高到低 `{Auth64,TypeInfo2,Tag11,Status4,Src10,Dst10}`，即 Auth[100:37]/Type[36:35]/Tag[34:24]/Status[23:20]/Src[19:10]/Dst[9:0]。Port/VC/Pool 单独由同一个完整候选提供；上游 valid 一旦提出须保持整组候选到 accepted，只有共同 reset 可以取消。没有内部候选队列或另一个 early capture 事件。

## 所有权与实施边界

只有一个真实 `upli_credit_bank`、一个独立 WrRsp 相位与一个生产 `upli_write_response_channel`，后者真实使用公共 parity。沿前余额非零且沿前初始化确认、实际连接资格及端口时隙都满足才可发；同沿返回信用或新初始化不能旁路准入。一次实际发出只扣原 port/VC 或 Pool 账户一个信用。

首个真实发送建立相位，之前 `o_tdm_known=0`、`o_tdm_port=0`；首发之后沿后进入下一 port，已知相位每周期前进，空周期或被阻塞候选不能暂停。相位与 Req/OrigData、Read Response 独立。未配置 candidate port 不接受；不增加不属于 bank 的协议错误编码。

所有状态用共同上升沿同步低有效 reset；typed leaf 同 reset 作组合屏蔽。信用返回组无 ready、不受候选 valid 或 TDM 限制。bank 保留原有非法/溢出/未配置端口诊断，其注册单周期 `o_credit_error` 再汇总为直到 reset 的 sticky；不借此声称损坏信用输入后的发送/恢复安全策略已经实现。异常信用的抑制和站级隔离另行定义。

完整 Write 因果、最后 OrigData 接收后的允许响应周期、命令/type/status 合法性、Auth启用时取值、ISOLATE与Tag生命周期仍由上游执行器/站级资格层保证。本模块是已构建响应的原生发送服务，不是命令执行器、RX或完整station。

## 独立验证与实际范围

TDD 首先以新 TB 对缺失的实际 sender 模块运行 Icarus：`missing_module_red` 返回2并明确报告 Unknown module type；没有用脚本预检查缺文件代替编译器红测。实现后，所有 healthy case 都实例化一个真实生产 bank、一个生产 Write leaf 及其公共 parity，不用模型替换硬件资源。

独立 `write_response_sender_reference.py` 使用整数数组记录每个 port 的四个 VC 和 Pool 账户，依据输入事件、沿前信用、连续初始化采样和独立相位预测发送；不导入已有 UPLI/RTL helper。101位 payload 通过固定数值切片拆分，以逐字段 population-count 生成期望 parity。TB 另有整数信用 journal，只根据外部返回与实际 native valid/port/VC/Pool 扣账，再比较实际银行余额。输入在低电平准备、沿前比较、上升沿后比较状态；计数不会在采样沿反向驱动候选。TB 也检查等待候选完整保持，不把上游违规改字段当发送器缓存能力。

实际 `frozen_*` 配置如下，各 case 的参数、异构容量向量、命令、耗时、原始输入/期望及源/产物哈希在其 `result.json` 中：

| PORTS | 信用位宽 | 初始化周期 | 实际周期 | 实际发送 | 等待候选周期 |
|---:|---:|---:|---:|---:|---:|
| 1 | 3 | 2 | 1192 | 762 | 105 |
| 1 | 16 | 3 | 1241 | 738 | 156 |
| 2 | 3 | 2 | 1223 | 637 | 287 |
| 2 | 4 | 3 | 1262 | 646 | 296 |
| 4 | 8 | 5 | 1570 | 475 | 814 |
| 4 | 16 | 2 | 1552 | 467 | 805 |

共8040周期、3725次真实发出。覆盖全部有效 port/VC/Pool 路径，零容量账户、初始化短脉冲、最终确认同沿不旁路、信用耗尽及当拍返回不旁路、并行信用返回和同沿收发、首次非零 port 发出建立相位、idle 推进、等待候选保持、未配置端口候选拒绝，以及多次有状态共同 reset 后重新建连资格和发布信用。完整101位各自 walking-one、随机高位 Tag/Auth/ID 与非零状态均按实际输出比较；编码保持不是所有命令/状态合法性验证。

这是六个明确配置，不是端口/位宽/初始化参数全集笛卡尔积。实际配置账户容量为0..19，16位计数配置经过真实功能和展开检查，但不声称枚举了全部65536个信用数值。候选低 valid 时字段可变化；已提出但未接受的 valid 候选必须保持，没有存储器代上游保存其任意违规变化。

三个真实隔离 RTL 注错在已通过的4端口/8位信用/5周期初始化配置上验证：`debit` 将 bank 的实际发送扣账输入置零，`phase` 错误地仅有发送时才推进相位，`high_tag` 清除 payload 中最高 Tag 位。三者均编译0、实际运行1，由具体 `WR_SENDER_POST` 或 `WR_SENDER_PRE` 失败检出，原始失败日志与副本保留。

Icarus `-g2001`、Verilator `-Wall` 无豁免和 Yosys `memory_map; check -assert` 在六个配置全部通过；层级均为一个 bank、一个 Write leaf、一个公共 parity，零锁存器。`validate_verilog_artifacts` 用实际时钟/reset和完整接口契约检查109行候选 RTL，0错误/0警告；首个技能配置缺 ports 的错误保留为配置失败，不算 RTL 失败。整技能自测脚本会清理外部技能状态/缓存，超出候选目录所有权，明确未运行；硬件工具结果与该未运行项分开记录。

非法/溢出信用的定向诊断只在无响应发出的周期注入，验证 bank 整沿保持、错误与 sticky、共同 reset 清除。不把它扩展为损坏返回与正在发送并发时的恢复证明；完整异常所有权策略仍由 station 故障管理任务负责。

## 发布文件与复跑

冻结候选 `build/development/upli_write_response_sender/upli_write_response_sender.v` SHA-256：`6c15608737f63088083fa733a7612888121cbb29c44e6cf5c1ae246912d210b5`。

可安装验证文件位于候选 `release/verification/upli_channels/`：`run_write_response_sender.py`、`write_response_sender_tb.sv`、`write_response_sender_reference.py`。runner 的 ROOT 固定为自身 `parents[2]`，安装后直接从 ROOT/rtl/upli 读取 sender、bank、leaf、parity；`--rtl` 可显式覆盖候选。每个源读取同一份 bytes 写快照和计算哈希，实际编译快照，避免并发编辑改变所测源码。结果目录 `ROOT/build/verification/upli_channels/write_response_sender/LABEL` 拒绝覆盖 label。

安装后执行：

```sh
python3 verification/upli_channels/run_write_response_sender.py --label write_sender_p4 --ports 4 --width 8 --init-cycles 5
python3 verification/upli_channels/run_write_response_sender.py --label write_sender_fault_debit --ports 4 --width 8 --init-cycles 5 --fault debit
```

候选最终六配置从 `/tmp` 通过绝对 runner 路径和显式 `--rtl` 完整运行。release 下 `rtl` 相对链接及 `build` 仅为本地迁移验证设施，不能作为发布文件复制；只安装候选 RTL、三个 verification 文件及本契约。`freeze.json` 列完整哈希、健康/红测/故障证据与依赖；下一步由 root 连接 station TX 的独立 Write 通道和真实信用接口，再验证端到端响应因果与三相位并行。此候选未修改生产或库存。
