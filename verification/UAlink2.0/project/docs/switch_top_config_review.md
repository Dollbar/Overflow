# Switch 顶层动态配置集成自检

本测试实例化真实 `ualink_switch_top`，包含真实 route lookup/table、arbiter、fabric 和 scaffold；不替换叶模块、不修改生产RTL，不宣称标准Switch管理CSR或完整链路协议。被测 top SHA256：`66fc4e51c011422b5641a2e5b1c9884ce4b6c848482409605c3dceeaa15780c1`。

配置为 PORTS=1/3/4/5，各运行 ROUTE_CONFIG_ENABLE=0/1，DATA_WIDTH=37，共8个正常案例、195项明确断言。正常与Python -O运行完全相同。默认模式即使写/提交输入同时有效，全部配置状态输出仍为0，外部静态表正常转发。

动态模式覆盖初始active表disabled、shadow写入不穿透、pending、完整十位ID、所有端口真实数据转发、所有端口同时观察的原子路由置换、重复enabled ID拒绝（PORTS>1）、同拍write/commit双拒绝、reset清除shadow/active和停顿包owner。提交前后同时观察所有出口完整data/valid/last与源ready；首个提交后的组合检查发生在下一采样沿之前，防止分多拍发布被顺序检查掩盖。

提交必须同时满足无输入valid、无在途owner。测试分别检查首拍stall、已接纳非last、valid=0且last=1的气泡、恢复有效的last握手当拍，全部拒绝提交；last之后输入撤去才允许提交。气泡仍保留data/last/ready，不能因为valid=0丢owner。idle合法提交后真实报文改变出口。

独立期望来自测试定义的端口置换与固定37bit字面值，没有调用DUT状态或RTL算法计算期望。输入在下降沿后修改并稳定跨越上升沿，检查在组合settle后进行，避免TB同沿阻塞赋值与DUT采样竞态。所测流遵守包内目标稳定；非法上游中途换目标的恢复不在范围内。未扫描全部十位ID、全部数据bit或任意端口数；数据bit矩阵由独立fabric测试覆盖，不能据此声称本顶层测试穷尽所有输入。

实际top故障隔离副本两项均编译0、运行1且命中CONFIG_MISMATCH：删除quiescence中的packet_owned条件，在气泡case23错误公开quiet=1及commit_accepted=1；将lookup的active_route_ids接回外部静态i_route_ids，在首次全端口检查case350失配。故障未修改生产文件。该集成TB在生产叶模块安装后首轮即通过，没有虚称旧壳编译失败为功能TDD红测；fabric独立实现的真实旧壳红测另有记录。

最终证据：`build/development/switch_top_config/runs/final/result.json`、`final_O/result.json`；可发布脚本在候选 `release/verification/ip_tops/run_switch_top_config.py` 与 `switch_top_config_tb.sv`。以只含生产快照和发布测试的独立目录 `release_replay/` 重放10案例全部满足预期。各结果含准确命令、输入源码/TB/runner副本、编译与运行日志及逐文件SHA；独立重算见候选 `audit.json`。不进行PPA或STA。

```sh
python3 verification/ip_tops/run_switch_top_config.py --label fresh_config --faults
python3 -O verification/ip_tops/run_switch_top_config.py --label fresh_config_O --faults
```

发布布局ROOT为脚本parents[2]，产物为 `build/verification/ip_tops/switch_top_config/<label>/`，新label拒绝覆盖。下一步由主线安装该测试并继续既有Switch停顿/锁包及真实Endpoint-Switch-Endpoint回归；本次未改库存和top。

冻结TB SHA256：`70373df17dc1aec34d25eacc8e33a2c84b0b725cef07437849c07f1a33ca0f41`；发布runner SHA256：`6b01a7fdf211c03ea86b5c426931d4836bee2fc9ce3cde46403d1ab0a22a538a`。
