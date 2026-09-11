# Endpoint request context 顶层集成候选

已将真实 `upli_endpoint_request_context` 接到既有 `upli_endpoint_ip_top` 内真实request bridge descriptor握手。没有新增credit bank、连接状态或Drop控制器，也没有实现backend执行器。该集成基于 `docs/upli_endpoint_request_context_execution.md`、`docs/upli_endpoint_context_execution.md` 和 `docs/upli_endpoint_ip_top_execution.md` 已冻结本地接口，不定义新UPLI线字段。


仅在候选目录修改现有upli_endpoint_ip_top副本，不创建另一前端、信用或Drop所有者。按root确认接口，追加C_REQUEST_CONTEXT_ENABLE=0（默认完整legacy行为），C_CONTEXT_CAPACITY=4、C_CONTEXT_GENERATION_WIDTH=8及派生slot/count宽度。本轮固定station输入8位，必须由调用方在共同epoch保持稳定，原有Source Accelerator本地station/port/Tag唯一域限定不变。

启用时bridge descriptor唯一消费者为真实request_context的admission，原i_rx_request_ready不影响该握手。现有o_rx_request_*是只读观察，新增o_context_request_ready/token使实际admission可见。backend issue输出完整station/port/VC/pool、Request184、Data2048、BE256、poison4/data_pools4及token；i_backend_issue_ready只标issued不释放。i_backend_release_valid/token经真实context验证合法后才释放，o_backend_release_ready、o_context_error、o_context_count独立公开。非法release不扩大Drop。backend_implemented继续0，直到真正执行器接入。

context reset使用共同i_rstn && !o_drop_roles[1]，与bridge取消同一Completer holding；四RX保留原共同reset及pending信用排空。此处没有新epoch/LinkDown恢复协议，外部必须同步取消下游执行承诺。关闭参数时所有新增输出归零，bridge原ready原样接回，新增输入无副作用。

TDD先在旧top副本只追加接口并输出0（无context）观察真实station→native RX/SRAM→bridge测试失败。再最小接入context。1/2/4ports验证descriptor入表、issue全字段稳定、容量直到release才回收、非法/旧token、本地共同reset、实际信用journal不重复返回。使用已有真实station/connection_side/KD28和独立源descriptor期望，不用backend预生成协议响应。至少context数据/握手/reset实际接线fault必须被检出。g2001、Verilator -Wall与Yosys检查真实层级只有一个context和既有owner数量。


## 接口及所有权

新增参数均追加在既有参数之后：C_REQUEST_CONTEXT_ENABLE默认0；context容量默认4；generation默认8位；slot/count参数按真实表规则派生。新增端口追加，不改变既有命名接口；已有实例按命名连接兼容。新增 `i_context_station[7:0]` 必须epoch内稳定。启用时 `o_rx_request_*` 仅观察原descriptor，实际fire是valid且 `o_context_request_ready`；外部legacy ready刻意随机变化也不能成为第二消费者。

`o_backend_issue_valid/token/station/port/vc/pool/payload/data/be/poison/data_pools` 与 `i_backend_issue_ready` 是唯一backend交付接口。四已issued上下文持续占容量，直到 `i_backend_release_valid/token` 和 `o_backend_release_ready` 合法握手。全字段在issue背压期间保持；本地token为generation+slot，184位Request中的原11位网络Tag、57位地址、Src/Dst、Auth/ASI/属性与几何均原样保存。未知、重复、旧代次release报 `o_context_error`，不改变其它context，不送进role Drop。没有实际backend或响应尾部执行者时不能用自动release测试驱动器冒充完成，`o_backend_implemented`仍为0。

context reset直接使用共同rstn且非原CompleterDrop；Drop在组合周期屏蔽issue，下一同步沿取消表项，与原bridge保持同一取消边界。四RX仍用共同reset，不因新增context而重新初始化信用。已issue工作被取消时外部执行器必须共同取消旧token承诺，这里没有独立LinkDown或完整epoch协议；有限generation回绕不能无限拒绝旧事件。Source Accelerator本地station/port/Tag唯一域之外的远端Src混流仍需系统评审，不能把当前固定Src777的传输用例扩称多远端命名空间证明。

## 实测与独立检查

RED `red_first` ports1：旧top副本仅补端口零输出，没有context；真实station/connection/SRAM/bridge运行后满四预约检查id521失败，compile0/run1。随后才添加真实context实例。首次实际实现包 `first_actual` 通过两轮事务后在非法release检查失败，原因是TB手动release撤销晚一个negedge，多发重复请求；证据保留，改为沿前稳定驱动后通过，没有修改生产或掩盖RTL错误。

最终 `final_matrix` ports1/2/4均通过，每配置62次admission、57次issue、53次合法release，9条未完成context在共同reset/Drop取消。两轮24个混合Read/Write请求逐字段比较；每轮同时运行真实RdRsp/WrRsp发送/退休流，响应流独立构造，不能称backend因果回复。正常epoch排空检查真实账户journal，head实际退休才允许同账户credit return。context另用源candidate建立的immutable descriptor队列、独立token生命周期表对照首次issue valid，未用DUT输出重新生成期望。满四表时第五笔停在真实bridge，上游仍有实际SRAM容量；先issue四项而不开release，表占用仍为四，随后释放才排空。

非法release包括未知token、重复release、同Tag新代次期间的旧token；每配置6个诊断周期、无Drop。reset分别取消四条未issue和四条已issue的真实表项，恢复后同Tag重新Write完整交付；CompleterDrop再取消一条已admission holding。输出统计heads331/returns330是启用非故障epoch的监测累计，故障窗口暂停该旧journal且共同reset允许取消pending，不能据此声称跨reset累计信用严格相等。每个正常drain窗口逐账户实际归还和容量都独立核对，fault/reset窗口限定为取消/恢复检查。

`final_legacy` ports1/2/4保留旧前端两轮+错误/恢复验证，每配置50个descriptor、301个heads/returns；所有新增输出在新增输入持续非零时仍确定归零。启用和legacy六配置均g2001、Verilator -Wall、Yosys通过，无latch。Yosys真实层级启用仅增加1个context，原station1、creditbank4、nativeRX4、orderedRX4、bridge1、collector1、connection2、role-controller1、parity36保持；关闭context实例数0。

`final_fault_admission/tag/release/reset` 四个真实顶层接线mutant均compile0/run1：bridge错误改用legacy ready导致重复接纳诊断(id501)；Tag高位接错导致全字段issue不符(id505)；断开release valid导致实际表占用与外部合法退休账本不同(id500)；context reset错误仅接共同rstn、漏掉CompleterDrop导致取消检查失败(id531)。最后一项专门证明Drop取消连接，不能误称单独丢失共同reset线的fault。

局部技能检查对候选顶层0 errors/9条模板格式warnings；安装总门因缺agents-md-generator/scripts/manage_docs.py保持HOLD。既有context叶模块的历史文本检查争议未在本次重新宣称关闭，真实hierarchy EDA均检查了该模块。

## 使用及交付

候选：`python3 build/development/upli_endpoint_context_top/run.py --label NEW --kd28-root /home/ljy/work/IC/OverFlow --static`。
发布后：`python3 verification/upli_channels/run_endpoint_context_top.py --label NEW --kd28-root PATH --static`；legacy加 `--legacy`；fault加 `--ports 4 --fault tag`。KD28 root由参数明确传入，functional source必须匹配third_party/kd28_dependency.json，不依赖隐含相邻目录。Icarus/vvp、Verilator和Yosys来自本地工具。

结果位于 `build/verification/upli_channels/endpoint_context_top/NEW`，含源快照、依赖hash、命令/返回码、全日志和hierarchy统计。release目录五项文件为精确拟安装清单；另有局部patch供人工审阅。独立release_replay已实际运行ports1正常（含全部静态）和ports4 Tag fault并通过，freeze.json记录最终标签与哈希。

不覆盖实际backend存储副作用、响应生成/尾部release关联、原生完整端到端Endpoint事务闭环、跨station/Src全命名空间、PPA/时序签核或形式证明。本次只打通真实前端至上下文和明确执行边界，不创建伪执行器。
