# Switch 原子路由配置服务复核

主线已安装此处冻结的RTL并接入真实顶层；集成结果见[Switch总装审查](switch_integration_review.md)。以下候选阶段与发布副本记录按各自快照保留。

`switch_route_table` 为现有十位目标查表提供本地 shadow/active 配置服务；不是规范CSR地址图，也不代表完整UALink路由、管理平面或Switch。候选位于 `build/development/switch_route_table/`，本轮没有修改production、inventory或top。主线安装及数据通路接入必须另行验证。

接口参数 `PORTS=4`、`INDEX_WIDTH=max(1,ceil(log2(PORTS)))`，允许显式加宽索引，参数表示范围为正端口数至1024、索引1..10位；本轮实际验证PORTS1..5。所有状态使用 `i_clk` 上升沿和同步低有效 `i_rstn`。输入为 `i_write_valid`、`i_write_index[INDEX_WIDTH-1:0]`、`i_write_route_id[9:0]`、`i_write_enable`、`i_commit`、`i_quiescent`；输出如下：

| 输出 | 契约 |
|---|---|
| `o_write_accepted` | 当前沿有效且索引合法、无并发commit时接纳一次shadow写入 |
| `o_commit_accepted` | 当前沿commit、无并发write、quiescent且shadow无重复enabled ID时接纳整表发布 |
| `o_route_ids[PORTS*10-1:0]` | active表，port p在`[10*p+:10]`，直接接lookup的同名输入 |
| `o_port_enable[PORTS-1:0]` | active使能，bit p对应目的p |
| `o_pending` | shadow和active存储bit不同，包括disabled entry的ID；相同值写入不产生虚假pending |
| `o_error` | 有效非法事件的组合诊断，不粘滞，不是线上错误码 |

shadow可在traffic期间编辑，active只在合法commit沿整表原子切换。两个enabled entry的相同ID拒绝commit；disabled重复允许。非quiescent提交、非法索引以及同拍write+commit均拒绝且保留此前两表内容；同拍write+commit不论索引是否有效都双拒绝。拒绝不会丢弃shadow修改。合法且内容未改变的commit仍返回accepted。复位沿将两表ID/enable全部清零；复位期间抑制ack/error。两个accepted都是本周期组合确认，实际副作用发生在时钟沿。

`i_quiescent` 是可信的外部保证。停止入口接纳、排空在途包与锁定owner、确保全部端口安全，以及跨时钟适配，必须由主线完成。本服务不从lookup valid或管理写入推断空闲，不实现CSR总线或CDC。

发布版复现入口：

```sh
python3 verification/ip_tops/run_switch_route_table.py --label NEW_P3 --ports 3 --index-width 3 --checks
python3 verification/ip_tops/run_switch_route_table.py --label NEW_FAULT --ports 4 --fault duplicate
```

入口通过 `ROOT=Path(__file__).resolve().parents[2]` 读取 `ROOT/rtl/switch/switch_route_table.v` 与真实 `switch_route_lookup.v`，输出到 `ROOT/build/verification/ip_tops/switch_route_table/<label>/`，不依赖development目录或复制的dependencies。已有label拒绝覆盖。候选源目录仍保留原 `run.py`、`contract.json`、TB及全部历史证据。发布版已在独立项目布局 `release_replay/` 中从任意工作目录 `/tmp` 实际运行，标签 `portable_from_tmp` 的行为、g2001、Yosys和Verilator全部通过。

最终候选标签为 `evidence/frozen_p{1..5}_{auto,wide}`，分别真正省略DUT INDEX_WIDTH参数使用默认值、或显式设为3；五端口两种方式的实际宽度同为3。每例包含定向0/1023及高位ID、250周期固定种子918241的混合编辑/提交/忙碌/索引激励、两次reset，以及直接连接现有lookup的逐周期目标结果对照。独立scoreboard用每ID占用位图判重复，RTL用端口对比较；每个沿前后都检查active原子可见性与pending。

| PORTS | 默认/显式宽度 | 写入次数 默认/显式 | 提交次数 默认/显式 | 仿真周期 默认/显式 | 映射cell 默认/显式 |
|---|---|---|---|---|---|
| 1 | 1/3 | 47/14 | 21/21 | 265/265 | 26/26 |
| 2 | 1/3 | 100/34 | 20/20 | 274/275 | 36/37 |
| 3 | 2/3 | 65/43 | 28/28 | 279/279 | 49/49 |
| 4 | 2/3 | 104/60 | 24/24 | 282/283 | 65/65 |
| 5 | 3/3 | 80/80 | 27/27 | 287/287 | 85/85 |

十次运行全部编译0/运行0、Icarus Verilog-2001通过、Yosys `memory; opt; check -assert` 通过且零latch。Verilator `--lint-only --language 1364-2001 -Wall` 全部返回0，未禁用警告。Erie技能轻量静态检查使用明确的i_clk规格，`evidence/skill_static_explicit` 结果0 issue。所有非单端口配置实际拒绝enabled重复；单端口重复不适用。默认PORTS2/4无可编码非法索引，因此显式3位配置补充验证非法index。所有配置都实际拒绝busy commit与同拍write/commit。

`evidence/frozen_leak/duplicate/busy` 分别真实将active ID输出接到shadow、移除重复门控、移除quiescent门控。三例均编译0/运行1，分别命中 `ROUTE_ACTIVE`、`ROUTE_ACK`、`ROUTE_ACK`，没有预设失败返回值。旧generic壳 `evidence/shell_red` 编译0/运行1，真实能力输出未实现。首版加宽enable索引的lint警告与早期技能检查记录保留；最终使用固定entry完整索引比较和明确编译期循环界限，没有更改checker或豁免规则。

冻结SHA256：

- RTL：`8042939304a3b459bee49458f0f532bd84b4cfdf52c0246eaa8fa07b60550977`
- 发布runner：`7bca175f692703eddc3a38b4ee807d30af9f87fe0c0fe7e9481add95d1ed01c5`
- 发布TB：`9fc4645ff1b36992f4c1b6c9c6e451d221832ef08c462895b66fba3d9947ee07`
- 受测lookup：`4cb4c2558b2efe42e479806d88349c23f479224ac1a78c7538b5741db137fc8e`
- 本地接口契约：`e9144e7f7abd6b2ecaa9d99da5a5a1b42bbf6a184ecb72abf075c640fa8faf70`

最终候选源与十份正常产物逐项hash一致。上述为本地配置服务和lookup接口验证；没有执行真实fabric排空协议、运行中Switch重配置端到端验证、形式证明、CDC或STA。下一步主线安装发布源后，用真实包owner/入口门控验证quiescence与原子切换的系统因果关系。
