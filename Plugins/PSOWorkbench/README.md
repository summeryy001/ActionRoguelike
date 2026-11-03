# PSO 工作台 0.1

入口：AR2 编辑器“工具 → 渲染工作流 → PSO 工作台”。Windows DX12/SM6 Development 首版，Android仅预留，不会执行不完整流程。

## 使用流程

1. 设置方案名称、缓存组、运行地图与Cook地图。新工程默认读取 GameDefaultMap 并使用手动采集；AR2 的 TestLevel 与自动路线仅在工程方案 WorkbenchUI.json 中定义，需从下拉框加载。Game 目标默认工程名，可在高级设置覆盖。
2. 保存方案。逻辑方案保存在Config/PSOWorkbench/Profiles；引擎和Insights本机路径保存在编辑器用户配置，不随方案提交。
3. 点击检查配置。需要时应用构建配置：备份DefaultEngine.ini/DefaultGame.ini，仅启用Stable Keys、共享Shader代码和Native Libraries。未更改项目默认PSO运行模式。
4. 构建采集包：自动构建Game、Cook、归档EXE与匹配SHK。编辑器可以保持打开，不链接Editor DLL。构建前会提示保存脏资源。
5. 运行采集：选择完整/补缺/隔离策略。手动模式正常游玩覆盖，结束时点击“结束当前游戏并保存记录”；自动模式使用项目适配路线及完成标记。每次独立用户目录、日志和Trace。
6. 转换：自动筛选当前采集包的有效会话，核对记录与SHK Hash，调用引擎expand。安装：按方案/缓存组命名SPC，备份同名旧输入，保留项目其他输入。
7. 构建Bundled包：Cook合并项目匹配输入，保存运行时缓存与数量，核对PAK清单。
8. 运行验收：选择关闭/自动/Bundled/Combined模式，可选Fast或后台目标预算。驱动清理默认关闭，勾选后启动前会确认。检查实际设置、退出及目标缓存批次，不把队列0当作完成证明。
9. Insights分析：高级设置选择UnrealInsights.exe，或首次启动编辑器前设置PSOWORKBENCH_INSIGHTS环境变量。后台解析有效验收（或有效采集）Trace，按方案中的开始/结束秒数导出相关 CPU Scope，默认0–15秒。

任务互斥，同一项目仅允许一个工作台后台任务。编辑器显示阶段状态、原始日志尾部、成功产物摘要及具体错误。失败不替换上一次成功产物；历史成功不代表当前有效，配置与上游变更会标记待更新，修正后重试对应步骤。关闭面板不主动终止后台构建；重新打开编辑器后可读取方案成功产物。首版不提供构建强制中止或后台任务重连UI。

## 产物与平台

任务及完整证据：项目/Saved/PSOWorkbench/Jobs。方案状态：项目/Saved/PSOWorkbench/Profiles/<方案>/state.json。路径基于uproject，不受启动编辑器的UserDir影响。

Runtime模块在非Shipping运行中观察Begin/Complete以支持诊断面板；仅带PSOWorkbenchSession启动参数时写退出摘要和响应stop.request进行保存、停止Trace与正常退出。它不增加正常游戏Loading门控，也不实现“未就绪自动隐藏”。

缓存组当前用于输入命名和来源记录，所有匹配SPC仍按引擎默认规则合并。按场景/玩家进度过滤、Chunk/UsageMask、CDN挂载和Runtime分组调度尚未实现。补缺集合不能未经覆盖验证就当作BundledOnly的完整集合。

Android已保留平台选项和任务入口边界，但设备选择、部署、采集回收、移动Shader格式及APK构建尚未实现，UI明确禁用。当前未验收SM5、其他RHI、Shipping或蓝图-only项目的构建目标推导。

## 移植与依赖

复制插件到目标C++项目Plugins并启用，重新编译该项目Editor/Game。后端脚本随插件携带，不依赖AR2旧Scripts目录；运行时记录不依赖AR2的PSOStartupDiagnostics模块。目标地图、动态资源Cook输入与自动路线需要按业务在UI配置，AR2缓存不能直接复制使用。

本地UE5.8引擎已包含Epic aa697db65d45a27da969b4b4aa850df732b2325f线程池销毁修复；未修复引擎在Auto+Trace退出上有已知风险。其他引擎版本需单独验证。PowerShell后端使用UTF-8 BOM以支持Windows PowerShell5，读取请求/INI显式按UTF-8，Launch包装器保留启动错误。

所有性能数据仅对当次构建/运行配置成立。驱动清理为请求，不保证完全成功；批次完成不是全局就绪或全游戏覆盖；并行CPU Scope数量和耗时之和不是独立PSO数量或墙钟时间。

## 运行时 PSO 面板

Development/PIE 中默认显示简版，Ctrl+F7 循环“简版 → 详细版 → 隐藏 → 简版”，主菜单和游戏内均适用。PIE 必须让游戏视口获得键盘焦点，避免在编辑器面板打字时误触发；不占用 F9。控制台 PSOWB.Overlay 0/1/2 可直接设置，PSOWB.CycleOverlay 或旧 PSO.ToggleStartupCheck 可循环。AR2 旧面板已停止绘制，避免重叠。

简版读取实际 CVar、自动预缓存支持状态、Bundled 开关与已观察批次、引擎待处理数；详细版补充 Proxy 设置、批次墙钟和按需创建/慢创建累计统计。关闭、没有观察到批次、编译中、完成各自独立；processed 只在完成事件更新，不伪造连续百分比。-1 表示该配置不可用。所有数字为进程级，PIE 继承 Editor 历史。

显示快捷键不改变 PSO 策略，也不清理缓存。需要比较关闭/自动/Bundled/Combined 时，应在工作台选择模式后启动新进程；已创建 PSO 不会因运行中关开关而撤销。Hit/Miss/TooLate 由引擎 stat PSOPrecache 查看，需要支持的 Validation 配置；未开启采样时的0不是无漏项证明。面板不拦截资源加载，不实现未就绪隐藏；保留的 AR 主菜单绿色编译提示属于原项目 Blueprint，不是此插件面板。
## 项目适配与产物依赖（schema 2）

通用插件不内置项目地图、技能日志或 Listen Server。地图 URL 选项默认空；仅需要时在方案填 ?listen。NoSteam 等额外参数由方案逐项配置。自动路线必须有完成标记；预期成功次数大于0时，还必须填写本项目的成功动作日志正则。项目结果输出参数名可选，工作台将 Session 目录传给它。AR2 示例集中在 Config/PSOWorkbench/Profiles/WorkbenchUI.json，不随插件移植。

构建前准备脚本可填写项目相对路径 .ps1（推荐）或本机绝对路径，仅使用可信脚本；参数按数组传递。脚本非交互执行，返回非零则不启动 Native Build，命令与日志保存在该任务目录。准备步骤可以生成 TS/配置等构建输入；若其改变采集包依赖，旧采集/转换也必须重新生成。工作台不替目标项目自动猜测 Tools 仓库或登录环境。

每个成功产物保存当前阶段配置、唯一身份、上游身份与文件 Hash。包身份覆盖归档内 EXE/DLL/PAK/UTOC/UCAS，采集与转换检查记录/SHK/SPC；验收检查日志、Trace 和 Runtime 摘要。代码、脚本和 INI 按内容 Hash 检查；大体积源资产只用路径/大小/修改时间检测变化，不保证识别人为保留大小和时间的替换。引擎根目录与 Build.version 被记录，但不替代发布流水线的精确引擎构建身份校验。

依赖链：采集包 → 采集会话集合 → Stable 清单 → 已安装输入 → Bundled 包 → 验收 → 分析。换采集包、新增记录、重新转换/安装、改变包体或 SPC 集合会使相关下游待更新；仅切运行模式不要求重建采集包，但旧验收和分析待更新。改回完全匹配的配置且依赖仍一致，可恢复历史有效结果。旧 schema 记录保留但要求重新生成，不凭旧文件存在自动升级为有效。

UI 会即时比较当前方案的相关字段，显示待更新并传播到下游。磁盘上的外部改动通过“检查产物依赖”核验；界面“已完成（上次依赖检查有效）”不是持续文件监控。每次实际执行也会重新检查，过期结果不能绕过 UI 供下游使用。新任务失败时历史证据仍保留。可运行 Scripts/Tests/Dependencies.Tests.ps1 查看独立夹具回归；夹具文件不是实际 PSO 缓存，不是性能测试数据。

Runtime 模块仅用于 Editor/Game/Client Target，明确排除 Server；Android 尚未实现闭环。移植前仍须核对目标引擎接口、项目构建准备、Cook 范围、正式 Stage 校验和输入冲突。