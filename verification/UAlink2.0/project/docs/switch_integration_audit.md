# Switch 拆分总装独立接线审查

只读审查 `build/development/switch_integration_plan.md` 和当前生产 `ualink_switch_top`、`switch_route_lookup`、`switch_arbiter`、`switch_fabric`、`switch_route_table`。本轮没有修改生产或测试，也没有自行重跑总装。对已冻结本地 unicast packet profile，未发现阻断接线问题。

## 已核对结论

1. **矩阵方向一致。** Lookup 输出 `route_match[source*PORTS+egress]` 原样接 arbiter 和 fabric；arbiter 输出 `selected[egress*PORTS+source]` 原样接 fabric。Fabric 按相同 source / egress 交叉索引同时检查选择与目标，data 切片保留全 DATA_WIDTH 位，last 原样来自选中源。没有多余转置或把 source-major 当 egress-major 使用。
2. **Raw owner 没有被误当实际传输。** Arbiter 锁定后在 valid 气泡和 route 失配时保持 raw selection；fabric 仍检查对应 route 位，再以 source valid 生成出口 valid。有效路线的气泡继续透传 data / last / ready，保持旧 top 的接口行为；route 失配则关闭该路径，owner 保留等待恢复。
3. **退休以真实有效接纳为准。** Top 给 arbiter 的 ready 为 `i_ready & o_valid`，同时 arbiter 内部仍要求选中源 valid、route 匹配和 last。Fabric 若因冲突关闭输出，不会触发虚假末拍退休。该反馈没有组合环：arbiter 的选择过程完全不读取 ready；fabric 的 o_valid 不读取下游 ready，后者只反馈 o_ready。
4. **配置提交使用实际包所有权。** 配置模式中 `o_route_quiescent = rstn && !(|packet_owned) && !(|i_valid)`，不是检查 o_valid / o_select。首拍 stalled 的沿前 i_valid 阻止 commit，随后 owned 阻止；已锁包内气泡即使全部 valid=0 也不能 commit。末拍实际退休所在沿仍非 quiescent，下一周期所有源无 valid 且 owner 清除后才可提交。
5. **同沿配置和新请求不会混用表。** Commit 接纳要求当前无任何 i_valid；若新请求同沿已经有效，commit 被拒绝。接纳 commit 后 active ID 和 enable 一起用 NBA 切换，后续请求读取新表。Shadow 写入不会影响当前 lookup；同拍 write / commit、非 quiescent commit 或 enabled duplicate 均由 route table 拒绝，active 保持。
6. **默认模式保留静态接口。** `ROUTE_CONFIG_ENABLE=0` 直接把既有 i_route_ids / i_port_enable 接 lookup，write / commit / pending / config_error / quiescent 输出全部为零，悬空新增配置输入不影响静态通路。新增 fabric_error 独立报告选择冲突；正常唯一目标、整包稳定目的条件下不改变有效 packet 传输。
7. **复位边界一致。** Lookup 无时序状态，arbiter / route table 使用相同同步 rstn；fabric、arbiter raw select / owned 在复位低电平时组合关闭。配置模式的 quiescent 有 rstn 限定，不在复位中接纳 commit。表的 active / shadow 在复位时钟沿清空；复位前的配置 pending 不是异步清零状态，不能另行宣称它具有异步复位语义。

## 现有实测证据核对

生产 `build/verification/ip_tops/switch_arbiter/integrated_leaf/result.json` 的 PORTS1..5 均 passed、compile0 / run0，实编译 RTL SHA 与候选冻结相同。

已只读核对 `reports/ip_tops/switch_module_refactor_final/summary.json`：默认静态配置 PORTS2/3/4/5 均 compile0 / simulation0，分别交付 1086 / 1566 / 2024 / 2421 个 beat；routing / hold 两项真实接线变异均 compile0 / simulation1 并标记 detected。该 summary 的 top SHA 和全部 support_sources SHA 与审查时工作区一致。此结论不扩大为动态配置总装已经实测；动态提交、忙态拒绝及 reset 场景仍由对应完整回归提供证据。

审查时源码身份：

| 文件 | SHA256 |
|---|---|
| `ualink_switch_top.v` | `66fc4e51c011422b5641a2e5b1c9884ce4b6c848482409605c3dceeaa15780c1` |
| `switch_arbiter.v` | `4a1005fe57d8443bae78849e51995b21f6f223f4f4585dd5df6d938a611be0e5` |
| `switch_fabric.v` | `0ecb20eee74469030bae6834cc6e3db6543c2bbe70fa85dedb685712db243ea2` |
| `switch_route_lookup.v` | `4cb4c2558b2efe42e479806d88349c23f479224ac1a78c7538b5741db137fc8e` |
| `switch_route_table.v` | `8042939304a3b459bee49458f0f532bd84b4cfdf52c0246eaa8fa07b60550977` |

## 仍须遵守的边界

配置管理必须先使所有 ingress valid 停止并让既有包正常结束；即使一个 valid 因无路由而不能前进，也会阻止 commit。本地接口不强行取消该请求。配置模式复位后 active 表全 disabled，不能把外部静态表当成自动初始化数据；先配置并提交，再启动 ingress。

源须在整个已开始 packet 内保持目的身份，包括气泡。非法中途 retarget 可能使同一源产生多个 raw owner，fabric 会诊断并关闭相关路径；本模块没有定义从这种违约中自动恢复。配置模式 quiescent 规则保证合法管理操作不制造这种中途改路由；默认静态模式仍由调用方保证路由表在活动包期间稳定。

本次不声称规范 VC / QoS、多播、真实 TL 路由提取、每端口 TL / DL 终止、完整管理 CSR、原生协议一致性、CDC、形式等价或 PPA 已闭合。
