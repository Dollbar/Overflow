# 外部依赖

通过显式 `KD28_ROOT` 只读接入授权的 KD28 SRAM 存储映射及行为模型。文件名、接口和 SHA-256 见 [依赖登记](kd28_dependency.json)。本工程不包含其源文件。登记中的阶段性使用记录属于历史信息；当前使用范围见 [工程状态](../docs/status.md)。

标准单元 Liberty 通过 `LIB_ROOT` 等显式配置传入，不随工程发布。synthetic SRAM 时序视图不等于真实工艺签核模型。没有接入完整 SerDes 或商业 VIP。
