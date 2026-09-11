# Endpoint Read Completer 实作审查

本次将 `rtl/endpoint/endpoint_read_completer.v` 的占位接口替换为真实四槽执行器。验证对象为 `CAPACITY=4`、`SLOT_WIDTH=2` 的普通单 64 B Read 子集；它不是完整 Endpoint。每槽预留请求描述符和 512 位结果，必须依次发生请求接纳、内存命令握手、合法内存结果握手，才允许该槽产生 Response 和 Data。内存命令按接纳顺序发出，结果按 slot 可乱序返回，发送按请求顺序提交。

## 冻结接口和生命周期

共用 `i_clk`，`i_rstn` 为同步低有效复位；运行时 `i_local_id[9:0]` 稳定。请求保存完整 Tag 11 位、双方 ID 10 位和地址 57 位；长度、Attr、ASI、Metadata 原样保存到内存接口。接纳条件是目的 ID 等于本地 ID、地址 64 B 对齐、Length=15、Attr=FF、VC=0、Pool=0、ASI=0、Metadata=0。非法描述符 `ready=0,error=1`；容量满只背压。RTL 不限制地址在 4 KiB 内。

`o_mem_valid/i_mem_ready` 真实握手后，从下一周期起才接受对应 slot 的结果；零周期同沿结果不属于此接口契约。结果状态只允许 0/3。`o_mem_result_ready=i_rstn`，空闲、未 issued、重复完成、越界 slot 或非法状态的有效返回均消费并诊断，不更新槽。默认四槽的两位 slot 没有可编码的越界值；回归覆盖空闲、未 issued 和重复槽，不能据此宣称非二次幂越界已验证。

队首完成后实际实例化 `endpoint_response_encode`，保留 Tag/Status，交换请求 Src/Dst，生成单 Beat、Offset=0、Last=1 的 Response。`i_source_captured` 只转移一次 Header；`o_data_valid`/`i_data_accepted` 分别表示提议和实际接纳的 0/1/2 个 256 位半 Flit。低半先提交，部分接纳后剩余高半移到低位。Header 和 Data 可分别先被接纳，只有 Header 与两半 Data 均被接纳才退休。无有效 Header 的 capture 和超过提议数的 Data 接纳会诊断，非法反馈不推进对应状态。

复位清除本地生命周期和占用，阻止旧数据再次有效。外部内存也必须取消旧 epoch 的未完成操作：slot 只有索引，没有世代号；复位后槽重新使用时，本模块不能识别迟到的旧返回。测试覆盖已保存结果、尚未发送时复位，以及重新分配前的旧返回诊断，不声称具备跨复位 epoch 区分能力。

## 实际验证与证据

先对原壳运行 `--label shell_red --mode shell`：编译返回 0，运行返回 1，实际报 `FAIL unimplemented_completer ready=0`。该证据保留旧壳源码快照；当前新接口不再适用 shell 模式。最终命令：

```sh
python3 verification/endpoint_transaction/run_completer.py --label ordering_final
```

证据位于 `reports/endpoint_transaction/completer_ordering_final/`，包含 `summary.json`、源码/编码器/测试脚本快照、独立字节内存与向量、完整编译/运行日志和命令。标签不可覆盖；再次运行须使用新标签。Python 直接编码预期字段并从字节数组生成预期 512 位数据；SystemVerilog 内存 BFM 独立按实际完整地址访问字节内存，并按已握手 slot 返回，未读取 DUT 内部状态或用 DUT 输出生成预期。BFM 4 KiB 映射外返回 Status=3；这是测试内存行为，不是 RTL 地址限制。

正常编译/运行均返回 0：32 个请求、32 个内存命令、32 个结果、32 个完整响应；另有 1 个复位取消事务，不计入这 32 个正常事务。覆盖 4 槽填满、218 次满槽等待、37 次内存反压、38 次单半接纳、13 次双半接纳、9 次高地址访问和 18 次非法事件。17 个乱序结果关系样本、14 个 Header 先完成样本、8 个 Header 前 Data 接纳事件，累计 302 周期。高位地址、Tag/ID 边界、完整两半数据、随机延迟、独立 Header/Data 反压和复位后恢复均实际自检。

三个隔离源码注错均编译返回 0、运行返回 1：地址 bit56 截断报 `memory_descriptor`；以 issued 代替 completed 提前发送报 `response_before_memory_result`；高半数据翻转报 `data_high`。`completer_initial/` 保留首次检查器未将提前响应的通用诊断计为有效检出的失败；修正因果检查后 `completer_final/` 和最终 `completer_ordering_final/` 均检出三类故障，没有覆盖失败记录。

默认四槽另经 Verilog-2001 编译通过；Yosys `read_verilog; hierarchy -check; proc; opt; memory; opt; check -assert; stat` 通过，映射后 313 个通用 cell、0 latch，证据 `reports/endpoint_transaction/completer_synthesis_default/summary.json`。这不是工艺综合、时序或面积结论。容量 1 仅通用综合通过；探索容量 3 时 memory 映射产生未用第四行读选择的未驱动警告并使 `check -assert` 失败，保留于 `completer_synthesis/`，不计通过；其他容量未验证。当前可交付参数限定默认四槽。最终 RTL SHA-256：`179ace95dc7c90afe1e150c87a6e9b3499aeb8dc0025204dc1e1e3a7f481cba1`。

下一步是在真实接收解析器与 `tl_tx_prepared` 间连接本接口，验证接收、内存执行、Response/Data 信用与发送所有权的完整因果链。此单位测试的发送端是按真实反馈语义建模的 sink，未实例化 TL/DL；多 Beat、其他操作、认证、Link Down 恢复和完整 UALink 合规性均不在本次通过范围。
