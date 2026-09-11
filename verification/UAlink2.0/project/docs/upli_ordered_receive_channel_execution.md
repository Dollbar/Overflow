# Ordered receive 独立验证契约

接口按root冻结：原receive_channel参数与输出保留，删除消费者account输入，新增head_account3、per-port order_counts(CW+3)、order_error/sticky(P)。每port order深度为五账户真实容量之和，0容量不创建数据或信用。order只引用真实账户FIFO，非新的payload缓存或信用。

在沿t实际接收的account与port先保存到元信息寄存；沿t后的registered receive_accepted描述这次接收。沿t+1用该accepted和对应元信息入order队列。不得用t+1变化的原生输入。测试连续改变port/VC/pool/data，覆盖此延迟。消费只有consume_valid&&ready，原FIFO和order同沿各pop一次；head_valid不保证credit-return元数据空间。无order头时底层account=7、ready=0，公开o_head_account=0，不报告underflow。

沿前守恒：physical_occupancy = order_count + accepted_pending，逐port求和；两边都仅计实际保存尚未退休的Beat。计数应≤sum(capacity)。当拍新接收不能借当拍释放的满账户空间；order合法同拍pop+push保持数量。顺序FIFO中每一项的account必须匹配真正保存的pool/VC：pool1选择account4，pool0选择原VC，池数据仍保留原VC。

信用是实际初始化器/return_queue输出，接真实sender credit_bank；初始发布恰好各容量，返回只能对应此前消费的同port/原VC/pool，批量最大4且不能跨元信息。公开bank余额与独立事件journal比较；测试不读DUT内部或用DUTorder头生成预期队列。

per-port强顺序为本地策略。四类通道须分别实例化，不能跨通道制造依赖；本测试只证明一条通道的顺序/信用，不证明Req/OrigData owner、TDM、parity或Tag关联。

## 安装后验证结果

生产 RTL SHA-256 为 `fd845d71da9c16d131e5748d9e176f96d26f94cefa1d0b39d8d1d084f32d0236`。正式矩阵使用异构五账户容量并包含零容量账户/port：1、2、4端口分别运行2563、2829、3344周期，共3699次真实接纳、3696次实际退休及3696次原账户信用归还。每项配置定向在一个registered accepted尚未登记journal时复位，因此总计三拍旧epoch接纳被取消；最终SRAM、返回元数据与对端credit bank均排空并恢复声明容量。

三个可编译RTL故障均由独立trace checker检出：入队误取下一周期live account在周期100产生账户顺序失配，入队误取live port在周期333破坏`order_count + accepted_pending = physical occupancy`，payload最低位翻转在周期101产生完整tuple失配。另有定向控制故障测试强制journal账户与SRAM保存VC/Pool不一致，要求本地错误可见且`o_consume_valid=0`；初版在报告错误时仍退休而形成真实RED，修复后保持两份所有权等待外层处置。普通和Python `-O`运行的stimulus与结果一致；Verilog-2001、严格Verilator和Yosys结构检查另行通过。

该结果只关闭每个Native channel内部按port的正常跨账户接纳顺序。它没有检查或转换parity，不关联Req/OrigData burst或Tag，不实现Drop、Isolation、控制状态保护或Endpoint事务上下文。不同VC采用每port强顺序，可能产生允许的保守队头阻塞；后续完整station需保持四通道独立前进并单独审查公平性。

执行命令：`python3 verification/upli_channels/run_ordered_receive.py --label LABEL --kd28-root PATH`。runner读取生产RTL，校验实际外部KD28源SHA；`--expect-missing`只接受明确 unknown-module 编译失败。每次产物位于 `build/verification/upli_channels/ordered_receive/LABEL`，保留源码、stimulus、trace、命令、stdout及独立check.json。接口缺失 RED 只证明测试入口先于生产模块存在；行为结论来自安装后绿色矩阵和真实故障注入。
