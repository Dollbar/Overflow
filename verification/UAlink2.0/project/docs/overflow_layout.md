# Overflow 分区导出布局

`scripts/export_overflow.py` 从指定的不可变 Git 提交读取 tracked blob，把设计、验证与模拟器放入现有 Overflow 根仓库的三个分区。它不读取工作树改动或 untracked 文件，不执行 commit/push，也不修改根仓库其它项目或 REUSE 标注。

| 原工程路径 | Overflow 根目录下的位置 |
|---|---|
| `rtl/**` | `rtl/UAlink2.0/**` |
| `verification/**` | `verification/UAlink2.0/**` |
| `model/**` | `simulator/UAlink2.0/model/**` |
| `simulator/**` | `simulator/UAlink2.0/**` |
| README、Makefile、AGENTS、.gitignore、scripts/config/docs/specs/variants/third_party | `verification/UAlink2.0/project/**` |

`rtl/README.md` 保留在设计分区作为入口；RTL 本身没有额外嵌套一层 `rtl/`。验证 testbench/package/VIP 不会混入设计目录。私有目录、局部配置、生成物和 third_party 实际依赖 payload 不导出；third_party 的使用说明与 JSON 等配置元数据可以导出。源 Git symlink 和 gitlink 不会被展开，当前入口对这些条目明确拒绝。

## 兼容工程根

`verification/UAlink2.0/project` 提供四条受管相对链接：

```text
rtl          -> ../../../rtl/UAlink2.0
verification -> ..
model        -> ../../../simulator/UAlink2.0/model
simulator    -> ../../../simulator/UAlink2.0
```

Python 根定位使用两个受管标记：验证分区的 `.ualink-root` 内容为 `project`；模拟器分区标记为 `../../verification/UAlink2.0/project`。导出器解析 Python AST，只替换从该源文件恰好上溯到原工程根的 `Path(__file__)` 表达式，支持 `resolve().parents[N]`、等价 `.parent` 链及 pathlib 导入别名。替换表达式选择最近祖先标记，找不到标记时保留原表达式作为 fallback；HERE、同级资源路径、字符串和注释不盲改。

另对明确的 `Path(__file__).resolve().relative_to(ROOT)` 自身源身份表达式进行定点适配，要求 ROOT 是已识别的工程根绑定，输出原 tracked 相对路径。当前快照的这类表达式在 `verification/endpoint_transaction/run_originator.py`；这是源身份修复，不是全局改写任意 `relative_to`。

只对 `verification/README.md` 和 `rtl/README.md` 改写其 `../docs/` 链接；验证入口增加进入 project 后运行 Makefile 的说明。其它历史 Markdown 保持原内容。三分区均生成 `.gitignore`，屏蔽缓存、仿真产物和运行目录；将来若源含相同映射位置的 `.gitignore`，导出因映射冲突拒绝，必须明确审核合并策略。

## 执行与保护

目标根目录须已存在且不是 symlink，提交参数须为十六进制 Git object ID，不接受 HEAD 或分支名：

```sh
python3 scripts/export_overflow.py --source /path/to/UALink \
  --commit FULL_SOURCE_COMMIT --dest /path/to/Overflow --check
python3 scripts/export_overflow.py --source /path/to/UALink \
  --commit FULL_SOURCE_COMMIT --dest /path/to/Overflow
cd /path/to/Overflow/verification/UAlink2.0/project
make test
```

`--check` 只读验证并输出更新/删除计划，不创建目录；计划有待写入项时仍返回0，以 `up_to_date` 区分是否已经一致。首次导出要求三个目标子树为空或不存在。后续增量依赖 `verification/UAlink2.0/.ualink-export.json`：其中记录提交、原源路径/blob/hash、目标 hash/权限、确定性变换与四条链接边界。

写入前先核查全部冲突。已有受管文件若被本地改动、已有受管链接被改向、目标父路径是 symlink、同一路径存在非清单 owner 文件，都会拒绝；即使非 owner 文件内容恰好相同也不接管。删除仅限旧清单中未改动且本次不再需要的文件，其它文件保留。单文件原子替换、清单最后写入；进程内异常会尝试回滚已处理项，但不承诺断电或强制终止下整个多目录事务原子性。

导出和哈希仅遍历 Git blob 与清单中的具体路径，不递归跟随 project 兼容链接；`verification -> ..` 的目录环不会被用于导出扫描。该清单是本仓库工作流的所有权记录，不是对恶意伪造清单的密码学授权机制。发布前应审核目标 Git diff，再运行实际入口；外部授权 SRAM/PDK 仍由调用者显式提供。

## 本轮验证

```sh
python3 verification/tools/test_overflow_export.py -v
python3 -O verification/tools/test_overflow_export.py -v
```

15项临时 Git 仓库测试在普通及 `/tmp` 下的 `-O` 模式均通过。覆盖不可变提交/脏工作树/untracked 隔离、路径与哈希、README/ignore、四条链接、原布局与新布局 Python 导入及 fallback、自身源身份、只读/idempotent、增量删除边界、owner 修改保护、非 owner 同内容碰撞、目标 symlink 逃逸、源 symlink、清单路径逃逸和目标映射冲突。测试输出 unittest 结果，临时仓库自动清理。

已对当时的 `88a330e` 源提交做临时空目标只读规划，856个源文件、0排除，目标未发生写入。这不替代后续最终提交的实际 Overflow 导出与运行验证；最终生产发布由 root 选择包含本工具及最新 VIP 的不可变提交后执行。

## 后续上游合并

Write增量发布准备时，远端main已推进到`186769aea7d14adfa5add3e823a6c7e571702508`：清空RTL命名空间README并增加`KD-UAlink2_0.png`。本地发布clone先fast-forward，保留图片为非导出器owner内容，并把远端README原字节合并回源`rtl/README.md`。核实远端Git blob后，仅将旧manifest对应README条目身份同步为该已审查内容，再运行正常导出保护；没有覆盖上游内容或放宽导出器规则。旧manifest和对账记录保存在`build/publication/write_remote_reconciliation/`，最终manifest仍由不可变源提交重建。
