# Endpoint 接收字段与响应组装实现

`endpoint_receive_transactions` 和 `endpoint_response_assembler` 已从未实现壳替换为真实同步 Verilog-2001 RTL。当前功能是从已保存 TL 记录提取未认证、未压缩、单 64B Read 请求与普通 Read Response，并按字段顺序组装完整响应。因果内存执行、Tag 生命周期和双端事务闭环由上层负责，不能从本单位测试推导已经完成。

规范和实际接收栈映射依据见 [接收契约独立审查](endpoint_receiver_contract_review.md)，字段依据见 [字段审计](endpoint_fields_audit.md)：Common 2.0 §5.1.1/5.1.2/5.3、Tables 5-27..30。没有改变原接收 SRAM、信用归还或标准线上编码。

## 实现与接口

receiver 使用单个 600 位 `r_record` 保存 `{releases80,classes6,msg2,flit512}`，另存本地 port2。输入握手 `i_read_valid && o_read_ready` 时完整捕获，EMPTY/CHECK/LOWER/SCAN/UPPER 五状态处理；CHECK 检查整字类别、Message、字段结构及全部事务 profile，通过后才发布本字任何请求或响应 header。未支持字段不允许跳过后继续错误关联后续 Data。

请求输出为 `o_request_valid/i_request_ready` 及完整 Tag11、SRC10、DST10、ADDR57、LEN6、ATTR8、VC2、POOL、ASI2、metadata8。它支持请求起点 sector0/4、响应起点0/2/4/6，以及同一个 Control 中多个请求或请求/响应混排。类型来自真实 `tl_control_decode` 起点，字段内部 payload 不被当成独立字段。

请求 profile 限 CMD3、64B 对齐、LEN15、ATTR FF、VC/POOL/ASI/metadata0、CLOAD0、NUMBEATS0。CLOAD0 时忽略 CWAY；NUMBEATS0 是当前局部限制，不能称为标准对全部 Read 的接收要求。完整地址补回最低两位，包含最高地址位；地址范围是否映射到实际内存由 completer 判定。

响应 profile 限 FTYPE2、RD_WR1、VC/POOL0、LEN/OFFSET0、LAST1、RSPTYPE0、STATUS0/3。SPARE 忽略，SRC 不参与功能关联，接收器输出 port2、Tag11、DST10、status4、offset2、last、num_beats2、完整 data512、data_error。STATUS3 仍收两个 Data 半字，data_error 在当前支持子集中恒零。

assembler 是实际独立实例 `u_assembler`：固定八槽、每槽32位的有序 header FIFO，保存 `{port,tag,dst,status,offset,last,num_beats}`；一个256位首半寄存器；一个完整512位响应保持寄存器。第一 Data 写低256位，第二 Data 写高256位，完整响应以 `{second,first}` 发布。FIFO 队首只有在第二半已转入完整结果寄存器后出队；输出反压不覆盖数据。输入 header 和 Data 使用各自 ready/valid，本模块要求 header 先于其 Data 已接纳；空上下文 Data 或不同 port 的续半立即锁存错误。

新 lower Control 会把响应 header 追加在已有 header 之后，再消费 upper；因此旧尾与四个新响应同字时最多五个待组装描述符，不会被四槽容量卡住。普通 type0/1 Message 与 FC/NOP 不消费 Data；数据中的位型不被重新解析为 Control。释放向量只随整字保存供审计，原 top 已完成真实信用归还，receiver 不产生第二次释放。

## 错误、反压和复位

压缩字段、Write/Atomic、不支持 profile、BE、AuthTags、Poison、非法类别/Message、非零 mandatory NOP 等锁存 `o_error`，之后停止新输入和新事务输出，直到同步低有效复位。Poison 是规范合法的 Data 替换方式，但本子集未实现其传递，因此明确停流；它不被当作普通 Message 跳过。错误不会自动变成另一 Tag 的成功结果。

正常输入/请求/响应等待、header FIFO 满或完整结果输出占用均是背压，不报错。合法 header 等待未来 Data 没有新增超时计数器；上层超时/LinkDown/epoch 恢复仍未实现。统一复位清除 holding、所有 header 所有权、首半及完整响应有效状态。

单 holding 顺序解析可能让请求背压阻塞同字旧响应。局部测试只保证有限背压撤销后排空；真实双端系统应由上层保留 completer 请求容量并验证资源依赖，不能将这一单位结果称为任意无限背压下无死锁证明。

## 独立测试与实测

```sh
python3 verification/endpoint_transaction/run_receiver.py --label receiver_fresh --faults
python3 -O /absolute/repo/verification/endpoint_transaction/run_receiver.py --label receiver_fresh_optimized --faults
```

需要 Python、Icarus Verilog/VVP，入口从自身位置解析根目录。输出为 `build/verification/endpoint_transaction/<label>/result.json`、独立 `vectors.json`、每个 case 的实际源/TB/编译及运行命令、输出和返回值、源与产物 SHA256。已有 label 拒绝覆盖；下一步使用这些 typed 输出接入真正 originator/completer 与原 TL 接收存储。

先在原壳实际旧接口执行 `receiver_shell_red --shell-baseline`：两个壳均成功编译，运行在 `SHELL_CAPABILITY` 断言失败；该阶段的 passed 表示成功观察到预期能力缺失。历史壳源与命令保留在此目录，当前 typed 接口不能直接重跑旧接口模式。

最终 `receiver_release` 和从 `/tmp` 执行的 `receiver_release_optimized` 各 **41/41 通过**：36个 receiver 配置、1个 assembler 独立容量配置、4项实际 RTL 故障挑战。检查不依赖 Python assert；负向挑战要求特定 tuple 或结果断言，编译失败、watchdog 和任意非零退出不算检出。

- ordered 场景实际捕获23条记录，产生5条请求与13条完整响应。覆盖两个请求位置、全部四个响应位置、完整高位 Tag/ID/地址、非零 FC/SPARE/CWAY、同字多请求、混合请求与响应、旧尾加四新 header、跨字 Data、Message 空隙、status3 和有限请求/响应背压。
- 35个其他 receiver 配置验证逐项不支持 profile、压缩/Write 类型、整字预检、Poison、孤立 Data、port 错配及部分响应期间复位。失败流不产生成功结果，错误后保持停流。
- assembler 直接测试三批各8个 header，满8槽时持续的第9个 header只被背压，未被接纳也不报错；实际完成24个不同完整结果，覆盖读写指针环绕、输出保持和排空后的孤立 Data 错误。
- TB 使用独立固定字段基值和规范位注入构造输入，以独立请求 tuple、响应 tuple 和不同 Data 半字作全位 oracle。它不调用生产编码器或模型 encode/decode。握手后还检查真实 `r_record` 的全部600位保存；该局部元数据刺激不是信用归还模型，实际 publisher 连接由系统级回归验证。

| 隔离源副本注错 | 必须观察到的失败 |
|---|---|
| assembler 交换两个256位 Data 半字 | 完整响应 tuple 比较失败 |
| receiver 丢弃请求 Tag 最高位 | 完整请求 tuple 比较失败 |
| 有多个 header 时错误选用下一槽 | 完整响应 Tag/数据归属比较失败 |
| receiver 错误跳过 Poison | 预期 failstop 结果断言失败 |

早期顺序注错曾导致无上下文等待，被保留为探索记录；最终顺序挑战改成对有效队列跳选下一槽，以实际完整响应比较失败为检出。最终入口不把超时当作这个挑战通过。

`receiver_static` 保存最终 RTL 的 `iverilog -g2001 -Wall`、Verilator `--lint-only -Wall`、Yosys `hierarchy -check; proc; opt; check -assert; stat` 结果，三者均返回0，Verilator无警告。它只证明语法、lint与通用结构可综合性，没有新增工艺 STA、面积签核或完整协议符合性声明。

本轮仅修改两个指定 RTL、单位测试入口和本文；库存晋升、旧壳聚合移除、core/top 接线与实际双端因果 Read 回归由 root 统一完成。
