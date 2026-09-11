# Originator Isolation 义务账本候选

候选对应库存 `ras_originator_isolation` 稳定模块；本轮只在 `build/development/ras_originator_isolation` 开发，未替换生产壳。它保存可信事务所有者登记的响应义务，输出 Isolation、CMPTO dummy 生成请求和显式新 epoch 恢复资格；不输出 Drop、不制造已完成事件、不修改任何信用。

Common 2.0 §3.1.3（印刷页 87–89）是隔离作用域、dummy CMPTO、迟到真实响应丢弃与信用继续运行的条款依据。本说明仅释义：Accelerator 的 Originator 隔离覆盖该 role 全部端口；Switch INC Originator 使用每端口作用域。此候选将 LinkDown 映射为相同隔离触发，是本地保守策略；有限 epoch 与恢复握手是本地管理契约，不能当作规范 CSR/自动恢复序列。

## 冻结接口

Verilog-2001 模块 `ras_originator_isolation`；`PORTS=1` 支持 1/2/4，`CAPACITY=4` 支持 1..4，`IS_SWITCH=0` 为全角色作用域，1 为端口作用域，`EPOCH_WIDTH=8` 支持 2..16。`i_clk` 上升沿、`i_rstn` 同步低有效；事件字段在沿前稳定。所有槽/端口编号固定 2 位。非法配置必须展开失败。

| 接口 | 精确定义 |
|---|---|
| `i_isolate[PORTS]`, `i_link_down[PORTS]` | 来自可信角色/连接所有者的事件。当前沿就合并到隔离状态；重复触发幂等。不从坏报文字段推断作用域。 |
| `i_link_up`, `i_init_done`, `i_drop` | 各 PORTS 位外部状态；既有组件仍是唯一 Drop 所有者。 |
| `i_track_valid/o_track_ready` | 登记实际接纳请求的义务。输入 slot2、port2、epoch、tag11、read1、beats3；beats=1..4，Write 要求 1。空槽、正确 epoch 与合法描述符才接纳。隔离中新请求也可以登记，等待 dummy。 |
| `i_complete_valid/o_complete_ready` | 实际正常响应全部消费之后的完成事件，包含 slot2/epoch。ready 在 reset 外为 1。已隔离槽的迟到完成消费并标记 discard，永不消除 dummy 义务。未知/旧 epoch 完成还产生诊断。 |
| `o_dummy_valid/i_dummy_ready` | 轮询未发出的隔离槽；输出原 slot、port、epoch、tag11、read、beats 及 status=8。请求在反压中锁定全部字段。握手只标记 issued，count 不减。 |
| `i_dummy_done_valid/o_dummy_done_ready` | 后级完成整个 dummy 响应义务后的独立 slot2/epoch 确认。必须在先前沿已发出请求；同沿 request+done 不满足 issued 条件。未知、未 issued、旧 epoch 和重复确认消费诊断、不销账。 |
| `i_recover_valid/o_recover_ready` | 需已有寄存隔离、义务全空、`i_quiescent=1`、全部 link_up/init_done、全部外部 Drop 清零、无当前隔离触发及 track/complete/dummy_done 事件，并且输入新 epoch 精确等于当前+1。 |
| `o_recovered`, `o_epoch` | 恢复实际握手脉冲；握手才清 Isolation 并切换 epoch。最大 epoch 永远拒绝再次恢复，禁止回绕。 |
| `o_isolated`, `o_forward_allowed` | 当前隔离含本沿触发；forward 要求 link_up、init_done、非 Drop、非 Isolation。仅资格输出，真实 sender 必须自行接入。 |
| `o_count`, `o_error[3:0]` | 所有 pending 义务，包括 issued 未 done。error 位 0/1/2/3 分别是非法 track/正常完成/dummy_done/恢复事件；沿前组合诊断，不自动升级 Drop。 |

`o_track_ready` 取决于描述符，不是普通应用请求接口；事务所有者必须在接纳请求的同一原子边界完成登记，不允许先接纳后丢失登记。已占槽上的有效重复登记拒绝并诊断。只允许每次一个登记、真实完成和 dummy 完成；不同槽可并行。回收当沿不再重用同一槽。dummy 请求的无效字段归零；count/epoch 是同步寄存状态，复位采样之前不承诺组合归零。

隔离的“取消在途”仅指停止正常转发资格，并把已登记义务转交 dummy 生成责任；没有凭空擦除义务。`dummy_ready` 不是完成，只有匹配 `dummy_done` 才销账。请求已握手而后级迟迟不完成时恢复必须持续拒绝。共同 reset 会取消本地义务历史；外部实际数据、Tag、信用与事务所有者需要按真实系统契约共同处理，候选没有实施这些操作。

## 测试与复跑

独立 Python 字典账本生成沿前预期，不读 DUT 内部信号。SV 在下降沿驱动并比较全部公开输出，再由上升沿提交事件；避免同沿调度竞态。缺模块红测保留在 `red/`；初次实现的 dummy 反压选择漂移在 `release/build/verification/ras/isolation/hold_red/` 真实失败，修复后增加了相应 mutation，没有覆盖旧证据。

候选实际执行命令（仓库根）：

```sh
python3 -B build/development/ras_originator_isolation/release/verification/ras/run_isolation.py --label frozen --rtl build/development/ras_originator_isolation/ras_originator_isolation.v --faults
python3 -B -O build/development/ras_originator_isolation/release/verification/ras/run_isolation.py --label frozen_optimized --rtl build/development/ras_originator_isolation/ras_originator_isolation.v --faults
python3 -B build/development/ras_originator_isolation/release/verification/ras/run_isolation.py --label default_epoch --rtl build/development/ras_originator_isolation/ras_originator_isolation.v --case 4 4 1 --epoch-width 8
```

每次完整矩阵：PORTS1/2/4 × CAPACITY1/2/3/4 × IS_SWITCH0/1，共 24 正常配置，27,756 个独立模型时隙；另 9 实际 RTL 故障全部 compile=0、runtime=1 且出现自检失败。故障覆盖请求接纳提前销账、迟到真实完成销账、epoch 回绕、错作用域、旧 epoch done、忽略 quiescent、Tag 高位丢失、未 issued done、反压选择漂移。正常/-O 每次 636 登记、15 正常完成、619 dummy 请求、537 dummy 完成、2,385 真实完成丢弃观察、137 恢复；剩余 84 义务在明确 reset 下取消。默认 8 位 epoch 单项另测 1,663 时隙、255 次恢复并拒绝 255→0。

24 配置每个均通过 Icarus `-g2001`、Verilator `--language 1364-2001 -Wall`（零豁免）、Yosys `proc; opt; memory_map; check -assert`。默认 8 位参数另通过同三项。6 个非法参数展开全部失败。技能 `validate_verilog_artifacts`：128/128 代码行具有同行注释，零错误、零警告。未执行会写到候选目录之外的整个 skill 自测脚本，不将此报告写成整个 skill 验证通过。所有命令、工具返回码、运行时间和源/产物 SHA 均在结果 JSON 中。

复制 `release/rtl/ras/ras_originator_isolation.v`、`release/verification/ras/{run_isolation.py,isolation_tb.sv,isolation_reference.py}` 与本文即可安装。安装后从任意 cwd 用绝对入口路径运行，runner 以 `Path(__file__).resolve().parents[2]` 定位工程：

```sh
python3 -B verification/ras/run_isolation.py --label REVIEW_NEW --faults
python3 -B verification/ras/run_isolation.py --label EPOCH_NEW --case 4 4 1 --epoch-width 8
```

输出 `build/verification/ras/isolation/LABEL/` 的 vectors、source 快照、日志、映射网表及 `result.json`；label 必须新建，既有标签不会覆盖。`freeze.json` 保存可复制文件与证据哈希。

## 接入缺口与限制

尚未接真实 Endpoint/Switch 事务接纳、Tag 生命周期、native RX、sender、dummy 编码器、全 Beat 响应回压或 credit/Link 初始化。本测试是实际候选 RTL 加独立事件模型，没有声称系统恢复/全链路集成。

slot+epoch 是外部事务所有者提供的可信身份。同一 epoch 内某槽已回收并复用后，任意旧事件若仍携带相同 slot+epoch，候选不能分辨；上游须过滤这种别名，或后续集成增加世代 token。Tag 只完整保存到 dummy 请求，不在完成口重新认证。跨全局 reset 后 epoch=0，也要求共同复位排空旧事件。不能用此模块单独证明 Tag 安全或去重可靠性。

恢复资格是保守的全实例边界：即使 Switch 只有一个 port 隔离，仍等全部账本清空并要求所有 link/init/Drop 资格。非隔离端口平时仍可正常完成，但没有逐 port epoch 独立恢复。epoch2 与默认 epoch8 已实际仿真；其他合法宽度仅声明参数范围，未做逐宽矩阵。没有 watchdog、自动 Isolation 触发策略、dummy 数据生成、软件恢复协商、故障重同步、形式证明、宏 STA 或认证结论。
