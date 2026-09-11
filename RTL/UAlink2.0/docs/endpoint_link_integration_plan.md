# 两端 TL/DL 实际模块集成计划

本任务仅修改 `verification/endpoint_link/` 和本计划/审查文档。依据 `config/tl_tx_buffered_contract.json`、`config/tl_receive_credit_contract.json` 与 `config/dl_replay/data_port_contract.json` 的已定义数字接口实施。

1. 建立两份实际 `tl_tx_prepared`（内含 `tl_tx_buffered` 与 prepared partition）、`tl_credit_admitted_port`、`tl_receive_credit` 与 `dl_replay_data_port`，发送/接收均使用显式授权 KD28 同步 SRAM 模型。
2. 测试适配器每个 DL 本地不透明槽保存一个 `{6'b0, M[1:0], TL[511:0]}`，共 520 bits。这是本地集成记录格式，不是标准 DL flit，也不代表 640-byte framing/CRC/FEC。
3. TL 信用扣除与源消费只发生于 DL 正常 payload_accept；重放必须来自 DL SRAM，不能再次消费 TL。对端仅在 DL payload_accept 后推进 TL 信用/接收 SRAM；退休通过真实 FC 发布器、TL 发送队列及反向 DL 返回信用。
4. 保存完整周期/事件跟踪，独立比较源 header/data 顺序、所有正常/重放 DL 数据、端到端 TL 记录、600-bit SRAM 退休字和信用归还；注入 CRC-status failure、丢槽，并检出实际连线数据破坏/重复消费等故障。
5. 用唯一 `--label` 保存编译/执行命令、工具版本、源码和外部模型校验值、trace、独立检查结果；拒绝覆盖既有证据。

本轮不生成生产 Endpoint 顶层，不生成未决 CRC 位序 A19，不连接完整 DL 控制/RS/PCS/FEC，也不声称 UPLI 读写响应闭环或 G2 完成。准备好的 Request/Response 是独立源流，尚非实际内存执行器生成的响应。后续将依据实测结果列出剩余连接边界。
