# 原生接收 TDM 观察器契约与候选验证

候选 `upli_receive_tdm_monitor` 依据已读取 Common Rev2 §2.5（pp.41–42）及现有 `model/ualink/upli_tdm.py` 的正常相位规则实现。它观察实际 RX 原生事件；本次用真实 station TX 输出模拟这些入站字段。模块不产生 ready，不修改信用、存储或隔离状态，也不是 TX scheduler。规范私有正文不随候选复制。

参数 `C_NUM_PORTS=1`，合法值仅 1/2/4，其他值以未定义非法配置实例导致展开失败。`i_clk/i_rstn` 为同域时钟和同步低有效共同复位。输入分别为 `i_req_valid/i_req_port[1:0]`、`i_data_valid/i_data_port[1:0]`、`i_rd_valid/i_rd_port[1:0]`、`i_wr_valid/i_wr_port[1:0]`，均连接实际 native valid/PortID，不能连接候选 valid。valid=0 时忽略该通道 PortID。

输出 `o_error[3:0]` 是 i_rstn 限定的当前沿前组合诊断，bit0/1/2/3 对应 Req/OrigData/RdRsp/WrRsp；`o_error_sticky[3:0]` 在上升沿累计，直到共同 reset。`o_phase_known[2:0]` 低至高对应 ReqData/RdRsp/WrRsp；`o_expected_port[5:0]` 每组两位、相同低位优先布局。它们是寄存状态，表示当前待采样时隙；未知组的期望端口为零但不可作为有效相位依据。

首个合法实际 Request 建立 Req/OrigData 共同相位，OrigData 单独出现报错且不能建相位；首次 Request 与同端口 OrigData 可同沿合法出现。Read/Write Response 各由自己的合法首事件独立建立相位。建立后每个时钟周期都递增并按端口数回绕，包括 idle。

故障后采用明确的本地诊断 profile：非法首编号不建相位；合法首 Request 即使同沿 OrigData 错误仍建立 Request 相位；已知组在错误沿继续既定周期，不跟随错误 PortID 重同步。错误按通道分别保持。该选择不同于 Python 原模型抛异常后的未提交状态，不宣称协议故障恢复、RAS、Isolation 或复同步。输入 parity 完整性、连接资格及后续处置由上层负责；本模块不推断信用事件的 TDM，信用返回不受此相位检查。

候选 RTL SHA-256：`3b5df8ec524ebb26dfbd617f2e1904715a7f98b953eb53f06f9422860c6a66fe`。完整可复制清单及其哈希见候选根 `freeze.json`；安装内容仅 `release/rtl/upli/upli_receive_tdm_monitor.v`、`release/verification/upli_channels/` 下四个脚本/TB文件，以及本文。不要复制候选 build 证据到生产源目录。

独立 Python oracle 保存首事件的绝对时钟编号和原始 PortID，用时间差取模推导后续时隙；不读取 DUT 状态，不导入现有 UpliTdm 或 RTL helper。TB 在下降沿驱动、上升沿前检查组合诊断，在 NBA 后检查寄存相位及 sticky。每个正常配置覆盖全部 16 个 valid 组合 × 256 个可表示四通道 PortID 组合，另外有合法流、首次 Data 拒绝、idle、共同/独立首相位、错误后继续既定相位、reset 与固定种子随机事件。不是所有任意长度事件序列的穷举。

| 端口数 | 实际单元向量时隙 | station 观察时隙 | station Req/Data/Rd/Wr 事件 |
|---|---:|---:|---|
| 1 | 8261 | 1001 | 54 / 90 / 131 / 58 |
| 2 | 8296 | 1131 | 57 / 94 / 136 / 65 |
| 4 | 8366 | 1351 | 59 / 96 / 136 / 58 |

单元合计 24923 个向量时隙，每配置另有一个预置同步 reset 沿；station 表只统计 rstn=1 的采样沿，共 3483 沿/1034 原生事件。station TB 实例化已有真实三 sender 和四 KD28 SRAM 接收/信用链路，并在实际输出上接本监测器；独立附加 oracle 只使用这些输出和绝对采样编号，不读取任何 sender 或 monitor phase 作期望。两轮完整流及中途带未完成数据 reset 都通过。完整字段/信用链路的原 station scoreboard 也正常完成。

三种隔离 RTL 注错为相位寄存器写错、idle 停止相位推进、Read 通道错接 Request PortID。都仅修改快照，Icarus 编译返回 0，真实 VVP 运行返回 1，且有 TDM_PRE/TDM_POST 数据不符证据。失败发生即停止，不将完整向量文件长度算作注错执行覆盖。1/2/4 配置的 g2001、无豁免 Verilator `--lint-only -Wall`、Yosys `hierarchy -check; proc; opt; check -assert` 均通过。技能 artifact gate 最终 82/82 代码行符合注释门限，0 error/0 warning。完整技能仓库自检会修改候选目录之外的状态，本轮未执行，不声明该门限通过。

真实缺模块红测保存于 `release/build/verification/upli_channels/receive_tdm/missing_module_red`，Icarus 因缺少真实模块返回 2；首轮 P4 常量比较 lint 失败、技能注释/循环常量解析失败及修正后结果均保留。最终 `frozen_final` 和 `frozen_optimized` 各有三正常单元、三实际故障、三真实 station case，全部通过；正常及 -O 向量逐字节一致，所有记录的制品哈希复核一致。

候选根位于 `build/development/upli_receive_tdm_monitor/`。在项目根复跑（使用未存在的新 label）：

```sh
python3 build/development/upli_receive_tdm_monitor/release/verification/upli_channels/run_receive_tdm.py --label NEW --rtl build/development/upli_receive_tdm_monitor/upli_receive_tdm_monitor.v --faults --station --station-root "$PWD" --kd28-root /path/to/authorized/kd28/root
```

实际最终运行的 label 是 `frozen_final`，KD28 根为 `/home/ljy/work/IC/OverFlow`，station 根为 `/home/ljy/work/IC/UALink`；`python3 -O` 使用 label `frozen_optimized`。完整绝对命令、依赖来源/哈希和工具日志保留在对应 result.json。可安装 runner 的 `ROOT=parents[2]`，正常生产入口为：

```sh
python3 verification/upli_channels/run_receive_tdm.py --label NEW --faults --station --kd28-root /path/to/authorized/kd28/root
```

安装后产物写 `build/verification/upli_channels/receive_tdm/NEW`。仅做单元回归可省略 station/KD28 参数。下一步由主线审查并安装冻结文件，再将实际 RX 字段接入监测器；候选当前不代表完整 station RX、协议认证、STA 或物理互操作。
