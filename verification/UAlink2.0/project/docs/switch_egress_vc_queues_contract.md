# Switch egress VC/Request-Response queue contract

候选库存名 switch_egress_vc_queues；只在 build/development 开发，不改变当前 production/scaffold。职责是按出口、Request/Response 和 VC 分离的真实有界完整 packet 缓存。既有两叶 switch_credit_reservation 与 switch_egress_packet_queue 组合复用，packet queue 再复用 upli_receive_fifo；不重复容量状态机。

PORTS=1/2/4，VCS=1/2/4；VC 是原始2bit值，须小于VCS。类别 response=0 Request，1 Response。domain=response*VCS+vc；slot=domain*PORTS+egress。每slot CAPACITIES[UNIT_WIDTH]硬分区，不借其它VC/类别容量；0容量禁用。payload和token宽度参数 DATA_WIDTH=544、TOKEN_WIDTH=8，UNIT_WIDTH=4，合法范围与底层相同。资源单位是本地完整word，不自行推导标准线上packet长度/编码。

每ingress提供 i_header_valid、source-major i_route_match、i_header_units、i_header_token、i_header_vc[2]、i_header_response。o_header_ready 是真实接纳脉冲：同时取得该域的whole-packet reservation和queue descriptor。唯一route且units合法、整笔沿前容量足够、该slot无未完成writer、source没有body owner或sticky错误时才可能接纳。各slot独立RR选择持续eligible源。非法route/units/VC报告o_header_error并拒绝；普通满、busy和背压不error。

每ingress最多一个body owner，跨所有域共用。接纳header保存domain/egress；i_body_valid/data/last/token只路由到已保存目的，不重新使用当前header字段或route。首body必须在下一沿或以后；所有N个真实接纳word完成才释放该source写owner。最后word的last/完整token由实际queue核查，错误不静默接受。下一header可以在前packet等待输出时接纳，但不能绕过尚未完成body owner。无owner body会诊断并阻止同沿header预约，避免出现已扣账但未保存的token。

每slot独立 i_ready 与 o_valid/data/last/token；完整入队前不发布，最后实际出队才归还完整units。各slot单独输出，不在本叶实现物理egress合并/跨域优先级。输入source共享会造成源自身队头阻塞；Request不能占Response存储，但若同一个source尚欠Request body，它也不能越过此owner发Response。这是明确的本地接口边界，不宣称端到端无死锁。

诊断：o_header_error逐source为当拍非法首部；o_body_error逐source为当拍非法body；o_source_error_sticky逐source从下一沿阻断。o_queue_error_now/o_queue_error_sticky逐slot保留底层诊断。o_error聚合；各域互相不因一个错误全局冻结。错误沿已有提交输出仍可实际退休，下一沿对应queue sticky阻断；无Drop/rollback。所有层i_clk/i_rstn同域、同步低reset，共同取消旧token与credits，RAM内容不必清零。

公开o_available/o_reserved/o_queue_reserved/o_stored/o_completed按slot，o_source_busy按source，供实际资源边界核对，不把监视状态当oracle内部捷径。输入和输出payload原样，Req/Rsp/VC保存由队列物理归属保证。尚未实现线上TL提取/重打包、物理出口scheduler、管理配置、跨时钟域和LinkDown恢复；达到此本地缓存职责后才能建议晋升库存，完整Switch仍需独立集成。
