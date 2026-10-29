# AR2 PSO workflow history

## 00 — Local baseline (2026-10-29)

Source: the current local ActionRoguelike working copy, including prior gameplay/crash fixes and diagnostics. This is not pristine upstream AR. Internal project and module names remain ActionRoguelike.

Automatic PSO precaching, global shader precaching and bundled precaching are disabled explicitly in Config/DefaultEngine.ini. Stable shader key generation is disabled. No historical .spc, .shk or .upipelinecache files were copied. On-demand PSO creation during normal rendering still occurs.

Editor and Win64 Development targets compiled successfully using F:/Git_Repository/4399-unreal/unrealengine-4399 (458.24 seconds). 1,949 copied source/content files matched the source AR at preparation time. No AR2 Cook/package or cold-cache benchmark has been performed. The user has since opened the editor and used PIE; system driver caches are therefore not assumed cold.

Local launch/build/package scripts and existing diagnostic code are retained. Generated outputs remain ignored. This first commit captures the current working tree, including any editor-saved asset state present at initialization; earlier preparation was not yet under Git.

## Planned separate stages

1. Enable stable shader keys and perform the initial collection Cook; record effective settings and output provenance.
2. Record a repeatable packaged gameplay route; retain scripts and collection summaries.
3. Convert matching recording + stable shader keys into the bundled .spc build input.
4. Cook and verify the runtime bundled cache and shader library loading.
5. Compare disabled, automatic, bundled and combined modes under controlled cold/warm conditions.

Each completed stage or meaningful fix gets its own local commit and validation entry. Commit history is the authoritative sequence; stages are not marked complete before verification. No remote is configured or pushed.

## 提交语言约定（2026-10-29）

后续 commit message 使用中文，专业术语保持英文；保留已有基线提交及标签。此次仅更新文档约定，不涉及代码或运行配置。

## 统一默认入口地图（2026-10-29）

将 EditorStartupMap 从 TestLevel 改为 MainMenu_Entry，与现有 GameDefaultMap 一致，便于从主菜单开始验证。仅修改编辑器默认入口，不改变 MapsToCook、PSO 配置或当前已打开的地图。已核对两个配置值一致并检查 Git diff；不涉及 C++，无需重新编译。已有独立包的 GameDefaultMap 原本就是 MainMenu_Entry。

## 阶段 1：补齐冷／热基线脚本（2026-10-29）

用户已确认独立包 Host Game、Primary、Blackhole、Dash 正常，截图显示 Auto=0、Bundled=0。新增 RunBaseline.ps1、CMD 入口及 BASELINE-GUIDE.md：默认 dry run，显式 Execute 才启动三对冷／热测试；复用包内 PSOValidation 自动流程，直接进入 TestLevel。记录全包 Hash、配置查询、日志、Trace、缓存目录快照与技能窗口帧数据；失败即停止，不将缓存清理请求当成成功证据。

验证：PowerShell 语法解析与通过 BAT 的一对 Cold/Warm dry run 成功；没有启动游戏、清理驱动缓存或修改包。实际性能测试与 Trace 分析仍未执行，阶段 1 尚未整体验收完成。

## 阶段 1：三对独立包基线验收（2026-10-29）

Evidence：Saved/PSOBaseline/20261029_210954_82eed6。六次 acceptance.Valid=true、ExitCode=0、SuccessfulActions=6，五项 PSO 配置均为 0。实际为 DX12 SM6、1280×720、直接 TestLevel listen 的固定自动路线。

技能触发后 2 秒内最大 Tick 帧耗时的三轮中位数（Cold/Warm，ms）：Primary_First 132.7669/9.8159；Blackhole_First 132.1477/80.2984；Dash_First 91.8447/8.8454；Primary_Repeat 10.2161/8.2412；Blackhole_Repeat 9.1299/9.2144；Dash_Repeat 9.4065/9.3121。慢 Graphics 创建次数中位数 98/12，慢 Compute 创建次数 217/0；次数不是卡顿帧数。

限制：Cold 仅确认请求 clearPSODriverCache，DriverCacheClearVerified=false；EngineReportedInitSeconds=null，ProcessWallSeconds 是整条路线耗时而非启动耗时。AI、瞄准和可见资源非完全确定，窗口最大值不直接等同 PSO 耗时。Warm 黑洞三轮分别 90.2672、80.2984、8.9764ms。

试跑 Trace 的 computer-use 分析：Warm 首次 Dash 的 57.91ms 帧中，Sync_RenderingThread 53.65ms；同期 Background Worker #1 的 Graphics PSO Create time 55.36ms。该结果属于此前试跑 20261029_195726_f227f8，不混入本批统计。用户决定不继续追查 Dash 覆盖差异。

阶段 1 基线已固化；阶段 2 先仅开启自动预缓存，Bundled 继续关闭。

## 阶段 2：自动预缓存准备

开启 Auto、GlobalShaders、Validation=2、ProxyCreationStrategy=1；Bundled 保持关闭。测试脚本增加显式 Profile Auto，默认仍为 Baseline。发现旧 Inventory 用绝对路径排除 Saved，导致包根本就在 Saved 下时清单为空；修正为相对路径。阶段 1 的包 Hash 一致性未得到有效验证，已有帧、日志和 Trace 仍保留，不补写成已验证。

配置修改不涉及 C++；正在使用原 UE 本地引擎重新 Cook/stage/package，阶段 2 尚未验收。

阶段 2 初次验证：BuildCookRun 47.69s，BUILD SUCCESSFUL。两次 Cold 试跑 Evidence 分别为 20261029_212325_c14503、20261029_212605_b9eb6e；五项实际配置符合 Auto，六项动作和复活均成功，最终 pendingAuto=0，但进程都返回 777003，acceptance.Valid=false，Warm 未执行。引擎 GenericPlatformCrashContext.h 定义该代码为 CrashReporterCrashed；日志正常收尾不足以证明进程正常退出。尚无有效崩溃栈，未放宽验收或标记阶段 2 完成。下一步定位退出阶段异常后重跑一对，再开展正式三对。

验证：PowerShell Parser 无错误、git diff --check 通过；新的 package.json 非空（9630 字符），相对路径 Inventory 已覆盖包内容。任务数量/完成耗时的完善和 Insights 对照仍待退出问题解决，不以现有诊断混合队列数字作为独立 Bundled 指标。

## 退出异常定位进展

2026-10-29：常规第三次复现 777003（20261029_233908_64a33b）。使用 Windows Debug API 在调试器下复现，路线完成并返回 0；退出前捕获 breakpoint，DbgHelp 符号解析为 FPageAllocator::Construct 的 PageAllocator 静态析构函数 +63。对应 MemStack.cpp 的 FPageAllocator 析构和 LockFreeFixedSizeAllocator.h 的 GetNumUsed()==0 检查，是目前的排查线索；尚未确定未释放页的持有者。

实验性提前初始化 FPageAllocator：Editor/Game 编译成功（100.76s），重新打包成功（约41s），但 Cold 仍为 777003（20261029_234659_9f912c），故已撤回该源代码实验，未将其作为修复提交。当前包仍含该无效实验编译产物，后续正式测试前必须按恢复后的源码重新构建打包。

调试实验第一次误复用了第二次失败运行的输出路径，其日志/Trace 已被调试运行覆盖；20261029_212605_b9eb6e 不再作为独立失败证据使用，以首次失败、第三次和最近失败记录为准。所有调试运行均不纳入性能统计。转储和临时调试脚本保留于忽略的 Saved 下。

阶段 2 尚未通过，正式三对未启动。下一步核对退出断点的检查条件、剩余 MemStack 页持有者与线程清理顺序；不通过忽略退出码、强制结束进程或降低检查掩盖异常。

## 阶段 2 范围调整：组件／材质 Auto

材质请求清理实验编译、打包成功但仍以 777003 退出（20261029_235838_0197ce），已撤回源码。Validation=0 的隔离仍退出 777003；保持 Auto=1、Validation=2、ProxyCreationStrategy=1，仅令 GlobalShaders=0 的隔离返回 0。该隔离包尚含清理实验，需恢复源码后重新打包并试跑确认。

将阶段 2 的 Auto profile 明确改为组件／材质预缓存：PSOPrecaching=1、GlobalShaders=0、Validation=2、ProxyCreationStrategy=1、ShaderPipelineCache.Enabled=0。与基线相比，GlobalShaders 保持 0。Global Shader 开关相关的退出缺陷尚未根治，留作独立问题，不声称完整 Global 自动预缓存已通过。

准备按恢复后的源码重新 Build/Cook/package，确认正常退出后再进行正式三对。先前提前初始化页分配器和清理材质请求的源代码实验均不进入正式版本。

补充隔离结论：恢复源码、仅 GlobalShaders=0 的干净包仍失败（20261030_000458_7beeb3）。此前 Global0 返回 0 的隔离包同时含 ClearMaterialPSORequests，因此不能把正常退出单独归因于关闭 Global Shader。当前重新验证“GlobalShaders=0 + 测试退出前清理材质预缓存请求”的组合；该组合的单次成功尚不足以宣称根治。清理只在测量与 Trace 停止、WaitForAllTasks 完成后调用，不能掩盖测量期间问题。

组合方案复测（20261030_000747_05268f）：Cold 返回 0，但 Warm 返回 777003，故仍未通过。继续排查 PSOPrecache.cpp 中全局 FPSOPrecacheStateCache，其 CachedPSOPrecacheResults 可持有 FPSOPrecacheRequestResult.AsyncCompileEvent，静态析构前未显式清空。

新增引擎候选补丁 Patches/UE58-PSOPrecache-exit-cleanup.patch：在 FCoreDelegates::OnExit 期间清空该缓存，提前释放事件引用；本地共享引擎 PSOPrecache.cpp 已应用该候选改动，其余已有引擎工作区改动未动。AR2 测试退出前仍清理材质请求。正在构建和验证，不将候选当成已证实根因。该引擎改动会进入后续使用本地引擎重新构建的程序，当前 Client2 既有包未更新。

## 根因证据：PSO 私有线程池的所有权

诊断版记录的两个未释放页，其分配栈均为 FCpuProfilerTrace::OutputDynamicEventType -> FMemStackBase::AllocateNewChunk，调用方为 PSO 编译线程 FPSOPrecacheAsyncTask::DoTaskWork，经 FQueuedThreadPoolWrapper::FScheduledWork 执行。证据在 Saved/OutstandingPagesSymbols.txt。与先前“缓存事件引用”的猜测不同，直接持有者是存活工作线程上的 CPU Trace 名称缓冲区。

本地 PipelineStateCache.cpp 的 FPSOPrecacheThreadPool::Get 自行 Allocate/Create 底层线程池，随后仅保存非 owning FQueuedThreadPoolWrapper。ShutdownThreadPool 只 delete wrapper，wrapper::Destroy 排空工作但不销毁底层线程池，造成工作线程及 TLS 遗留。候选修复由 FPSOPrecacheThreadPool 使用 TUniquePtr 保持底层线程池所有权，先销毁 wrapper 再 Reset 底层 pool，后者析构调用 Destroy，等待线程退出并清理 TLS。

先前清空材质请求、提前初始化 allocator、清空状态缓存的实验均已撤回。临时页分配栈诊断已从 Core 源码撤回。恢复原阶段 2 GlobalShaders=1，与 Auto=1、Validation=2 一起复测。唯一引擎功能改动记录在 Patches/UE58-PSOPrecache-owned-thread-pool.patch；尚在验证，不把实验包纳入性能报告。

线程池所有权修复试跑通过：Saved/PSOBaseline/20261030_002654_838eef，Cold/Warm 均 ExitCode=0、Valid=true、SuccessfulActions=6，GlobalShaders=1、Auto=1、Validation=2、ProxyCreationStrategy=1、Bundled=0。Editor/Game 编译成功（69.70s）、打包成功（43s）。临时 Core 诊断和两个无效源代码实验均已撤回；引擎仅保留 RHI 的底层线程池 ownership 修复。本地引擎修改不代替 AR2 补丁来源记录。

## 阶段 2A：自动预缓存、无就绪等待的正式三对（2026-10-30）

Evidence：Saved/PSOBaseline/20261030_002930_239d21。六次均 Valid=true、ExitCode=0、SuccessfulActions=6。全部采用修复私有线程池 ownership 的同一包；Auto=1、GlobalShaders=1、Validation=2、ProxyCreationStrategy=1、Bundled=0。同样 DX12 SM6、1280×720、固定时间 TestLevel 路线，不等待预缓存归零。

| 操作 | 阶段1 Cold | 阶段2A Cold | 阶段1 Warm | 阶段2A Warm |
|---|---:|---:|---:|---:|
| Primary_First |132.7669|130.2181|9.8159|12.4253|
| Blackhole_First |132.1477|23.6412|80.2984|11.5617|
| Dash_First |91.8447|16.1651|8.8454|13.7215|
| Primary_Repeat |10.2161|13.8541|8.2412|10.9516|
| Blackhole_Repeat |9.1299|14.7826|9.2144|10.8450|
| Dash_Repeat |9.4065|14.1127|9.3121|11.6244|

单位 ms；技能触发后2秒内最大 Tick 帧耗时的三轮中位数。阶段2A第3轮 Cold Primary_First=316.6561ms，不能因中位数约130ms忽略该尖刺。Cold Graphics 慢创建次数中位数从98降至43，Compute从217到219；Warm Graphics从12到1，Compute均0。这些创建次数不等于卡顿帧数。

结果：黑洞和 Dash 的 Cold 长帧改善；首次 Primary 没有明显改善，重复技能和 Warm 的若干指标略高，不能声称全局无卡顿。Cold 首次技能约5秒时仍有三千余待处理任务；当前流程未设置资源/PSO就绪门控。pendingBundled 字段实际为混合剩余数，Bundled开关仍0，不能据它声称加载了随包PSO。尚未做此次正式批次逐帧 Insights 归因，也没有可靠的 process-to-interactive 启动统计。

新增 AnalyzeBaseline.ps1，可按 ExpectedPairs 验证完整运行和技能窗口并写 summary.json。已用阶段1三对与阶段2试跑校验中位数，与先前结果一致；失败批次被拒绝。正式批次 summary 已生成。引擎补丁 reverse --check 通过，Core临时诊断与Engine状态缓存实验均已撤回，RHI仅保留6行新增/1行替换的ownership修复；阶段2正式包无临时分配栈开销。

下一步阶段2B：在场景/技能资源加载完成后等对应PSO就绪，再启动相同相对技能路线；分别记录等待耗时与可玩阶段帧耗时。随后再进入 Stable Keys/Cook/record/convert/Bundled 流程。DriverCacheClearVerified=false、阶段1旧Hash校验缺失、AI和资源可见性非确定性等限制继续保留。

## 阶段 2B：等待已加载资源的 PSO 队列就绪

新增 opt-in `-PSOValidationWaitForReady`，脚本 profile 为 AutoReady，配置与 Auto 相同。MapReady 后，等待玩家存活、IsAsyncLoading=false、NumActivePrecacheRequests=0 连续稳定0.5秒，记录 gateComplete/ReadyForSkills 后再启动5/10/16秒等同一相对技能时间表。每秒记录队列和加载状态，180秒超时返回非零；脚本验收必须看到 pendingAuto=0、asyncLoading=0 的 gateComplete。

ReadyWaitSeconds 是地图首次测试 Tick 到门控释放的等待，不能称作进程完整启动耗时。等待期间世界继续 Tick、AI和可见性仍可能变化。队列归零只覆盖已提交请求，未生成的技能组件和未来动态资源并不会自动被覆盖；该试验用于判定是否需要下一步定向资源/组件预加载。没有预先释放技能来人为暖场，也没有人为延长 PSO 编译。

正在重新编译打包并试跑一对；阶段2B尚未验收。

门控试跑通过：20261030_005209_87ffc6，Cold/Warm 均 Valid=true、ExitCode=0、六项动作成功。等待分别41.736s/0.752s；Cold Primary_First 窗口最大23.0955ms。代码编译57.68s、打包44s成功。试跑初版尚无 ProcessToReadyGateSeconds 字段；正式脚本增加按日志 UTC 与启动时刻计算的进程启动至门控释放耗时，不将其称为完整交互就绪。等待期间世界和AI继续运行，可能自然暖化额外PSO，必须作为比较限制。

## 阶段 2B 正式三对结果（2026-10-30）

Evidence：Saved/PSOBaseline/20261030_005549_11234d。六次 ExitCode=0、Valid=true、SuccessfulActions=6、ReadyGatePassed=true；实际 Auto=1、GlobalShaders=1、Validation=2、ProxyCreationStrategy=1、Bundled=0。三对使用同一个门控包，package inventory 在批次前后检查通过。

| 操作 | Cold 中位数 ms | Warm 中位数 ms |
|---|---:|---:|
| Primary_First |23.7288|10.6929|
| Blackhole_First |12.6035|12.2419|
| Dash_First |13.3911|10.2411|
| Primary_Repeat |10.3154|11.6038|
| Blackhole_Repeat |10.5289|10.7689|
| Dash_Repeat |11.0264|11.2407|

同一口径：技能触发后两秒内最大 Tick 帧耗时的三轮中位数。Cold Primary 三次23.0275/24.2222/23.7288ms；Warm第2轮Dash仍有37.688ms长帧，不据此声称零卡顿或直接归因PSO。

门控等待（地图首次测试Tick到释放）：Cold 45.444/44.038/45.492s，中位数45.444s；Warm 0.731/0.768/0.503s，中位数0.731s。进程启动到门控释放中位数 Cold 48.6696613s、Warm 3.7419192s，是依据日志UTC与启动时刻估计，不能当作完整用户交互就绪时间。精确每轮值以 acceptance.json/summary.json 为准。

对比阶段2A无门控Cold中位数，Primary 130.2181→23.7288ms、Blackhole 23.6412→12.6035ms、Dash 16.1651→13.3911ms。结论是当前测试路线通过约45秒冷启动等待降低技能释放阶段长帧。两个阶段的包因测试代码增加门控而不同，不是同包严格A/B；世界在等待期间继续模拟，AI可自然触发额外资源和PSO，不能把全部改善都归因于自动预缓存。没有声称已加载资源之外的技能组件完整覆盖，没有将所有慢创建计数当作路线内计数。

测试门控仅在 opt-in PSOValidation 路线使用，正常 Host Game 尚未接入面向玩家的 Loading/输入门控。Trace包含 MapReady/ReadyForSkills/技能书签，已保存供复核；本轮尚未做每个残余长帧的 Insights 调用链归因。DriverCacheClearVerified=false 等先前限制继续保留。

AnalyzeBaseline 增加等待与进程到门控耗时的汇总，已对试跑与正式批次运行成功。阶段2B的队列门控实验完成；下一阶段为 Stable Shader Keys 的首次采集 Cook，然后录制/转换 Bundled PSO，生产化 Loading 和定向覆盖保留后续接入事项。

## 阶段 3A：Stable Shader Keys 首次采集 Cook（2026-10-30）

NeedsShaderStableKeys=true，保留 bShareMaterialShaderCode=true、原SM5/SM6目标配置。新增 PackageCollection 脚本，使用独立采集包输出目录，记录命令、日志、EXE SHA256及SHK快照。无C++改动，不需要重新编译目标。

Cook/打包成功：Saved/PSOCollection/Cooks/20261030_011759_fe7356，BuildCookRun 37.18s，脚本总38.60s。Global SM5/SM6与ActionRoguelike SM5/SM6共四个SHK，SM6项目键112994字节、Global键274165字节。当前尚未生成AR2原始PSO记录或SPC；采集脚本已准备，实际运行验收待下一步。

采集将显式关闭Auto并以logPSO记录，文件缓存Enabled=1用于记录、StartupMode=0暂停预编译，ExcludePrecachePSO=0；独立UserDir。无需清理驱动缓存，不将本次运行当作性能对照。PowerShell Parser与git diff --check通过，转换与Bundled运行时加载尚未执行。

## 阶段 3B：首次 PSO 原始记录（2026-10-30）

采集验收通过：Saved/PSOCollection/Recordings/20261030_012108_86abbf，ExitCode=0、六项动作和复活成功、十项实际配置与请求一致、PackageUnchanged=true。自动预缓存关闭，DX12 SM6，文件缓存记录开启且预编译暂停，没有请求驱动缓存清理。

生成一个 .rec.upipelinecache，116181字节，SHA256=42CE6F48EB8E89032383CA706E42110EEDBDD8C852B4E444009322A3527D649E。最终 BoundPSOsOnly 日志为 saved 508 total、508 new、5 removed；508是本次保存的记录数，不代表整个游戏全部PSO，也不是预编译完成数量。匹配SM6项目与Global两份SHK已复制至该证据目录的StableKeys中，并核对其Cook快照Hash。录制日志和Trace保留。下一步转换Stable PSO清单并检查丢弃/映射情况。

## 阶段 3C：转换 Stable PSO 打包输入（2026-10-30）

新增 ConvertPSO 脚本，验证原始记录和匹配Cook的SM6 Global/项目SHK Hash，调用本地ShaderPipelineCacheTools expand。正式转换Evidence：Saved/PSOCollection/Conversions/20261030_012733_b16dc6，ExitCode=0、Valid=true。读取508条原始PSO、14105条唯一Shader稳定映射，生成700个stable PSO组合；未发现PSO映射失败日志。组合数可能因Shader稳定键别名/候选组合扩张而多于记录数，后续Cook解析后会再次去重。

安装输入 Build/Windows/PipelineCaches/PSO_ActionRoguelike_PCD3D_SM6.spc，47544字节，SHA256=06D410DF5D67E76C62EF5428BC4008947A31D3B1E85E75F8966A838563B8EC5B。早先手工预览转换输出47499字节，同样700组合，未安装；并行输出排序/压缩可能变化，不要求两次SPC字节相同，正式输入以脚本manifest为准。仅此SPC作为特意生成的Build输入纳入Git，原始记录和SHK保留在忽略的Saved。

观察到首次Stable Keys Cook在尚无SPC输入时也生成了3512字节的SM5/SM6运行时stable缓存；本地引擎IncludeComputePSODuringCook默认2（仅自动加入Niagara Compute）。已将当时Metadata运行时缓存补充快照至原CookEvidence/RuntimeCaches，待后续Dump核对数量。不能将所有stable文件都解释为来自手工SPC。录制时StartupMode=0，预编译暂停；没有用这次采集评价预缓存性能。

下一步重新Cook生成包含SPC的运行时stable缓存，核对加载与完成数量，然后做同包模式对照。
