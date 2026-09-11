# 实际双端 Read 因果事务

`ualink_endpoint_top` 新增展开参数 `TRANSACTION_MODE=1`，在原有真实 TL 捕获/发送SRAM、信用、接收600bit SRAM、DL重放上接入实际事务核。默认0保留既有prepared源接口。模式1使用内部应用ready/valid请求和内存服务接口；这不是原生UPLI接口，也不改变完整双IP交付范围。

新实现六个模块：`endpoint_transaction_core` 总装、`endpoint_read_originator` 请求发起、`endpoint_tag_table` 结果容量/Tag生命周期、`endpoint_read_completer` 内存执行与响应、`endpoint_receive_transactions` 记录解析、`endpoint_response_assembler` 有序两半Data组装。复用前轮的两个字段编码器。当前202项库存变为66个部分实现、136个未实现壳；位图仍只显示壳状态，不表示完整协议符合性。

## 所有权与真实连接

应用握手先预约四槽表的一项与完整512bit结果容量。完整11位Tag按本地port匹配；一个pending请求holding在TL source capture后停止重复提交，但保留到实际`u_tx.o_header_taken[0]`才标sent。当前该Request源只有本Read originator，每组只有一个未压缩Read字段；未来其他Request生产者需要传递精确身份，不能混用无Tag的header_taken。

Receiver只在能保存整个600bit字时允许原接收SRAM退休。分类、msg和释放元数据随512bit载荷原子保存，原信用发布器继续负责释放，事务核不二次归还。接收器先预检整个字，再解析自然起点上的多个请求/响应；八槽描述符FIFO保持旧响应尾半和新Control多个响应的顺序，完整两个Data半Flit之后才公开结果。未支持的tenure/Poison/Auth在本接收器锁存诊断并停止直到统一reset，不跳过未知流继续误配数据。

Completer在收到真实请求后才保存描述符并发出57bit地址内存读；真实内存结果握手后才构造匹配Tag及交换ID的Response。四个结果槽允许内存按slot乱序返回，Response按请求顺序发送；Header捕获与两个Data半Flit全部接纳后才释放槽。Response Data类别1的低半连接`data0[511:256]`，高半连接`data1[511:256]`，低256位类别0保持无Data。

Originator只接纳已sent的完整对应响应。收到完整Data后可公开应用完成，应用ready握手后才释放Tag。status3仍携带完整线上Data，但应用`complete_data_valid=0`且数据清零。未知、重复、未sent和非法结果被局部诊断，不更新有效表项或伪造完成。

## 最终独立验证

下表均实例化两套真实Endpoint顶层和两端口Switch，使用16个应用Read刺激（每端8个），没有预生成Response fixture。地址含完整高位未映射地址，Tag含0/4/1024/2044等相同低位值。内存BFM仅接收真实mem请求；检查器逐笔核对应用预约→实际TL请求头消费→内存读→内存结果→首次完成valid→应用退休，不把应用反压期间的提前valid漏过。

| 配置/实际故障 | 结果 | 实测边界 |
|---|---|---|
| `causal_final` 正常BANK_DEPTH3 | 16/16完成，562周期 | 每端4 outstanding，0重放 |
| `causal_final_recovery` | 16/16完成，624周期 | 每端一次CRC坏槽、一次丢槽和4次重放；内存执行/完成不重复 |
| `causal_final_minimum` BANK_DEPTH1 | 16/16完成，624周期 | 两bank最小深度，部分Data接纳接口保持有效 |
| `causal_final_data_fault` 响应高Data半清零 | 编译0、仿真1，检出 | 完整512bit结果不一致 |
| `causal_final_retirement_fault` 绕过receiver ready退休 | 编译0、仿真1，检出 | 完整Data错配，不把丢记录当成功 |
| `causal_final_tag_fault` 去掉响应Tag最高位 | 编译0、仿真1，检出 | 真实Tag表诊断触发顶层检查 |

完成数据使用16个冻结512bit字节向量，期望不调用内存BFM函数。BFM数据生成混入地址高于byte低8位的行号，使地址0与256内容不同；这些数据是测试内存定义，不宣称真实系统缓存一致性或内存模型签核。独立审查指出的首次valid因果与共享函数oracle问题已在上述最终矩阵补强。历史`causal_fault_retirement`曾因诊断分类未列入而记录passed=false；保留旧记录，最终引用新标签，不回改旧结果。

单位验证另见 originator 的1/2/4本地端口与7故障、completer的32条真实内存/响应链与3故障、receiver/assembler的41项完整字段/半字/容量/拒绝/复位与4故障。单位配置不等于多物理端口完整集成。模式1两套顶层展开/结构检查通过，未推断为新工艺STA或门级面积成绩。完整当前源码校验值和运行记录见 [因果事务证据](endpoint_causal_read_evidence.json)。

```sh
make ip-transaction-smoke KD28_ROOT=/authorized/Overflow IP_RUN_LABEL=fresh_causal
make ip-transaction-elaborate KD28_ROOT=/authorized/Overflow IP_RUN_LABEL=fresh_causal_elab
python3 verification/endpoint_transaction/run_transactions.py --kd28-root /authorized/Overflow --label fresh_minimum --inject --bank-depth 1
python3 verification/endpoint_transaction/run_transactions.py --kd28-root /authorized/Overflow --label fresh_fault --fault retirement
```

输出在`build/verification/endpoint_transaction/`；展开输出在`build/verification/ip_tops/`。运行器校验显式KD28功能文件SHA，复制RTL再编译，故障仅修改隔离副本，保存源/产物校验、命令、返回值和日志。已有标签拒绝覆盖。

## 尚未完成

当前仍为单物理端口0、Auth关闭、单64B普通Read（length15/attrFF/VC0/pool0/ASI0/metadata0），状态0/3。任意合法Read长度/掩码、多beat响应模式、Write/Atomic/INC、压缩、认证、安全、管理、PHY和标准逐跳TL/DL仍需完成。544bit数字链路仍是24bit本地DL头加520bit不透明TL记录，CRC由显式状态输入，不能称标准DL framing或互操作。

顶层测试仅初始统一reset；单位测试覆盖在途清除，但尚未证明整个双端网络在途reset恢复。内存接口需配合取消旧reset epoch的结果；slot索引不能识别槽复用后迟到的旧结果。Auth/port配置必须在reset期间设置并保持稳定。顶层error是诊断汇总，不等于所有健康TL/DL模块立即停止或协议LinkDown恢复。默认四槽completer通过；其他容量尚无完整功能覆盖，其中CAPACITY3通用memory-map探索有未驱动警告，明确不计通过。CDC/RDC、完整参数矩阵、工艺STA和最终签核未完成。

下一阶段扩展真实事务与恢复/参数覆盖，随后逐项替换剩余136个壳；不让局部PPA或小模块形式证明取代完整模块功能推进。
