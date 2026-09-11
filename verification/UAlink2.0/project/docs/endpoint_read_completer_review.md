# 普通 Read 完整长度执行器复核

依据 [普通 Read 契约复核](endpoint_read_contract_review.md) 的 Common 2.0 §2.7.4.4–6、Table 2-7、§2.7.5、§2.8 与 Table 5-30 实现普通未压缩单播 Read。`endpoint_read_completer` 在既有参数和端口末尾追加 `FULL_READ_ENABLE=0`、`i_mem_result_data_full[2047:0]`、`o_mem_be[255:0]`；默认模式保留旧单64B行为及原故障注入锚点。`endpoint_response_encode` 仅追加同名默认零参数，不改变端口。当前集成仍限定 VC0/pool0，不包含压缩、INC、安全或逐 Beat poison。

完整模式接受 DWORD 对齐、LEN0..63、整个访问区间不跨256B区域的 Read；完整57位地址、ATTR、ASI、metadata均保存并透传。BE bit0 对应256B对齐区域的首byte：首DWORD采用ATTR低nibble，末DWORD采用高nibble，中间全部有效，LEN0完全忽略高nibble。全零BE仍是实际请求。一次后端结果携带最多四个自然64B Beat，低512bit为请求地址向下对齐64B后的第一个Beat；此数据原点与整个区域BE原点须明确区分。成功数据全部保留，包括无效lane的非零值。

本实现统一发送 **Single-Beat response**：每Beat一个LEN0的64bit Header和两个Data半Flit，OFFSET按相对Beat递增，最后实际发送的Beat才LAST。Header与Data独立反压、支持单半字接纳；前一Beat的两种所有权全部交付后才切换下一Beat，整个事务发送完后释放槽。状态0/2/3/6/8来自同一次真实后端结果，各Beat一致；非零状态制造全零Data并发送原定全部N Beat。结果可按slot乱序返回，响应保守按请求顺序发送。未知、未issued、重复、未用slot或保留状态结果消费诊断，不覆盖有效槽；第一次内存命令握手的同一沿还不算已issued。

复现命令：

```sh
python3 verification/endpoint_transaction/run_read_completer.py --label NEW_C3 --capacity 3 --checks
python3 verification/endpoint_transaction/run_read_completer.py --label NEW_FAULT --fault last
```

容量可选1/2/3/4，测试显式固定两位slot；`--fault` 支持 `data/be/last/early`。全部实际源、runner、TB、独立向量、命令、日志、内存字节文件和hash保存在 `build/verification/endpoint_transaction/<label>/`；已有label拒绝覆盖。`--checks` 对同份隔离源执行 Icarus Verilog-2001、Yosys `memory; opt; check -assert` 与 Verilator `--lint-only --language 1364-2001 -Wall`，没有禁用警告或lint pragma。

独立Python oracle枚举4096个DWORD起点/LEN组合（2080合法、2016非法），另有LEN0与LEN1各256个ATTR、五状态×N1..4、三种未对齐地址和两个零BE向量，共4633行。SV BFM从独立byte数组构造全部2048位结果，实际后端命令和响应逐字段对照；自然lane、完整Tag/ID、高位地址、上层未用Beat与返回N的边界均有检查。每例2614个实际请求/内存命令/合法结果/完整响应，5460个Header及10920个Data半字，2019个请求拒绝，35次零BE执行、893次地址bit56执行。Header预期采用独立位位置常量，不调用被测encoder生成预期。另对encoder新旧两模式共同遍历8192个状态/OFFSET/LAST/LEN/VC/pool/valid组合。

| 最终标签 | 容量 | 仿真周期 | 乱序先返回关系数 | 映射cell数 | latch |
|---|---:|---:|---:|---:|---:|
| `ordinary_read_frozen_c1` | 1 | 50757 | 0（单槽不适用） | 1856 | 0 |
| `ordinary_read_frozen_c2` | 2 | 29518 | 375 | 1932 | 0 |
| `ordinary_read_frozen_c3` | 3 | 22218 | 709 | 2006 | 0 |
| `ordinary_read_frozen_c4` | 4 | 19037 | 915 | 2080 | 0 |

四例编译、运行、g2001、Yosys映射检查、无豁免Verilator均返回0。每例实际填满对应容量；固定种子195241控制变化的内存延迟和随机独立Header/Data反压，均观察到Header先交付、Data先交付、部分/整对接纳。未知、未发、全部11种保留状态、重复结果和非二次幂未用slot均检查；还测试四Beat结果在Header捕获且仅一半Data交付后同步复位，确认剩余Beat不泄漏、旧结果被拒绝。工具wall time记录于result.json，不把cell数解释为物理面积或STA结论。

`ordinary_read_frozen_data/be/last/early` 分别真实旋转2048bit结果Beat、交换区域BE两半、强制每Beat LAST、跳过后端完成门控。全部编译0、运行1，分别命中 `READ_DATA_LOW`、`READ_BE`、`READ_HEADER`、`READ_CAUSAL`。旧源能力红测 `ordinary_read_capability_red_fixed` 编译0/运行1，实际拒绝合法地址4/LEN0/ATTR05请求；更早一次红测因TB缺参数展开失败，单独保留且不算行为证据。早期 `ordinary_read_final_early` 已真实运行失败，但首先命中未知诊断值而未被runner计为指定故障；补强未知/提前响应因果断言后重跑最终全部配置与故障，没有修改旧结果。

默认零模式的 `reports/endpoint_transaction/completer_ordinary_read_legacy_c3`、`..._c4` 各32请求回归通过；原地址高位、提前响应、上半数据故障均检出，容量3另检出错误回绕；两配置原g2001和Yosys检查通过。新旧两种响应编码模式也分别通过上述独立8192组合。没有执行完整项目strict style门限或形式证明，不能将这些检查称为全项目静态签核。

冻结SHA256（四配置受测源及全部产物逐项复核一致）：

- Completer：`0c102d02eed69528a8257b69cd63da17454207fb5cd3b5cf64f45212bcff73f5`
- Response encoder：`08470e495bcbc58f85556f13e6a89b1139e0584bfb010b970f908852e37092b7`
- runner：`d0300f549c6306c8e4d996c3d659fc6b7d7aadb69338edb350210483bc83ad82`
- TB：`27610f2c2ab4c82768524af43b2c60a2acedcb2c875aa9c47eeb1836d23fb0e5`

Python语法与本轮差异空白检查通过。本报告仅验证执行器与逐Beat发送，不包含完整Endpoint集成、接收Multi-Beat/乱序Single-Beat聚合、Tag最终退休或真实TL/DL链路恢复；下一步把冻结接口接入core并用独立实际路径测试复核这些因果关系。
