# 阶段 4：构建 Bundled PSO 包

本工具负责阶段 4 的构建验收。运行时缓存打开、预编译完成和冷/热性能对照需要后续单独验证。

## 前置条件

- 已编译 AR2 Game/Editor，`Binaries/Win64/ActionRoguelike.exe` 是预期版本。
- 阶段 3 的 SPC 已安装到 `Build/Windows/PipelineCaches`，匹配 `*ActionRoguelike_PCD3D_SM6.spc`。
- 保持 Stable Keys、共享 Shader 代码库配置；关闭 UE 编辑器和游戏。
- 引擎路径默认本地 UE 5.8，可用 `UE_ROOT` 覆盖。首版仅验收 Windows PCD3D_SM6，不提供跨平台通用保证。

## 命令

CMD 预览（只生成 command.json，不运行 Cook）：

```cmd
call "F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\PackageBundled.local.bat"
```

执行 Cook 和打包：

```cmd
call "F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\PackageBundled.local.bat" -Execute
```

PowerShell 也可以直接运行同目录的 `PackageBundled.ps1 -Execute`。

调用引擎 RunUAT BuildCookRun，使用 `-skipbuild -skipbuildeditor -cook -stage -pak -iostore -archive`。不重新编译 C++，也不清理驱动缓存。Cook 会更新共享的 Saved/Cooked 和 staging 工作目录，但不会覆盖此前独立归档的采集包与证据。不得同时启动另一轮 Cook 或构建。

## 输出与验收

每次输出 `Saved/PSOBundled/Builds/<时间_标识>/`：

- command.json：输入清单、SHA256、引擎/项目提交、实际命令；Inputs：SPC 快照。
- cook.log、pso-build-summary.log：构建完整日志与 PSO 相关摘要。
- StableKeys：本次 Cook 的 SM6 映射；RuntimeCaches：生成的 SM6 stable 缓存快照。
- Package/Windows：独立归档包；*.pak.list.log：UnrealPak 的包内清单。
- acceptance.json：Valid 是构建验收，RuntimeVerified 始终为 false。

检查输入前后不变、Cook 成功并明确读取各个 SM6 SPC、Content/Metadata 缓存非空且为本次生成并且哈希一致、归档 EXE 匹配预编译版本、包内 PAK 清单包含 SM6 缓存。拒绝仅凭旧文件存在判成功。

构建成功后才更新 `Saved/PSOBundled/current-build.json`；失败轮次保存 acceptance.json 和错误，不更新成功指针。脚本不会自动开启运行时 Bundled 开关：下一步必须显式指定运行配置并观察 cache open/begin/complete，不能把文件已入包解释为预编译已生效。

Cook 可能处理项目配置的其他 Shader 格式，首版仅针对已有 SM6 SPC 验收。PSO 数量、拒绝项和去重统计保留原始日志，不能把 SPC 的 Stable 组合数直接当作运行时完成数量。

## 运行验收

预览或实际执行仅 Bundled 验收（默认读取 current-build.json，也可传 -BuildManifest 指定 acceptance.json）：

```cmd
call "F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\ValidateBundled.local.bat"
call "F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\ValidateBundled.local.bat" -Execute
```

使用已验收新包、独立 UserDir，直接进入 TestLevel listen 并执行固定技能/死亡/复活路线。Auto=0、GlobalShaders=0、Bundled=1、StartupMode=1、SaveUserCache=0，关闭 Validation 和代理等待策略；不清理驱动缓存。最多300秒，超时只终止本次启动的游戏。运行前后校验包容器和 EXE 未改变。

运行输出 Saved/PSOBundled/Runs/<时间_标识>/，包括 manifest.json、game.log、capture.utrace、frames.csv、acceptance.json、runtime-summary.log。严格检查实际设置、Shader 代码库加载、目标 stable 缓存打开、正数 Begin 队列及相同数量的 Complete、事件顺序、六次动作、复活和 ExitCode=0，无 Ensure/Fatal/Assertion。队列0或文件存在不能代替这些事件。构建 acceptance 不被改写，运行验收单独保存。

Insights 离线解析（PowerShell）：

```powershell
& 'F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\AnalyzeBundledTrace.ps1' -EvidencePath '本次运行证据目录'
```

默认使用本机定制 UnrealInsights，可传 -InsightsExe 替换。无 UI 解析并导出前10秒的预编译事件，保存命令、日志、precompile-events.csv 和 trace-analysis.json。精确筛选 FShaderPipelineCache::PrecompileGraphics/Compute，因为 Frame 轨道可能不受导出名称过滤影响。首版要求证据路径无空格。

这只是运行功能验收：预编译 CPU 调用数量与回调互证，不证明全部玩法覆盖、所有驱动编译均发生在该窗口或没有剩余按需创建。SubmissionSeconds 是引擎上报的时间，不是整体启动时间；WallSeconds 是 Begin 到 Complete。正式冷缓存性能比较属于阶段5。
