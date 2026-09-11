# Switch single-resource packet queue candidate review

候选 `switch_egress_packet_queue` 已完成独立 reservation→实际 FIFO/存储→packet 退休反馈验证，尚未安装生产。RTL SHA-256 `a9eba89ec31cc4061f0b65c34dabf36eb695f698d72c2fecac05413fc08a043a`。复用生产 `upli_receive_fifo` 的注册读、预取缓存及真实字容量控制；完整 packet 发布与整笔释放是本候选新增逻辑。

`switch_egress_vc_queues` 和 `switch_egress_repack` 当前只是库存壳；`tl_tx_data_fifo` 是固定256bit双bank半Flit队列。本候选没有 VC/请求响应独立资源分区，因此不替换这些库存模块，也不宣称完成标准 Switch。后端是可综合的本地同步存储数组与显式合法地址读选择；未宣称 SRAM 推断、KD28 绑定、物理面积、时序或大容量性能。

接口见契约文档（可安装布局为 docs/switch_egress_packet_queue_contract.md）。每出口一个未完成 writer，但可以同时保留多个已写完 packet；opaque token 在整个 packet 保存，token 数值可在不同描述符重复。输入 units 是调用者定义的完整 word 数，不从544bit自行推导标准 framing。reserve_ready 是沿前资源邀请，不看组合 grant_units；只有合法 reserve valid/ready 事件保存描述符，非法单位以 error_now 拒绝。实际生产 reservation 保证只输出合法 grant，调用者不能把非法参数上的 ready 当无条件接纳。首次 write 必须晚于 reserve 沿。

只有全部 N 个 word 实际写入后 packet 才可见；输出最后 word 真实 ready/valid 握手一次归还原始 N units。中间出队、最后入队、空闲和背压均不归还容量。零/超额预约、无 owner 写、错误 token、过早/缺少 last 均有诊断。错误沿既有已提交队首仍可退休并正确记账，下一沿 sticky fail-stop；这样不引入 reserve 错误→output valid→release→grant 组合依赖。reset 必须与 reservation 统一取消所有旧描述符；错误恢复、丢弃/回滚和独立 LinkDown 不在本候选内。

TDD：原始 red_compile.log 在候选实现前显示实际缺失 typed module，exit2；这是接口缺失 RED，不冒充行为失败。red_replay/ 保存最终 TB、依赖和缺失模块编译的可复跑结果。行为 oracle 为独立 Python deque packet 队列、整数字节/word 保存与 credit/RR 账本，只读公开时序接口，不读 DUT 内部、不复制 FIFO 预取实现。真实接纳输入 word 作为已保存数据的期望，刺激生成函数不用于计算输出期望；数据/token 真接线故障均被检出。TB 在负沿驱动，正沿抓公开接口，影响组合 reserve_token 的源计数使用 NBA。

候选 frozen/frozen_optimized 与隔离生产布局 portable/portable_optimized 全部通过。每次有4正常配置合计7600周期，3非法输入配置各1900周期，另一个固定字面量直接接口TB。normal 与 -O 的所有逐周期 trace/coverage 相同，证据 manifests 每份94制品逐个复核。

| Ports | Data bits | capacities | cycles | reserved packets | written words | released packets | released units | reset canceled packets |
|---|---|---|---|---|---|---|---|---|
| 1 | 8 | [1] | 1900 | 197 | 197 | 196 | 196 | 1 |
| 1 | 544 | [7] | 1900 | 93 | 371 | 92 | 369 | 1 |
| 2 | 33 | [3, 7] | 1900 | 201 | 533 | 200 | 532 | 1 |
| 4 | 544 | [2, 5, 0, 7] | 1900 | 207 | 616 | 206 | 614 | 1 |

正常配置共覆盖28次同沿原包释放/新包预约、53次最后入队/旧word出队并发；每配置均验证 reset 取消1个未退休描述符。异构零容量不发布ready。持续刺激跳过禁用目的出口，避免发送器在禁用路由上停止而把空闲周期算有效压力。非法token/early-last/missing-last各检测1次错误并跨reset恢复；直接TB另检查零/超额预约、无owner写、busy时重复预约不二次扣账、未完整隐藏、完整word/token保持和一次整笔退休。

7项实际RTL变异均 compile0/run0，独立checker拒绝：提前发布partial在cycle7；每word释放10；漏最后word5；token位损坏7；数据位损坏7；release缩成1单位14；预约缩成1单位4（历史label double_charge，实际mutation是 first-unit-only）。这些证明定向checker检错能力，不是形式完备性。

静态：PORTS1/2/4各g2001、严格Verilator -Wall和Yosys proc/opt/memory_map/opt/check -assert共9项通过；另一个真实 reservation+queue 总装 flatten/memory_map/check -assert通过。技能审计0 errors、11非阻断建议。早期 integrated/ 的depth7 memory_map实际暴露192位补齐读分支无驱动；现已用默认零且仅合法固定地址读选择修复，原失败日志保留，没有 setundef 掩盖。所有检查仅为数字功能/可映射性，未做STA/PPA。

开发执行：`python3 build/development/switch_egress_packet_queue/run.py --label NEW --faults`。可安装布局执行：`python3 verification/ip_tops/run_switch_egress_packet_queue.py --label NEW --faults`；结果为 build/verification/ip_tops/switch_egress_packet_queue/NEW。release/ 包含RTL、portable runner、独立reference、3份TB/helper与契约/本review；复用依赖由主线既有源码提供，hash列于freeze.json。

下一步必须单独设计资源域分区 wrapper 与 ingress packet owner：首拍只预约一次，后续全部word绑定同一出口/token，实际最后退休回同一个容量账本。当前组合fabric没有这条缓存接入；本候选不更改生产top或库存状态。容量只实测1/2/3/5/7，未声称遍历全部UNIT_WIDTH或大容量布局。
