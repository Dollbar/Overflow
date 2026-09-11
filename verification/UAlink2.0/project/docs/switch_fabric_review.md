# switch_fabric 候选实现交接

主线已安装此处冻结的RTL并接入真实顶层；集成结果见[Switch总装审查](switch_integration_review.md)。以下候选阶段与发布副本记录按各自快照保留。

候选仅位于 `build/development/switch_fabric/`，未修改 production RTL、库存、scaffold 或 top；未提交。范围是研发 packet datapath 的组合交叉连接，不包含仲裁状态、路由查找、逐端口TL/DL终止、标准Switch解析、安全或管理。

## 接口与行为

参数 `PORTS=4`、`DATA_WIDTH=544`，均要求正整数；没有时钟或内部寄存器。

| 信号 | 宽度与含义 |
|---|---|
| i_rstn | 1；为0时所有输出，包括o_error，组合置零 |
| i_valid / i_last | PORTS；各输入源的valid与包末标记 |
| i_data | PORTS*DATA_WIDTH；source s使用[s*DATA_WIDTH +: DATA_WIDTH] |
| i_route_match | PORTS*PORTS；**source-major**，位s*PORTS+e表示源s匹配目的e |
| i_select | PORTS*PORTS；**egress-major**，位e*PORTS+s表示目的e选择源s |
| i_ready | PORTS；各目的下游ready |
| o_ready | PORTS；返回各源的ready |
| o_valid / o_last / o_data | 分别PORTS / PORTS / PORTS*DATA_WIDTH，按目的排列 |
| o_error | 1；非法选择矩阵的组合诊断 |

合法选择要求每个出口最多选择一个源，且每个源最多被一个出口选择。全零行合法，表示无选择。选择与对应route bit同时成立时，输出valid取源valid、完整data与last原样传递、源ready取目的ready。**i_valid=0仍传播data、last和ready**；只把o_valid置零。不能以源valid重新门控所选数据或反压，否则会改变原top已锁定包内气泡行为。无选择或route不匹配时该路径输出保持零；route mismatch本身不产生本模块o_error，路由合法性仍属于lookup。

非法选择按原始i_select统计，不被route不匹配、valid=0或ready=0掩盖。同行多hot会阻断该出口的所有路径；同源被多个出口选择会阻断所有这些出口指向该源的路径。无关合法源/出口继续传输，同时o_error=1。不会通过循环最后一次赋值选择一个任意赢家。route矩阵的唯一目标有效性仍由调用者/lookup负责，fabric不二次执行目标查找；即使测试提供非唯一route矩阵，也只按实际选择建立路径。X/Z不是此二值硬件接口的另一个合法编码，不声明未知值的协议恢复语义。

## 与当前top的关系

读取的 `rtl/switch/ualink_switch_top.v` SHA256 为 `5f9c73a3087c093ff560d7595b69fb0a1e817ec5f0fdb27952b8839242d3ab38`。旧top在selected[e]=s且route_match[s*PORTS+e]时的四项赋值，与本候选合法连接逐项相同；无选择/不匹配/复位均为零。lookup的匹配输出不受valid门控，所以锁定气泡仍有合法route bit。

接入时保留现有top的owner、round-robin、selected计算及状态更新，只将已选索引转换为egress-major onehot并替换四项数据/ready赋值；转换不能附加i_valid条件。旧top支持稳定packet目标前提下的锁定，非法上游在包中改变目标可能让不同出口仍锁同一源，此时新fabric会诊断并failclosed，不能把这段非法选择行为宣称与旧top等价。o_error如何接入top诊断由主线明确处理，不能悄悄丢弃。

本次没有宣称完整旧top形式等价或已接入实际ESE；合法选择的对照是上述实际源码赋值语义和独立组合oracle。主线接入后仍须运行旧停顿、锁定、包内气泡、多包次序以及ESE回归。

## TDD与独立检查

```sh
python3 build/development/switch_fabric/run.py --label fresh_shell_red --shell-red
python3 build/development/switch_fabric/run.py --label fresh_fabric --faults --static
python3 -O build/development/switch_fabric/run.py --label fresh_fabric_O --faults --static
```

产物保存在此目录的 `runs/<label>/`；新label拒绝覆盖。生产旧shell用于红测，runner的非零退出与result.passed=false是预期未实现证据，不把它记作功能通过。`runs/shell_red` 使用真实旧shell编译0、运行1命中FABRIC_UNIMPLEMENTED，随后才生成候选RTL。

独立Python期望把选择矩阵视作边集合，以行/列基数定义冲突并按位重建输出；没有调用RTL生成器或读取DUT内部状态。另有手算三端口异向映射字面值验证两种矩阵布局，避免单靠同一个循环生成刺激和预期。TB只逐行驱动向量并在组合稳定后比较所有输出位，包括invalid源data/last与ready。

13配置：P1/W1,7,544；P2/W1,32,544；P3/W7,544；P4/W1,32,544；P5/W13；P8/W65。覆盖每一输入/输出组合、每个数据bit、valid/last/ready组合、不匹配、选中路径reset、所有P<=4并发全排列与valid/ready组合、P<=3全部选择位图、气泡下冲突、无关路径存活和固定种子的随机图。不是随机PPA或时序测试。

六故障实际修改隔离RTL副本：valid清零data、route矩阵转置、数据最高位翻转、绕过冲突阻断、ready接错源索引、取消reset门控。均要求实际编译0、仿真1且命中FABRIC_MISMATCH，才记为检出。

最终证据为 `runs/final/result.json` 与 `runs/final_O/result.json`。各19个仿真案例通过（13正常配置与6个故障检出），每配置完整日志、向量及RTL/TB副本均保留。P1/W1、P3/W7、P4/W544、P8/W65各执行Verilog-2001、严格Verilator -Wall及Yosys read/hierarchy/proc/opt/memory_map/opt/check -assert/stat，共12项静态检查；不使用警告抑制，不进行工艺STA或面积签核。

## 推进到主线

候选RTL文件为 `switch_fabric.v`；可复跑测试为 `run.py` 和 `fabric_tb.sv`。本地runner ROOT解析按当前开发目录布局定义，移动到正式verification目录时需明确适配其ROOT与输出目录，不应原样移动后假定仍可运行。由主代理审核后再复制到正式路径、晋升库存并刷新聚合层，接入top并执行真实兼容回归。本目录开发产物不是已发布生产功能。

最终正常与-O各56743个正常组合向量，19/19案例、12/12静态检查通过；各140项制品哈希独立重算零差异。

发布副本位于release/，其中verification/ip_tops/run_switch_fabric.py使用ROOT=parents[2]，读取生产rtl/switch/switch_fabric.v，输出build/verification/ip_tops/switch_fabric/<label>；TB与RTL内容与候选完全相同。发布后命令：`python3 verification/ip_tops/run_switch_fabric.py --label fresh --faults --static`。shell-red选项仅适用于历史壳，typed晋升后不应再作为预期红测调用。
