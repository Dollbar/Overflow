# 完整普通 Read 与在途写复位集成

本轮把普通未压缩Read从固定64B扩展为全部合法DWORD长度、首尾字节掩码及多Beat完成。`FULL_READ_ENABLE=1`提供完整2048位完成数据和相对Beat的256位字节掩码；`WRITE_ENABLE`仍独立控制写服务。默认参数保持此前Read/Write子集，详细接口与规范边界见[实施契约](endpoint_read_execution.md)和[规范审查](endpoint_read_contract_review.md)。这不是完整双IP交付或工艺签核。

## 所有权和数据路径

Read encoder按完整地址和LEN计算应收Beat数及区域BE，formatter把BE转换为相对首Beat的掩码并随Tag预约完整结果存储。接收器支持每Beat独立Header的single模式，以及一个Header对应多Beat的multi模式；multi忽略无效OFFSET并由长度重建逐Beat偏移/结束，single保留原OFFSET/LAST。Tag表检查实际发出、种类、已收位图、状态一致性及LAST与收齐时点。single允许跨Tag和任意地址顺序，错误状态也必须收齐全部Beat才完成。

Completer一次保存真实2048位后端结果，按single模式逐Beat发送Header和两个Data半字，最后Beat交接完才释放槽。五种普通返回状态都传送全部应有Beat。应用成功数据只保留请求掩码所选字节，错误返回数据及掩码清零；未选线上lane必须由Originator忽略，置零仅为本地完成接口策略。

Read/Write后端派发继续等待前一笔真正的内存结果，结果slot及状态必须匹配。fullRead-only配置对写请求同时封锁valid/ready，并保持Write backend复位。新增端口追加于原接口之后，旧512位完成口为完整结果低Beat视图。

## 当前实测证据

- `full_read_encode_red`在旧编码器上编译成功、运行因不支持小Read而失败；`full_read_encode_final`检查64×64几何×256 ATTR，532480合法组合、516096跨界组合全部符合预期，另检查地址对齐/VC/pool/空闲及固定原始编码。
- `full_read_receiver_final_checked`覆盖2081请求（含一个Write旧尾）和404个响应Beat，single/multi、五状态、无效OFFSET/LAST、多Beat跨Word、反压均通过；五类非法记录和三份真实RTL扰动检出。旧Write接收的`full_read_write_receiver_final`全部33项及静态检查通过。
- [Tag表审查](endpoint_read_tag_table_review.md)：三个容量的617次完成、single乱序/跨Tag与multi顺序、错误状态完整收齐、四份真实RTL扰动，正常和优化Python全部通过。
- [Completer审查](endpoint_read_completer_review.md)：容量1/2/3/4各4633向量，2614实际事务/结果、5460个Header/10920半字，五状态和零BE仍全Beat，四类真实扰动被检出。旧模式兼容保留。
- `full_read_only_mode`动态验证8周期写拒绝、不产生后端/Tag所有权，随后小Read带非零ASI/META被真实core预约并稳定持有Header。
- `full_read_top_width_fixed`实际Endpoint（originator8/completer3、Read/Write完整模式）及Switch的Yosys层级/过程/优化/check通过。此前`full_read_top_elaboration`因receiver在声明前引用rsp_out切片导致Yosys无法识别宽度；调整声明顺序后通过，原失败记录保留。
- `full_read_root_static`中encoder和receiver完整模式无豁免Verilator通过；完整core两种WRITE_ENABLE配置仍各有15条警告，静态门限不计全部闭合。
- `full_read_legacy_capacity`旧默认29项全部通过；`full_read_write_compat`在bank1和重放下重新完成旧Write/Read长度矩阵566事务。

[真实 Read ESE](endpoint_read_endpoint_switch_review.md)三组正常配置共1652请求/完成、12次真实Write执行、8次重放；两个完整矩阵各812完成。实际RTL掩码错误和2048位后端高位断线均被检出。ESE发送器采用single模式，multi接收由receiver/Tag单元验证，尚非multi响应的端到端证明。

[独立 Read 模型](endpoint_read_model_review.md)普通及优化Python各11项通过，各遍历532480合法几何/ATTR掩码组合、120个内存场景和四Beat全部24排列；四项实际模型变异均检出。Tag容量1/3/4完整Yosys memory_map检查全部通过，无残留memory或未驱动问题；这不等于工艺映射。记录哈希汇总见[证据清单](endpoint_read_evidence.json)。

## 复位结果与边界

[写复位审查](endpoint_write_reset_review.md)涵盖部分Data但BE前、后端已接纳未执行、已执行且应用完成背压三窗口。统一reset取消pending/result/协议所有权，但保留后端内存和累计执行数。新轮先真实Read核对是否保留旧字节，再同Tag进行新WriteFull及读回。执行前取消不得产生副作用，已经执行的字节不得伪rollback。

最终RTL的`full_read_write_reset`和`full_read_write_reset_minimum`重新通过两bank×三窗口，共108个新轮完成；最终RTL另有`full_read_write_reset_endpoint_fault`（stage1）与`full_read_write_reset_backend_fault`（stage2）两项实际漏复位故障，编译成功、运行按预期检出。这些测试使用默认FULL_READ_ENABLE=0验证新增RTL的Write兼容，不能冒称完整Read在途复位或独立LinkDown/epoch已经完成。

工程级`make test`在本次最终源码上返回0，工具测试199项含2项跳过；各旧模型套件通过。2045份ESE/复位制品哈希复核一致，声明的真实Tag故障源码与正常生产源码的差异单独识别。

## 复跑与未完成项

```sh
python3 verification/endpoint_transaction/run_read_encode.py --label fresh_read_encode
python3 verification/endpoint_transaction/run_read_receiver.py --label fresh_read_receiver --faults
python3 verification/endpoint_transaction/run_read_modes.py --label fresh_read_only
python3 verification/ip_tops/run_elaboration.py --kd28-root /path/to/authorized/Overflow --label fresh_full_read_top --writes --full-reads --originator-capacity 8 --completer-capacity 3
python3 verification/endpoint_transaction/run_write_reset.py --kd28-root /path/to/authorized/Overflow --label fresh_write_reset --bank-depth 1
```

产物位于对应`build/verification/endpoint_transaction/`或`build/verification/ip_tops/`新label目录，保留源码、SV、日志与哈希。各模块新runner提供独立复跑命令。完整ESE矩阵是代表起点/长度/ATTR组合；不以其数量代替全几何模块证明。

仍须完成poison/DataError路径、native UPLI、压缩/缓存、安全和错误恢复、标准Switch逐跳TL/DL/PHY、INC、管理、CDC/RDC及真实工艺STA/PPA。该增量不会删除这些完整Goal要求，也不以数字行为模型冒充宏、SerDes或协议认证。
