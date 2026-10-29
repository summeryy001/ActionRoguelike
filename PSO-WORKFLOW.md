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
