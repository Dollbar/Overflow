# 按容量分组完整Control字段的阶段审查

新增 `tl_control_partition`，把一个源Control中的独立事务字段分成实际容量可容纳的若干输出Control，再接入已有实际Tx SRAM、packer、信用端口、双端数字延迟链路和Rx SRAM/FC发布器。四位游标只在下游头部FIFO实际接纳时推进；最后一个分组入队才确认整个源字段组。

## 规范边界与数据保真

Common2.0 §5.1.1规定字段、Data/BE及AuthTags的顺序，§5.8规定CMD/Data信用继承，§5.9规定自然对齐和字段格式。模块使用真实解码器提供的完整边界，选择能放入初始化总物理容量的最长非空前缀，保留字段原扇区位置，已完成和未选中的扇区用零NOP覆盖。它不改写任何字段位，原数据序列不变。Auth模式最多四个输出标签；输入可提供八个64位标签，按已完成字段数移位，未用输出槽为零。

原始Control只能包含同类Request或Response字段及零NOP填充。非零FC、混类、未决tenure或非法格式由独立诊断拒绝，源不被部分确认。FC仍走独立真实发布器。初始化后的容量/Auth/shared必须在复位时期保持稳定，源Control及其标签必须保持到`o_source_taken`；因此等待FIFO时分组不会随当前信用余额改变。实际发送时仍由原端口复查余额、catch预算和数据可用性，本模块不提前扣减或复制账本。

此处重新分组的是多个**独立字段**。单个多Beat字段本身若超过总容量，仍报告shortfall并保持源，不跳过该字段。§2.7.8允许读响应源端选择Single-Beat形式，但不能因此推导出任意改写正在转发的Multi-Beat响应，更不能推导任意Write/Atomic拆分。完整UPLI转换和单笔超容量处理仍开放。

## 实测范围

单位RTL共4,856个时序向量（WIDTH8/16各2,428），覆盖两类、Auth/shared、容量0/1/2/4/8、各种字段尺寸及边界、错误源、单笔超容量、组内复位和FIFO停顿。5个模型用例由缺失实现的实际失败开始。

双端每种缓存配置为WIDTH8/16 × Auth0/1 × Shared0/1 × 数字延迟1/3，共16配置。所有20个逻辑CMD/Data账户初始容量均为1；共享模式下两个Data Pool合并成物理slot10容量2，slot15为0。普通缓存为头部深度2、每Data bank深度3；另一组使用头部和每bank深度1。

每种配置的两端两类各提供12个源字段组，包含同VC的多字段组、不同VC可共同发送的组、未压缩请求/响应、压缩请求/单Beat读响应、BE、Data与非零AuthTags。每种缓存配置总共完成768个源组、2,624个线上Control分组、3,456个事务字段，其中576个源组需要多个分组。两种配置合计1,536个源组、6,912个字段全部按顺序完成；每种接纳及消费Data/BE半Flit为7,872个。

独立审计不调用分组选择模型来判断字段保真：它从源组和实际输出分别解析字段，将位值、扇区起点、顺序、Tag、Offset、Last等逐一核对，并检查源确认仅发生于该组全部原字段入队之后。另从实际线上字段重建Data/BE所有权、接收600位SRAM退休字和信用返回；队列与分组观察关联，确认没有越过已接纳输入提前消费，并核对精确容量、源/输出停顿保持和最终信用守恒。

最终双端夹具还检查Single-Beat读回复的完成：同Tag的四Beat回复使用Offset0至3，最后Beat置Last；不同VC的独立回复各使用Offset0/Last1。每个配置每端36个完整读回复，分别核对Tag、目的地、VC保持、Offset不重复和Last后的禁止额外Beat。该检查没有实例化完整UPLI收发接口或匹配最初Read Request，不声称完整应用互操作。

8种单位故障各两个宽度，共16次检出：游标不推进、源过早确认、标签偏移丢失、字段位破坏、中间切断字段、Auth超过四槽、忽略容量、允许非零FC。实际双端另有56次检出：游标不推进、源过早确认、忽略容量各16配置，标签偏移丢失8个Auth配置。负例采用同RTL早期已通过的字段/Data夹具；最终补充的完整读回复审计有独立新运行记录。全部真实编译和运行，没有以编译失败或改写期望值代替故障检出。

严格Verilator lint两宽度通过。Yosys通用综合分别107,455/108,075 cells、4个同步复位FF位，全部由输入i_clk驱动。该统计只包含字段分组模块及解码/准入依赖，不包括真实Tx/Rx存储或完整端口，未做工艺映射/STA，不代表目标频率达标。四位状态和较大的组合选择逻辑仍需后续工艺PPA评估。

Artifact技能门零错误、14项风格建议：保留原生接口、紧凑分组和生成索引写法；所有RTL非空代码行有同行中文语义注释。全局技能自检实际失败于外部缺失`agents-md-generator/scripts/manage_docs.py`。首次双端TB使用嵌套内联genvar导致Icarus输出连接报错，改为显式模块级genvar后通过；所有失败和通过记录保留。

干净导出中的`make test rtl-smoke`实际结束，退出码0；已核对当前全部RTL及Makefile与导出副本字节一致。最终读回复完成语义夹具和审计器在导出后单独实际运行，普通Python与`-O`审计均通过；不把文档/验证脚本后续编辑宣称为导出时的同一快照。

## 复跑与后续

```sh
python3 verification/tl_control_partition/test_model.py
python3 verification/tl_control_partition/run_rtl.py
python3 verification/tl_control_partition/run_peers.py --kd28-root /authorized/Overflow --label peers_semantics
python3 verification/tl_control_partition/run_peers.py --kd28-root /authorized/Overflow --bank-depth 1 --header-depth 1 --label minimum_semantics
python3 verification/tl_control_partition/run_checks.py --kd28-root /authorized/Overflow
python3 verification/tl_control_partition/run_skill_gate.py --skill-root /path/to/verilog-generator
python3 verification/tl_control_partition/check_evidence.py
make test rtl-smoke
```

输出在`build/verification/tl_control_partition/`，已有目录拒绝覆盖，独立审计普通Python与`-O`均需通过。后续仍包括完整容量感知UPLI处理、每VC调度、单笔超容量完成、Poison及其余TL消息、完整在线资源/参考归纳、工艺STA和完整Endpoint/Switch其余模块；完整Goal未完成。
