# 首批模块功能与衔接

已把三个未实现接口壳替换成有类型的真实 RTL：普通 Read 编码、普通 Read Response 编码、Switch 唯一启用目标查找。总库存仍为202项，现有60项部分实现、142个未实现壳。Endpoint slot11/12与Switch slot53保留但壳位清零；零位不代表整个模块职责或协议符合性完成。

- **RTL_SIM**：编码器1345条独立全位向量通过，5项真实故障检出；真实TL decode/tenure观察到Read零Data、Response两个Data半Flit。字段生成未接入真实请求/执行/完成链。
- **RTL_SIM**：lookup在1/2/3/4/5端口完成13044次整矩阵比较，2项真实故障检出；完整保留10位ID，拒绝无目标与重复启用目标。真实Switch调用公开onehot端口。
- **RTL_SIM**：提取后Switch在2/3/4端口通过完整字、包所有权、停顿保持、公平性及路由/保持两故障检查；四端口双Endpoint重放集成交付201个唯一记录，完成178次退休、10次重放，包含2个CRC坏槽与2次丢槽。
- **GENERIC_SYNTH**：两套顶层在当前全部RTL与固定SRAM黑盒绑定下，展开及结构检查通过；此处没有新工艺STA或门级面积结论。

Switch六步544位整字形式等价尝试在2/3/4端口均达到资源时限，明确未证明；未继续扩大求解。实际全宽回归单独成立，不能替代无界等价。

详细实现边界见 [字段编码评审](endpoint_fields_review.md) 与 [路由查表评审](switch_route_lookup_review.md)。证据校验值及当前RTL清单见 [增量证据](typed_modules_evidence.json)；原始运行产物保留在本地忽略目录，发布副本携带可复跑入口和摘要。旧顶层门级综合摘要仍属于前一个57+145快照，不借用为本次新源码的测量。

```sh
make ip-module-smoke IP_RUN_LABEL=fresh_modules
make ip-top-smoke KD28_ROOT=/authorized/Overflow IP_RUN_LABEL=fresh_system
make ip-top-elaborate KD28_ROOT=/authorized/Overflow IP_RUN_LABEL=fresh_elaborate
python3 verification/tools/test_ip_scaffold_lifecycle.py
```

输出在`build/verification/`与`reports/ip_tops/`，各入口要求新标签。骨架更新用`python3 scripts/materialize_ip_scaffold.py --refresh-aggregates`显式刷新两个有生成标识的聚合文件，变化的叶RTL仍禁止覆盖。已晋升条目的稳定slot继续占用，不能分配给新壳。

下一步把单64B Read串成真实因果事务：先预约完整Tag和结果容量，再发请求；远端从实际收到的字段发起内存读，收到内存完成后生成匹配ID/Tag的响应并供应完整Data；本端收齐数据后才报告应用完成，应用退休后释放Tag。所有阶段必须在反压、重复、未知Tag、错误地址和复位下保持所有权。标准逐跳TL/DL、native UPLI、Write/Atomic、PHY、INC、安全、管理、CDC/RDC及工艺时序仍未完整实现或签核。
