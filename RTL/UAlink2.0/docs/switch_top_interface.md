# 研发 Switch 顶层接口

`rtl/switch/ualink_switch_top.v` 是已实现、可综合的内部数字 packet fabric 顶层。默认 4 个输入/输出端口、每拍 544 位，能直接保持 Endpoint 数字接口的 24 位 header 与 520 位 payload。它使用独立 10 位目标 sideband，不从 544 位数据中推断 UALink 标准目的字段。

当前顶层包含唯一目的解码、每输出轮询仲裁、包内 owner 保持、首拍停顿保持和同步复位。它尚未包含标准 TL 目的解析、每端口 TL/DL 终止、管理 CSR、INC、安全功能或完整 UALink Switch 的其他必需模块。因此“顶层已有可工作的内部 fabric”与“完整标准 Switch 已完成”必须分开。

## 固定接口与参数

| 名称 | 方向 / 宽度 | 语义 |
|---|---|---|
| `PORTS` | 参数，默认 4 | 对称输入/输出数量，RTL 要求至少 1；本轮实测 2/3/4 |
| `DATA_WIDTH` | 参数，默认 544 | 每拍原样传递的完整数据宽度 |
| `clk`, `rstn` | 输入，各 1 位 | 共同时钟上升沿、同步低有效状态复位；复位期间抑制有效传输 |
| `i_route_ids` | 输入，`PORTS*10` | 每个目的端口的 10 位逻辑 ID，端口 p 位于 `[p*10 +:10]` |
| `i_port_enable` | 输入，`PORTS` | 使目的端口参与路由匹配；不是源输入禁止位 |
| `i_valid`, `o_ready` | 输入 / 输出，各 `PORTS` | 每源 ready/valid 握手 |
| `i_data` | 输入，`PORTS*DATA_WIDTH` | 源 p 位于 `[p*DATA_WIDTH +:DATA_WIDTH]` |
| `i_dst` | 输入，`PORTS*10` | 每源当前包的目标 ID |
| `i_last` | 输入，`PORTS` | 每源当前 beat 是否结束一个包 |
| `o_valid`, `i_ready` | 输出 / 输入，各 `PORTS` | 每目的独立 ready/valid 握手 |
| `o_data`, `o_last` | 输出，`PORTS*DATA_WIDTH` / `PORTS` | 原样转发选中源的完整字与末拍标志 |
| `o_route_error` | 输出，`PORTS` | 组合指示 `i_valid && enabled目标匹配数量不等于1` |

路由表和目的使能在复位期间配置，在正常运行期间保持稳定。允许 self-route。相同 ID 仅在多个 enabled 项同时匹配时构成歧义；disabled 项不参与匹配。未知 ID、仅匹配 disabled 端口或重复 enabled ID 都使有效源 `o_route_error=1`、`o_ready=0`，不会静默接收后丢弃。错误标志是当前输入的组合状态，不是 sticky 中断或内部错误队列。

源在 `i_valid && !o_ready` 时必须保持 valid、data、dst、last；一个多 beat 包内必须保持同一 dst。允许已获得 owner 的源在相邻 beat 之间插入 valid 气泡，owner 会保留。数据和 last 在 valid=0 时没有外部语义。配置动态变更或包内目标变更不属于合法输入序列，需要先复位/停流。

## 转发与仲裁行为

数据通路无内部队列，空闲输出可以在同一周期组合地传递源 data/valid 和目的 ready。每个输入只有一个合法目标，每个输出每拍最多选择一个输入，输入与输出握手一一对应。多个独立目的可以同拍传输。

每个输出单独保存轮询起点。复位后起点为源 0；最后一个 beat 真正握手后，从刚完成包的源之后开始选择下一个包。未到 `last` 的包独占输出，包括包中间的气泡和目的反压。

首次选到有效 beat 即使尚未握手，也在该时钟沿锁定 owner。这样下一周期出现更低编号竞争者时，不会替换已向下游展示且被反压的 beat。只有 `o_valid && i_ready && o_last` 或复位可以释放此 owner。

公平性以完整包为仲裁单位，需要源最终给出 last、目的持续取得接收进展。持续单拍争用且目的 ready 恒为 1 时，每个请求源在 `PORTS` 个周期内获得一次服务；没有给出有限包长或持续接收条件时，不承诺有限等待上界。复位取消所有未完成包所有权，上游/下游需共同处理被复位中断的在途包。

## 执行和本轮证据

从仓库根运行可移植入口；输出目录始终按仓库根解析，必须使用新 label：

```sh
python3 verification/ip_tops/run_switch.py --label switch_check
```

默认在 Icarus/VVP 中运行 2/3/4 端口、544 位完整字以及两个真实 RTL 注错配置。输出包括 `reports/ip_tops/switch_<label>/summary.json`、源/TB/入口快照、工具版本、每 case 的实际编译/运行命令、返回值与日志。现有 label 会拒绝，不覆盖早期失败。

本轮实际命令为 `python3 verification/ip_tops/run_switch.py --label final`：三个正常配置全部编译/运行返回 0；两个注错都编译返回 0、运行返回 1。证据位于 `reports/ip_tops/switch_final/summary.json`。

独立多端口 scoreboard 不重演轮询算法。它独立扫描目标 ID，使用刺激内源标签与递增序号追踪源，比较完整 544 位数据、last、输入/输出握手守恒、每源顺序、每输出包 owner、反压时稳定性。定向阶段覆盖首次高编号源被反压后加入低编号竞争者、所有端口同时 self-route、持续争用公平界、未知/disabled/重复目的、复位打断未完成包；每端口配置另有 1200 周期随机 1..4 beat 包与目的反压，最终有界排空，不以无流量作为通过。

两类注错只操作报告目录中的 RTL 副本：路由比较 `==` 改为 `!=` 会触发 `FAIL route_error`；绕过已锁 owner 会在 cycle 2 触发 `FAIL hold`。检查器只把实际行为比较失败计为检出，编译错误和超时不计。

测试先以隔离的无传输实现验证了失败能力：`switch_red_no_delivery_retry/` 中编译 0、运行 1，报告 `FAIL directed_delivery count=0`。最初测试台语法错误保存在 `switch_red_no_delivery/`，不计为有效行为红测。`switch_initial/` 保留初版已通过的正常/注错结果；补充 explicit self-route、disabled-route 与组合偏移默认赋值后重新执行到 `switch_final/`。

Yosys `read_verilog; hierarchy; proc; opt; check -assert; stat` 对 2/3/4 端口全部返回 0，最终网表没有 latch 单元；证据在 `reports/ip_tops/switch_synthesis_final/summary.json`，每配置保存完整命令、日志及 JSON 网表。早期综合发现仅用于仲裁扫描的 `offset` 未在所有组合路径赋初值，随后补默认值并重跑；原证据保留在 `switch_synthesis_initial/`。这些结果说明当前代码可以完成通用综合展开和结构检查，不构成工艺映射后的面积、STA、最大频率或物理签核。

## 下一步接入

Endpoint 初版每个 544 位 slot 作为单 beat、`last=1` 包接入，10 位目标由上层显式提供。随后逐步接通完整标准端口链、标准目的解析、管理配置与错误恢复；保留当前 fabric 的独立回归，分别报告新增模块的实现状态和验证范围。

完整模块骨架已接入 `u_scaffold`；`o_pending_features[127:0]` 的低127位表示未实现接口壳。`run_switch.py` 已纳入这些角色依赖，系统入口见 `ip_top_bringup.md`。位图不代表既有部分实现已具备全部协议能力。
