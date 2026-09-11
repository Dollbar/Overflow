# 工艺网表等价审查

`tl_control_partition` 及其解码、tenure、信用准入三个依赖，在 WIDTH8/16
两种参数下，已完成当前 RTL 与 `static_reduction` 实际 TSMC28 工艺网表
的一沿复位后二值顺序等价证明。没有改动 RTL、真实网表或时序约束。
这项结论只覆盖该模块及两个实际映射参数，不代表完整 IP、协议一致性、
四态 X 传播或物理签核完成。

## 闭合方法与实际证据

`run_cec.py` 将原 RTL 用 `prep/techmap/opt` 降低为布尔门，并展开实际
Liberty 和映射网表；黄金侧没有复用映射过程的 `synth` 路径。两侧同步
复位/使能由 `dffunmap` 表示为真实 D 输入前的组合逻辑，四个寄存器均
保留。每侧核对原始输入、十个输出共529位、完整四位真实状态、实际 D/Q
连线及原始正沿 `i_clk`，并拒绝未知单元、X/Z逻辑连接、多驱动及悬空
有效逻辑输入。

BLIF只对四个真实 Q 网络作一一对应的名称替换。为消除后端输出的无用
别名，沿全部输出、每个寄存器 D 和时钟反向追溯，仅删除不在这些逻辑
中的 `.names` 定义。保留原始端口和全部四个 `.latch`；移除的四个
`r_cursor` 端口只是额外观察端口，不是原始设计端口。没有新增自由输入，
没有删除寄存器或切断其驱动。三个自动检查专门覆盖下一状态和时钟不能
因缺少输出扇出而被删除、有效状态输入悬空必须拒绝、多驱动必须拒绝。

ABC CEC默认按名称对应原输入、原输出及寄存器 Q，将共同 Q 作为任意
相等的当前状态，检查全部529位原输出和4位下一状态函数。WIDTH8/16
的直接检查分别约26.77/26.52秒通过，无悬空网络警告、错误或未决比较。
这是所有二值状态和输入下的关系保持证明，不依赖额外协议合法性约束。
上一阶段已证明任意初始状态经一个有效复位沿，两侧全部真实状态均为零；
结合该基例与本次当前状态相等时的输出/下一状态等价，即得到复位之后
任意长度输入序列的二值等价。没有依靠 `equiv_induct` 的弱历史关系或
仿真置信度补足基例。

新增两种实际网表故障各检查两种位宽：改变游标最低位真实 FF 的 D，
以及将真实工艺门驱动的 `o_tags[0]` 替为零。四次均被 CEC 判为不等价。
随后用未切断状态的完整双设计时序 miter，分别在复位不生效的转移沿及
输出周期作 SAT 查询，四次均产生实际反例。结合此前两次复位旁路、两次
时钟接线故障，共八次真实工艺网表负向检查有明确检测证据。

`check_cec_evidence.py` 重新核对实际库/源码/网表身份、BLIF转换、状态
匹配、所有比较对象、正常 CEC 日志、四个新增 SAT 反例和原复位前置
证明；普通 Python 与 `-O` 审计均通过。汇总为本地 `cec_evidence.json`。
完整流程仍保留失败记录：首次 CEC 已报等价，但因无用别名警告被包装器
判为未通过；清理过程补上逻辑追溯检查后，完整矩阵重新运行。

```sh
python3 verification/tl_partition_mapping/run_cec.py --label cec_closed
python3 verification/tl_partition_mapping/run_cec.py --fault transition --label cec_transition_checked
python3 verification/tl_partition_mapping/run_cec.py --fault tags --label cec_tags_checked
python3 -m unittest discover -s verification/tl_partition_mapping -p 'test_*.py'
python3 verification/tl_partition_mapping/check_cec_evidence.py
python3 -O verification/tl_partition_mapping/check_cec_evidence.py
```

正常运行退出0，两个故障运行应退出1；汇总审计检查其确实为不等价而非
工具失败。所有标签目录须不存在，原始映射与复位证据须预先生成。新证据
保存在 `build/verification/tl_partition_mapping/`；工艺库不复制入库。

## 保留的复位阶段与证明探索记录

本阶段使用 `static_reduction` 的实际 TSMC28 映射网表、实际 Liberty
布尔与寄存器模型，以及同一份当前 RTL。未改动 RTL、映射网表基线或
STA 约束。输入源码、库、健康网表、实际被测网表和运行脚本均记录 SHA256；
故障只施加于本地网表副本。

WIDTH8/16 都已通过一沿复位证明：从任意二值初始状态出发，在一个
`i_rstn=0` 的有效时钟沿后，gold 与 gate 的四位真实游标全部为零。
查询没有初始化为零的假设，也没有约束数据或握手输入。状态检查确认
每份设计恰有四个状态位，观察端口覆盖全部实际寄存器 Q，时钟均来自
原始 `i_clk`。未切断内部驱动，也未新增自由状态输入。

验证器还核对原始十个输出端口、529 个输出位和四个真实状态观察位。
这是覆盖对象清单，**不是 529 位输出的等价证明完成数**。
`--reset-only` 的通过只表示复位阶段通过，始终将
`mapped_equivalence_closed` 保持为 false。

真实网表负例分别改变驱动 `r_cursor[0]` 的一个工艺寄存器连接。
复位旁路把 D 改接为 `i_source_valid`，保留实际寄存器，两种位宽均产生
零状态复位的实际 SAT 反例；时钟负例把 CP 改为常量零，两种位宽均在
SAT 前被状态/时钟清单拒绝。两类各运行 WIDTH8/16，最终结果由
`verification/tl_partition_mapping/check_evidence.py` 对实际日志、反例和
源文件身份复核，写入本地 `evidence.json`；普通 Python 与 `-O` 审计均通过。

早期 D 固定为一的负例使寄存器被常量优化移除，因此新清单检查先拒绝
了它，不能把它记成执行过 SAT。较早未加该清单的单独实验确有复位
SAT 反例，两份记录分别保留。另一个显式初态别名实验被 Yosys 拒绝，
原因是映射状态的内部别名解析；随后全实际状态零初始化的三周期复位
历史基例通过。这不是任意后续输入下的完整等价证明。

尚未完成的实际试验包括：WIDTH8 单步游标关系归纳在 90 秒求解时限
超时；固定初始游标为零的子问题同样超时；仅保留原输出及状态观察点
的 `equiv_simple` 在 600 秒外部时限终止，未进入后续归纳；对完整证明
逻辑做 ABC 归约的试验在 240 秒外部时限终止。失败日志、脚本和退出
状态保留，未将工具未完成解释为 RTL 错误或证明通过。

上述 SAT 探索未完成的复位后关系与输出义务，现由前述直接 CEC 方法补齐。
参考周期五角十组 STA 通过、主周期最差 setup 为 −1.250022 ns 的结论
沿用原有块级实测，本阶段没有新的时序收敛或完整顶层 STA 结论。
完整 Endpoint/Controller 与 Switch 数字 IP 的 Goal 继续进行。

复跑命令见 `docs/tl_partition_mapping_plan.md`；生成文件位于被 Git 忽略的
`build/verification/tl_partition_mapping/`。私有库和原映射记录须先备齐，
缺失依赖或证据会失败，不能以空矩阵通过。
