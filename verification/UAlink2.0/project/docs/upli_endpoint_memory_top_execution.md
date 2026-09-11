# Endpoint memory lifecycle 顶层集成

本候选在既有真实native前端、request bridge和context之后增加一个已实现的 `endpoint_memory_adapter` 实例。生产接口到command/result/completion/final/release的生命周期已实际连通；memory操作与原生响应formatter仍是外部职责，`o_backend_implemented`保持0。不得把验证中的字节内存BFM或formatter当成生产RTL。

依据已有 `docs/endpoint_memory_adapter_execution.md`、`docs/upli_endpoint_request_context_execution.md`、`docs/upli_endpoint_context_top_execution.md` 及四个typed通道契约。此次不新增标准协议码或字段。


C_MEMORY_ADAPTER_ENABLE默认0，新增参数/端口追加；打开必须C_REQUEST_CONTEXT_ENABLE1。真实唯一context issue接已安装endpoint_memory_adapter；新增memory command/result/completion/final接口完整映射adapter，无额外寄存周期。只有adapter release_valid/token接真实context，旧外部issue_ready/release_valid/token在此模式无消费作用。关闭新增功能保留已有原生及context模式，新输出归零。

完整command携带本地token、station、port/VC/pool、原Request184、Data2048、BE256、poison及data_pools4，网络Tag不改变。result完整2048位/status4/poison4；completion表示外部formatter接纳结果，不等于最后response退休。最终外部owner必须依据实际response最后native传输确认final token；adapter核对状态/token后才送最终release。o_memory_issue_ready和o_memory_release_valid/token作为实际事件观察；旧o_backend_issue_*保留观察。backend_implemented继续0：生产并未实现memory操作或自动formatter。

adapter和context共用i_rstn且非既有CompleterDrop。无第二Drop/credit owner；不把非法result/final本地诊断擅自扩大成Drop。共同取消包括外部backend pending和formatter；已执行memory不能虚假rollback，不声明独立LinkDown/epoch保证。

独立测试用实际station TX/connection/nativeRX/KD28/context链路；字节写内存BFM实际执行后延迟result。Python独立bytearray oracle离线生成逐请求完整result和逐native响应期望，test-only formatter驱动真实station response候选，只有实际最后native有效拍匹配才报告final。测试侧formatter不可发布到生产RTL；正常及-O均保留断言有效的checker（Python显式失败判断）。覆盖ports1/2/4、command/result/completion/final等待、context容量、未知/旧result/final、共同reset及真实接线fault。先RED旧top只增加零输出接口，再接adapter。


## 新接口的明确职责

新增参数 `C_MEMORY_ADAPTER_ENABLE=0` 追加，打开必须 `C_REQUEST_CONTEXT_ENABLE=1`；不合法组合(0,1)和非法mode2必须展开失败。默认关闭新输出归零，原native和context外部生命周期保持。启用时原 `i_backend_issue_ready / i_backend_release_valid/token` 无消费作用，原issue输出仅观察。真实adapter独占context issue ready和最终release。`o_memory_issue_ready` 与 `o_memory_release_valid/token` 公开实际事件，不建立第二credit或Drop owner。

`o_memory_command_valid / i_memory_command_ready` 与完整command字段交给实际backend；字段有本地token、station8、port/VC/pool、Request184、Data2048、BE256、poison/data_pools4。result输入包含valid/token/status4/data2048/poison4，错token/早到/重复结果被adapter消费并诊断，不能改变合法事务。completion输出valid/token/status/data/poison由外部formatter接纳；completion_ready本身绝不释放。`i_memory_final_valid/token / o_memory_final_ready` 只有实际最后response native传输完成之后才能由对应外部owner驱动；adapter核对token及状态后产生最终release并等待真实context接纳。

特别注意：completion不含原Request身份。测试formatter在真实command fire保存metadata，之后用该保存值格式化；绝不能借用可能已指向下一请求的原context issue输出。生产自动formatter仍需新增这种元数据保持/查询路径和真实TX尾部token关联，当前不宣称自动回包。

adapter和context共享共同reset且非既有CompleterDrop，不增加role状态。外部backend pending/formatter必须随共同取消停止旧事件；已发生的memory字节效果保持。此处无独立LinkDown/epoch恢复，也无无限代次ABA保证。station/port/Tag域沿用此前单Source Accelerator profile，跨远端Src混流不在本次固定Src777测试证明中。

## 独立自检与实测

测试实际实例化station TX、connection_side、native保护/有序接收、KD28 SRAM、request bridge、context和memory adapter。后台BFM在命令真实接纳后延迟13周期才逐字节执行：普通Write按BE，WriteFull忽略输入BE写全部有效Beat。backend返回完整2048位；Read256返回4个原生RdRsp拍，Read状态0/2/3/6/8均返回完整拍并保持poison；Write由实际单WrRsp传输结束。

Python reference使用独立bytearray内存及冻结字段位常量生成192行fixtures（8个epoch×24个候选）。实际执行前缀为24/24/0/2/1/2/1/2；未执行的假定后续fixtures不计覆盖。内存按port分区各256B；此测试全部请求用同一已知自然对齐region，写长度覆盖代表1..4个64B Beat和普通/Full，不宣称所有4..256B偏移几何、地址翻译或全后端语义。原Request含完整Auth/Src/Dst/Tag、VC/pool及poison的数据透明传递被比较，Auth计算不在scope。

source candidate入独立journal；context admission/issue、memory command、真实backend result、completion、每拍native响应、final、release分别记账。所有首次valid与背压稳定字段都比较独立期望，formatter不能自行生成oracle。`MEM_TRACE`记录command、completion、native_last、final、release周期，明确断言 `completion < native_last < final < release`；final被接受后的下一周期应有真实release。completion背压、native发完但final延迟、已issue但command未接纳均不得归还context容量。

最终使用automatic checker：`release_matrix`（1/2/4，含static/参数guard）、`release_optimized`（同矩阵python -O），每配置57个实际命令、56次执行/合法result、55个completion/实际native末拍、54个final/实际context release。1条命令在执行前reset取消；另有已执行但completion未取、native已发但final未报时取消。ports1/2取消4条context、ports4取消3条，差异来自执行前reset时额外prefetch context是否已到达，不能把这些全称backend执行取消。共同reset保持已写字节，之后Read oracle校验保留值。

每配置10个错token/早到/旧epoch final诊断周期；这些本地事件未扩大Drop。正常drain逐原始信用账户验证heads/returns和容量恢复；跨reset累计分别257/256、258/256、256/255，存在被共同取消的transport pending，不能伪称全epoch累计严格相等。没有重复credit owner；实际Yosys层级仅增加1个memory adapter，原context1/bridge1/station1/creditbank4/nativeRX4/connection2/role-controller1等维持。

`release_legacy` ports1/2/4关闭两新层，所有新增memory输出在输入非零时全0，原50descriptor/301head/301return均通过。`release_context` ports4保留context启用而memory关闭的原外部生命周期（62 admission/57 issue/53 release/9取消）通过。以上静态均g2001、Verilator -Wall、Yosys无latch通过；正常/-O用于完整memory矩阵，未额外声称legacy也做了-O全交叉。

五个实际接线mutant在普通及-O均compile0/run1：错误用legacy issue ready、command Tag高位翻转、截断result最高512位、断开final valid、把completion当release且错误借用completion token。最后一项即时id600捕获提前释放；final断线即时id624捕获，最终证据不靠全局timeout。runner所有通过条件用显式布尔检查，Python-O不会删除断言。

## RED与检查者修复记录

保留初始两个装配失败：既有生产TB已追加兼容空端口导致重复绑定；Icarus不能将复杂索引array元素直接用作fscanf目标。修正后 `red_ready` compile0/run1，旧top只增加零输出接口，尚无adapter，错误让旧外部release进入context，id601证明缺唯一backend owner。之后才接真实adapter。

加强提前release mutant时发现继承静态 `ck` task可被多个posedge进程并发覆盖参数；debug轨迹表明cycle280提前release、281 count3/qwrite4，旧checker未即时失败而仅timeout。三份候选TB均改为 `task automatic ck`，所有最终release标签已重跑，提前release现在281周期直接id600失败。历史timeout故障包保留，但不作为修复后即时断言的证据。

局部技能顶层检查0 errors/9模板格式warnings；安装总门仍缺agents-md-generator/scripts/manage_docs.py，HOLD保留。没有修改技能或隐藏失败。另保留早期legacy静态3条unused路由告警，已在关闭分支显式声明未使用路由后严格重跑通过。

## 运行与交付

候选：`python3 build/development/upli_endpoint_memory_top/run.py --label NEW --kd28-root /home/ljy/work/IC/OverFlow --static`。
生产布局：`python3 verification/upli_channels/run_endpoint_memory_top.py --label NEW --kd28-root PATH --static`，可用 `python3 -O`。关闭兼容用 `--legacy`，context-only用 `--context-only`，故障如 `--ports 4 --fault release`。运行依赖本地Icarus/vvp、Verilator、Yosys；KD28路径显式参数传入，源码必须匹配third_party/kd28_dependency.json。

结果写 `build/verification/upli_channels/endpoint_memory_top/NEW`，保留source/fixtures/log/每命令返回码/hierarchy及hash。release目录是7项精确安装文件（top、runner、独立reference、三TB、执行文档），其它生产模块只作为已安装依赖。freeze.json列源码SHA、验证标签和重算结果；独立release_replay检查发布布局不依赖build/development。

没有PPA/STA/形式/认证声明；没有完整生产自动formatter、backend执行器或网络response尾部自动关联。这里交付的是实际模块生命周期连接及真实对端验证，完整Endpoint产品闭环仍需上述外部owner落实。
