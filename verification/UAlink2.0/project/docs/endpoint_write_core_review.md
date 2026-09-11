# 混合 Read/Write 核心集成复核

本轮测试两端真实 `endpoint_transaction_core(WRITE_ENABLE=1)`，包含真实 formatter、共享 Tag 表、接收解析/组装、Read/Write completer 和共享后端调度。测试专用桥保存实际 Control 与 Data 半字，分别产生 Header capture 和实际发送确认，并按真实 Header 的 CMD/NUMBEATS/RD_WR 将记录送入对端 receiver。桥每次只接纳一个 Data 半字。它是 prepared/receive 握手模型；本报告不计作实际 `tl_tx_prepared`、TL credit/packer、DL 或 Endpoint–Switch–Endpoint 验证。

可复现入口：

```sh
python3 verification/endpoint_transaction/run_write_core.py --label NEW_LABEL --capacity 4
python3 verification/endpoint_transaction/run_write_core.py --label NEW_FAULT --fault dispatch
```

支持容量 1/2/3/4；`--fault` 另有 `write_be`、`write_data`。输出位于 `build/verification/endpoint_transaction/<label>/`，包括全部隔离 RTL、TB、输入向量、字节内存前后快照、实际命令/日志和 SHA256 清单。已有 label 拒绝覆盖。

两端各发 19 笔混合请求。Python 按区域字节建立独立最终内存与每次 Read 的完整 512 位预期；SV 后端按相对 Beat/byte 遍历实际 RTL 提交的数据和 BE，直到真实 result 握手才更新内存，并逐命令核对全部 2048 位数据、256 位 BE、57 位地址及属性/ASI/metadata。每个请求只能执行和完成一次，完成前必须已有对应实际后端结果。Write 后 Read、Full256/Full64、跨三个 Beat 的稀疏 Write、区域 128/192 位置、全零 BE、byte255、地址 bit56、完整高位 Tag/ID，以及 Write 状态 0/2/3/6/8 和 Read 状态 0/3 均有实际激励。后端采用确定性的变化延迟 40–76 周期，非随机测试；应用前 501 周期阻塞，之后周期性反压，并检查完成字段保持。

| 实际标签 | 容量 | 请求/完成 | Write/Read 后端完成 | 周期 | 应用阻塞采样数 |
|---|---:|---:|---:|---:|---:|
| `write_core_review_c1` | 1 | 38/38 | 18/20 | 2342 | 804 |
| `write_core_review_c2` | 2 | 38/38 | 18/20 | 1617 | 826 |
| `write_core_review_c3` | 3 | 38/38 | 18/20 | 1574 | 821 |
| `write_core_review_c4` | 4 | 38/38 | 18/20 | 1460 | 813 |

四配置均 Icarus 编译 0、VVP 运行 0；每例实际达到对应容量上限，包含 2 次零 BE 完成、4 次高地址完成和 112 次单半字接纳，最终逐字节检查两个 4096-byte 内存并确认占用归零。检查了排空后的同步复位；未覆盖在途复位恢复。

`write_core_review_be/data/dispatch` 的实际隔离源码故障分别断开后端 BE、清零进入 Write completer 的完整 Data、提前放开共享 dispatch。三者均编译 0、运行 1，分别命中 `MIXED_BACKEND_BE`、`MIXED_BACKEND_DATA`、`MIXED_DISPATCH_EARLY`，没有用预设失败返回值替代仿真。`write_core_review_red` 使用父代理保存的旧 core，因无 WRITE_ENABLE 参数展开失败（返回 2），只作为接口红测。最初 `write_core_initial_c4` 的超时由测试桥把 NUMBEATS 错取成 VC 引起；修正至 Header 低 2 位后通过，旧失败完整保留，不归因 RTL。

冻结复核时，全部受测源与当前文件逐项 hash 一致；本轮只新增测试与本文档，无生产 RTL 编辑：

- core：`9638ef06d3ca85807a7eea41f79f59ce0e43e495ee761bc8ff446230c4eae213`
- runner：`9f982e4187227fc21795bc361c00211e5673f160e778f2909d4d712cc017e0cf`
- TB：`7bb1b883b27d9dcc976bce31cd62e9715904f5a740c93bad877bfd27df48a870`

Python 语法检查通过。该层验证内存因果和字段贯通，不替代编码器独立 literal 测试或 exhaustive Write 几何测试；未执行形式证明或物理签核。下一步由实际 prepared/TL/Switch 路径回归复核相同字节语义，并另测在途复位和跨接口异常恢复。
