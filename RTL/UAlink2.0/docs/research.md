# UALink 调研报告

调研日期：2026-09-07。结论级别：公开一手资料，保留最初公开调研的证据边界。此后已接入用户提供的三份规范正文；当前技术约束以 正文研读报告（历史文档已清理） 为准。本报告不是规范替代品，也不是法律意见。

## 1. 版本与资料基线

UALink 2.0 已发布：联盟于 2026-04-07 宣布相关规范获批，不应再按“未发布的未来版本”规划。[发布公告](https://ualinkconsortium.org/wp-content/uploads/2026/04/UALink-2.0-Specification-PR_FINAL.pdf)

本次核查的官方目录如下。版本不同是规范拆分的结果，不应强行把配套文档全部命名为 2.0。

| 文档 | 官方列示版本 | 本项目处理建议 |
| --- | --- | --- |
| Common | 2.0 | 核心目标；先提取端点、交换和 INC 相关要求 |
| 200G Data Link and Physical Layers | 2.0 | 首选链路方向；与 Common 联合核定 |
| Manageability | 1.0 | 同期研究管理接口，按实现角色确定范围 |
| Chiplet | 1.01 | 后续候选，不把 UCIe 集成作为首轮依赖 |
| 128G Data Link and Physical Layers | 1.0 | 替代 PHY 路径候选，本期不混用 |
| 200G | 1.0 | 历史背景，不能代替 2.0 正文 |

来源：[官方规范目录](https://ualinkconsortium.org/specification/)。目录称 128G 规范可用，但说明文本仍待补充；不能把“说明待补充”解释为规范未发布。Chiplet 在四月公告中为 1.0，当前目录为 1.01，取得文件时仍须核对封面及修订记录。

## 2. 技术定位：不是换名字的 KDLink

UALink 面向加速器 Scale-Up，基本通信语义包括远端 load/store/atomic，研究必须覆盖请求、完成及内存副作用，而非仅验证 payload 能从 A 到 B。官方 FAQ 还描述了交换中对同一 flit 内不同目的消息拆包、分别路由再打包的思路；这是交换微架构的重要研究线索，但确切 2.0 规则仍需正文核定。[官方 FAQ](https://ualinkconsortium.org/faq/)

官方 1.0 概览说明软件维护一致性的基础方式。不能由“内存语义”推导出完整硬件缓存一致性、自动 CPU 一致性或本项目已经具备统一地址空间。[1.0 概览](https://ualinkconsortium.org/wp-content/uploads/2025/04/UALink-1.0-Specification-Overview_FINAL-1.pdf)

Common 2.0 引入网内计算 INC。官方介绍以归约等操作说明其减少数据搬运的潜力，但不等于所有 Collective 都能直接在交换机执行，也没有给本项目提供可直接编码的算子、数据类型或异常语义。[INC 官方介绍](https://ualinkconsortium.org/blog/exploring-in-network-compute-how-ualink-is-redefining-ai-scale-up-architecture-1509/)

官方公开介绍将规模定位在单 pod 最多 1,024 个加速器，并说明利用 Ethernet 技术基础加入自身通信机制。工程判断：不应因此假定普通 Ethernet MAC、RoCE 或商用以太网交换机能直接互通。[联盟架构说明](https://ualinkconsortium.org/blog/building-open-scalable-ai-infrastructure-with-ualink-1532/)

因此不继承 KDLink 的 16-bit 地址、8-VC、共享 CRC 粒度、Exact-Once 机制或分层路由定义。仅可在另行审查后复用通用 FIFO、仿真基础设施、流量分析方法等与标准无关的资产；当前没有复制任何旧代码。

## 3. 实现边界建议（非规范指定框图）

```text
NPU/存储系统                         管理软件
    ↕ 本地适配接口                     ↕
UALink 端点协议逻辑 ───────────── 配置/遥测/错误管理
    ↕ 分层传输与链路处理
数字 PHY / SerDes IP
    ↕ 物理链路
UALink 交换设备：端口处理 → 消息路由/仲裁 → 端口处理
                         ↕
                   INC 功能（按规范）
    ↕
其他 UALink 端点
```

这是项目职责划分，不是已经确定的标准接口或 RTL 层次。建议先研究端点 IP、交换 IP 与管理软件三个交付对象；不要未经系统评估就决定“每张板一个 ASIC”或“每个 NPU 一个独立 ASIC”。端点逻辑可否集成 NPU、采用独立芯片或 chiplet，要由本地总线带宽、封装和授权条件共同决定。

交换结构的端口数、级数、内部总线宽度、仲裁和缓存深度属于实现设计空间，但必须满足标准的顺序、流控、前进性及能力声明要求。暂不冻结固定叶域大小或两级路由。

## 4. 带宽口径与性能研究

公开 1.0 概览列出 800 Gb/s/link，并允许每加速器多个 link；这不是本项目已经实现的带宽，也不能单凭旧概览锁定 2.0 的合法链路配置。[1.0 概览](https://ualinkconsortium.org/wp-content/uploads/2025/04/UALink-1.0-Specification-Overview_FINAL-1.pdf)

工程预算须分别报告以下量，均采用十进制 GB/TB，并注明单向或双向：

- 每 lane 的标称速率、实际物理比特率与编码/FEC 开销；不要互相替代。
- 每端点链路容量：若 R 为每 lane 每方向的预算速率、L 为有效 lane 数，则单向容量为 R×L/8。
- 有效吞吐：在同一计量边界扣除协议、空闲、重传及争用损耗；避免对已经扣过编码的容量再次扣除。
- 全域单向注入容量：各端点单向注入能力之和，不代表任意流量模式都能达到。
- 单向二分带宽：跨选定二分割的单方向容量；对 N 个等带宽端点，只有拓扑和交换能力支持时才能以 N×B/2 作为无阻塞设计目标。
- 端到端有效上限还受 NPU 内存接口、DMA、本地总线、交换缓存与反压限制。

KDLink 之前的双向 4.096 TB/s 只是历史背景，**未自动冻结为 UALink 目标**。需要先选定规范合法端口组合，再与 NPU 可持续注入量和封装/功耗约束匹配。

INC 对归约类流量的收益与 AllToAll(v) 的拥塞优化应分开衡量。工程推断：任意目的端需要不同原始数据的 AllToAll 通常不能通过归约来减少有效载荷；需研究打包效率、队列隔离、调度和热点，不能套用 INC 的宣传收益。

## 5. PHY、VIP 与认证边界

Synopsys 公开页面列有 UALink 控制器、PHY 和验证产品，但这不提供源码或项目使用授权。[厂商 IP 页面](https://www.synopsys.com/designware-ip/interface-ip/ualink.html)

其 VIP 详情当前标明 UAL_200 1.0，并列出协议分层检查、错误注入及链路配置能力。因此这是外部验证渠道候选，**不是已经确认可用的 2.0 VIP**；需取得具体发行版、覆盖条款及许可证信息。[VIP 详情](https://www.synopsys.com/verification/verification-ip/ualink.html)

本轮没有选定商业 IP，也未证明存在可直接使用的开源完整 2.0 RTL/VIP。未来依赖评估要分别检查：

1. 数字链路 BFM：时延、背压、错误注入，可用于协议调试，不能证明电气合规。
2. 标准相关数字 PHY：编码、FEC、训练、lane 处理等，以正文明确的层次边界为准。
3. 模拟 SerDes 与封装/信道：需要适配的 IP、模型及真实硬件条件，不由 RTL 仿真代替。
4. STA：需要实际数字设计、时序约束和对应工艺库；Liberty 无法代替高速链路电气验证。
5. 跨实现互操作/联盟一致性验证：独立的外部证据层级，不能以自研 VIP 自测冒充认证。联盟一月文章介绍其相关验证框架建设，本文不据此断言当前预约、认证或测试包的可用状态。[联盟合规介绍](https://ualinkconsortium.org/blog/advantages-of-ualink-rigorous-compliance-interoperability-testing-1237/)

## 6. 正文获取与使用条件

Common 下载页要求身份信息及 EULA 同意。条款给予内部评估用途的有限许可，本身不授予实施及相关 IP 许可；同时说明非会员选择实施时须自行承担并解决所需第三方权利。不能简化成“非会员绝对不能做”，也不能说“公开标准天然可以无条件开源”。[Common 评估协议](https://ualinkconsortium.org/specification/ualink-common-2-0-specification/)

最初公开调研阶段没有提交表单。后续获用户明确授权及表单信息后，已提交三份申请；官网返回联系确认，没有自动下载。用户随后手动提供 PDF，正文研读已开始。详见 [接入状态](../specs/acquisition_status.md)。规范、第三方 IP 与本项目原创代码的许可分别审查，评估授权不等于全部实施/发布权利已确认。

## 7. 资料冲突处理

- FAQ 部分回答仍面向 1.0，包括对未来 Collective 的描述；2.0 状态以新版公告及目录为准。
- 下载页评估协议模板日期为 2025-04-07，不是 Common 2.0 发布日期。
- 厂商宣布支持某生态不等于每个 VIP 发行版已覆盖 2.0。
- 目录、公告和介绍不能取代下载文件的修订记录、勘误及 normative 条款。

所有未核定项登记在 [待核定事项](open_questions.md)。当前可以继续公开资料分析，但不开始凭空设计 wire-format。下一阶段见 实施计划（历史文档已清理）。
