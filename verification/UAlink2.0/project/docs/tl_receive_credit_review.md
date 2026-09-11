# 真实接收存储与信用发布闭环审查

本阶段新增 `rtl/tl/tl_receive_credit.v`，把实际 600 位 SRAM FIFO 的消费事件直接接到 FC 发布器。发布器不能接收归还向量时，应用端看不到可接纳的 read_valid；FIFO 退休和 release_taken 是同一个事件。初始化和正常归还使用真实 FC/MSG1 输出，经实际 tl_credit_port 扣费与接收，不由测试端伪造正常信用返回。

## 功能范围与证据

16 组配置：信用 WIDTH8/16 × Auth0/1 × Shared0/1 × 数字链路延迟1/3。每端30个事务，每个 CMD 槽初始1个信用，每个 Data 槽4个信用，FIFO 深度100，恰好等于保守容量预算。共5,412双端测试周期、3,072个实际存储/消费字、1,712个FC、32次初始化完成；960个CMD和2,016个Data信用随真实FIFO消费返回。独立审计真实逐拍 trace，核对输入/消费序号、实际发送的数据、保存的释放归属、初始发布排序以及每槽累计发布不超过初始加已消费释放。

七类真实接线故障各在16配置下检出，共112次：提前归还、丢归还、错槽归还、错误共享完成消息、存储数据位翻转、绕过容量预算、发送确认提前。沿用健康用例的同一套TB和向量；故障TB仅重定向自己的trace输出路径。第一次故障运行曾覆盖原 trace 路径，运行前已保存 healthy_trace；驱动脚本已修正，最终检查重新运行。

另有WIDTH1/8的本地预装FIFO试验：发布器未初始化/发送受阻时保持真实存储字，完成初始化后恰好消费一次，再验证带未消费字复位会取消旧数据和信用。两个绕过发布ready的实际RTL故障各在两个配置检出，共4次。这是明确的本地接口定向测试，不作为合法线上启动序列。

两配置严格 Verilator lint 零警告；通用 Yosys 综合分别68,063/96,345个单元、2,210/2,370个FF位、19个 KD28_SRAM_SDP_256X32 宏。检查实际 FF 和 SRAM 的时钟均为 i_clk、无锁存器；八个时钟/异步复位/宏删除图损坏样本均被拒绝。另有三个合法参数展开和六个非法参数拒绝，包含WIDTH1/16与DEPTH65535。编译覆盖不等同于最大容量功能证明。

技能 artifact 检查0错误、14项命名/区域/常量书写建议；全局技能自检仍因缺少 manage_docs.py 未通过。归档保留原始错误日志。最终RTL只补充模块名注释，相对于功能回归源的去注释语义文本完全一致。

## 已复现的持续前进性缺陷

单槽 Data 信用降为1后，在WIDTH8/Auth0/Shared0/延迟1场景，运行6,000周期仍未前进。两端发送/消费索引均为3，FIFO都为0，Tx上下文仍有3/4个未完成半Flit，发布器中有真正消费产生的待返回信用。最后100周期无实际收发、消费或FC提交。这个反例属于目前测试组合使用的“仅在完整Data tenure边界插入FC”调度方式；不能直接推出所有合法UALink调度都必然死锁。

下一阶段必须设计真正的事务准入与信用预约/调度，并处理初始容量小于整个事务需求的情况。不能把默认信用改大、删除多Beat测试或简单永久阻塞请求来声称已解决。还需核对独立的CMD/Data分配、Pool共享、同拍归还、单Beat Read Response模式和原始UPLI事务语义。

## 容量与剩余边界

`2 × Σ初始20槽信用 ≤ DEPTH` 是当前确认tenure的保守共享FIFO资源预算：每CMD最多为头部和额外BE占两个字，每Data信用为两个32B半Flit最多占两个字。保守预算拒绝并不表示该配置在所有微架构中都不合法。它尚不是实际在途Flit、已发未达信用、存储驻留与消费释放的在线联合容量归纳证明。

组合目前在测试顶层连接两套实际端口/存储/发布模块。数字延迟链路不是DL/PHY；没有新产品Endpoint/Switch顶层。命令/地址/长度全部语义、未确认特殊指令、完整参考归纳、CDC/RDC跨域集成和工艺映射/STA仍开放。Auth选项验证当前半Flit分类，不代表密码学认证实现。

## 复跑

```sh
python3 verification/tl_receive_credit/test_model.py
python3 verification/tl_receive_credit/run_rtl.py --kd28-root /authorized/Overflow
python3 verification/tl_receive_credit/run_rtl.py --kd28-root /authorized/Overflow --label small_credit --data-credits 1 --single
python3 verification/tl_receive_credit/run_checks.py --kd28-root /authorized/Overflow
python3 verification/tl_receive_credit/run_parameters.py --kd28-root /authorized/Overflow
python3 verification/tl_receive_credit/run_handoff.py --kd28-root /authorized/Overflow
python3 verification/tl_receive_credit/run_skill_gate.py --skill-root /path/to/verilog-generator
python3 verification/tl_receive_credit/check_evidence.py
```

small_credit命令预期非零，代表保存的真实反例。输出在 `build/verification/tl_receive_credit/`；新运行目录不覆盖旧结果。最后的审计同时要求健康通过和已知反例成立，结果中明确保留small_credit_liveness=false与full_goal_complete=false。
