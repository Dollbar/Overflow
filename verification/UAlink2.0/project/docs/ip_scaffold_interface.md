# 未实现功能的显式接口骨架

模块库存`config/ip_module_inventory.json`是生成入口。库存中planned模块具有明确
源码路径与角色位号；生成骨架不将其状态改成implemented，不证明这些功能已完成。
已有真实RTL不能被覆盖或降级为骨架。

每个骨架统一使用输入`i_clk/i_rstn/i_enable/i_valid`、`i_data[511:0]`、
`i_meta[127:0]`，输出`o_ready/o_valid/o_data[511:0]/o_meta[127:0]`
和`o_implemented/o_error`。未实现时implemented/ready/valid及数据/元数据均为0；
`o_error=i_rstn && i_enable && i_valid`。因此它不会伪装为可接纳事务的功能，
也不会静默透传输入。时钟端口是未来实现接口预留，当前骨架无状态。

角色聚合模块为`ualink_endpoint_scaffold`和`ualink_switch_scaffold`，接口完全相同：

```verilog
input wire i_clk;
input wire i_rstn;
output wire [127:0] o_pending_features;
```

聚合层真实实例化本角色所有库存planned骨架，把enable、valid、data、meta绑0；
时钟与复位直通。位图使用库存稳定slot，每个对应位为该子模块`!o_implemented`，
未分配位为0。能力缺口不是运行状态，因此复位期间仍显示pending。角色聚合层仅作
结构与缺口展示，没有连通、仿真通过或协议实现声明。

脚本`materialize_ip_scaffold.py`默认仅创建不存在的文件；已存在文件若与预期不同则拒绝，
不会覆盖未来叶模块实现。只有显式`--refresh-aggregates`可以刷新两份固定路径且保留
生成器标识的聚合文件。`--check`只读核对全部预期文件，不创建目录或修改文件。
结构检查器独立核查模块声明、角色实例与slot，并使用Yosys展开角色聚合层核对
实际常量位图；源码文件存在与功能已实现分别报告。

## 生成位置与稳定角色位图

初次落盘库存为202个RTL模块：57个`existing_partial`保持原有实现，145个`planned`
生成接口骨架。planned状态表示功能尚未实现；文件已创建后结构报告使用
`materialized_shell_only`，不继续称这些文件缺失，也不将它们升级为功能完成。
库存的目标路径为`rtl/<subsystem>/<module>.v`，未来实现可原址替换；生成器按该
路径创建，只有两个角色聚合模块位于`rtl/scaffold/endpoint/`及`rtl/scaffold/switch/`。

Endpoint包含109个planned角色实例，稳定slot为0..108；Switch包含127个，slot为
0..126。同一共享模块可以同时出现在两个角色中，角色位号各自独立，不能把实例数
简单相加当作独立模块数。Endpoint位图为`00001fffffffffffffffffffffffffff`，
Switch为`7fffffffffffffffffffffffffffffff`。位号来源是每个库存条目的
`feature_slots`，不是文件名排序或当前目录遍历结果。

## 执行命令与产物

从仓库根目录执行：

```sh
python3 scripts/materialize_ip_scaffold.py
python3 scripts/materialize_ip_scaffold.py --check
python3 scripts/check_ip_structure.py --label NEW_STRUCTURE_RUN
```

生成器输出145个planned源文件及两个角色聚合文件；再次运行时相同文件只核对，
不同文件报错退出而不覆盖。`--check`不创建目录，不写文件。两脚本均可用
`--root PATH`检查隔离的仓库副本。

结构检查器要求新label，输出不可覆盖的
`build/verification/ip_structure/NEW_STRUCTURE_RUN/`：`evidence.json`保存结构数量、
角色位图、源与库存哈希；`interfaces.json`保存展开前端口；两个角色分别有
`*_hierarchy.json`、`*_flattened.json`及Yosys脚本/日志；`scaffold_contract.sv`
及对应SAT日志检查拒绝服务行为。

检查器不调用生成器模板。它对145个实际模块分别连接任意输入，在独立断言中证明
ready/valid/implemented及输出data/meta为0、error等于rstn&&enable&&valid，且没有
输入假设、状态或存储器。角色检查在优化前检查真实子模块数量、端口绑0和各slot
连接到对应子模块的implemented反相，优化后再核对128位实际常量。只硬编码正确
最终位图而没有真实子实例，不能通过该检查。

下一步应逐模块建立正式语义接口、实现并验证，再审核库存状态与聚合关系变更。
生成器默认不会覆盖不同的旧聚合文件；库存调整导致预期聚合变更时需要先审查晋升，
再显式启用下述刷新模式。结构通过不代表规范功能齐全、时序达标、
安全协议完成或整IP交付完成。

本轮实际执行普通与`-O`结构检查均通过，最终`evidence.json`逐字内容一致；记录位于
`build/verification/ip_structure/scaffold_final/`及`scaffold_final_optimized/`。
8项真实副本检查验证了只读核对不改文件，以及缺源码、已有实现保护、假ready、错误
error条件、仅硬编码位图、缺角色实例和接口宽度错误均被拒绝；记录位于
`scaffold_mutations/results.json`。最终汇总为同目录上层的`scaffold_summary.json`。
这些检查证明库存结构及骨架的明确未实现行为，不证明145项计划功能已经实现。

## 叶模块晋升与显式聚合刷新

当一个叶模块建立了typed接口、实现及独立功能证据后，先在库存中把该项从planned
晋升到合适的实现状态，同时**保留其原有全部`feature_slots`**。原槽位仍属于该模块，
不能分配给另一新功能。生成器与结构检查器都检查所有携带feature_slots的条目，
包括`existing_partial`，而不是只检查剩余planned条目。

之后执行：

```sh
python3 scripts/materialize_ip_scaffold.py --refresh-aggregates
python3 scripts/materialize_ip_scaffold.py --check
python3 scripts/check_ip_structure.py --label AFTER_REVIEWED_PROMOTION
```

刷新只允许覆盖以下两份固定聚合路径：

- `rtl/scaffold/endpoint/ualink_endpoint_scaffold.v`
- `rtl/scaffold/switch/ualink_switch_scaffold.v`

发生内容变化时，旧文件必须具有生成器的两行开头标识，并且声明对应的唯一角色
module。无标识、身份不符、符号链接或变化的叶RTL均拒绝处理。写入前先检查所有
预期文件，避免某个叶保护失败之前已改动聚合层；每份聚合文件通过同目录临时文件
原子替换，并保留原权限。`--check`与`--refresh-aggregates`互斥。

晋升后的typed叶不再经过通用骨架模板，也不再被接到通用服务聚合端口；真实功能
连接由其实际父模块负责。聚合层删除它的未实现壳实例，其原pending位变0，但槽位
在库存中继续保留。**pending位清零仅表示该通用壳已晋升，不等于该模块的全部规范
功能已完成**；`existing_partial`仍须保留其准确功能边界。库存若删除历史槽位信息，
生成器没有独立历史数据库来重建它，因此库存审查必须保留分配记录。

生命周期检查全部在临时库存/RTL副本中执行，没有修改本次工作树的库存或真实聚合
文件。8项普通与`-O`测试通过，包括：叶RTL拒绝覆盖、默认拒绝变化聚合、显式刷新
两角色聚合且typed叶字节保持、晋升后槽位复用拒绝、无标识聚合拒绝、只读/刷新模式
互斥，以及实际CLI刷新与只读无写入。刷新成功的副本还通过Yosys展开、位图检查及
剩余壳行为证明。红测、最终日志和测试入口保存在
`build/verification/ip_structure/scaffold_lifecycle/`；下一步由root协调实际晋升后
再执行生产库存的显式刷新和结构复验。
