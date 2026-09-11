# Native RX 请求保持桥执行与验证

`rtl/upli/upli_endpoint_request_bridge.v` 已实现一个可综合的完整事务 holding：从真实、按每port顺序保存的 Request184/OrigData580 接收头转移数据，公开完整 Request184 + Port/VC/Pool + Data2048/relativeBE256/poison4/data-pools4 描述符。输入端不重分配 Tag、Src 或 Auth，输出端不自行发明 Response。本模块为已验证候选的生产布局版本；发布安装与顶层接入由集成流程单独管理。

此为 Endpoint native 请求保存/转交子块，范围经 root 确认；不是完整 Native station、Tag/RAS状态机或 TL/Backend端到端桥。其正常语义依据 docs/upli_native_rx_execution.md、docs/upli_endpoint_context_execution.md 及 Common2.0 §2.6 pp43–45、§2.7.4 pp49–52、§2.7.8 pp71–72、§4.1 p101。原生首Req/首Data同沿、TDM和parity必须在上游native接收边界检查，此模块的SRAM头接口不能反推原始到达时刻。

## 行为与所有权

输入具有 head_valid 与 consume_valid，两者不等价。Request仅在完整holding空闲且普通几何合法时转移；Read不消耗OrigData，Write/Full从同一保存port逐拍转移Num+1个头。Request的完整Port/VC/Pool/Auth/Src/Dst/Tag保存到真正下游接受，外部selector或原生输入噪声无法改变它。Data Offset必须递增、Last只在末拍、VC匹配原请求，Pool和poison可逐拍改变。普通CMD3/28/29及DWORD对齐、256B区域、Num与Full几何已检查；非法头不退休，并保持局部诊断至共同reset。

三个事件分别计账：

1. `req_transfer`/`data_transfer` 把一个完整头复制进已预约holding；原SRAM/顺序项同沿退休，原账户信用可按既有receive_channel正常归还。
2. 信用返回是既有注册返回接口的独立事件，可晚于head transfer，且不受下游descriptor反压影响。
3. `o_request_valid && i_request_ready` 只释放holding，不再次消费接收头，不产生第二笔信用返还。

holding只接受一笔事务，是保守吞吐选择。Read可在另一个真实Request FIFO中排队并与旧Write尾部同时入站；holding完成旧Write后再转移Read，不拒绝合法native overlay。该模块没有端到端outstanding表、Tag重复检测或自动公平调度；i_select_port由上层选择下一服务port。共同reset清holding/部分数据/停用标记，取消的descriptor不交给下游。

ByteEn保持全部原始64位，输出为relativeBE。Full中无意义BE也透明保存，由命令执行/序列化层选择忽略并按几何重建。当前模块不检查普通Write BE是否超出有效访问范围，未来Endpoint资格/转换层必须完成该项；本回归的BE用于逐位保存、zeroBE和lane映射测试，不能称为全部合法内存写profile回归。Poison仅保存，不将它执行成成功写。Auth非零值在此作为上游已检查的透明字段保存，不代表已具备认证或Auth inactive资格检查。

## 实际验证结构

TB实例化两个真实 `upli_ordered_receive_channel`，各自内部真实receive_channel/FIFO/KD28 SDP存储及独立信用返回，再连接两个真实credit_bank。两个实际connection_side按外部req/ack交叉，共同同步reset。外部KD28根由命令显式提供，核对 third_party/kd28_dependency.json 的五份hash；未复制受限外部源码。

独立native journal从发送沿的原始payload、port、VC、pool建立，实际SRAM head-transfer逐位对照；另一队列只在真实head-transfer后记录可归還元数据。每个正常返回批次逐项检查其原VC/Pool及数量，禁止未转移先返还或最终descriptor接受后重复返还。独立Python fixture按原始字节位置生成完整descriptor数据/BE预期，不导入RTL codec或读DUT holding作为oracle。所有刺激负沿准备，无posedge计数反馈改变当沿输入。

每端口138个普通字段/几何场景：64种Read长度、64种Write长度、10种Full合法地址/长度几何；普通长度各取一个合法起点，**不称2080几何全交叉**。Request VC0..3与pool0/1独立组合，Data跨VC/pool、非零高Auth/Src/Dst、高Tag/最高地址位保留。每笔完整输出至少31周期下游反压，overlay旧Write另等41周期。独立检查首次valid即全部头已真实转移，反压期间全tuple稳定，最终仅一次descriptor。

额外实际场景：Read与Write第二数据拍同沿进入真实Request SRAM，等待旧Write组装/反压后再转交；四Beat Write仅复制两拍时共同reset；完整descriptor反压时reset；非法DWORD地址头不消费；重复Data Offset在已复制一拍之后停用、坏头不消费；reset后同Tag新轮正确完成。每个正常配置共6次初始化时期，部分时期故意以reset取消未提交事务。

## 红绿及故障结果

首次 `red_first` 在实现RTL前使用接口兼容的fail-closed stub，真实接收系统编译0、运行1，第222周期 mismatch40（没有形成应有完整descriptor）。这是缺功能红测，不是生产RTL缺陷报告。`frozen_red` 使用后续TB也复现同一失败，保留完整来源。

最终正常标签 `candidate_matrix`：

| ports | 完整descriptor | head transfer | 正常返回信用数 | 反压观察周期 | 检查数 | 总周期 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 143 | 369 | 369 | 4448 | 50544 | 7747 |
| 2 | 281 | 707 | 707 | 8726 | 102222 | 15107 |
| 4 | 557 | 1383 | 1383 | 17282 | 221553 | 31840 |

三配置均compile0/run0，Verilog-2001编译、无waiver的strict Verilator lint、Yosys proc/opt/check/stat均exit0。共981笔完整descriptor、2459次真实头转移与同数正常归还；取消的事务不计完整descriptor。这里“归还数”按实际credit编码展开为条数，不是返回总线有效周期数。

最终实际故障均保留可编译的修改快照，compile0/run1：

| label | 实际变更 | 检出 |
|---|---|---|
| candidate_tag_high | RTL翻转保存Request的Tag最高位输出 | mismatch22，cycle28，完整身份不符 |
| candidate_data_lane | RTL翻转Write的最低Data位 | mismatch23，cycle13597，完整Data/BE/poison对照失败 |
| candidate_reset_leak | TB中真实DUT reset接线仅在完整holding阶段被屏蔽；RX/bank/connection仍reset | mismatch20，cycle31557，旧descriptor出现在新epoch |
| candidate_retire_bypass | 实际ordered receive ready旁路加入最终request_ready | mismatch1，cycle31354，额外退休破坏保存所有权并触发桥的非法头诊断；不虚称由信用journal率先检出 |

历史 `final_reset_leak` 采用直接删除完成位reset，初始X即被检出，不能冒称在途reset覆盖；最终接线故障先完成合法初始化和流量，直到持有完整事务时才屏蔽reset。历史green_first严格lint有两个未使用几何切片告警，已改为明确低位几何与舍弃余数，后续strict检查无waiver通过。

## 静态技能门禁与交付

`check_skill.py --label static_fixed --netlist evidence/release_matrix/p1/rtl.json` 检查候选最终RTL：0错误、9项模板/标题建议warning，98/98代码行具备解释性注释；此前静态工具对条件赋值产生REL_WIDTH报错，改为明确if/else后通过。完整skill installation门禁实际exit1，原因是工具安装缺少 `agents-md-generator/scripts/manage_docs.py`，发生在其工作目录检查；记录为安装门禁HOLD，不与实际EDA结果混写。没有安装/修补外部skill。

执行命令：

```sh
python3 verification/upli_channels/run_endpoint_request_bridge.py \
  --label NEW --kd28-root /path/to/authorized/OverFlow --static
python3 verification/upli_channels/run_endpoint_request_bridge.py \
  --label NEW_FAULT --kd28-root /path/to/authorized/OverFlow --ports 4 --fault reset_leak
```

输出位于 `build/verification/upli_channels/endpoint_request_bridge/LABEL`，包括同次读取的RTL/TB/reference快照、fixture、命令/返回码、日志和hash；外部依赖只保存身份与显式路径。开发阶段的冻结清单保留在交接证据中；每次本runner的result.json保存当前实际源码及全部产物hash。

安装/集成尚需：接上真实native parity/poison保护封套及唯一role Drop；完善入口Req/首Data同沿与尾部连续性监控；完整Source/Port/VC/raw response贯通现formatter/core，保留共用Tag命名空间；relative/regional BE资格转换；真正Endpoint TL/DL/Switch/backend→native Response因果测试。当前没有backend响应、密码学授权、Tag最终完成或LinkDown恢复，也没有全IP控制路径保护、STA/PPA/形式证明。以上pending不能因本请求holding通过而移除。

## 生产布局重放

编译来源是工程根 `rtl/upli/upli_endpoint_request_bridge.v` 及真实接收/信用/连接依赖，测试文件从 `verification/upli_channels/` 读取。Runner 使用自身位置的 `parents[2]` 定位工程根，不读取开发候选目录。外部SRAM仍显式传 `--kd28-root`，核对工程 `third_party/kd28_dependency.json`。首次TDD红测与技能门禁属于开发证据，生产runner只提供正常/实际fault及可选static。

发布适配后的实际重放结果记录在开发交接freeze中；复制五个发布文件不能代替既有RTL依赖、KD28依赖清单或授权外部根。后续接入仍需上节列出的native保护与Endpoint因果路径。
