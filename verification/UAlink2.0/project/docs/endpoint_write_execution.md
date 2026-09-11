# 普通 Write / WriteFull 实施契约

本契约落实 `endpoint_write_contract_review.md`，目标为真实双 Endpoint/Switch 下普通未压缩 Write/WriteFull 全合法地址位置及长度。单64B Read作为既有混合事务回归保留；完整Read、压缩、认证、poison、UPLI、PHY和管理等原目标不缩减。

## 本轮接口约定

- 单时钟、同步低有效复位；所有生产 RTL 使用 Verilog-2001。应用仍为单物理port0、VC0及VC信用；ASI/ATTR/META在写事务中原样转发给后端，不假定其内存系统语义。
- 一次应用握手保存整个Write：`is_write/full`、原有port2/tag11/address57/dst10/length6/attr8，以及`asi2/metadata8/data2048/be256`。data最低512位是相对Beat0，随后依次Beat1..3；BE按整个256-byte区域的自然字节编号，WriteFull忽略输入BE并根据范围重建全一有效字节。
- 普通Write校验完整长度、256-byte边界及范围外BE；WriteFull要求64-byte对齐及长度为64的倍数。TX发未压缩128位字段，附2N个Data半字，普通Write最后追加一份256-bit BE。
- `endpoint_write_originator`持有Write header/data：`i_request_valid/o_request_ready`接收全事务，`o_source_valid/o_source_control256/i_source_captured`转移Header，`o_data_valid2/o_data512/i_data_accepted2`分别表示可接纳0/1/2个顺序半字；`i_header_taken`是真实TL发送事件。Header、全部Data/BE及发送确认都完成后才释放pending。
- `endpoint_request_formatter`在一个共享Tag表和一个有序待发holding下接受Read/Write。使用上述同一应用接口；输出单个类别0 prepared Header及Data/BE。Read编码仍复用现有单64B编码器。后续请求不能绕过当前未交付Header/Data的请求。
- `endpoint_tag_table`扩展请求/响应kind与完成kind，新增输入`i_allocate_is_write/i_response_is_write`、输出`o_complete_is_write`，追加参数`WRITE_ENABLE=0`保留旧Read入口。混合模式统一比较完整(port,Tag)，错误kind响应不能完成任何槽。Write支持远端状态0/2/3/6/8，忽略无效OFFSET/LAST、要求LEN0且无DataError；Write完成data_valid恒0，数据恒零。Read保留现有0/3及单Beat规则。
- 接收器扩展`WRITE_ENABLE=0`保持旧入口，WRITE_ENABLE1时提供上述已完整组装的Write与原Read请求，以及带kind的无Data写响应。共享Data所有者队列按Control顺序消费Write Data/BE与ReadResponse Data；接收整600-bit记录仍只接纳一次。
- `endpoint_write_completer`接纳**已完整组装**的请求（tag11/src10/dst10/full/address57/length6/attr8/vc2/pool/asi2/metadata8/data2048/be256）。CAPACITY默认4、SLOT_WIDTH默认由容量导出；内存接口为`o_mem_valid/i_mem_ready/o_mem_slot/address/length/attr/asi/metadata/data2048/be256`，完成接口`i_mem_result_valid/o_mem_result_ready/i_mem_result_slot/status4`。内存valid表示整个事务可执行；接纳不等于执行完成。
- Completer只在真实后端完成后生成256-bit Control（最低64位WriteResponse、其余NOP），经`o_source_valid/o_source_control/i_source_captured`提交；响应无Data。结果可按slot乱序返回，响应保守按接收顺序输出，非法结果消费诊断但不更改有效槽。
- Read/Write执行需共享有序dispatch，当前更强的顺序约束可等先前请求完成再执行后一请求，避免对重叠地址重排。数据采集与响应接收不能被该后端等待阻塞。

## 实施与验证顺序

- [x] 独立字节模型覆盖64×64普通Write几何组合及WriteFull十种合法组合、BE位置/零掩码、五种状态和非合法输入。
- [x] 先观测现有Write壳真实不提供服务；实现Write序列化、共享Tag/formatter，验证capture、实际发送和全部Data/BE所有权。
- [x] 先观测旧Completer壳失败；实现完整请求缓冲、实际内存完成及无Data响应，检查多槽/反压/乱序结果和真实接线故障。
- [x] 接收器和core/top接入混合请求、Data所有者队列、共享后端次序；重复旧Read与容量/复位关键回归。
- [x] 双实际Endpoint/Switch执行WriteFull后Read、稀疏Write后Read、全部有效长度与错误/重放；检查每笔执行次数和最终逐字节状态，不用只读回同值掩盖重复写。

全部输出保存在新label的build/reports目录；源码、SV、pkg/VIP与脚本按现有三分区导出。规范私有正文、外部库及生成产物不入库。未完成或静态门限未闭合时如实保留HOLD，不宣称完整IP或工艺签核。
