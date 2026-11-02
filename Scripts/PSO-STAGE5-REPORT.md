# 阶段 5：同包四模式 PSO 对照（2026-11-02）

24次正式运行全部通过，四种模式各3对Cold/Warm，无失败排除或重跑。基于固定时间技能路线，仅Bundled在本路线取得最低的冷启动首次技能帧峰值；Combined也明显改善首攻，但Auto后台队列仍未完成。这不是全游戏覆盖结论，也不据此建议所有生产项目关闭Auto。

## 构建与条件

- 使用阶段4构建 `20261030_175525_8214c7`，未重新编译、Cook或更换包。
- EXE SHA256：`5F96BCA8641B296CA113237431AAEC4711E805D37ABF66785B4B8B40A3E98531`；包内SM6缓存512项，Graphics171/Compute341。分析器核对12对package.json指纹完全相同。
- 本机 i7-12700，64GB，Windows11 22621；日志确认使用 RTX4060Ti、驱动610.47。DX12 SM6、1280x720窗口、VSync0、MaxFPS0，所有运行均开启相同Trace通道。
- 直接进入TestLevel listen。首次技能按路线开始后5/10/16秒执行，重复操作23/28/34秒；测试包括死亡和复活，无额外就绪等待。进程到路线开始时间不等于可交互启动完成时间。
- Baseline Auto0/Bundled0，Auto Auto1/Bundled0，Bundled Auto0/Bundled1，Combined Auto1/Bundled1。Auto相关模式GlobalShaders1/Validation2/ProxyCreationStrategy1；其他为0。所有模式StartupMode1/SaveUserCache0。
- 每次Cold传clearPSODriverCache，随即运行不清理的Warm；每次独立UserDir，不共享UE用户缓存。轮次之间轮换Profile顺序。清理请求未独立证明完全成功；本地引擎不覆盖旧LocalLow/NVIDIA/DXCache。本文“冷”均指该请求条件。

## 冷运行：首次操作后2秒窗口最大Tick帧耗时

单位ms，三次中位数。括号表示最小—最大。

| 模式 | 首次左键 | 首次黑洞 | 首次Dash |
|---|---:|---:|---:|
| Baseline | 106.05（63.22—106.39） | 95.96（8.13—127.87） | 85.60（69.83—90.05） |
| Auto | 127.48（123.46—136.95） | 16.07（15.17—16.92） | 14.63（13.86—14.92） |
| Bundled | 7.91（7.62—8.12） | 10.29（8.97—10.32） | 8.78（8.40—9.35） |
| Combined | 25.80（18.77—33.51） | 15.82（14.45—16.19） | 15.17（14.19—17.44） |

Auto的首攻没有改善，后续黑洞和Dash明显降低；这与阶段2“不等待”的趋势一致。Combined首攻改善，但并未达到本路线仅Bundled的帧峰值。验证的是完整配置组合，不能把所有差异只归因于一个开关；Auto模式还包括Validation和代理策略及更广泛的后台工作。

## 热运行：首次技能最大帧耗时中位数

| 模式 | 左键 | 黑洞 | Dash |
|---|---:|---:|---:|
| Baseline | 10.30 | 9.91 | 9.17 |
| Auto | 8.64 | 9.76 | 9.20 |
| Bundled | 8.90 | 9.37 | 10.03 |
| Combined | 8.82 | 9.28 | 9.08 |

大部分热样本接近，但不能保证完全无卡顿。Bundled热Dash有一轮52.54ms，Baseline热重复黑洞有一轮77.91ms，已保留在原始数据而非剔除。未逐项完成这些异常的根因归属，不将其自动认定为PSO。

## 时间与后台工作

| 模式 | 冷：进程→路线开始，秒 | 热：进程→路线开始，秒 | 冷Bundled批次墙钟，秒 | 热Bundled批次墙钟，秒 |
|---|---:|---:|---:|---:|
| Baseline | 1.69 | 1.60 | — | — |
| Auto | 2.24 | 1.99 | — | — |
| Bundled | 2.75 | 1.70 | 2.87 | 0.32 |
| Combined | 2.27 | 2.18 | 0.16 | 0.18 |

这两个计时区间起止点不同，可能重叠，不应相加。全部Bundled/Combined运行均观察到打开512项缓存、Begin512、Complete512。

Combined的0.16秒只表示随包观察批次，不表示全部PSO工作完成。例如第1轮冷Combined在Complete之后，路线开始仍有4126项pendingAuto；首攻时3354项。冷Auto对应为4094和3415项。NumPrecompilesRemaining还可能混入Auto，不能把日志中pendingBundled值直接解释为随包独立队列。

冷重复技能峰值中位数：Baseline约7.89—8.13ms，Bundled约8.49—9.24ms，Auto约14.40—14.49ms，Combined约15.38—16.74ms。后台队列仍在运行是可观察事实；CPU/驱动争用是合理解释，但这里没有把代理、Validation和其他世界状态开销独立拆开验证。

冷运行慢创建计数中位数（Graphics/Compute）：Baseline92/214、Auto37/178、Bundled0/1、Combined13/19。这是进程级计数且不包含全部Auto作业，不是卡顿帧数，也不是首次技能独占统计。

## Insights 交叉检查

每种模式选择首次左键帧耗时最接近中位数的冷样本：Baseline第2对、Auto第2对、Bundled第3对、Combined第3对。使用定制Insights离线导出0—15秒CPU Scope，原始Trace保留全部时间范围。

- Baseline在首攻近似窗口内出现约102.71ms的RHICreateGraphicsPipelineState，与首次操作窗口慢帧并存。
- Bundled相同近似窗口内观察到的Graphics创建事件最大约0.0087ms；大量创建已前移，目标批次完成有日志旁证。
- Auto和Combined在首攻近似窗口仍有PSOPrecompilePool线程执行长Compute创建事件，分别观察到约3359.90ms和662.72ms的Scope；这些后台区间不是游戏帧耗时，也不能直接当作纯编译CPU时间。与pendingAuto日志一起支持“后台工作未结束”。
- 近似窗口通过Trace内RoguePSOValidation首次Tick时间+5秒定位，非精确Bookmark对齐。统计帧窗口以游戏日志和CSV为准；以上只是CPU路径交叉证据，不能据此逐个认定阻塞依赖。
- 导出的Scope统计含嵌套和并行事件，不将SumMs相加作为墙钟时间；PSOPrecache: Unknown名字本身不证明缓存Miss。

## 结论与边界

1. 阶段3收集的缓存确实覆盖了本固定路线的重要首次使用组合，阶段4入包后在同包运行中取得收益。
2. Auto开关本身不保证首次技能前完成；若采用Combined，仍需考虑预编译预算、资源加载范围和必要就绪门控，不能把随包Complete当成全局Ready。
3. 仅Bundled本轮更快，不代表覆盖未来玩法。仍有按需创建，未跑场景/材质/画质组合可能缺失，不能用512项推断全量覆盖。
4. 当前仅完成固定时间释放对照。阶段2的AutoReady使用历史测试包，不合并进本次严格同包统计；本轮没有为Bundled修改就绪门控或重新出包。
5. 驱动冷状态未完全证明、AI/可见性非严格确定、每模式仅3次且顺序轮换不构成完全平衡设计，所有结果限于本机和本路线。

后续Loki保留完整/补缺/隔离采集、场景/分包分组、CDN分发、分阶段预编译及就绪门控等配置维度。阶段6整理可迁移工具与验收约定，不直接复制AR2缓存产物。

## 证据与复现

批次目录：`F:/Git_Repository/summeryy001/ActionRoguelike2/Saved/PSOComparison/20261102_172037_5011e5`。

summary.json包含24轮记录和48组技能统计；skill-runs.csv为逐次值，skill-summary.csv为中位数与极值，run-summary.csv为时间/计数；pairs.json记录12个有效对，0个排除尝试。hardware.json记录环境。trace-summary.json及各代表运行的comparison-events.csv、insights-comparison.log、comparison-trace-analysis.json提供Insights证据。

操作与重跑见PSO-COMPARISON-GUIDE.md；正式运行约17:20—17:49（Asia/Shanghai）。全部包指纹一致，未改项目运行配置默认值，AR2仅本地提交。
