# 独立Request/Response候选与数据所有权审查

新增 `rtl/tl/tl_tx_channels.v`，在原实际半Flit packer之前分别检查Request和Response队首。缺信用、缺本拍负载或catch预算不足的一个队首，不会优先于已经可发的另一类。该模块使用外部持有的两个准备好头部源和两个有序Data/BE源；**尚未实例化实际Tx FIFO或SRAM缓存，也未完成超容量事务**。

## 规范与状态分离

私有 Common 2.0 §9.1要求跨链路流控保持Request/Response独立性；§5.1.1–§5.1.2规定有序Data、旧尾交换和Auth限制；§5.7、§5.8分别约束catch与信用。此实现覆盖现有已确认的字段tenure，未扩大未决指令编码。

先选择本拍完全可发的类别；两类均不可发时，优先考虑有信用但需显式NOP恢复catch预算的类别；其余等待由内层packer处理。相同等级采用轮换，偏好只随实际头部发送更新。类0只接受Request字段，类1只接受Response字段；错误类/格式和总容量不足分别输出两位诊断。

四个外层状态位分别保存偏好类、当前Data所有者、停顿中的头部类及锁定有效位。内层packer另有四位状态。上半可携带A类旧尾，下半同时携带B类新头：当拍Data确认仍发给A，头部确认发给B，下一拍Data所有者才切至B。接收方仍按规范从实际头部推导归属，不引入新侧带。

来源必须保持未确认队首，真实端口的`o_tx_taken`是唯一消费事件。`i_pending`、物理信用、共享初始化状态与Tx catch预算都从同一个实际端口取得。缺数据的完整持续前进性还依赖外部队列最终供给两个非尾部半Flit或一个尾部；实际Tx缓存深度和供给停顿尚待集成证明。

## 实际验证

每种模式为 WIDTH 8/16 × Auth 0/1 × Shared 0/1 × 数字链路延迟1/3，共16配置。各端各类都有30个准备好Control队首，带独立索引的数据源；重复压力、已确认请求/响应格式、Data/BE和多字段无Data头部均参与测试。真实后端包含packer、admitted port、接收600位SRAM和实际FC发布器。

| 模式 | Request/Response头部实际消费 | Data/BE半Flit实际消费 | 实际SRAM消费字 | FC/完成消息转移 | 测试循环 |
|---|---:|---:|---:|---:|---:|
| 两类可持续发送 | 960 / 960 | 4,736 / 3,392 | 5,966 | 3,538 | 7,834 |
| Request队首永久超容量 | 0 / 960 | 0 / 3,392 | 2,624 | 2,296 | 6,696 |
| Response队首永久超容量 | 960 / 0 | 4,736 / 0 | 3,328 | 2,566 | 7,036 |

正常模式实际观察38次跨类“新头部+旧尾”；Auth模式禁止该合并。独立Python逐拍解析实际字段，重建两个类的头/数据消费索引和有序token所有权，验证每一个Data/BE字属于正确来源，重建并比对每一个实际退休600位SRAM字、队列深度、释放所有权、数字链路延迟、输出停顿保持、FC不早于真实消费及最终信用守恒。正常Python与`-O`均通过。

阻塞模式的首头需要三个专用VC Data信用，而相应类只配置一个；另一类有四个。两种阻塞模式的被阻塞头部和数据在所有观察行均未被确认、未丢弃；另一类完整排空，并保留被阻塞类的容量不足诊断。这里的通过仅证明**另一类独立前进**，不代表被阻塞事务完成，也不把总Goal缩减为只服务可发送类。

单位RTL时序比较1,258行，覆盖两类信用/数据缺失、错误类别、停顿中另一类到达、旧尾与新头归属切换、Auth、轮换和catch NOP优先。正常模式第一轮未观察到跨类旧尾，保留了该覆盖缺口记录；在保留连续三Beat压力的同时调整首笔为一Beat，使下一类确有足够信用，并加入必须观察到跨类合并的终点检查。

8类真实单位故障各跑两宽度，共16次检出：忽略就绪优先级、用新头类代替旧Data类、丢失Data所有者更新、丢失停顿类锁定、固定Request优先、错误Data确认类别、允许错误类头部、隐藏catch NOP。实际双端另外运行64次故障：两个Data所有权错误各16配置，以及忽略就绪优先级分别注入两个阻塞模式各16配置；全部失败。故障实际编译并运行健康夹具，非修改期望值制造失败。

严格Verilator lint两宽度通过。Yosys通用综合分别85,148/85,948 cells、8个FF位；所有触发器是输入时钟上的同步复位类型。这是类别选择模块及其packer/解码依赖的通用结构，未包含完整端口、接收SRAM或工艺STA，不代表工艺面积或时序收敛。

Artifact技能检查零错误、10项风格建议。全局技能自检依然实际失败于外部缺失 `agents-md-generator/scripts/manage_docs.py`，未把这项写成通过。缺失模型/RTL、首次TB编译错误（带宽字面量紧贴问号）、覆盖缺口、健康与故障证据均保留。

干净导出中的 `make test rtl-smoke` 实际运行结束，退出码为0。已逐字节核对当前全部 `rtl/**/*.v` 和 `Makefile` 与导出副本相同；文档和最终审计脚本不在该一致性声明范围。结果和源码哈希保存在 `compatibility_result.json`。

## 后续及复跑

实际Tx FIFO和SRAM队列、每VC选择、容量感知UPLI事务处理、Data Poison与其余TL消息、完整在线容量/参考归纳和工艺STA仍开放。当前标签全零是分类夹具，不是密码认证；准备好的Control来源不是完整UPLI事务解码器，数字延迟链路也不是DL/PHY。

```sh
python3 verification/tl_tx_channels/test_model.py
python3 verification/tl_tx_channels/run_rtl.py --label unit_final
python3 verification/tl_tx_channels/run_peers.py --kd28-root /authorized/Overflow
python3 verification/tl_tx_channels/run_peers.py --kd28-root /authorized/Overflow --blocked request
python3 verification/tl_tx_channels/run_peers.py --kd28-root /authorized/Overflow --blocked response
python3 verification/tl_tx_channels/run_checks.py --kd28-root /authorized/Overflow
python3 verification/tl_tx_channels/run_skill_gate.py --skill-root /path/to/verilog-generator
python3 verification/tl_tx_channels/check_evidence.py
make test rtl-smoke
```

这些命令均要求通过；阻塞模式的通过含义如表所示。输出在 `build/verification/tl_tx_channels/`，同名目录拒绝覆盖。最终 `evidence.json` 对当前编译源码SHA、实际运行分母和原始观察进行审计；完整两套IP交付仍未完成。
