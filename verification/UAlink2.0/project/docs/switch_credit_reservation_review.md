# Switch packet capacity reservation candidate

选择库存 planned `switch_credit_reservation`。这是本地出口真实缓冲容量的预约/释放管理，不是UALink线上信用格式或TL/UPLI银行。当前顶层尚无真实egress queue，故候选不宣称已接通Switch容量闭环。集成位置是route_lookup之后、packet-owner建立/egress queue descriptor实际接纳之前；queue真实退休反馈release。

参数PORTS=1/2/4、UNIT_WIDTH=3..16、DEFAULT_CAPACITY、CAPACITIES[PORTS*UNIT_WIDTH]。每ingress i_request_valid与units以及source-major i_route_match；每egress i_admit_ready、i_release_valid/units。输出每ingress request_ready、egress-major grant onehot矩阵、每egress grant_units、release_accepted、available/reserved和逐源request_error/逐出口release_error，聚合o_error。时钟i_clk、同步低有效i_rstn。

request_ready是本沿实际packet预约接受；要求唯一route、1≤units≤该出口容量、沿前available≥units、admit_ready和本出口release无错误。输出grant只在真实预约沿有效；不承诺未接纳前内部选择不变，上游保持候选到接纳。完整packet单位一次减去，禁止以首Beat一单位代替完整长度。各出口独立RR，每次真实接纳后指向该源之后；背压、idle、资源不足不推进。持续eligible源至多等待PORTS个该出口有效仲裁机会；有限packet/资源与下游可接受是公平性的前提，不声称无资源也有限时延。

release只表示此前已占有的本地缓冲units已真实释放，1≤units≤沿前reserved。同沿release不能释放新grant，也不旁路给当前不足的request。合法同拍grant/release以净值更新available；非法release隔离本出口沿，余额/轮询保持、不接纳本出口request，其他出口独立前进。非法request不接纳、不占资源，不阻塞其他合法source；正常满或ready低不error。复位后available=真实empty queue容量、RR从source0开始；复位前已外部写入的存储/packet所有权须由同一epoch一起取消。

只有一个对应的queue容量所有者能接这个service。它不保存packet本体、不证明Data tenure、跨VC/Request-Response独立资源、防死锁或Drop/LinkDown恢复。每种独立资源域需要自己的实例/明确分区，不能让requests耗尽response预留。实际top若采用此候选，还须增加egress queue及packet单位计算、一次首拍预约token、完成入队/退休关联；严禁每个后续Beat重复预约，不能直接把已有任意544bit链路slot当完整标准packet。

测试用独立整数容量账本、每出口Python deque轮转顺序和固定事件向量；TB只比较公开ready/grant/units/余额/诊断，不读内部指针。真实旧壳已compile0/run1 RED。绿色要求1/2/4ports、公平性、背压、异构/零容量、整笔不足、同拍收放、非法route/units/release、reset和真实RTL故障。运行 `python3 build/development/switch_credit_reservation/run.py --label LABEL --faults`，产物results/LABEL；下一步由root审查安装候选并实现真实queue总装，测试不含STA/PPA/标准认证。

# Switch packet capacity reservation 审查结果

候选实现库存 planned `switch_credit_reservation` 的本地完整packet容量预约。RTL SHA256：`b9fb610062cd62511e137afbedafeb82cecdeb096383f08883791582dfa95f31`。未修改生产目录/库存；实际顶层尚无egress queue，因此该结果不能称顶层信用闭环完成。

真实旧壳 `red/source.v` 编译0、运行1，以 `PLANNED_RESERVATION_NOT_IMPLEMENTED` 证明原generic壳不能提供预约服务。typed接口、独立Python整数账本/轮转deque参考与SV全公开字段比较在候选隔离开发。参考不读取RTL内部，不复用RTL编码函数；向量显式验证饱和持续eligible下0..P−1公平次序。资源暂不足时不保证有界等待，公平界限以真实下游可接纳和持续eligible为前提。

最终 `results/frozen` 与 `frozen_optimized` 普通/-O各四配置：P1/W3/容量[5] 928周期；P2/W4/[3,5] 964周期；P4/W4/[2,5,0,7] 1039周期；P4/W16/[65535,257,4,0] 1039周期，合计3970周期。包括每出口RR、背压不推进、整packet不足、同沿release不能旁路、合法收放净值、非法route/零或超大units、错误release出口隔离、独立并行出口、零容量与reset取消旧epoch。

六个真实RTL故障均compile0/run1，由具体 `RESERVATION_MISMATCH` 检出：RR不前进cycle5、只扣首unit cycle116、绕过ready cycle36、同沿释放旁路cycle117、过量释放被接受cycle119、route矩阵转置cycle4。checker比较完整grant矩阵/units、ready/releaseaccepted、available/reserved与逐端诊断，不只累计成功次数。

P1/P2/P4分别g2001编译、Verilator `--lint-only -Wall` 无警告、Yosys `proc; opt; memory_map; opt; check -assert; stat` 均通过。初轮lint的常量收窄警告保存在first，已显式取位修复。技能owned RTL artifact门禁零错误、15项建议警告；常量循环界限使用明确32位localparam，使门禁的保守常量识别与实际elaboration一致。没有4-state/X穷举、形式公平证明、工艺STA或PPA/硬件互操作。

集成应由真正egress queue提供容量和退休release，在完整packet首部形成一次reservation token；保存source/egress/units/资源类别直到全packet完成。此后body不能重复预约或随route变化重选。当前 `route_lookup→arbiter→fabric` 需把“有资格的新首部”与“已有packet owner的body”分开；只把ready随手AND进现arbiter不足以保存已预约的所有权。Request/Response/VC独立资源保证以及buffer token有效性由未来queue层负责；本模块只能检查释放量不超总used，无法凭units识别释放是否来自正确packet。不可接原TL或UPLI账户而重复扣账。

可安装release包含一个RTL、独立runner/TB/reference及本审查文档；生产命令：

```sh
python3 verification/ip_tops/run_switch_credit_reservation.py --label reservation_review --faults
python3 -O verification/ip_tops/run_switch_credit_reservation.py --label reservation_review_optimized --faults
```

输出 `build/verification/ip_tops/switch_credit_reservation/LABEL`，包括源快照、vectors、coverage、命令/日志、summary与manifest。portable版本在隔离release_replay根实际执行，避免只验证依赖候选路径的runner。下一步由root复制后重跑，并保留egress queue未集成的pending范围。
