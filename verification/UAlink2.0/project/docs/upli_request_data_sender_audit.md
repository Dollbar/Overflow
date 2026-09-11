# 原生 Request/OrigData 共享发送器独立审查

本轮只读检查候选 `build/development/upli_request_data_sender/upli_request_data_sender.v` 与执行契约，未修改 RTL/TB。未发现确定的接线错误。实际 Yosys `hierarchy -check; proc; opt_clean; check -assert; stat; write_json` 对下列三个有界配置返回0，并对生成的层级 JSON 逐位比较真实连接。证据在 `build/development/upli_request_data_sender/independent_audit/result.json`；它不是行为等价证明、STA 或完整参数穷举。

| PORTS | 信用位宽 | 初始化确认周期 | 实际每个顶层的模块数量 |
|---:|---:|---:|---|
| 1 | 3 | 3 | sender1、burst_control1、credit_bank2、Request leaf1、OrigData leaf1 |
| 2 | 4 | 2 | 同上 |
| 4 | 16 | 3 | 同上 |

两个银行在 sender 内分别对应 Request 和 OrigData，不是两套 sender 各自扣信用。wrapper 向唯一 sender 原样传递 C_NUM_PORTS/C_CREDIT_WIDTH、两个独立容量向量、默认容量、初始化位宽和周期，固定 `C_REQUEST_WIDTH=184`；没有另一个 TDM 相位或尾部存储。检查到实际余额输出位宽为 PORTS×5×CREDIT_WIDTH，输入数据2048/BE256/Error4完整。

184位打包的实际切片从低位向高位为 Metadata[7:0]、Attr[15:8]、Length[21:16]、Command[27:22]、Address[84:28]、NumBeats[86:85]、Tag[97:87]、Dst[107:98]、Src[117:108]、AuthTag[181:118]、ASI[183:182]。已核对每个 Request leaf 输入来自 sender 的对应切片，每个 typed 输出同时成为 debug payload 重打包的同一切片；没有字段遗漏、交换或高位截断。Port/VC/Pool 单独来自 sender 实际事件，不取未接受候选。

`u_request.i_valid` 接 `raw_o_req_valid`，并非 `i_candidate_valid`。底层 control 的实际 Request valid 与 candidate_accepted 为同一事件，包含连接、时隙、信用初始化、信用余额及旧 burst 所有权资格；Request leaf 的复位门控不能在候选未接受时制造发送。全部 OrigData valid/port/data512/BE64/offset/last/error/VC/pool 均由 sender 输出进入 `u_orig_data`，再到公开输出，parity 也由该 leaf 提供，未发现绕过 leaf 的数据路径。

wrapper、sender、两个银行、burst_control 的 i_clk/i_rstn 实际连接同一输入；Request leaf 只使用同一 i_rstn 做组合门控，OrigData leaf 无独立状态或复位，其有效事件已由 sender 复位资格约束。正常尾部发送同样受共同 reset 抑制；本审查没有另外宣称异步复位、CDC/RDC 或异常断链恢复。

需精确表述的文档项：执行契约第二段原写 typed output modules “generate/check protection groups”；当前两个 TX leaf 只生成 parity，没有接收的 parity 或 RX error 端口，应写“generate parity”。已向 owner 报告，属于交付范围措辞，不是 RTL 接线缺陷。后续复用公共 parity leaf 也不自动表示 wrapper 已启用其接收检查。

这是完整暂存 Request/OrigData **发送服务**，不是完整 station/RX。上游必须提供合法命令、匹配的 has_data、两处 NumBeats 以及长度/地址/BE几何，认证未启用时按契约将 AuthTag 置零。wrapper 传输层不检查这些关系；随机字段保持测试只证明位保留，不能称所有随机组合都是合法 UPLI 请求，或所有命令语义均已执行。

审查快照：wrapper SHA-256 `acd90c8a2feaf04177a52558cb58d180a9ae06e9305932bf73f2058585be4115`；Request leaf `a2e02374041e4615c0c68e449747cbd85594226fe880c3b3f7e0e6577fd57fda`；OrigData leaf `36bce7856ddea52b0e76090e3ae1d166dac64bda4bf9706068f358b83c3eb530`。此时两个 leaf 使用各自 XOR 生成逻辑，**尚未计入后续公共 parity 实例改造**；改造后须另保留对应源码哈希和回归。六个源的完整哈希及前后无变化检查在证据 JSON 中。最初统计脚本未去掉 Yosys hdlname 的转义前缀导致解析失败，已保留 `parser_first.json`；它不属于 RTL 失败，也未覆盖原日志。
