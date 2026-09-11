# 完整 Read 共享 Tag 表实现与检查

`endpoint_tag_table` 追加 `FULL_READ_ENABLE=0`，默认保持既有 Read/Write 行为。完整模式在预约时保存 Read 的 N-1 和相对首 Beat 的 256-bit 有效字节图，结果空间扩为 2048 bit。每 Tag 独立保存已收 Beat 位图、响应模式和统一状态；Single-Beat 可乱序及跨 Tag 交织，Multi-Beat 必须从 OFFSET0 顺序返回且总长度匹配预约。只有 LAST 与全部预期 Beat 恰好收齐同时成立才标记完成，五种合法错误状态也必须收齐。非法 Beat 不更新任何槽，不释放或损坏别的事务。

完成输出由既有仲裁锁定，应用反压时身份、完整数据、mask 和状态保持。成功 Read 只保留 mask 指定字节，未选 lane 置零；这是本地 API 策略，不要求对端发送的无效 lane 为零。错误和 Write 的 full/mask 输出为零，旧 512-bit 数据口是完整结果的低 Beat 视图。成功的零 mask Read 仍完成一次并保留成功 data_valid。共享 `(port,tag)` 空间、kind 检查、真实 Header 发出标记与应用接纳后退休均保持。Poison 本轮仍诊断拒绝，不把普通长度扩展称为 poison 支持。

新增端口为 `i_allocate_read_num_beats[1:0]`、`i_allocate_read_mask[255:0]`、`o_complete_data_full[2047:0]`、`o_complete_mask[255:0]`，均追加在原接口之后。默认和 Write 路径不依赖新增预约输入。原 `r_data` 名称及现有 Tag/kind/目的/重复响应/完成重选/错误 data_valid 的故障锚点保留，既有故障测试实际仍检出。

## 独立测试与证据

```sh
python3 verification/endpoint_transaction/run_read_tag_table.py --label fresh_read_tag --faults
python3 -O verification/endpoint_transaction/run_read_tag_table.py --label fresh_read_tag_optimized --faults
python3 verification/endpoint_transaction/run_originator.py --label fresh_read_tag_legacy --faults
python3 verification/endpoint_transaction/run_write_originator.py --label fresh_read_tag_write_legacy --faults
```

输出保存在 `build/verification/endpoint_transaction/<label>/`，包括独立 Python 事件/字节预期、隔离 RTL/TB/runner、命令、实际日志及产物哈希。label 必须全新。期望完整字节由 Python 对应用 Beat 字节逐 byte 施加 mask，SV 比对实际完整结果；不读取 DUT 内部状态来生成期望，不调用生产编码器或共享模型作为 oracle。SV 在负沿驱动，沿前检查事件合法性，正沿后检查结果，避免计数反馈 ready 的同沿竞态。

| 证据标签 | 结果 |
|---|---|
| `read_tag_full_red` | 最初 fixture 把 Python bool 输出成文字导致解析失败；保留，但不算功能红测 |
| `read_tag_full_red_runtime` | 使用旧表及显式兼容 wrapper；三个容量均 compile0/run1，实际缺少完整 mask/数据能力触发 COMPLETE_BYTES，随后才修改生产 RTL |
| `read_tag_full_final` | 7/7：容量1/3/4分别完成202/207/208笔，另四个真实 RTL 故障均检出 |
| `read_tag_full_final_optimized` | Python `-O` 同样7/7，覆盖与结果一致 |
| `read_tag_full_legacy_final` | 原默认 Read Originator 10/10，含七项既有实际故障 |
| `read_tag_full_write_legacy_final` | 既有 Write/formatter 4/4，含 kind 与 Data 次序故障 |
| `read_tag_full_static_refined` | FULL_READ_ENABLE 0/1 的 Verilog-2001、严格 Verilator `-Wall`、Yosys hierarchy/proc/opt/check，六项均返回0 |

正常用例覆盖 N1..4 的全部 Single-Beat OFFSET 排列×五状态、各 N 的 Multi-Beat×五状态、完整 mask/稀疏 mask/零 mask、未发送/未知响应、跨端口同 Tag、共享 Read/Write Tag 冲突、容量满、应用保持与 reset。负例包含早 LAST、缺 LAST、重复/越界 OFFSET、模式变化、Multi 顺序/长度错误、状态变化与全部普通保留状态、错 kind/目的/高 Tag 位和 poison。被拒绝的 Beat 后再补发正确 Beat，可验证先前数据与身份未被污染；这是 Tag 单元的局部恢复测试，不宣称系统对协议错误必然恢复。

四个新故障分别在隔离实际 RTL 中绕过 byte mask、把所有 Beat 写向 Beat0、收到首 Beat 即 done、取消跨 Beat 状态一致性。均实际编译成功并运行失败，分别命中字节、提前完成或响应合法性断言。未以预设 exit code 代替实际仿真。最终正常及 `-O` 两组共98份 artifact已重新计算 SHA256，零缺失、零差异。

初始静态尝试保存了两项表达式位宽警告；已显式扩宽清零路径。随后 `read_tag_full_static_final` 在 Yosys proc 阶段因逐 byte 动态写入的中间表达式规模触发60秒超时，记录在该目录 `attempt.json`。最终改为组合 byte mask 后一次写入512-bit Beat，语义测试全部重跑通过，静态检查也通过；没有进行形式等价、工艺面积或时序宣称。

## 冻结身份与边界

| 文件 | SHA256 |
|---|---|
| `rtl/endpoint/endpoint_tag_table.v` | `98cee3d7f48ff4e0b83e7318a7af68cc505b47fff84ed76772eeeb85a156e623` |
| `verification/endpoint_transaction/run_read_tag_table.py` | `56445cb5a98b20dca0ffb0bf562fad03b8f43ba64807fe19f34567c866364c90` |
| `verification/endpoint_transaction/read_tag_table_tb.sv` | `99a9b23765f119843466c2b7441e6d0efd66c4e6fddbd938bfd0302646933f85` |

本模块接收已经归属并组成完整512-bit Beat的内部响应；Multi-Beat OFFSET/LAST由 receiver 重建，不能将本表的逐 Beat检查直接套到有歧义的原始 Multi Header LAST 上。表中不重算请求地址/LEN/ATTR几何，调用方负责合法几何和 mask；尚需真实 encoder→formatter→receiver→completer→core/top 数据链路测试。无效事件 o_error 为当前事件诊断，系统 fail-stop/reset策略由上层决定。下一步按 [实施契约](endpoint_read_execution.md) 接通这些真实模块，独立验证完整普通 Read 与既有 Write 的后端执行及重放因果。
