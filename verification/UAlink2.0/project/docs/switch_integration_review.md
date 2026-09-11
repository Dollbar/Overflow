# Switch 包子模块与原子路由配置集成

三个真实子模块已替换原接口壳，并接入`ualink_switch_top`：`switch_arbiter`保留每出口整包owner和轮询顺序；`switch_fabric`按完整字宽转发并拒绝选择冲突；`switch_route_table`保存shadow/active路由表并在空闲边界原子发布。库存为202个RTL条目：72个部分实现、130个壳。这里是明确目的sideband的本地单播packet服务，不是完整标准Switch或规范CSR实现。

## 顶层行为

默认`ROUTE_CONFIG_ENABLE=0`保留旧静态路由输入和数据通路接口，新增配置ack/pending/error/quiescent全为零。置一后，shadow单项写入不影响当前流量，显式commit在全部端口无输入valid、无锁包owner且shadow无重复enabled ID时才提交。并发write/commit、非法索引和busy提交拒绝，保留两表。复位沿清空表并关闭全部目的。新增参数和端口均追加，见[接口](switch_top_interface.md)。

仲裁器输出egress-major raw selection，lookup提供source-major route_match；fabric完成实际有效性门控。raw owner在首拍停顿和包内气泡中保持。顶层用`i_ready & o_valid`反馈真实出口接纳能力，只有实际有效末拍握手才退休，避免冲突路径被拒绝但内部虚假释放。包内dst不得变化；非法输入引发的选择冲突失败关闭，不承诺自动恢复。

`o_route_quiescent`必须同时看有效输入和实际owner。仅valid为零的包内气泡不允许配置切换；最后Beat握手的同拍也拒绝commit，下一完整idle周期才允许。管理方需要暂停新入口请求以到达idle；未实现自动停流、跨域管理或标准CSR映射。

## 实测与证据

- [仲裁器](switch_arbiter_review.md)：PORTS1..5共9465周期通过，7项实际逻辑故障检出。发布runner在生产路径重跑相同配置及g2001、无豁免Verilator、Yosys均通过。
- [交叉连接](switch_fabric_review.md)：13个端口/宽度配置、56743个组合向量通过，6项实际RTL故障检出，12项静态检查通过；生产路径重跑通过。
- [路由表](switch_route_table_review.md)：PORTS1..5默认/显式宽索引共10配置，3项实际故障检出；生产路径另重跑PORTS3、3位索引及静态检查。
- 实际top `module_refactor_final`：PORTS2/3/4/5，共5426周期、7097次完整字交付、3033个包，路由错接与提前释放包owner两项真实故障检出。
- [配置集成](switch_top_config_review.md)：PORTS1/3/4/5×静态/配置两模式，195项检查；气泡误判quiescent、lookup绕过active表两项真实顶层故障检出。覆盖同拍多端口原子切换、busy拒绝、重复ID、disabled初始态和复位。
- `switch_modules_full_read`：实际Endpoint→Switch→Endpoint完整Read/Write矩阵，在bank1及注入重放下完成812笔事务、4次真实Write执行和8次重放；该ESE仍使用默认静态路由模式。动态配置与多Beat包衔接由上述top配置测试验证。
- `switch_modules_config`：完整Read/Write Endpoint及启用配置的Switch通过Yosys层级/过程/优化/check。Switch为143个展开模块、1187个通用cell；这不是标准单元映射、PPA或STA。结构检查确认全部130个壳仍明确未实现，稳定slot不重排。

工程级`make test`返回0，199项工具测试含2项条件跳过，其余旧模型套件通过。配置/ESE共463项制品hash复核一致且受测生产源码无漂移。[只读接线审查](switch_integration_audit.md)未发现阻断问题。完整Endpoint core的既有严格lint债务及完整顶层STA仍开放。

## 复现

```sh
python3 verification/ip_tops/run_switch_arbiter.py --label NEW_ARB --static
python3 verification/ip_tops/run_switch_fabric.py --label NEW_FAB --faults --static
python3 verification/ip_tops/run_switch_route_table.py --label NEW_TABLE --ports 3 --index-width 3 --checks
python3 verification/ip_tops/run_switch.py --label NEW_SWITCH --ports 2 3 4 5
python3 verification/ip_tops/run_switch_top_config.py --label NEW_CONFIG --faults
python3 verification/endpoint_transaction/run_read_endpoint_switch.py --kd28-root /authorized/path --label NEW_ESE --matrix --bank-depth 1 --inject
python3 verification/ip_tops/run_elaboration.py --kd28-root /authorized/path --label NEW_ELAB --full-reads --writes --route-config
```

各runner输出新label的源码/SV/向量、编译运行日志、覆盖和hash到`build/verification/ip_tops`、`build/verification/endpoint_transaction`或`reports/ip_tops`。不覆盖旧记录；候选研发目录仅保留历史证据，发布入口不依赖它。记录身份见[switch_integration_evidence.json](switch_integration_evidence.json)。

后续仍须补全标准TL路由解析与逐跳TL/DL终止、每VC缓存/资源、公平性条件、vPod/多播、PHY、INC、安全、管理、CDC/RDC和实际工艺STA。三个模块的部分实现和壳位清零不会关闭这些完整Goal要求。
