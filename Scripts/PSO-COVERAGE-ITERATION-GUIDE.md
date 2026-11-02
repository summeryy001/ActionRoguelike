# 覆盖迭代：更大的 Bundled 集合

首轮扩展为开发测试夹具，不声称全游戏覆盖。原固定技能/死亡/复活完成后，-PSOCoverage 追加20个项目Niagara效果、7类道具生成与适用接口交互，变换相机角度和距离，136秒结束。不开此参数时仍执行原56秒路线。配置显式Cook所需目录，避免动态字符串资源漏Cook。

## 生产与输入关系

1. 修改采集夹具后重新编译Editor/Game。先保持原SPC，使用PackageBundled生成新Control包，记录构建清单。
2. 使用CollectCoverage.ps1 -BuildManifest 'Control acceptance.json' -Execute采集。Auto关闭、记录开启、预编译暂停，无驱动清理；检查20个效果、7类道具、6次技能、复活、退出、记录与包一致性。
3. 使用ConvertPSO.ps1 -Recording '采集目录' -Execute转换。新记录和匹配SHK在CookSnapshot中保存兼容清单供转换器验证。
4. 将验证后的新SPC作为额外输入安装，命名PSO_Coverage01_ActionRoguelike_PCD3D_SM6.spc；保留原SPC，不把两份组合数相加当最终数量。PackageBundled会读取并合并两份，再验收Expanded包。
5. 两版必须EXE相同，.ucas/.utoc资源容器Hash相同；PAK因运行时缓存不同可以变化。不能直接拿修改前的历史包与修改后包当缓存单变量比较。

## 对照命令（PowerShell）

```powershell
& 'F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\RunCoverageIteration.ps1' -ControlManifest 'Control acceptance.json' -CandidateManifest 'Expanded acceptance.json'
& 'F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\RunCoverageIteration.ps1' -ControlManifest 'Control acceptance.json' -CandidateManifest 'Expanded acceptance.json' -Execute -Repeats 3
```

默认预览。正式执行两版Bundled/Combined各3次冷请求，共12次原路线运行；交替版本顺序。追加两次仅Bundled的扩展夹具诊断（每版一次），共14次。这里聚焦冷启动，不重复阶段5热矩阵。每次独立UserDir并传clearPSODriverCache；清理是否彻底未独立证明。若任一运行失败，停止并保留证据，不放宽条件。

结果位于Saved/PSOCoverage/Comparisons/<时间_标识>。运行完成后：

```powershell
& 'F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\AnalyzeCoverageIteration.ps1' -EvidencePath '对照目录' -Repeats 3
```

输出技能中位数与极值、进程到路线开始时间、批次数量/墙钟，以及扩展52—136秒区间Max/P95/长帧计数。夹具诊断每版仅1次，包含同步加载、模拟和视角变化，不能将差值全部归因于PSO。

## 已遇到的兼容问题

- 全目录Cook发现LeverBP直接读取并通过可写引用访问ActiveGameplayTags。先尝试只读仍失败，最终恢复该Transient属性的BlueprintReadWrite兼容访问；未改变能力系统算法。此Demo内容兼容改动不应照搬Loki。
- TargetDummy在夹具点因碰撞拒绝生成，首轮20个效果但仅6类道具，严格验收失败；改为测试夹具AlwaysSpawn，重新构建并完整重采。
- PackageBundled曾使用PowerShell自动变量$Input作为循环变量，PowerShell7嵌套管线导致SPC日志匹配误判。改名SpcInput，保留失败验收，不手改为成功；重新Cook/打包验证。

数量以实际去重后的运行时缓存为准，不以达到1000为目标制造无关排列。后续更多地图、画质档位、角色或真正玩法分支需要各自的覆盖用例与来源标记。

首轮结果见PSO-COVERAGE-ITERATION-REPORT.md。AnalyzeCoverageTraces.ps1 -EvidencePath '对照目录' 可在游戏全部结束后，用定制Insights离线导出两次夹具Probe的前155秒相关Scope；默认程序可用-InsightsExe覆盖。按首Tick近似对齐52—136秒，不把嵌套/并行Scope耗时相加，也不把Tick的400ms上限当作真实最大停顿。首版要求路径无空格。
