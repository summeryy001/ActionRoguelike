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

## 阶段 2 补充：替换为 Epic 官方线程池修复（2026-10-30）

用户提供 Epic commit aa697db65d45a27da969b4b4aa850df732b2325f（2026-04-17，PSO thread pool tears down inner thread pool also.）。已确认与本地退出异常根因相同：原实现只释放 Wrapper，未销毁私有底层线程池。官方修复除释放底层池外，还加入 ShutdownThreadPool 的 LockCS 和 bHasShutdown 检查。此前“未找到官方同类修复”的调查结论由此更新。

通过 epic 只读用途的 Git remote、blob:none 过滤和 depth=2 获取官方提交；公司 origin 未变。先备份并仅反向应用旧的本地所有权补丁，再在公司引擎 fix/pso-thread-pool-official 分支引入官方提交。中文移植提交 04e066ad1c0b041e397b70026e8bac9d8620ca41 保留官方作者及原 SHA；与官方 patch-id 均为 37ed9799a17db50c935fe12562d102f18ba1a7fb。仅提交 PipelineStateCache.cpp 的 15 行新增/3 行删除，其他已有引擎改动未纳入。切换分支触发既有 GitDependencies hook，报告 DefaultMaterial.uasset 与 ReplayServer/.project 本地差异，未强制覆盖。导入提交时跳过 hook，源码补丁本身无需新增依赖。

AR2 Editor 与 Game Development 编译成功，129.09 秒。编译日志 Saved/PSOOfficialFix/20261030/build.log。仅替换已有 Saved/PSOValidation/Package/Windows/ActionRoguelike/Binaries/Win64/ActionRoguelike.exe，沿用既有 Cook 资源，旧 EXE 已备份至 Saved/PSOOfficialFix/20261030/previous-ActionRoguelike.exe。本轮没有重新 Cook SPC，也未推进阶段 4。新 EXE SHA256=5F96BCA8641B296CA113237431AAEC4711E805D37ABF66785B4B8B40A3E98531。此前历史批次与采集包仍代表当时构建，不应声称它们已更新为官方修复。

新增 Scripts/TestOfficialPSOFix.ps1，默认仅生成运行清单，-Execute 启动回归。测试显式 Auto=1、GlobalShaders=1、Validation=2、ProxyCreationStrategy=1、Bundled=0，独立 UserDir；不清理驱动缓存，不用于冷启动性能统计。正式证据 Saved/PSOOfficialFix/20261030_161016：AutoTrace1、AutoTrace2、AutoReadyTrace、AutoNoTrace 四轮均 Valid=true，ExitCode=0、六次动作 started=1、Complete、respawnAlive=1，无 Ensure/Fatal/Assertion，实际配置匹配。前三轮生成非空 utrace；最后一轮 -trace=none 未生成 Trace。AutoReadyTrace 队列就绪 waitSeconds=0.666。这里只验证本地 Windows DX12 SM6 Development，不代表所有平台和退出时序覆盖完毕。

初次试跑 Saved/PSOOfficialFix/20261030_160746：首次左键 started=0，只有五次动作成功，严格验收判失败并停止；退出码仍为 0、Trace 已生成，未观察到崩溃。保留该证据，未放宽验收条件，随后完整四轮重跑通过。该问题属于路线动作未启动现象，尚未进一步归因。

公司修复分支已推送，MR：https://git.gz4399.com/4399-unreal/unrealengine-4399/-/merge_requests/1 ，目标 release-5.8.3。尚未合并目标分支。AR2 只做本地提交，未配置 remote 或推送。Client2 Game/包未更新；共享引擎的 RHI Editor DLL 已随本轮编译更新。Patches 中旧补丁作为阶段历史保留，当前应采用官方 diff，禁止叠加两套补丁。

## 官方修复合并确认（2026-10-30）

用户已审核并合并公司 MR !1，远端源分支已删除。同步 origin 后，本地 release-5.8.3 已 fast-forward 至 077f17da50，包含移植提交 04e066ad1c。PipelineStateCache.cpp 与已编译、已完成四轮回归的移植版本无差异，无需仅因合并提交再次编译。既有其他引擎本地改动保留。阶段 2 的退出崩溃修复已进入公司目标分支；阶段 4 尚未开始。

## 阶段 4A：Bundled 构建工具首版与首次构建验收（2026-10-30）

新增 Scripts/PackageBundled.local.bat、PackageBundled.ps1 与 PSO-BUNDLED-GUIDE.md。默认预览，-Execute 执行 BuildCookRun；沿用已编译 Game/Editor，不清理驱动缓存。独立归档 Saved/PSOBundled/Builds/<时间_标识>/Package；不覆盖阶段 3 采集包和快照。前置验证 SM6 SPC 存在且非空，保存输入快照及 Hash；检查构建期间输入/EXE 不变、SPC 读取日志、运行时缓存的生成时间与 Content/Metadata Hash 一致、归档 EXE Hash，以及 UnrealPak -List 包内缓存条目。成功才写 current-build.json。acceptance 的 RuntimeVerified=false 明确区分构建和运行验收。构建会更新 Saved/Cooked 与 staging 工作区，因此禁止并发 Cook。

首次通过 CMD bat 验证时发现 Windows PowerShell 从 PowerShell 7 继承 PSModulePath 后无法自动找到 Get-FileHash；脚本改用本地 .NET SHA256 实现，随后 CMD 默认预览与执行均通过。PowerShell Parser、git diff --check 通过。最终版增加数量解析，使用本次原始 Cook 日志回放核对 508/0拒绝/192合并/512输出通过；该数量解析增补未再次执行整轮 Cook，首次 acceptance 的数量可查 pso-build-summary.log。

构建证据：Saved/PSOBundled/Builds/20261030_175525_8214c7，ExitCode=0、Valid=true，含包内清单验收共66.08秒。SPC 700个稳定组合由本次 Cook 解析合并为508项，0拒绝、192合并；额外 Compute 加入后 sanity 前513项，过滤1项可能不支持的 RHI feature（FTSRRejectShadingCS Perm_53），最终512项：Graphics171、Compute341、RT0。不能简单把512-508都解释成新增可用项，因为中间还有过滤。

SM6 runtime cache 116653字节，SHA256=8761495A70F5B4442F61465B48D83F1DE7E78D075B8F258A7A4482ADFD5BB69F，已核对进入归档 PAK；SM5 无手工 SPC，本次仍由 Cook 自动写出29个 Compute PSO。这也为之前约4KB的自动生成缓存提供进一步证据。包内 EXE SHA256=5F96BCA8641B296CA113237431AAEC4711E805D37ABF66785B4B8B40A3E98531，使用已回归的官方线程池修复 Game。

当前只完成阶段4的构建部分。项目默认 Bundled 仍关闭，脚本未启动游戏，未观察 cache open/begin/complete，也未做冷缓存性能对照；后续运行验收需要显式传入 Bundled/StartupMode，并区分 Auto 混合队列与真正的随包事件。Loki 后续工具需保留采集模式（完整/补缺/隔离）、按场景/资源包分组、随包或CDN分发及分阶段预编译的配置维度；本脚本首版仅针对 AR2 Windows SM6 构建验证。

## 阶段 4B：仅 Bundled 运行与 Insights 验收（2026-11-02）

新增 ValidateBundled.local.bat/ps1：读取已通过的构建清单，验证 EXE、缓存证据及运行前后包容器一致，独立 UserDir，显式 Auto=0、GlobalShaders=0、Validation=0、ProxyCreationStrategy=0、ShaderPipelineCache.Enabled=1、StartupMode=1、SaveUserCache=0。默认预览，-Execute 才运行；不清理驱动缓存。本次无需改 C++、重新编译或 Cook。

实际证据 Saved/PSOBundled/Runs/20261102_162509_e0bf49，使用阶段4A构建 20261030_175525_8214c7。Global/ActionRoguelike 共享 Shader 库均加载；打开目标 ActionRoguelike_PCD3D_SM6.stable.upipelinecache，512 entries，GUID=9C734A07464D0E082F25489C37E48254；Begin queued=512，Complete processed=512，wallSeconds=0.339780、submissionSeconds=0.073735。七项运行配置实际值核对正确。六次技能 started=1、Complete、respawnAlive=1、ExitCode=0，无 Ensure/Fatal/Assertion，Trace与CSV存在，包容器和EXE运行前后未变，Valid=true。

新增 AnalyzeBundledTrace.ps1，调用定制 UnrealInsights -NoUI -AutoQuit，通过 ExecOnAnalysisCompleteCmd 导出前10秒 Precompile 事件并精确筛选 CPU Scope。实际分析退出码0：FShaderPipelineCache::PrecompileGraphics=171次、PrecompileCompute=341次，与构建分类及512项批次一致；trace-analysis.json Valid=true。保留导出CSV、命令和日志。最初试导出 *PSO* 的 pso-events.csv 也保留在证据目录，其中包含 Frame 轨道及其他事件，不把其全部行数作为 PSO 数；正式分析使用 *Precompile* 并按准确名称筛选。

时间解释：0.339780秒是本次已有驱动缓存条件下的 Begin→Complete 墙钟时间，0.073735秒是回调上报时间；均不是冷启动耗时或整个启动耗时。CPU Scope 数量只作为提交路径旁证，不等于额外独立 PSO 或驱动实际编译次数。本次直接进入 TestLevel，不验收 MainMenu Loading门控；队列完成不证明全游戏覆盖，仍可能有后续按需创建。

阶段4功能闭环已完成：输入SPC→Cook生成运行时缓存→入包→Shader库/目标缓存打开→512项预编译批次完成→玩法及退出通过。项目默认 Bundled 仍关闭，仅本次脚本覆盖配置。下一步阶段5应基于这一最新包统一四种运行模式并做正式冷缓存对照，不能沿用不同包历史数据当严格同包结论。脚本通过CMD预览/执行、PowerShell Parser与git diff --check验证；AR2继续仅本地提交。

## 阶段 5 工具：同包四模式固定时间释放对照（2026-11-02）

新增RunComparison入口、RunComparisonPair执行器（基于已验证基线脚本独立扩展，旧脚本不变）、AnalyzeComparison汇总和操作指南。固定阶段4已验收包，无C++/资源/缓存改动，不重新构建。默认预览，-Execute执行四模式各3对Cold/Warm；按轮次轮换模式顺序，每对Cold立即接Warm。每次冷请求clearPSODriverCache，独立UserDir，记录Hash与驱动目录快照。清理是否成功未独立证明，源码亦不清理旧LocalLow/NVIDIA/DXCache，不宣称彻底冷缓存。

对照配置包括Baseline、Auto、Bundled、Combined；Auto相关模式Validation2/ProxyCreationStrategy1，其他模式0，作为实际配置组合报告。Bundled模式核查目标库Begin/Complete；动作未启动但退出正常可重跑整对，最多3次，全部失败尝试保留并排除，其他严重异常停止。首版只做固定时间路线，AutoReady门控不用于Bundled模式，不更改包来混入就绪对照。CMD四模式预览和Parser通过，正式批次已启动，性能结果待完成后另行提交。

## 阶段 5 结果：24轮同包对照完成（2026-11-02）

Evidence Saved/PSOComparison/20261102_172037_5011e5，四模式各3对冷/热，24/24有效、12/12有效对、0排除/重跑。EXE/全部包指纹一致，模式实际值、技能6次、复活、退出均验收通过。未重新编译或Cook。AnalyzeComparison成功输出48组技能聚合，已验证会拒绝未完成批次。

冷首次左键/黑洞/Dash窗口最大帧耗时三次中位数(ms)：Baseline106.05/95.96/85.60；Auto127.48/16.07/14.63；Bundled7.91/10.29/8.78；Combined25.80/15.82/15.17。热首次技能中位数约8.64—10.30ms，但存在个别异常：Bundled热Dash52.54ms、Baseline热重复黑洞77.91ms，不剔除或直接归因PSO。

Bundled冷/热批次墙钟中位数2.87/0.32秒，Combined0.16/0.18秒；均观察到512项打开、Begin/Complete512。Combined批次完成后仍有大量Auto pending，不能解释为全局PSO准备完成。冷进程→路线开始中位数秒：Baseline1.69、Auto2.24、Bundled2.75、Combined2.27；不是完整交互启动时间。driver清理仍仅请求、未独立证明；AI/可见性非确定。

新增AnalyzeComparisonTraces，实际离线解析四个中位首攻代表冷样本（Baseline2/Auto2/Bundled3/Combined3），Insights退出0，导出0—15秒CPU事件。Baseline首攻近似窗口有102.71ms Graphics创建；Bundled窗口内观察Graphics创建最大0.0087ms；Auto/Combined仍有长Compute创建后台Scope。准确方法、原始路径、限制和结果见Scripts/PSO-STAGE5-REPORT.md。后台Scope不等于卡顿帧/纯CPU编译时间，不把嵌套并行SumMs当墙钟。

阶段5固定时间释放对照完成。尚未新建Bundled就绪门控，不将历史阶段2 AutoReady数据混入同包结论。仅Bundled优势仅适用于已采集路线，Loki生产策略仍需结合覆盖、后台预算与门控。下一阶段整理可迁移工具和工作流，不复制AR2缓存到Client2。

## Loki 落地要求：运行策略可配置（2026-11-02）

用户明确要求：阶段5的配置选择必须作为Loki PSO工作流的可选能力保留，不硬编码为Auto或Combined。此处记录需求，尚未修改Client2。

- 运行模式：Disabled、AutoOnly、BundledOnly、Combined，统一配置入口，启动时记录请求值与实际生效值；测试脚本可覆盖项目默认值。BundledOnly应显式关闭Auto及GlobalShaders自动预缓存，避免后台静默扩大预创建范围。仅改变运行开关且包内已具备匹配缓存时，可用同包切换；新增缓存、Shader格式或内容仍需重新Cook/打包。
- 支持Bundled主导方案：开发阶段广泛采集，运行时关闭Auto，以已采集集合预编译；漏项按需创建并持续记录、补采集。不能假设漏项只在边界或后期出现，应为漏项卡顿设项目验收标准。
- 采集策略与运行策略独立：完整采集、自动补缺、隔离验证不能与四种运行模式绑定。尤其BundledOnly不能未经覆盖验收直接使用仅补缺采集集合，因为该集合原本依赖Auto覆盖主体。
- 调度配置：启动/场景进入前/后台分批，按场景或资源包选择缓存集合；可配置并发/预算和是否等待就绪。运行模式的选择本身不自动实现这些能力，需要项目加载与门控逻辑配合。广泛收集不等于启动全量预创建，避免只增加覆盖却失控增加启动工作量。
- 分发配置：基础包、资源分包、CDN可分别组织匹配的缓存与Shader代码库；当前AR2本地产物归档仅为追溯，不代表已实现CDN加载。跨平台分别生成、验证产物。
- 验收：按模式检查缓存打开/Begin/Complete及Auto待处理请求、准备耗时、首次技能帧耗时、Miss/TooLate与正常退出；保存配置、构建Hash、日志及Trace。随包批次完成不等于所有Auto或全游戏PSO就绪。

以上属于可实现的配置化设计要求。AR2已经验证四模式可用同包启动覆盖；Loki的统一配置接口、场景分组/调度和分发接入留待后续实施，不能将需求记录解释为已完成接入。

## 阶段5覆盖迭代准备（2026-11-02）

用户要求在阶段6前扩大采集再对照。新增PSOCoverage opt-in模式：保持原技能路线，追加20个工程Niagara效果、7类道具、适用接口交互及相机距离/角度变化，136秒结束；目录显式纳入Cook。不是全地图/全玩法覆盖，不为达到1000制造排列。

增加CollectCoverage、RunCoverageIteration、AnalyzeCoverageIteration和指南。控制两版使用同一新EXE和资源，保留原SPC，新增Coverage01 SPC由Cook合并；不直接比较旧历史包。扩展对照仅测冷请求：两版×Bundled/Combined×3次原路线，加每版一次扩展夹具诊断，共14次。默认预览，不自动删除用户文件，继承驱动清理请求的限制。

先全目录Cook暴露LeverBP访问Transient ActiveGameplayTags的兼容问题。原属性无Blueprint可见标记，BlueprintReadOnly尝试仍无法传可写引用；最终BlueprintReadWrite恢复旧内容访问，Editor/Game重新构建成功。记录失败构建20261102_193820_fa07cc和194236_81483a。PackageBundled PowerShell7自动变量Input被管线覆盖造成误判，改SpcInput；194601_f9044f的Cook成功但构建验收失败，未当成功，随后重构建通过。首轮采集194826_5c4f1d记录586项但TargetDummy碰撞失败，严格验收不通过；AlwaysSpawn夹具修复后重新编译、Cook和重采。

正式采集Saved/PSOCoverage/Recordings/20261102_195402_4552d5：Valid=true、Exit0、6技能、复活、20效果、7道具及包Hash通过，588条记录。转换20261102_195703_44a153：798稳定组合、50867字节、SHA256=E8F0B2FACC9DA8302C03870C5A186948C6BDC599D2EAE90450C61AE81AC202F9。已安装Build/Windows/PipelineCaches/PSO_Coverage01_ActionRoguelike_PCD3D_SM6.spc，保留原输入。

Control构建20261102_195322_37eaf6，原SPC在新资源范围下生成541项（171 Graphics/370 Compute）；Expanded构建20261102_195709_b9ea1c，合并新旧输入生成602项（221 Graphics/381 Compute），均0映射拒绝。原512到541来自新增Cook资源自动Compute，并非此次跑包新增；严格迭代净增61项（50 Graphics/11 Compute）。共同EXE SHA256=45CA75EA11E8079CECAD497D2E2002848A100D43CFDE1A2E77BAA5A693BF2AC4。对照执行器已核对两版.ucas/.utoc Hash完全一致，.pak随缓存改变。预览通过，正式运行已启动，结果待完成另行提交。

## 阶段5覆盖迭代01结果（2026-11-02）

对照批次Saved/PSOCoverage/Comparisons/20261102_195916_3a43c4，12次原路线冷请求（两版×Bundled/Combined×3次）与2次扩展夹具Probe全部通过，无重跑。EXE和资源容器一致；额外解析PAK清单1675文件，仅SM5/SM6运行时缓存Hash不同，当前使用SM6。

原路线三次中位数左键/黑洞/Dash(ms)：Control Bundled11.94/10.35/12.64，Expanded Bundled11.40/10.67/10.03；Control Combined27.28/15.89/16.74，Expanded Combined15.53/16.12/16.64。Control Combined首攻有111.46ms极值，未排除。仅Bundled批次墙钟中位数从3.75到5.70秒，进程至路线开始4.05到4.43秒；区间不同不相加。Combined批次0.19到0.17秒，不代表Auto就绪；首攻pendingAuto中位数3512到3510，数量基本未变。

扩展52—136秒夹具Probe各1次：Control Tick峰值400ms/P95 9.31ms/超过50ms 12样本，Expanded23.41ms/8.47ms/0。引擎世界Delta默认可能Clamp到400ms（BaseGame.ini及WorldSettings），不能把400认作真实最长停顿。新增AnalyzeCoverageTraces实际Insights退出0：该近似窗口Graphics API创建最大217.61→1.31ms，Compute396.08→3.13ms；>50ms事件分别22/9降至0/0。单次Probe只是诊断，不是三次性能结论；有同步加载和模拟开销，Scope不等于纯编译时间。

报告Scripts/PSO-COVERAGE-ITERATION-REPORT.md保留来源、原始值范围、计时定义与边界。结果支持扩大覆盖能减少新内容首次出现的长创建，同时增加前置处理；不能由此保证全游戏覆盖或线性缩短Auto队列。覆盖扩展已完成本轮迭代，阶段6尚未开始；Client2未改动，AR2只本地提交。

## Loki 落地要求：单一缓存与分阶段缓存并存（2026-11-02）

用户明确要求同时支持全量单一Bundled方案及按场景/阶段采集、分发和预编译的方案，以玩家当前进度差异化准备。新手优先启动/教学/首战集合，已有进度玩家优先当前角色、当前关卡及近期可达内容；进度回退、重玩和跨阶段玩法仍须可选择对应集合，不能将玩家身份永久绑定某一个缓存。

建议组织共享基础集合与阶段增量集合，采集时保留场景、玩法、阶段、平台/RHI/Shader格式和构建来源。工作流可产出单一合并缓存，也可产出阶段缓存或适配引擎接口的过滤集合；不能假设每个逻辑分组一定等于一个可同时打开的独立文件，具体文件/Chunk/UsageMask方案需在本地引擎接口上验证。

项目依据当前进度选择必需集合，明确优先级、进入前等待条件、后台预算及暂停/恢复时机，并与Shader代码库可用性、资源分包/CDN挂载和版本匹配关联。记录各组完成事件及漏项，未就绪内容由项目决定等待、延迟展示或允许按需创建。采集顺序不保证运行时编译顺序，必须通过实际分组和调度实现。以上为阶段6/Loki接入需求，尚未实现运行时分组加载能力。
