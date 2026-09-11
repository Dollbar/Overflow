# 完整普通 Read 集成静态复核

本审查只读核对当前 Read encoder、统一 formatter/Tag、receiver、Read completer、core/top 的实际连接，没有改 RTL，也未重复执行集成作者正在运行的仿真。范围是 `FULL_READ_ENABLE=1` 下普通未压缩 Read 与 Write 的衔接；规范边界见 [Read 契约](endpoint_read_contract_review.md)。

## 已核对的真实连接

- `endpoint_read_encode` 的 N 由地址低六位与 DWORD长度计算，NUMBEATS 线上仍为零。区域 mask 的首 DWORD 分支优先于末 DWORD，所以 LEN0 忽略 ATTR 高 nibble；非首末 DWORD全有效。九位边界运算保留256，不把 LEN63溢出为零。
- `endpoint_request_formatter` 使用实际 encoder 的 N 预约唯一共享 Tag 表，并将区域 mask 右移 `64*ADDR[7:6]` 成为相对首 Beat 的 mask；未右移数据本身。预约与请求握手同沿，后续输入变化不会改变已保存几何。Read ASI/metadata 在完整模式原样传递，Write仍保留原有字段和数据所有权。
- `endpoint_receive_transactions` 为每个 Read Response Header 保存 `2*(LEN+1)` 个 Data 半 Flit，只有全部属于该 Header 的半字收齐后才开放响应出口。Multi-Beat以512-bit Beat逐次输出，OFFSET从0起递增，所有 Beat保留相同原Header NUMBEATS，LAST仅最终Beat。Single-Beat保留原OFFSET/LAST；不能用本地输出计数覆盖其乱序位置。
- receiver响应队列只在最终Beat握手后弹出 Header，response_beat同时归零；Write Response LEN0一次弹出且无Data。共享Data owner在Read全部半字或Write Data/BE全部到齐后才释放；此前保留旧尾优先处理的EARLY状态，避免新Control等待空间阻止旧尾释放。未发现新增Multi收集会把Data误交给下一Header的静态路径。
- `endpoint_read_completer` 一次真实后端结果保存整个2048-bit结果及唯一状态。它按允许的Single-Beat模式逐Beat发送独立Header，OFFSET递增，所有N Beat共享status，只有最终Beat LAST1。每Beat必须同时完成Header捕获和两个Data半字实际接纳才推进；最后Beat完成才释放事务槽。错误结果制造零Data但仍发送全部N Beat。
- `endpoint_transaction_core` 的Read共享dispatch释放条件包括此前真实内存命令已握手、当前结果slot匹配、结果valid/ready及五种合法状态。它不在request ready、首响应Beat或应用完成时释放后端顺序占用。未知slot或非法状态同时由completer诊断；原Read/Write响应Header锁定仲裁继续独立于Data接纳。
- `FULL_READ_ENABLE=1,WRITE_ENABLE=0` 使用完整Read数据路径，但应用Write候选同时禁止valid进入formatter和ready返回，并报告配置能力诊断。receiver拒绝Write请求和Write Response；Write completer保持复位。`FULL_READ_ENABLE=1,WRITE_ENABLE=1` 使用相同统一Tag及共享后端调度；没有另建可能冲突的Read Tag域。
- top向core传递完整后端result、区域o_mem_be、完整完成data/mask和两个feature参数；默认prepared分支显式将新事务输出置零。完整事务仍限定本地port0、Auth关闭，不能据此声明完整多端口UPLI或安全能力。

截至下表源码身份，本次静态复核未发现要求修改的具体集成接线错误。这不是动态互操作或形式等价结论。

## 证据边界与后续确认

Tag单元最终normal/-O、四项真实故障、默认Read/Write兼容及静态检查见 [Tag报告](endpoint_read_tag_table_review.md)。本审查人也是该Tag实现作者，对Tag自身不声称第二份独立实现审查；本次独立部分是另一作者的encoder/formatter/receiver/completer/core/top连接与规范契约对照。

接收器的人工退休记录能验证MultiHeader实际Data所有权和输出语义，但不能替代完整TL/DL链路。当前发送选择Single-Beat，因此单纯本端ESE往返不覆盖Multi RX；需保留独立原始Multi记录测试。实际ESE还应验证全部LEN、mask原点64/128/192、错误必须全部收齐、真实执行次数、Write后Read与重放，不把单元通过外推为这些集成结果已经通过。

应用看到的无效lane清零是本地API策略。原始wire无效lane无需清零，后端允许返回自然对齐的完整Beat内容；有效字节mask和地址几何才定义可用数据。Poison目前仍fail-stop，不属于本轮已实现能力。MultiHeader LAST的原文歧义通过receiver按LEN重建末Beat处理，不能将Single-Beat的LAST检查一并放松。协议错误后的系统恢复和统一在途reset需另列实测证据。

## 本次读取源码身份

| 文件 | SHA256 |
|---|---|
| `rtl/endpoint/endpoint_read_encode.v` | `2d8909bba95ece88309977fa630df0fbe99127161c2050297043c2b021410b42` |
| `rtl/endpoint/endpoint_response_encode.v` | `08470e495bcbc58f85556f13e6a89b1139e0584bfb010b970f908852e37092b7` |
| `rtl/endpoint/endpoint_request_formatter.v` | `12eac681aeff6498985e430477be51ad525e2490b050ac088b2e40e08c8e4b4e` |
| `rtl/endpoint/endpoint_tag_table.v` | `98cee3d7f48ff4e0b83e7318a7af68cc505b47fff84ed76772eeeb85a156e623` |
| `rtl/endpoint/endpoint_receive_transactions.v` | `7d8dfd2f649ab0741273f679285ec826ad225e58c29fdc22a09fb8a49583d104` |
| `rtl/endpoint/endpoint_read_completer.v` | `0c102d02eed69528a8257b69cd63da17454207fb5cd3b5cf64f45212bcff73f5` |
| `rtl/endpoint/endpoint_transaction_core.v` | `653ac977dd76d7ad37a2252a22e2a232fecc74638f36f3b304c77a4f2911eeec` |
| `rtl/endpoint/ualink_endpoint_top.v` | `7d825d1bf95addc1004605469cb38e563e4c2d9487bef9a61474e9e974b16a9a` |
