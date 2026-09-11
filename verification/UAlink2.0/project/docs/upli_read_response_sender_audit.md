# Read Response sender 独立审查

审查冻结候选 `build/development/upli_read_response_sender/upli_read_response_sender.v`，SHA-256 为 `4ec11412689f2daddf1f10afc77193898b4314ce0b3574109a37c0a0a5cc7e5f`。依据实施契约及其 Common Rev2 来源范围，未发现本次指定正常发送路径中的实质接线或所有权问题；本结论只适用于该源码身份。

- 首拍 NumBeats=0 绕过 multi 几何检查，任意 Offset/Last 均透明；Last=0 不留下本端口尾部所有权，也不推断 Tag 事务已经完成。NumBeats=1..3 才检查有效拍的 NumBeats/Tag/Dst/Status/TypeInfo、顺序 Offset 和末拍 Last。未声明的尾部及 pool 位不影响准入。
- 每个实现端口各自保存三个完整 619 位尾拍、索引、VC、pool 计划。接受后不再从候选读取旧尾部，其他端口可交织；本端口末尾拍当槽保守拒绝新首拍。Src 保留但不参加几何比较；AuthTag/Data/DataError 同样逐拍完整保留。
- 整笔有效 pool 计划分别统计专用 VC 与共享 pool 需求，与沿前余额比较；初始化确认和同沿信用返回没有准入旁路。候选首拍资格意味着真实首拍发送；唯一 bank 的扣账输入来自实际 typed 输出 valid/port/VC/pool，尾拍逐次扣账。同端口 busy 阻止其他候选挪用尚未扣除的尾部信用。
- 首次实际首拍建立独立 RdRsp 相位，之后包括 idle 周期都按配置端口数推进。银行、相位、尾部状态及 typed 输出使用共同 reset。全部 619 位经真实 Read leaf 输出，公开 payload 从这些输出重组。

独立执行的 Yosys `hierarchy -check; proc; opt_clean; check -assert; stat; write_json` 在端口/信用宽度 `(1,3)` 和 `(4,16)` 均返回 0；两配置均实际包含一个 bank、一个 Read leaf、一个公共 parity 实例。对生成网表逐位检查 619 位 leaf 输入/输出重组、实际扣账事件和公共 reset；对父模块组合逻辑做依赖追踪，accepted/error 均不直接依赖四个候选 Src 字段。该追踪在寄存器和子模块端口处停止，不构成时序形式证明。

独立源码快照、命令、Yosys 日志/网表及结果保存在 `build/development/upli_read_response_sender_audit/`，总结果为 `result.json`。首次本地解析脚本的集合类型错误保留在 `parser_first.json`，修复解析后复用已成功的第一份展开；没有改动候选 RTL。owner 的 `freeze.json` 正常、`-O`、故障及静态矩阵是另外一组证据，本审查没有重新执行或替代这些功能测试。

范围限制：有效连接及合法信用路径是正常连续发送保证的前提。信用错误变为可见后，sticky 关闭新发送和旧尾部，等待上层处理及共同 reset；这不证明损坏信用事件当沿可撤销，也不实现连续性恢复。请求/响应因果、授权资格、single 跨 Tag 收集、完整 RX/station、Isolation/RAS、STA 与真实互操作仍需上层或后续验证。本轮未执行整套技能仓库自检，不据此声明全工程严格门限通过。下一步由主线安装此冻结候选并验证实际 station TX 集成。
