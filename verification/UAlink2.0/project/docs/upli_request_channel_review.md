# 原生Request发送字段层与真实sender集成审核

本次实现完整189bit原生Request有效字段透传与四组even parity；模块不额外建立信用、连接或TDM状态，不过滤已经由共享sender实际发出的请求。实施契约和原规范定位见 `docs/upli_request_channel_execution.md`。候选位于 `build/development/upli_request_channel/`，由本代理编写的生产路径仅此契约文档；生产RTL、库存与top由主线独立集成。

真实旧壳先编译成功、运行失败，命中 `REQUEST_UNIMPLEMENTED`，证据为 `shell_red/`。新的原生wrapper未存在时，测试实例化真实 `upli_request_data_sender` 并得到缺失模块编译错误，见 `wrapper_missing_red/compile.log`；这明确是接口缺失证据，不记为功能红测。随后主线实现真实wrapper，本测试直接使用该源码而不是以TB临时连接作为完成依据。

## 原生字段独立检查

叶模块970向量，包括189个字段bit逐位、各bit的有效/无效/reset情形、手工全一字面值及400个固定种子混合值。Python参考用字段字典、独立字节计数计算parity；全一字面值绕过参考计算明确校验valid=1、Auth64 parity=0、Addr57 parity=1、控制68 parity=0。某些逐位向量故意不满足事务语义，例如低地址位或保留命令编码；它们验证透明字段层没有截断，不用于声称这些请求具备规范执行合法性。

原XOR候选开发测试实际修改Tag/Auth/Addr最高位、遗漏Pool保护、地址保护混入Tag以及反转valid parity，六故障均编译成功、运行失败命中REQUEST_MISMATCH。发布runner为兼容公共parity重构，改为六个稳定typed接线故障：Tag/Auth/Addr高位裁剪、Pool清零、Port位翻转、绕过valid门控；仍必须实际编译0/运行1且指定错误标记才算检出。公共primitive独立保护集合及等价证据由主线另记，本审核不代其宣称已完成。

Verilog-2001、严格Verilator -Wall、Yosys read/hierarchy/proc/opt/check -assert/stat均通过，无警告抑制。技能artifact gate最终0 errors、9个显式常量宽度建议；纯组合模块没有时序clock/reset过程，技能spec明确无此过程，i_rstn仅为同域组合屏蔽。技能全套selfcheck已运行，但因安装环境缺少 `agents-md-generator/scripts/manage_docs.py` 在前置检查失败，见 `skill/selfcheck.log`；不把该环境失败算通过，也未修改外部技能安装。此处没有工艺PPA或STA结论。

## 真实所有权与信用集成

生产helper候选 `upli_request_data_sender`只实例化一个既有burst_sender，其两套信用银行分别属于Req和OrigData。TB实例化两侧真实connection_side，连接、初始化、原生输出均来自真实RTL；完整原Request元组与完整Data/BE保存到独立TB队列，使用整数账户日志核对每个账户真实余额，TDM相位由独立周期模型观察。

PORTS=1/2/4各完成10个真实Request、11个实际Data Beat，分别708/1665/5071项检查。每配置活动请求使用最后端口以覆盖非零初始相位和wrap，其余端口参加信用初始化；这不是所有端口并发事务穷尽测试。活动流覆盖普通Write的1/2/3/4拍和不同VC/Pool计划、Read以不同VC/Request Pool覆盖旧Write尾拍、原数据/BE/VC/Pool不被新Read修改、Req pool耗尽、同沿返回信用不可旁路、Req有信用但完整三拍Data信用不足不得发出、补足Data信用后真实首拍发出，再共同reset取消余下两个尾拍和全部余额/相位。

原始wrapper_first的P2/P4曾失败，原因是TB对没有消费过的其它满账户也归还信用，实际bank正确拒绝整沿，而独立日志要求增加；修复只对实际消费账户归还，保留原失败证据。最终wrapper_credit_fixed全部通过，没有据该失败修改生产RTL。

三种真实wrapper故障分别让Request leaf直接读取候选valid、截断11bit Tag最高位、反接实际Pool，均在实际仿真被原生事件/元组检查检出。输入全部在下降沿后修改并跨越采样上升沿稳定；scoreboard在上升沿读取原始输入/实际事件后，等待NBA完成再比较银行余额，TB计数不反馈DUT控制，避免同沿驱动竞态。

## 发布重放与范围

发布文件在候选 `release/verification/upli_channels/`：`run_request_channel.py`、`request_channel_tb.sv`、`request_reference.py`、`run_request_data_sender.py`、`request_data_sender_tb.sv`。ROOT=parents[2]，只读生产 `rtl/upli/`，包含公共 `upli_parity.v` 依赖；不依赖build/development文件。独立 `release_replay/`仅使用复制的8个RTL及这些发布测试，normal与-O均通过。实际源码与逐文件证据SHA见候选 `freeze.json`。

```sh
python3 verification/upli_channels/run_request_channel.py --label fresh_leaf --faults --static
python3 -O verification/upli_channels/run_request_channel.py --label fresh_leaf_O --faults --static
python3 verification/upli_channels/run_request_data_sender.py --label fresh_sender --faults
python3 -O verification/upli_channels/run_request_data_sender.py --label fresh_sender_O --faults
```

输出分别为 `build/verification/upli_channels/request_channel/<label>/`、`request_data_sender/<label>/`，所有label必须新建。下一步由主线安装release文件及公共parity改版后复跑同一入口。

本次不实现或声称完成：原生Request接收保存/检查、RAS错误隔离恢复、Authorization认证、完整命令/地址/LEN合法性验证、Tag分配与退休、TL压缩或线协议认证。返回信用parity检查由公共parity/接收集成负责，本字段leaf和本sender TB不能将无输入parity接口的银行单独称为已具备端到端控制保护。

最终发布重放label：leaf为portable/portable_O，wrapper为mixed_vc_final/mixed_vc_final_O。各leaf结果46项制品、各wrapper结果31项制品全部重算SHA零差异。字段leaf SHA256为`a2e02374041e4615c0c68e449747cbd85594226fe880c3b3f7e0e6577fd57fda`；最终sender TB SHA256为`fc07d8fd0d8788541af5cbb52049973334df854dc04a03e6b7f2d173b569e6cb`。
