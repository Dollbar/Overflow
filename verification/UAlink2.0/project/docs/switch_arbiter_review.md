# Switch packet arbiter 独立候选交付

主线已安装此处冻结的RTL并接入真实顶层；集成结果见[Switch总装审查](switch_integration_review.md)。以下候选阶段与发布副本记录按各自快照保留。

候选将原 `ualink_switch_top` 内每出口包锁定及 round-robin 选择提炼成 `switch_arbiter`，采用 Verilog-2001。当前候选与发布暂存副本完全相同，生产安装和顶层接线由 root 承担；本报告不把模块单元通过当成 fabric / 路由配置总装已经通过。

## 接口与所有权边界

默认 `PORTS=4`，本次验证 1 / 2 / 3 / 4 / 5；参数必须为正整数，未定义零端口配置。

| 端口 | 方向 / 宽度 | 语义 |
|---|---|---|
| `i_clk`, `i_rstn` | 输入，各 1 位 | 单时钟，同步低有效 reset |
| `i_valid`, `i_last` | 输入，各 PORTS 位 | 每个源的有效 beat / 包末 beat |
| `i_route_match` | 输入，PORTS² 位 | `source*PORTS+egress`，外部保证每源唯一目的 |
| `i_ready` | 输入，PORTS 位 | 每出口实际接收能力，只影响时序退休 |
| `o_select` | 输出，PORTS² 位 | `egress*PORTS+source`，每出口至多一个 raw owner |
| `o_owned` | 输出，PORTS 位 | 实际 locked 状态，包含首拍停顿后与包内气泡 |

空闲出口按上次实际完成源之后的轮询次序，选择第一个 valid 且 route 匹配的源；ready 不参与选择。首个有效匹配 beat 即使 ready=0，也在时钟沿锁定该源。锁定后 valid 气泡、末拍反压及 route 暂时失配都保留 owner 和 raw selection；只有 route 匹配、valid / ready / last 同时满足的实际握手才释放并推进轮询。

`o_select` 不是 valid grant。fabric 必须同时检查所选源的 `i_valid` 与对应 `i_route_match`；不能在 route 失配时仅凭 raw selection 传输。输入契约仍要求单播、整包保持目的身份；本模块不处理多目标广播、非法路由表或中途改为其他有效目标的包恢复。root 将 `fabric_o_valid & downstream_ready` 送给 arbiter 的 ready，可避免 fabric 拒绝冲突时假退休，合法路径不改变。

`o_owned = i_rstn ? locked_q : 0`，组合 reset 同时屏蔽选择。配置层可在无 owned 且无 source valid 时提交路由更改，不能从 `o_select==0` 或当前 `o_valid==0` 推断包已结束。该配置提交判据由调用方实现，候选本身没有路由表 / CSR。

## TDD、独立模型与实测

先写 Python 队列参考和 SV 自检，再实际运行无选择的 fail-closed 同接口壳，`candidate_owned_red` 的 PORTS 1..5 均 compile=0 / run=1，由首个合法请求 `ARBITER_SELECTION` 检出。该红测证明新候选单元检查能拒绝未实现接口，不代表原 top 的内嵌仲裁不存在。

参考模型以每出口 Python deque 排列优先级，完成后旋转队列；没有调用 RTL，也没有复制 RTL 的整数 offset / candidate 扫描。多个 directed 场景另用手算 onehot / owned 断言约束模型。SV 在 negedge 驱动全部输入，沿前检查所有选择位和 owned，再在两次时钟沿之间翻转 ready 并恢复，验证选择不依赖 ready。没有 posedge blocking 变量反馈 DUT 的竞态。

`candidate_release` 的实际候选结果如下，所有编译与运行 exit=0：

| PORTS | 完整向量周期 | 固定随机 seed | 持续竞争每源完成次数 | 持续单 beat 时最大间隔 |
|---|---:|---:|---:|---:|
| 1 | 1843 | 31908 | 12 | 1 个完成包 |
| 2 | 1868 | 31909 | 12 | 2 个完成包 |
| 3 | 1893 | 31910 | 12 | 3 个完成包 |
| 4 | 1918 | 31911 | 12 | 4 个完成包 |
| 5 | 1943 | 31912 | 12 | 5 个完成包 |

共 9465 个真实时钟向量。覆盖 idle、首拍 stall 新竞争者、owner valid 气泡、包内 route 无效连续保持和恢复、末拍 stall、非末拍已接纳、同步 reset 与沿前组合 reset 屏蔽、多出口并行和矩阵转置、非二次幂回绕、每参数 1800 周期随机有限包及最后排空。最后排空要求无剩余包和无 owner。公平性结论有前提：请求持续 valid、路由稳定、下游持续 ready、包能在有限时间结束；不承诺永久背压、无限长包或无限气泡下的周期上界。

最终 7 个实际 RTL 副本变异在 PORTS=3 均 compile=0 / run=1，且必须命中选择 / ready 独立性 / owned 诊断，超时不算成功检出：

| label | 变异 | 检出 |
|---|---|---|
| `release_fault_ready_gate` | ready=0 时屏蔽组合选择 | row 1，SELECTION |
| `release_fault_stall_unlocked` | ready=0 时不锁定首拍 | row 2，SELECTION |
| `release_fault_early_last` | 不检查 ready 就按 last 退休 | row 2，SELECTION |
| `release_fault_route_release` | 状态更新忽略 route 匹配 | row 5，SELECTION |
| `release_fault_rr_stuck` | 完成后始终从源零开始 | row 14，SELECTION |
| `release_fault_reset_unmasked` | 组合选择不受 reset 屏蔽 | row 8，SELECTION |
| `release_fault_owned_as_valid` | 将 owned 错误限定为当前 valid | row 11，OWNERSHIP |

变异只改运行副本，没有修改冻结 RTL。`runs/<label>/result.json` 记录原始 / 实编译 RTL SHA、所有编译命令、日志及制品哈希。`audit.json` 已复核正式红测 30 份、最终正常 50 份、7 故障各 10 份制品，共 150 份，零缺失 / 零差异。

## 静态检查及限制

最终 PORTS 1..5 均通过 `iverilog -g2001`、`verilator --lint-only --Wall --language 1364-2001`（没有禁用 warning 或使用 Wno-fatal）、Yosys `proc; opt; check -assert; stat`。Yosys 每参数报告 0 problems，数组展开为寄存器的提示保留，不把它解释为 SRAM 或 PPA 签核。

技能 `skill_final/artifacts.json` 在明确 i_clk / 同步低有效复位的 spec 下为 `ok=true, errors=0, warnings=17`；警告是显式常量及 Erie 模板标题 / 区域建议，65 行代码的同线语义注释和构造注释均零违规。早期 `skill_check` 保留了 parser 不识别 ANSI 参数作为 loop bound、把 sequential for 循环变量计作 blocking 等报告；最终改用显式静态 PORT_COUNT 和每出口 generate 寄存过程后消除这些错误，随后重新跑全部真实候选和 faults。

独立 `verilog_lint.py` 不接受本次 spec，默认时钟名与 i_clk 不匹配，最终仍报告一个 DERIVED_CLOCK；源码直接由输入 i_clk 驱动 always，没有派生 / 门控时钟。带明确接口契约的 artifacts gate 和外部 Verilator 均通过。全局 `validate_verilog_skill.py` 已实际调用，因安装缺少 `/home/ljy/.codex/skills/agents-md-generator/scripts/manage_docs.py` 退出 1；该安装级门槛保持 HOLD，不能声称全局技能环境已通过。没有为消除报告修改技能或安装依赖。

这些结果限定为现有本地 sideband unicast packet 仲裁；不代表 VC 分离、规范全部 QoS / 仲裁、原生 UALink 路由、多播、多 station / vPod、CDC、完整 Switch 互操作、形式等价或面积 / 时序达标。

## 发布文件、命令与冻结身份

root 安装时只需复制：

- `switch_arbiter.v` → `rtl/switch/switch_arbiter.v`。
- `release/verification/ip_tops/run_switch_arbiter.py` → 同名生产 verification 路径。
- `release/verification/ip_tops/switch_arbiter_tb.sv` → 同名生产 verification 路径。
- `release/verification/ip_tops/switch_arbiter_reference.py` → 同名生产 verification 路径。

发布 runner 的 ROOT 为脚本 `parents[2]`，明确导入同目录 `switch_arbiter_reference`，只读取 `ROOT/rtl/switch/switch_arbiter.v`；输出 `ROOT/build/verification/ip_tops/switch_arbiter/LABEL`，不依赖 `build/development`。已用 `release/rtl` 暂存同 SHA 源独立运行发布 runner：`staging_check` PORTS1..5 仿真 + 全静态工具均 exit0，`staging_fault` rr_stuck 实际 compile0 / run1。该暂存运行不冒称安装后生产路径已测试。

```sh
python3 verification/ip_tops/run_switch_arbiter.py --label NEW_ARB --static
python3 verification/ip_tops/run_switch_arbiter.py --label NEW_ARB_FAULT --fault route_release
```

输出向量、reference / TB / RTL / runner 快照、各参数 compile / run / 静态日志、覆盖及 result.json；label 必须全新。独立候选命令为 `python3 build/development/switch_arbiter/run.py --label NEW --static`。下一步由 root 安装、连接 raw select 的 fabric route 门控和 o_owned quiescent 判断，再跑实际 Switch / ESE 回归；本次没有替它宣称总装完成。

| 文件 | SHA256 |
|---|---|
| RTL | `4a1005fe57d8443bae78849e51995b21f6f223f4f4585dd5df6d938a611be0e5` |
| 发布 runner | `9de1c4ddccddbb42c512b7994d5e6cda22bf7830996e4fe754162f647a37198e` |
| 发布 TB | `22901b0fde826b3bfd07cd4d7671e37de8059461b92d082ced19c9b12779e0c3` |
| 发布 reference | `dd107c20ee1e0c0571a05d98cd7a993ff472ade09dee8c0c74b0de5b68b1968b` |
