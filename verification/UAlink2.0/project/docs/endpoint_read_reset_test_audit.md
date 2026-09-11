# 完整 Read ESE 与混合事务 reset 测试独立审查

本任务只读测试源码与已有证据，不修改被审查测试/生产RTL，也不重复执行其他代理正在运行的回归。reset与Read ESE两组runner/TB均已完整读取，以下结果已核对作者保留的实际命令、日志和固定源码快照。审查区分测试设计可信度与某一固定RTL快照的实际通过结果。

## Reset：取消控制状态，保留已执行字节

`write_reset_memory` 的256-byte内存和累计执行次数只在初始化时清零；网络reset只清pending、result valid和服务状态。实际Write命令握手保存接收到的Data、区域BE与slot，70周期后才修改字节、累计执行并返回结果。独立Python预期不读取该内存：窗口1/2预期尚未执行而全零，窗口3预期保留已执行稀疏Write。复位沿后完整2048-bit快照检查可发现错误回滚或提前副作用。

三个复位窗口来自真实接口观察：部分Data尚无BE、完整请求已进后端但尚未执行、真实执行后应用完成已连续背压。复位前再次验证窗口条件，避免仅按固定时间宣称到达目标。复位后120周期禁止新请求，超过70周期执行延迟；检查旧执行、结果、完成和命令不得复活，再重新初始化并重用旧Tag。新轮先四次Read查看保留区域，再WriteFull并四次Read核对新字节，身份和执行/完成次数分别统计。

DUT输入相关的cycle/requested计数用NBA更新，reset/start/epoch在负沿驱动；只供scoreboard观察的状态用blocking更新。未发现旧ESE中同沿更新计数反馈ready/请求数据的竞态。后端自己的结果与执行脉冲采用NBA；scoreboard先记录执行再核对对应result，不能靠result valid独自宣称已执行。

两类故障实际将一个Endpoint或后端的复位接到仅上电有效的power reset；都先经过正常初始化并到达要求窗口。只在compile0、run1、目标窗口marker与具体故障marker同时满足时算检出。它们验证统一复位接线与本地后端取消契约，不是生产RTL内部任意故障覆盖。日志 `cancelled_results=2` 指旧应用完成预约取消：窗口1尚无后端命令，窗口3后端result已返回，不能解释为三个窗口均取消两条已经存在的后端result。

`write_reset_first/minimum` 各三个正向窗口，另 `write_reset_endpoint_fault/backend_fault/endpoint_fault_minimum/backend_fault_minimum` 四标签，共1362份artifact重新计算SHA256无缺失或差异，各source hash与编译快照一致。它们对应较早快照；完整Read扩展后的九个生产源已经不同。因此这些旧结果不能直接声称最终完整Read总装的reset兼容通过。既有复位测试仍使用默认Read64，并不覆盖完整Read事务收集到一部分Beat时的reset。

## Read ESE：实际字节、mask与逐Beat完成

runner的Python参考按应用地址/LEN/ATTR计算区域字节mask，再右移到相对首Beat的mask；LEN0通过首DWORD分支优先处理，忽略高ATTR。预期从独立字节内存生成，错误状态输出data/mask零是本地应用策略。刺激与预期共享操作表和应用数据，不因此自动自证；仍需核对SV后端使用实际收到的字段/字节，以及应用完成前实际全部响应Beat的因果。

SV内存只保存实际Write命令的Data/BE并修改自己的字节数组，Read按实际地址/LEN返回全部自然对齐Beat，未用高Beat填D7；它不读取expected fixture。scoreboard先将实际后端result的完整2048-bit raw数据、status与Python预期比较，再核对真实receiver到Tag的每Beat字段和选中字节，最后完整比较应用2048-bit输出、256-bit mask和legacy低512位。因而应用对无效lane清零不会遮蔽后端原始数据的错误；反之，wire未选lane本来允许任意值，不在receiver边界强制零。

每条Read的实际响应Beat数、offset、LAST、status均观察于receiver到Tag的真实握手。首次complete_valid就要求N个响应已经到齐，且最后响应早于当前周期；这项检查不等待应用ready。五状态中非零error同样必须收到全部N个Beat，不能因为预期应用data/mask为零而提前通过。完整ESE中的错误激励使用N4，其他N×状态由模块测试补足。后端状态是明确注入的测试条件，不证明后端自行实现权限或错误检测。

BFM status用独立的memory_issue索引驱动，该索引和请求索引、cycle、丢槽/CRC选择计数都以NBA更新；blocking cursor仅用于scoreboard，不反馈DUT/BFM输入。复核未发现之前ESE的同沿计数反馈竞态。完成保持检查覆盖完整数据与mask。实际Write执行脉冲、结果、Tag完成分别计数；两方向不同字节模式以及Write后Read可检出数据/方向错接。

`mask_ignored` 修改隔离实际Tag表的逐byte mask条件，其原始和变换后hash分别记录；`upper_data_lost` 在实际top后端结果输入处清零高1536位。两者均实际改变被测数据路径，而不是修改expected或预设返回失败。raw后端检查保留未破坏的数据，故第二项须由接收/应用数据比较发现；首项须由完整应用结果发现未选lane未清零。丢槽和CRC状态注入沿用真实DL重放路径，CRC是显式状态而非多项式计算。

matrix覆盖64种LEN的代表起点、64个DWORD起点的代表长度、LEN0全部256 ATTR及若干跨Beat稀疏mask，不是2080种普通合法几何的ESE穷举。发送方统一Single-Beat；此测试不覆盖Multi-Beat Header RX，也不覆盖Single-Beat乱序发送，分别由receiver原始记录及Tag单元测试承担。Switch仍使用显式路由sideband。Read ESE不执行在途reset；混合reset TB的Read为默认64B，因此完整Read收集期间reset依然是单独的集成覆盖缺口。

最终Read ESE证据已冻结：

| 标签 | 实际结果 |
|---|---|
| `read_ese_first` | compile0/run0，28请求/完成，每侧34个Read Beat、2次Write执行，1380周期 |
| `read_ese_matrix_first` | compile0/run0，812请求/完成，每侧619个Read Beat、2次Write执行，21571周期 |
| `read_ese_minimum_first` | bank1+丢槽/CRC恢复，compile0/run0，812请求/完成，每侧619个Read Beat、2次Write执行、4次重放，21658周期 |
| `read_ese_mask_fault_first` | compile0/run1，实际应用完整数据检查检出mask条件遗漏 |
| `read_ese_upper_fault_first` | compile0/run1，实际receiver数据检查检出高Beat清零 |

上述五标签各225份artifact，共1125份重新计算SHA256，零缺失、零差异；全部source hash与实际编译快照相符，当前生产源仅故障案例的刻意Tag副本变换不同。三个正向场景的Read Beat计数检查包含五种状态，错误响应未免除Beat数量与LAST要求。本审查未发现仍需阻止该功能增量交付的测试缺陷；前述覆盖限制与reset旧快照边界须继续保留。

## 已审查源码身份

| 文件 | SHA256 |
|---|---|
| `verification/endpoint_transaction/run_write_reset.py` | `6a722dfd40f88336ac65500156233ce6ba372485af8923f743be54caf79a5952` |
| `verification/endpoint_transaction/write_reset_tb.sv` | `af4b29812e3f97d9abae463198dc6044c3ecbf6fc38b033ae756cccdcd45e94c` |
| `verification/endpoint_transaction/run_read_endpoint_switch.py` | `aca85e57097b7329acbde25f5af90a542eb78b6aa777fa32d13801fde7a9cd74` |
| `verification/endpoint_transaction/read_endpoint_switch_tb.sv` | `583a8ebce3c5ac31b7ac634d7a1be56dd81aa70c21cb2c178775141cc9a5782b` |

本结论不扩写为独立LinkDown、持久性、原生UPLI、安全、PHY或物理签核；当前完整Read在途reset仍须单独验证。
