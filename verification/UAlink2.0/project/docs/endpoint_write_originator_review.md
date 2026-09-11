# 普通 Write 发起与共享 Tag 检查

本次替换 `endpoint_write_originator` 和 `endpoint_request_formatter` 两个未实现壳，扩展 `endpoint_tag_table` 的共享请求种类，并且只给旧 `endpoint_read_originator` 补接新增 kind 端口。生产代码是 Verilog-2001、单时钟、同步低有效复位。未修改 receiver、core、top、模型或库存。

字段和本地接口以 [endpoint_write_execution.md](endpoint_write_execution.md) 为准；规范来源及可实现边界见 [endpoint_write_contract_review.md](endpoint_write_contract_review.md)。普通未压缩 Write CMD 0x28、WriteFull CMD 0x29，按 Common 2.0 §2.7.4/§2.7.4.7、§2.8、Table 5-29 编码。共享完整(port,Tag)域和响应种类/状态依据 §2.7.4.2、§2.7.6.1、§2.7.8。本文不扩展认证、压缩、poison、UPLI或线格式能力。

## 实际实现

`endpoint_write_originator` 一次握手保存完整 Header 和最多八份256-bit Data，以及普通 Write 的一份256-bit区域BE。长度计算扩到9位，256-byte区域末端扩到10位；普通Write允许4..256B、DWORD对齐、不跨256B区域，检查范围外BE必须零。WriteFull要求64B对齐、长度为64B倍数，忽略输入BE并重建范围掩码。

数据按相对Beat0..3的低256/高256排列。普通Write只发送实际2N Data，再紧接BE；不会让未声明Beat污染BE。Header capture、Data accepted数量和实际header_taken分别保存：只有Header已捕获、实际Header已发送、全部Data/BE已交付三条件全部满足，才释放当前holding。正常背压保持所有权，非法接纳数量或反馈只诊断，不推进错误状态。Header可先于、后于或与Data接纳重叠。

`endpoint_request_formatter` 提供冻结的统一 `i_request_*` 接口，唯一类别0 Header/Data源，以及带 `i_response_is_write/o_complete_is_write` 的响应/完成接口。Read复用真实 `endpoint_read_encode`，Write复用上述serializer；**仅实例化一张** `endpoint_tag_table(WRITE_ENABLE=1)`。后来的Read/Write不能绕过当前未交付的Header/Data。一个待发holding限制吞吐，但已发送请求可以占满四个共享结果槽。

Tag表保留全部11位Tag与port身份，Read/Write共用冲突检查。新增kind端口追加于原接口尾部；`WRITE_ENABLE=0`忽略新增输入，保持原Read语义。混合模式响应必须匹配预约kind；Write接受状态0/2/3/6/8，LEN必须零且不能有DataError，忽略无效OFFSET/LAST。Write完成始终data_valid=0且Data=0；成功Read才提交512位数据。未知Tag、未sent、错误kind/DST/port、保留状态及重复响应均不修改槽。完成保持到应用握手后才释放Tag。

## 失败证据与自检

`write_originator_shell_red` 先编译两个原壳并实际运行：compile=0、run=1，报 `WRITE_SHELL_UNIMPLEMENTED ready=00 implemented=00`。这是旧壳无服务的运行失败，不以接口编译失败冒充红测。

新增两个独立SV检查器，均不调用Python模型生成完成期望：

- `write_serializer_tb.sv` 穷举64种DWORD起点×64种长度：2080合法普通Write、2016跨界组合；另10合法Full、6跨界Full和4个BE/对齐/长度非法向量。最终2090合法、2026非法，20763周期。每笔逐半字比较独立保存的Data/BE，应用握手后反转全部输入，覆盖零BE、稀疏BE、完整地址高位、Tag/ID高位、两半字部分接纳、背压、Header先/后Data、同拍capture/header/data和非法反馈、复位取消。
- `write_formatter_tb.sv` 检查单张表四槽共享容量、Read/Write相同Tag冲突、稀疏高位Tag、capture不等于sent、无Data写响应、错误kind/DST/port/LEN/DataError/状态、重复/未知/未sent响应、五种Write状态和Read零/三、乱序响应、完成背压及复位后Tag复用。最终11预约、10应用退休、10非法响应诊断、229周期；1预约被复位取消。

固定原始字段 `1a0a0020415a0000000000001e08c021` 对应 Write、地址60、LEN1、Tag1024、SRC17/DST513、ATTR81/ASI2/META5A、NUMBEATS1。该固定向量实际检出了初稿把CLOAD/CWAY误合为4位而不是3位的错误；几何TB曾使用同样错误的拼接，因此固定原始向量是必要的独立交叉检查。`write_originator_first/second` 保留失败，修正后固定向量通过。首次serializer失败还检出了未声明Data与尾BE重叠，已通过屏蔽未传输Beat修正；`write_serializer_first` 保留该运行失败。

最终 `write_originator_release` 四个case：

| case | compile/run | 结果 |
| --- | --- | --- |
| serializer | 0/0 | 2090合法、2026非法通过 |
| formatter | 0/0 | 共享所有权检查通过 |
| fault_tag_kind | 0/1 | 实际删除Tag表kind比较，检出 `WRITE_KIND_MISMATCH_ACCEPTED` |
| fault_data_order | 0/1 | 实际把serializer半字读指针偏移1，检出 `WRITE_SERIAL_DATA` |

旧 `run_originator.py` 未修改；`write_table_legacy_final` 的端口域1/2/4与全部7个实际RTL故障均按预期通过。早期 `write_table_legacy` 因旧脚本的文本变异锚点失配中止，随后通过等价重排数据有效表达式保留原锚点并完整重跑，没有把中止当作通过。

## 静态检查与范围

`write_originator_static_final`：Icarus `-g2001`、Verilator `--language 1364-2001` 和 Yosys `hierarchy -check; proc; opt; check -assert` 均退出0，Yosys报告0问题。没有进行工艺映射、STA或PPA签核；Tag结果数组被Yosys展开为寄存器是记录的结构选择。

四个模块的技能 `validate_verilog_artifacts` 均为0 error，警告依次10/9/11/9，主要为严格模板/命名建议。Verilator使用 `-Wno-fatal`，保留3个未使用输出连接和2个中间值未使用位警告；没有位宽截断、锁存或多驱动警告。第一份静态检查发现wire声明与assign需分离，已修正后重新进行真实仿真。

全局技能检查 `validate_verilog_skill.py --no-require-remote` 退出1：本机缺失 `/home/ljy/.codex/skills/agents-md-generator/scripts/manage_docs.py`。因此全局技能环境门限仍为HOLD；不能把模块仿真与静态检查通过改称整个技能链通过。

这一交付为发起端单位模块，不代表已完成真实双Endpoint写后读闭环。上游应用整事务接口和TL的0/1/2半字数量接纳是本地内部接口；不是原生UPLI连续Beat保证。ASI/ATTR/META透传不证明后端地址空间与一致性语义。WriteResponse由接收器提供，实际内存副作用及延迟完成要在completer/core/端到端阶段另验。

## 复现与冻结来源

在工程根目录使用新label，输出位于 `build/verification/endpoint_transaction/<label>/`，含源码/TB/runner快照、编译运行日志和哈希：

```sh
python3 verification/endpoint_transaction/run_write_originator.py --label write_originator_new --faults
python3 verification/endpoint_transaction/run_originator.py --label write_read_legacy_new --faults
```

| 源文件 | SHA-256 |
| --- | --- |
| `rtl/endpoint/endpoint_write_originator.v` | `6dd78c2f84ce2d80d5abf76f1ec902c1d8f322257935bedcc9b4c1f6b0ced958` |
| `rtl/endpoint/endpoint_request_formatter.v` | `57d8a2b63215d7f8cc0f4ae0654bc6e79dfaf92d80abb5f3e29b70d9e6327c81` |
| `rtl/endpoint/endpoint_tag_table.v` | `a593cae3e04f7895cbfa56b014a0e13e82ffdf493693dd9c3d0a74828c631362` |
| `rtl/endpoint/endpoint_read_originator.v` | `73d054e68f23d34cba6858b87f781ae1bd3b42630a3231b6ea48a1c48c95dd72` |
| `verification/endpoint_transaction/run_write_originator.py` | `6dbb6e43dab4569cad264237617cc28c4ed9180e6cb8731eb07552ca4a42a484` |
| `verification/endpoint_transaction/write_serializer_tb.sv` | `d4c74c364135970243077eab69c4eac38c10711838925dacc2d35d4d1cfdde70` |
| `verification/endpoint_transaction/write_formatter_tb.sv` | `0914f659f34f233ae7521dfdbbba588b4617bd864cc19e91278ec6a349a5e7ae` |
