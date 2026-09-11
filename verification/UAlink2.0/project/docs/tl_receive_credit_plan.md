# 实际接收存储与信用发布集成计划

Goal：完整双 IP 不变；本阶段接通真实 FIFO 退休到 FC 发布，建立后续双端资源证明的实际硬件基础。
Architecture：tl_receive_credit 连接 tl_receive_storage 与 tl_credit_publish。应用消费和释放向量接纳必须同拍；FC/MSG1 输出只在实际发送提交后退休。配置采用保守的共享 FIFO 预算 2×Σ(20个初始信用) ≤ DEPTH：每个 CMD 最多承担一个头部字和一个额外 BE 字，每个 Data 信用承担最多两个含其半Flit的存储字。此式是当前已确认 tenure 的本地充分容量条件，不是规范最小 FIFO 要求，也不是完整在线容量归纳证明。
Tech Stack：Python、Verilog2001、Icarus、Verilator、Yosys；授权 KD28 SRAM 外部引用。
Spec：本地 Common2.0 §5.8、Table5-26，以及现有 receive_context/credit_publish 契约。未确认特殊指令和 FTYPE6/7 不纳入新声明。

- [x] verification/tl_receive_credit/test_model.py：先验证预算边界（共享/非共享、W1/8/16、超容量/错误向量）、消费/释放原子握手和停顿。保存缺少集成策略的真实失败。
- [x] model/tl/receive_credit.py：独立容量公式与三方握手参考，不导入 RTL 或解析 RTL 表达式。
- [x] rtl/tl/tl_receive_credit.v：单时钟同步复位；WIDTH1..16、DEPTH1..65535；实际 SRAM 接收存储与发布器连接。reset/fatal 停止消费与发布；初始完成之前禁止消费。输出容量预算/发布状态供审计。
- [x] verification/tl_receive_credit/run_rtl.py：真实流水链路、实际信用端口与 SRAM、应用停顿、FC停顿、满容量配置和非法配置；逐字比较保存的 512 位数据及释放，独立解码实际 FC 检查守恒。
- [x] 实际错误接线对照：提前归还、重复归还、绕过发布反压、错误完成消息和错位存储数据必须被健康同套 TB 检出。
- [x] 严格 lint、参数拒绝、综合单时钟/无锁存审查与技能 artifact gate；独立状态/守恒审核后保存新证据与提交。全局技能包自检失败记录单独保留。

完整实际双端小信用 Data 事务可能在中途等待 FC 插入机会；先保存可重现证据，后续在事务准入/整段预约/调度层解决，不修改线上编码或缩小支持的传输长度来掩盖问题。新证据保存在 build/verification/tl_receive_credit/，源码永不放入生成目录；不重复堆积旧结果。
