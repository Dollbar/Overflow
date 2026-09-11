# Endpoint native RX 生产集成记录

日期：2026-09-11。`upli_endpoint_native_rx_path` 已从隔离候选安装到 `rtl/upli/`，RTL字节与冻结候选一致，SHA-256为 `69231f1e4da9acfdb7d35e0c7856821e7e000232869b2f88a03369568eb3c976`。生产验证入口、测试台和接口清单位于 `verification/ip_tops/`，runner使用自身文件位置直接解析工程根，因此可随工程整体重定位。

生产路径实际展开四个 `upli_native_rx_channel`、一个 `upli_receive_tdm_monitor` 和一个 `upli_endpoint_request_bridge`，并使用已登记的KD28功能SRAM依赖。Req/OrigData由桥形成完整请求holding；RdRsp/WrRsp保留完整可信head和原账户退休边界，等待独立响应collector。模块没有新增连接状态、Tag表或信用所有者。

普通及 `python3 -O` 两轮各覆盖1/2/4端口：合计216笔descriptor、1,341次head transfer和1,341次原账户信用归还。每轮1/2/4端口分别阻断37/57/60个Drop期间对端beat；进入Completer Drop会取消旧holding，可信旧信用仍排空，共同reset后同Tag可进入新轮次。g2001、严格lint和Yosys层级检查通过。请求字段断接、正确parity下返还pool错接、Rd TDM端口错接、Drop遗漏holding取消四项故障均编译成功并被运行检查拒绝。

与 `upli_rx_role_fault_controller` 连接时必须显式适配通道位序。native path公开顺序低至高为Req/OrigData/RdRsp/WrRsp，fault controller输入低至高为Req/RdRsp/WrRsp/OrigData；四位诊断应连接为 `{path_error[1], path_error[3], path_error[2], path_error[0]}`。返回信用错误仍按反向角色归属独立连接，不能先和正向Beat错误合并。

复跑命令：

```sh
python3 verification/ip_tops/run_endpoint_native_rx_path.py --label NEW --kd28-root /absolute/path/to/OverFlow --static
python3 verification/ip_tops/run_endpoint_native_rx_path.py --label NEW_TAG --kd28-root /absolute/path/to/OverFlow --ports 1 --fault tag
python3 verification/ip_tops/run_endpoint_native_rx_path.py --label NEW_POOL --kd28-root /absolute/path/to/OverFlow --ports 1 --fault credit_pool
python3 verification/ip_tops/run_endpoint_native_rx_path.py --label NEW_TDM --kd28-root /absolute/path/to/OverFlow --ports 4 --fault tdm
python3 verification/ip_tops/run_endpoint_native_rx_path.py --label NEW_DROP --kd28-root /absolute/path/to/OverFlow --ports 4 --fault drop_reset
```

输出写入 `build/verification/ip_tops/endpoint_native_rx_path/LABEL/`，包含源码快照、命令、日志、层级和SHA清单。下一步把RdRsp/WrRsp可信head接入唯一响应collector，再把接收前端、角色故障控制器和发送侧接入Endpoint聚合顶层。当前结果不覆盖backend因果执行、Isolation、dummy completion、恢复epoch、工艺STA或真实宏签核。
