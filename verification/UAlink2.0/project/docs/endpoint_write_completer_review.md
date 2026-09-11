# 已组装 Write 执行器实作与验证

`rtl/endpoint/endpoint_write_completer.v` 已替换 generic 未实现壳。它处理普通未压缩 Write / WriteFull 的完整已组装请求，覆盖全部合法地址位置与长度；本轮集成 profile 为 VC0、VC Pool、单本地 ID，ASI/ATTR/META 原样交付后端。本单元不解析原始 TL、不判断 Data 所属请求，也不是完整 Write 互操作或完整 Endpoint 的替代证据。

## 接口与所有权

参数 `CAPACITY=4`、`SLOT_WIDTH=(CAPACITY<=2)?1:2`，支持容量 1～4 及显式两位 slot。单时钟 `i_clk`、同步低有效 `i_rstn`；`i_local_id[9:0]` 运行时稳定。

- 请求：`i_request_valid/o_request_ready`，Tag11、Src/Dst10、Full、Address57、Length6、Attr8、VC2、Pool、ASI2、Metadata8、Data2048、BE256。一拍接纳预留完整描述符、四个相对 Beat、BE 和结果资源。
- 后端：`o_mem_valid/i_mem_ready`，Slot、Address57、Length6、Attr8、ASI2、Metadata8、Data2048、BE256。地址不截断；数据最低 512 位为相对 Beat0。命令反压时全部字段保持。WriteFull 忽略输入 BE，重建整个 256-byte 区域中请求范围对应的位图；普通 Write 保留任意合法稀疏或全零 BE。
- 完成：`i_mem_result_valid/o_mem_result_ready`、Slot、Status4。必须先有该槽实际命令握手，从下一周期起才接受完成。状态 0/2/3/6/8 原样保存；未知、未 issued、重复完成、未用槽及其他状态的有效返回均消费诊断，不更新任何有效槽。
- 响应：`o_source_valid/o_source_control[255:0]/i_source_captured`。只有已保存真实后端完成的队首槽可以发送。最低 64 位为 WriteResponse，Tag 原样、源目的反向、状态原样，LEN/OFFSET/RD_WR/LAST/RSPTYPE/SPARE 为零，其余 192 位 NOP。无 Data；仅在 Header capture 后释放槽。

`o_count[7:0]` 包括尚未发往后端、等待完成和等待响应捕获的槽。满槽是背压；非法请求 profile/destination、非法后端完成或无有效响应的 capture 用 `o_error` 诊断。普通 Write 校验四字节对齐、完整九位长度/末端及范围外 BE；WriteFull 另要求 64-byte 对齐与 64-byte 整数长度。没有复用 Read 的 Attr=FF 限制。后端命令按接纳顺序发出，完成允许乱序，响应按请求顺序输出；后端自身的执行/一致性策略由外部实现。

非二次幂槽阵列只读写实际槽的固定索引，通过有界组合选择取出命令与响应，未用索引不映射虚构存储行。同步复位只取消本地所有权，不回滚已经发生的内存写入；外部内存必须处理其旧 epoch，index-only slot 无法识别重新使用之后的迟到旧完成。

## 独立自检和实际结果

入口：`verification/endpoint_transaction/run_write_completer.py`，测试平台：`write_completer_tb.sv`。Python 从地址、长度、区域 BE 和字节数据独立计算期望；没有调用 RTL 编码器、tenure 算法或新增 `ualink.endpoint_write` 模型。Response 直接按已冻结位段构造期望，与 DUT 的 Verilog 拼接独立。

SystemVerilog 后端按**实际内存命令握手顺序**执行逐 Beat/byte 写入，随后独立延迟、乱序返回完成通知；Python 最终内存 oracle 按区域字节遍历。该后端选择允许副作用早于完成通知，但绝不允许 Completer 把命令接纳当作完成通知。每个请求分别记录接纳、命令、执行次数、真实结果及响应；最终比较全部 8,192 个字节和执行总数，不能靠重复写相同数据隐藏多执行。高位地址使用两个明确测试映射区，所有 57 位地址先逐字段比对；RTL 不继承测试内存映射范围。

先运行原壳 `--label shell_red --shell-baseline`：编译返回 0、运行返回 1，实际报 `WRITE_COMPLETER_UNIMPLEMENTED`。原壳源码与证据保存在 `reports/endpoint_transaction/write_completer_shell_red/`；后续新接口编译失败的 `interface_red/` 不冒充行为红测。

最终八个配置为容量 1/2/3/4 × 自动位宽/显式两位，目录 `reports/endpoint_transaction/write_completer_final_c{1,2,3,4}_{auto,fixed2}/`。八个配置全部通过，每配置实际检查：

- 4,096 个普通 Write 起点/LEN 组合，合法 2,080、非法 2,016；16 个 WriteFull 起点/长度候选，合法 10、非法 6。
- 加五状态及非法对齐/destination/VC/Pool/范围外 BE 用例，共 4,123 输入向量；2,095 接纳、2,028 拒绝、2,095 后端命令/执行/结果/响应，且每笔执行恰一次。
- 417 个全零 BE 成功事务、1,030 次高 bit 地址访问；128/192 起点的区域掩码、60/124/188 跨 Beat、全部 2048 位数据和非零 ASI/ATTR/META 均实际对照。
- 十一个非法状态逐个注入；空闲、未 issued、重复和可编码未用 slot，长命令/响应反压、填满实际容量及复位后旧完成拒绝均有自检。额外复位取消事务不计入上述正常执行总数。

| 容量 | 自动/固定两位周期数 | 最大占用 | 乱序关系样本 |
| --- | --- | --- | --- |
| 1 | 60,809 / 60,811 | 1 | 0（单槽不适用） |
| 2 | 30,841 / 30,843 | 2 | 1,002 |
| 3 | 20,897 / 20,897 | 3 | 1,584 |
| 4 | 15,866 / 15,866 | 4 | 2,051 |

实际命令示例（重跑必须使用新标签）：

```sh
python3 verification/endpoint_transaction/run_write_completer.py --label final_c4_auto --capacity 4 --faults --synth
python3 verification/endpoint_transaction/run_write_completer.py --label final_c3_fixed2 --capacity 3 --slot-width 2 --synth
```

其他容量按同样参数规则运行。输出包括 `summary.json`、源码/runner/展开 TB 快照、独立向量、初始/最终内存、编译/运行命令与日志，以及 `synthesis/{run.ys,netlist.json}`。新标签拒绝覆盖旧目录；初轮与最终轮证据均保留。

四类隔离实际源码故障均编译返回 0、运行返回 1：地址 bit56 截断报 `WRITE_MEMORY_FIELDS`；未完成即产生响应报 `WRITE_EARLY_RESPONSE`；BE 高低 128 位交换报 `WRITE_MEMORY_BE`；四 Beat 轮转报 `WRITE_MEMORY_DATA`。只修改证据目录内的 DUT 副本。

## 结构检查与冻结

八种配置均经 Verilog-2001 编译及 Yosys `proc; opt; memory; opt; check -assert` 通过，网表均 0 latch；容量 3 为 1,247 个通用 cell，容量 4 为 1,297 个。这是通用结构证据，不是工艺面积或时序签核。最终容量 3/两位 slot 的 Verilator `--lint-only --language 1364-2001 -Wall` 返回 0，没有规则抑制。

技能静态 helper 在 `write_completer_static_final/` 保留返回 2：4 error、3 warning。两条 DERIVED_CLOCK 实际指向直接输入端口 `i_clk` 的上升沿，helper 未提供确认时钟 spec；两条循环上界诊断指向展开期 `SLOTS` localparam，实际编译/综合可静态展开。常量风格 warning 也保留；不能声称该技能严格静态门限已通过。初轮 Verilator 的常量宽度与未使用选择信号警告已在最终冻结前消除，初轮证据未覆盖。

最终 RTL SHA-256：`df89ad8ebd63cfaa53a61c2c004cb8b3d6999d443970cea0eb6853167a096aa5`。runner：`91303ee06595f587a7cfacef754000dbf4ce55c16c57577b88c53a02b22197d2`；TB：`f81eaa88b4db991b08b273412bf5dae40c0e7ba997c36397a299221170efcd08`。

下一步接入真实 Write 组装器、共享有序 Read/Write 后端 dispatch 和无 Data 响应仲裁，验证写后读、重叠地址与 replay 下执行恰一次。压缩、poison、认证、原生 UPLI 连续 Beat、LinkDown/Isolation 恢复及真实缓存一致性均未由本单元测试证明。
