# Endpoint 单 Beat Read 字段独立审核

审核对象为 `docs/endpoint_transaction_plan.md` Task 1 的字段映射、拟新增的
`endpoint_read_encode` / `endpoint_response_encode` 组合接口，以及现有
`rtl/tl/tl_control_decode.v`、`rtl/tl/tl_control_tenure.v` 和
`model/tl/tl_tenure.py`。本次只读审查，仅新增本文；未修改 RTL、测试或契约，
没有运行新的编码器仿真，也没有重跑 SRAM 证明。

结论：**现有计划的 Table 5-29 / 5-30 位段与已读取的 Common 2.0 正文一致，
未发现阻止这两个编码器实现的规范矛盾。** 低位单字段加全零 NOP 可以被现有
结构解码器及 tenure 逻辑正确解释。必须另外检查的事务语义与后续接收边界如下。

## 依据与范围

直接读取 `specs/private/common.txt`，SHA-256 为
`15cd742c536e1e701a958db8a04f54666b072b8d95a72a834b0aa7d2c58e3383`，
与计划记录一致。本文仅保存实现映射与审核结论，不复制私有表格正文。

| 规范位置 | 本次核对内容 |
|---|---|
| §5.9.1 / Table 5-29，p137 | 128-bit 未压缩请求的全部字段与 55-bit 线上地址 |
| §5.9.2 / Table 5-30，pp138–139 | 64-bit 未压缩响应、RD/WR、LEN/OFFSET/LAST、响应 ID 与 RSPTYPE |
| §5.8、§5.9 / Table 5-27，pp135–136 | 全零 32-bit FC 字段可作 NOP；FTYPE 对应的字段尺寸 |
| §2.7.4 / Table 2-2、§2.7.4.4–7，pp49–57 | Tag、Read 命令、地址对齐、长度、属性与 NUMBEATS |
| §2.7.5 / Tables 2-15、2-16，pp62–65 | 响应 Tag/ID、VC、unicast 类型、状态和错误数据传输 |
| §2.7.8、§2.8，pp71–75 | 单 Beat 与多 Beat 语义、响应必须可被接收、自然字节位置 |
| §5.1.1，pp105–108 | Control/Data 分类、半 Flit 顺序、字段与其 Data 的对应关系 |

上述普通未压缩、Auth 关闭子集不依赖尚未关闭的压缩响应格式问题。
64-byte 对齐、LEN15、ATTRff、VC0、POOL0、ASI0、MetaData0、仅状态0/3属于
本次实现子集；不能据此将其他规范允许的 Read 或状态称为非法协议。

## 编码器字段与输入检查

请求的 FTYPE/CMD、VCHAN/ASI、TAG/POOL、ATTR/LEN/METADATA、地址、两侧 ID、
CLOAD/CWAY/NUMBEATS 均与计划的位段一致；这些位段恰好覆盖128位，无空洞或重叠。
响应的 FTYPE、VC、TAG、POOL、LEN、OFFSET、STATUS、RD/WR、LAST、两侧 ID、
RSPTYPE 和 SPARE 同样恰好覆盖64位。

- **请求地址必须保留完整57位。** 线上 `[79:25]` 对应输入 `[56:2]`，接收时补
  `2'b00`。输入 `[5:0]` 必须为零才满足本次64-byte profile；不能先截低位再
  把一个不对齐输入伪装为合法地址。`addr[56]=1` 本身不是编码错误。4KiB测试内存
  越界检查属于执行器，不能写入编码器，否则失去高位地址真实到达并返回状态3的路径。
- **完整 Tag11 与 ID10 都必须直通。** 对 Tag 的活跃性、重复分配和未发送状态
  检查属于有状态 Originator。编码器不得用4条本地槽位替代完整 Tag，不得截为低2位。
  ID 也不得因当前双端测试地址很小而缩窄。
- **请求常量须保持独立、精确。** 普通 Read CMD=`0x03`，REQ LEN=`15`表示16个
  DWORD即64 bytes，ATTR=`0xff`，NUMBEATS=`0`；后者描述 OrigData，不是请求将
  收到几个响应 Beat。Read 没有 OrigData 或 ByteEnable 半 Flit。
- **响应只表示一个完整 Read Beat。** RD/WR=`1`，LEN=`0`、OFFSET=`0`、LAST=`1`、
  RSPTYPE=`00`；不能将请求的LEN15直接复制进响应LEN，不能把LAST放成发送Header
  已完成的指示。STATUS0和3各有确定编码，其他状态输入应触发本地profile诊断，
  不应被截断、默认为0或视作同一种成功。
- **响应 ID 由调用者显式给出。** 上层从保存的请求产生 `rsp_src=req_dst`、
  `rsp_dst=req_src`，编码器将输入按响应位段原样放置。编码器内不得隐藏再次交换。
  响应DST用于回程路由；响应SRC只是调试信息，不能用于功能Tag匹配，SRC不可靠时
  原生UPLI另有置零规则。响应VC须继承请求VC；本次两者固定VC0满足该关系。
- **POOL 是本次TL发送实际使用的信用种类。** 不应简单复制UPLI池信息，也不能
  将请求消耗的POOL当作响应必须消耗的POOL。本次两个编码器均固定TL POOL0，
  后续仍由真实发送端检查可用VC信用。
- **CLOAD0与SPARE0是确定发送策略。** CLOAD0不加载地址缓存，CWAY发送0。
  SPARE未分配，发送0合理；不能由此擅自规定所有非零接收值必为线上错误。
  初始编码器将未使用的完整sector清零，不能把部分旧payload残留当NOP。

如果接口暴露长度、属性、VC、POOL、ASI或MetaData，上述本地profile比较必须
覆盖对应完整输入位宽；若它们不作为端口，则应直接生成明确常量。
端口选择若由上层暴露，port0限制由上层负责，不能伪装成线上额外字段。

组合模块不包含事务存储：建议明确 `output_valid = input_valid && profile_ok`，
`error = input_valid && !profile_ok`，idle/拒绝时输出全零Control。这是本地接口
选择，不是规范定义的恢复动作。输入invalid时不应因无关payload发起发送或信用消耗；
下游停顿期间必须由调用者保持输入与valid，直至发送器实际捕获。不能把组合valid
解释为已经捕获Header、保留Tag或发送完两半Data。

## 与现有解码、tenure 的精确关系

下面是直接按现有 RTL 静态推导的预期值，**不是本次新增仿真成绩**。

| 输入256-bit Control | decode valid | req/rsp数 | field_starts | request_starts / response_starts | tenure status / fields / data_counts / BE |
|---|---:|---|---|---|---|
| 低128位单个本次Read，其余零 | 1 | 1 / 0 | `8'hf1` | `01 / 00` | `0 / 1 / 32'h0 / 8'h0` |
| 低64位单个本次Response，其余零 | 1 | 0 / 1 | `8'hfd` | `00 / 01` | `0 / 1 / 32'h2 / 8'h0` |
| 全零NOP | 1 | 0 / 0 | `8'hff` | `00 / 00` | `0 / 0 / 32'h0 / 8'h0` |

`o_field_starts` **包括NOP/FC字段起点**，不能把所有置位都解释成事务。
事务提取必须使用 `o_request_starts` / `o_response_starts`，或在起点进一步
检查FTYPE。低位请求FTYPE位于sector3的最高4位，响应FTYPE位于sector1的最高4位；
输出起点仍是sector0。不能假定FTYPE位于字段最低sector的最高4位。

全零Control本身具有合法结构，所以编码器拒绝输入时即使输出清零，
`tl_control_decode.o_valid` 仍然为1。发送侧必须使用编码器自身valid门控，
不能用结构valid替代事务valid。

`tl_control_decode` 不解释Tag、地址、状态或命令payload。
`tl_control_tenure` 对CMD3产生零Data；对FTYPE2且RD/WR1，根据LEN产生
`2*(LEN+1)`个Data半Flit，和STATUS无关。因此状态3也必须提供完整两半Data。
这两个模块都不能替代Endpoint语义检查，特别是：

- 现有 Read tenure 分支不会拒绝非零NUMBEATS，也不检查LEN、ATTR、地址对齐；
- 响应结构合法或tenure为DD并不保证OFFSET0、LAST1、STATUS支持、RSPTYPE00；
- RD/WR误写为0会变成结构合法、零Data tenure的Write Response，而不是自动报错；
- 对错误/非法输入，只观察decoder/tenure成功不足以验收编码器门控。

Task1独立向量至少应分别覆盖 Tag最高位、ID最高位、addr56、SRC/DST非对称值、
状态0/3、RD/WR与LAST、每个受限输入的单独拒绝，以及idle时输出/valid。
用全零/全一和Tag=0/1/1023/2047可以覆盖边界，但这些少量Tag值不能单独检出所有
中间位交换；全11位walking-one及10位ID逐位变化更有针对性。地址测试应覆盖每个
保留地址位 `[56:6]`，并分别将低6位置1检查本地拒绝。至少一个真实字段位修改须
被独立原始常量/位段oracle检出；双方共用编码公式往返不构成独立验证。

## 后续接收组装的主要陷阱

1. **不能推广固定低位位置。** 单字段低位是首发策略。未压缩请求合法起点为
   sector0或4，响应为0/2/4/6；解析应处理解码器给出的实际起点，并忽略字段
   内部payload中看起来像FTYPE的位。多个字段的Data按字段起点从低到高对应。
2. **Data没有自己的Tag/VC/POOL。** 接收上下文必须从先前Control保留顺序、类别、
   tenure及信用归属。每个512-bit响应由低、再高两个256-bit半字组装；不能将
   Data高位像FTYPE的值重新解码为Header，也不能在第一半或Header到达时完成Tag。
3. **先保存完整接收记录，再退休一次。** 600-bit字中的类别和释放元数据与payload
   一起保留。lower/upper处理进度应分开；混合字中的一个新Request不能使另一半旧
   Response Data丢失、重复消费或产生第二次信用归还。
4. **错误状态不是Poison。** Table2-15和§2.7.5.1要求状态错误也传完整请求数据
   Beat及LAST；制造数据可用确定模式，规范推荐全1但不强制，测试填0不构成矛盾。
   DECODE_ERROR本身不置DataError。Poison/数据校验错误需单独保留，状态错误不能
   静默减少tenure或更新成功数据缓存。
5. **完整Tag与端口关联，并验证本地DST。** `(port,tag)`需匹配活跃且已实际发送
   的请求；功能关联不能依赖调试SRC。检查本profile长度、OFFSET/LAST和重复完成。
   不能因应用尚未取走结果就提前复用Tag，也不能把同低位Tag当同一请求。
6. **响应接收容量必须预留。** 已发请求的Response接收不能依赖Completer先处理
   另一个请求。单个holding word若被满请求队列阻塞，不能连带挡住已有Response；
   必须在集成层验证混合记录和两端同时4个在途请求的有限资源行为。
7. **未来多Beat不能只改LEN。** Single-Beat模式下多条LEN0响应仍可能属于同一
   事务，OFFSET可乱序且LAST可位于非最大OFFSET；Multi-Beat模式的一个TL Header
   带来连续多个Data半Flit。完成条件必须结合请求预期覆盖与LAST，而非“LEN0即
   结束”。所有Beat的STATUS一致性、每Beat DataError和UPLI重新生成需要另行实现。

本审核支持继续Task1字段实现与独立测试；并不宣称已有完整事务闭环、完整接收能力、
原生UPLI时序或全部规范符合性。
