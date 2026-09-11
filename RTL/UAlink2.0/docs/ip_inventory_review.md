# IP 模块清单范围审查

对照 [交付计划](ip_delivery_plan.md) §1–2、§4–5，只读审查 `config/ip_module_inventory.json` 快照 SHA-256 `e5f9f4db2e2548138166553c9fa79decdb165f862c438bf1e46a4e47f47b996d`。结论：**所检查硬件功能族均有责任模块，未发现整族遗漏；清单支持先备齐模块骨架，不证明功能或标准条款已完成。** 本次未重新查阅规范正文，章节引用仅按工程计划评估，不增加规范符合性声明。

| 计划功能族 | 清单支持与边界 |
|---|---|
| UPLI 调频、两阶段通告 | `station_rate_controller` 明列 Accelerator 两阶段与多端口 ACK、Switch 固定速率；依赖 Basic、`tx_pacing`、平台时钟适配，另有 CDC FIFO/事件桥 |
| 多 station、bifurcation | `station_array`、`station_bifurcation`、`station_port_identity` 覆盖数量展开、三模式与身份映射；不能据此宣称全部数量/模式已综合或允许 Pod 任意混搭 |
| DL Basic/UART、PHY 增强 | 既有 Basic/Control/UART/重放部分 RTL 加完整 DL/PHY 规划；Folding、Resiliency、interleave/deinterleave、对齐/deskew/rate-match 均有 owner；UART 自定义消息仍不在范围内 |
| INC 全范围 | primitive、组/成员/归约、Block Allocate/Invoke/Deallocate、队列/Tag/地址/状态/排空及整数/浮点/舍入/扩精度/确定性/错误聚合均有模块；不是仅 AllReduce 演示 |
| 安全 | GCM/KMAC、PCRC、请求/响应映射、三流换钥、counter、认证后释放、INC 域和可信配置均已分配；RoT/密钥注入留在外部平台边界 |
| 管理、RAS、CDC/reset | CSR/能力/路由安全配置/中断/遥测/快照、Drop/Isolation/timeout/link恢复、跨域事件/数据/复位均有 owner；管理网络服务与 CPER 持久化明确列在软件/外部范围 |

**需要细化，不能靠增加模块数关闭：**

1. INC 的“完整矩阵”和 `FP8等` 仍是范围描述，缺逐项合法 **primitive/算子 × 类型/精度 × 舍入/数值边界** 及 Block 生命周期验收映射。应挂到 `inc_numeric_dispatch` 等现有 owner，并保留 A10/A18 未决项；不需要仅为凑数量再建同义模块。
2. 调频的参考速率 ACK→切频→新速率 ACK 顺序、先 pacing 后 ACK、1 μs 时限及共享时钟域全部活动端口的完成屏障，需绑定具体 requirement、接口和测试。station 的端口数量/三模式能力/Pod 一致性/受控重配置，以及安全三流换钥与 reset/迟到消息，也需从模块级目的继续细化到验收条件。
3. `existing_partial` 没有未实现服务槽，不代表其功能完整；pending bitmap 是工程骨架状态，不能直接用作标准能力编码或“完整 IP”标志。两个顶层 `purpose` 中的“完整数字IP”应按目标范围阅读，交付说明必须继续标明当前实际功能 profile。

**最终快照重核：**202 条硬件记录均有文件且声明名匹配；57 条仍为 `existing_partial`，145 条仍为 `planned`，后者现已生成拒绝服务骨架。所有 planned 的 `existence_at_inventory=false`，所有既有部分实现的该字段为 true；新壳物化不是覆盖原生产 RTL，也不是功能完成。`id/module/path` 无重复，依赖无悬空；Endpoint 109 个、Switch 127 个角色槽位无重复/越界，槽位所属角色一致。上述功能族 owner 均仍存在，补充职责/层级/来源没有改变本审查结论；数字仅描述文件与范围记录，不是功能覆盖率。
