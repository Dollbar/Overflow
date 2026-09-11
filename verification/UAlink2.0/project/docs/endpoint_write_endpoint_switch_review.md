# 真实双 Endpoint / Switch 写后读检查

已在两个实际 `ualink_endpoint_top(TRANSACTION_MODE=1, WRITE_ENABLE=1)` 经实际 `ualink_switch_top` 连接下完成普通Write/WriteFull写后读。四个正常case共1172笔请求与1172次完成，其中实际后端执行320次Write，包含zeroBE的无修改执行。两个实际后端接口故障均被独立检查器检出。本次只新增测试、runner和此review，没有修改生产RTL或既有VIP/pkg。

## 实际路径与检查独立性

`write_endpoint_switch_tb.sv` 通过实际formatter/共享Tag表、prepared TL发送、DL重放、Switch、600-bit接收存储、Write接收组装、completer及共享有序dispatch访问后端。响应由实际completer在后端结果到达后产生，没有预生成WriteResponse或ReadResponse。

本次配置：端点ID17/513、port0、VC0/POOL0、Auth关闭、originator/completer默认四槽。每项信用容量为4，`RX_DEPTH=160`，足以预约四Beat Write；Data bank分别使用深度3与1。Switch施加有限周期背压，应用完成在500周期前背压，之后周期性背压；每端观察到四笔预约并存。

测试内的 `write_test_memory` 是可变延迟、256-byte本地内存服务：

- 实际Write命令握手保存地址、2048-bit相对Beat数据、256-bit区域BE和slot。后续才逐字节执行BE允许的写入，增加实际执行计数，再提供稳定slot的结果；命令接纳不代表执行完成。zeroBE仍执行一次并返回结果，但不修改字节。
- 实际Read命令在延迟后从后端当时真实字节数组读取64B，作为完整512-bit结果返回。模型不读取事务fixture、不调用期望值生成器，也不生成协议Response。
- 所有后端字段在命令接纳时保存；执行与结果valid在后续时钟产生。后端只采用实际收到的地址/Data/BE，不从应用侧偷读原始Write。

runner另用Python `bytearray` 从应用事务独立生成请求fixture、期望区域BE及每次Read的完整512-bit结果，写入带哈希的hex文件。期望模型按应用顺序更新字节；SV后端按真实收到的命令执行，两者没有共享内存数组或BFM内部pending/due状态。

scoreboard观察的事件包括：应用预约、真实 `u_tx.o_header_taken[0]` 和实际发送字段、后端读写命令握手、实际写执行脉冲、后端结果握手、每个首次及被背压的 `complete_valid`。它检查完整Tag/种类/地址、Write长度/ASI/ATTR/META、全部实际Data字节、整个区域BE、共享后端顺序和每笔执行恰好一次。完成valid必须晚于该事务对应的真实后端结果，Read完整数据对照独立fixture，Write的data_valid和data必须为0。应用背压期间完整完成结果不能变化。

执行次数检查是独立判据，不能通过“相同内容重复写后读回同值”蒙混通过：重复命令会违背严格事务序列，重复执行会违背每事务执行计数，最终后端总执行次数也必须等于计划Write数。重放期间这些检查保持启用。

## 事务矩阵与实测

基础程序每端10笔事务：Full256后读回四个Beat；地址60、长度8的跨Beat稀疏Write后读回两个Beat；地址128、长度64的zeroBE Write后读回未变化Beat。两端同时以不同数据模式向对端写入。

`--all-lengths` 在基础程序后增加：

- 普通Write所有64种长度4/8/…/256B，每种长度选择一个合法DWORD位置和稀疏区域BE，读回该请求覆盖的每个完整Beat。
- WriteFull全部10种合法起点/长度几何组合，输入BE故意与有效范围相反，确认Full忽略输入BE并仅使用传输Beat的全一BE；逐个覆盖Beat读回。

扩展程序每端283笔请求，其中77次Write、206次Read。**这里没有穷举2080种普通Write合法地址×长度组合**；2080种普通几何交叉由独立serializer单位回归覆盖，见 [endpoint_write_originator_review.md](endpoint_write_originator_review.md)。

| label | bank / 恢复 | 请求 / 完成总数 | 两端实际Write执行 | 两端重放 | 周期 |
| --- | --- | --- | --- | --- | ---: |
| `write_ese_final_basic` | 3 / 关闭 | 20 / 20 | 3 / 3 | 0 / 0 | 791 |
| `write_ese_final_lengths` | 3 / 关闭 | 566 / 566 | 77 / 77 | 0 / 0 | 11212 |
| `write_ese_final_minimum_recovery` | 1 / 开启 | 20 / 20 | 3 / 3 | 4 / 4 | 784 |
| `write_ese_final_lengths_minimum_recovery` | 1 / 开启 | 566 / 566 | 77 / 77 | 4 / 4 | 11190 |

四个正常case均compile=0/run=0，在所有预约、Read/Write completer及DL unacked/scheduled计数排空后，额外观察50周期再PASS。恢复case在每个方向丢弃一份原始负载、对另一份原始负载注入CRC失败状态；真实DL负责重放，后端执行次数没有增加。

| fault label | 实际改变 | compile/run | 检出 |
| --- | --- | --- | --- |
| `write_ese_final_be_fault` | 后端BE输入连线清零，其余请求和检查器保持 | 0/1 | 首次Full写后的实际Read返回与独立字节期望不同，`WRITE_ESE_READ_DATA` |
| `write_ese_final_completion_fault` | 后端在命令接纳后立即报告结果，尚未执行写入 | 0/1 | `WRITE_ESE_EXECUTION_CAUSALITY` |

fault只有编译成功、仿真失败且出现指定诊断才算检出。前者证明检查器观察真实内存副作用；后者只证明独立检查器能够发现后端虚报完成。RTL遵循合法后端结果接口，不能自行识别该信号是否与真实外部副作用一致，本测试没有声称它具备这种能力。

独立审查指出早期TB在posedge用blocking更新cycle、requested和originals，可能同沿改变ready、应用候选和drop条件。最终版本将所有反馈到DUT输入的计数及drop/corrupt标志统一改用NBA，采样沿输入保持稳定；仅独立观察状态采用blocking。六个final label全部由修复后的相同源码重新运行，早期label只保留历史，不作为最终矩阵证据。runner同时改为用同一份读取字节写源码快照及计算哈希，避免并行修改时出现快照与哈希身份不一致。

## 复现、快照与限制

在独立工程根目录执行，label必须是不存在的新目录。KD28路径显式传入，并逐份核对 `third_party/kd28_dependency.json` 中五份模型的哈希：

```sh
python3 verification/endpoint_transaction/run_write_endpoint_switch.py --label write_ese_new --kd28-root /home/ljy/work/IC/OverFlow
python3 verification/endpoint_transaction/run_write_endpoint_switch.py --label write_ese_final_lengths_new --kd28-root /home/ljy/work/IC/OverFlow --all-lengths
python3 verification/endpoint_transaction/run_write_endpoint_switch.py --label write_ese_min_new --kd28-root /home/ljy/work/IC/OverFlow --all-lengths --bank-depth 1 --inject
python3 verification/endpoint_transaction/run_write_endpoint_switch.py --label write_ese_final_be_fault_new --kd28-root /home/ljy/work/IC/OverFlow --fault drop_write_be
python3 verification/endpoint_transaction/run_write_endpoint_switch.py --label write_ese_result_fault_new --kd28-root /home/ljy/work/IC/OverFlow --fault early_write_result
```

输出位于 `build/verification/endpoint_transaction/<label>/`：源文件和runner快照、独立fixture hex、程序JSON、compile/run日志、完整工具命令及 `result.json`。六个最终label全部制品哈希与源码快照核对通过；核对时当前生产源与六份快照均一致。汇总审计为 `write_ese_final_lengths_minimum_recovery/audit.json`。

| 文件 | SHA-256 |
| --- | --- |
| `verification/endpoint_transaction/write_endpoint_switch_tb.sv` | `1a9773480e08f2f018ddeb131603800e09ea159d4ecff2c46d97d7222fa8d9f2` |
| `verification/endpoint_transaction/run_write_endpoint_switch.py` | `fc0cd501e9e6966e729047e0dc06e37b241f2684dfdaa2b1b32f8ed992a93cf3` |
| `rtl/endpoint/endpoint_transaction_core.v` | `9638ef06d3ca85807a7eea41f79f59ce0e43e495ee761bc8ff446230c4eae213` |
| `rtl/endpoint/ualink_endpoint_top.v` | `c7880d728ad1a0e34fb78faaa0d7d5be3bc36b0063a67c0519acaf4818095e05` |
| `rtl/endpoint/endpoint_receive_transactions.v` | `89a644f80a2c529a015f2d7ec7c98c1ea5fd643c71fe70d487bf56411144d7f7` |
| `rtl/endpoint/endpoint_write_completer.v` | `df89ad8ebd63cfaa53a61c2c004cb8b3d6999d443970cea0eb6853167a096aa5` |

该ESE矩阵限定在未压缩、无poison、无认证、状态0和单256-byte本地后端区域；五种Write错误/成功状态、非法字段及完整高地址位由各单位测试分别覆盖，此处没有把它们列入ESE成绩。只执行初始统一复位，不覆盖写副作用发生后的复位或独立LinkDown。程序顺序检查验证当前更强的共享有序后端dispatch，不证明真实缓存一致性、原生UPLI连续Beat或外部内存系统语义。

链路仍是既有本地544-bit数字DL记录加显式CRC状态的545-bit测试传输槽，不能称为标准线格式。未补写A19 CRC位序、标准framing、PHY/PCS/FEC/SerDes、管理恢复或联盟一致性认证。下一步可独立增加更多普通地址×长度交叉、错误后端结果及写后复位残留效应；这些未包含在本次1172完成的计数内。
