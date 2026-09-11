# 完整普通 Read 实施契约

目标是普通未压缩Read的完整DWORD几何及两类响应模式，与已实现普通Write/WriteFull共享Tag和后端顺序。规范审查见`endpoint_read_contract_review.md`；不以单64B兼容作为最终成功条件。原生UPLI、poison、INC及完整双IP其余目标保持。

## API和所有权

追加`FULL_READ_ENABLE=0`参数保持历史默认接口；开启后普通Read支持DWORD对齐4..256B、不跨256byte，ATTR低4为首DWORD BE、高4为末DWORD BE，LEN0忽略高4。ASI/META原样交付后端。Read线上Request NUMBEATS仍为0，不是响应Beat数。

- Read encoder追加`FULL_READ_ENABLE`参数和输出`o_num_beats[1:0]`（期望响应N-1）、`o_be[255:0]`（区域字节位图）。旧接口/默认行为不变。
- Completer追加`FULL_READ_ENABLE`、`i_mem_result_data_full[2047:0]`及`o_mem_be[255:0]`。一次后端结果含相对Beat0..N-1，最低512位为Beat0，旧512输入只在默认模式使用。五个普通状态0/2/3/6/8都返回全部N Beat；错误完成不可提前释放。选择明确允许的singleBeat TX模式：每Beat一个响应Header，LEN0、OFFSET=k，最后一个Header LAST1；每Header有两个Data半字。保存整事务直到所有Header/Data交接完。
- Receiver追加`FULL_READ_ENABLE`。完整模式须接受single模式LEN0、任意OFFSET0..3及LAST，并接受multi模式LEN=N-1；multi OFFSET无效，不以OFFSET/LAST建议值拒绝。Data owner按2N半字收齐一个Header的全部数据，再逐Beat交付512接口；multi内部重建offset0..N-1、仅最终Beat last1，同时每Beat保留num_beats=N-1。single保留原OFFSET/LAST。Write所有权不变。
- Tag table追加`FULL_READ_ENABLE`、`i_allocate_read_num_beats[1:0]`、`i_allocate_read_mask[255:0]`（相对Beat字节掩码）、`o_complete_data_full[2047:0]`、`o_complete_mask[255:0]`。每个Read预约完整2048位结果及expected/seen bitmap；各Beat状态必须一致，响应模式及长度必须与预约一致。single可乱序、跨Tag交织；multi须从0按序且与预约长度一致。重复/越界/缺Beat LAST/全齐却无LAST均诊断且不能错误退休。正确LAST与全部expected同时满足才done，错误状态也必须收齐。
- 完成full数据最低512位是相对Beat0；成功输出仅掩码所选字节（未选字节置零是本地API策略，不是线上Read数据强制值），错误结果full/legacy数据和mask清零、data_valid0；成功全零BE仍完成一次，data_valid表示成功Read，mask可全0。原512完成输出仅为完整结果的低Beat视图；应用完整Read须使用新增full+mask。
- Formatter新增相同full参数与完成输出，用实际Read encoder的N/BE预约统一Tag表；regional BE右移`64*address[7:6]`变成相对Beat掩码。旧Read originator默认显式关闭新能力，仍连接新增非消费端口以保持清晰。
- Core/top追加full参数、`i_mem_result_data_full2048`、`o_mem_be256`、`o_complete_data_full2048/o_complete_mask256`。FULL_READ_ENABLE1使用统一formatter和mixed接收/响应路径；WRITE_ENABLE0仍拒绝应用写请求，不偷偷开启写服务。共享dispatch对完整Read五状态都在真正后端结果后释放，不能在首个响应Beat或应用完成时释放。

## 验证顺序

1. 独立模型/几何字节mask覆盖64×64起点LEN及256 ATTR，固定原始Control字面值；明确合法几何2080，LEN0高半BE忽略、zeroBE合法及未选lane不参与结果比较。
2. Completer验证完整N Beat、五状态、后端真实结果前无Response、Data/Header独立背压和容量1..4；旧Read/Write回归保持。
3. Tag验证single乱序/跨Tag、multi完整长度/顺序、重复/缺失/错误kind/status变化/提前LAST、错误仍收齐、共享Tag冲突及应用背压。
4. Receiver验证真实Data共享所有者、每Header2N半字、single OFFSET/LAST保留、multi重建、旧尾与新Control因果、错误所有Beat及Write交织。
5. 真实双Endpoint/Switch下全部长度、首尾掩码、跨Beat/zeroBE、错误响应、最小缓存/重放与完整字节结果；内存命令、真实执行和完成次数独立检查。multi RX需独立原始记录或对端配置覆盖，不拿single TX的回环代替。

每次运行用新label保留失败/通过及源码/制品哈希。此契约描述待实现目标，尚未宣称全Read功能通过；现有Write快照不因参数/端口追加自动变更验证结论。
