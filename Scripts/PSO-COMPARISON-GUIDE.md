# 阶段 5：同包四模式冷/热对照

使用阶段4 current-build.json 指定的同一包，不重新编译或Cook。工具仅测固定时间释放路线（5/10/16秒首次技能），不添加新的就绪门控。每种模式3对冷/热，共24个有效运行。

```cmd
call "F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\RunComparison.local.bat"
call "F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\RunComparison.local.bat" -Execute -Pairs 3
```

默认仅生成命令和清单。执行会在每次Cold传 -clearPSODriverCache，紧接着Warm不传；这是清理请求，不证明清理完全成功。本地引擎清理 Local/NVIDIA/DXCache 和 LocalLow/NVIDIA/PerDriverVersion/DXCache，未覆盖旧的 LocalLow/NVIDIA/DXCache。脚本只调用引擎参数，不额外手动删除用户文件。运行前关闭所有UE编辑器/游戏。

四个 Profile：Baseline Auto0/Bundled0、Auto Auto1/Bundled0、Bundled Auto0/Bundled1、Combined Auto1/Bundled1。Auto相关模式 GlobalShaders1/Validation2/ProxyCreationStrategy1；其余为0。所有模式 StartupMode1、SaveUserCache0、DX12 SM6、窗口1280x720、VSync0、MaxFPS0。测试的是这些实际配置组合，不把代理或Validation的差异从结果中隐藏。

按重复轮次轮换 Profile 执行顺序，Cold/Warm 始终相邻。每次独立UserDir；比较包内容Hash并记录驱动目录前后快照，Bundled相关模式要求观察到目标缓存正数Begin和匹配Complete。全部技能、复活和退出成功才计为有效。仅对正常退出但技能未成功启动的情况尝试重跑整对，最多3次；所有尝试都保存，正式统计只使用完整有效对。反复失败停止，不放宽条件。退出异常、断言和Bundled验收失败停止。

证据位于 Saved/PSOComparison/<时间_标识>，pairs.json记录有效与排除尝试；各Profile子目录保存两次运行的清单、acceptance、log、trace和帧数据。Trace较大，应留足磁盘。

执行结束后在 PowerShell 汇总：

```powershell
& 'F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\AnalyzeComparison.ps1' -EvidencePath '本次批次目录' -ExpectedPairs 3
```

分析器拒绝缺少任何模式/对、无效运行或包指纹不一致，输出24轮明细、48组技能窗口统计、中位数和极值，以及进程至路线开始时间、Bundled批次和慢PSO创建统计。首次/重复技能的2秒窗口最大Tick帧耗时包含所有工作；慢创建计数不是卡顿帧数；CPU并行事件耗时之和不等于墙钟时间。

Insights重点对照首攻附近慢帧、PSOPrecache及驱动创建路径，Bundled事件用目标库Begin/Complete旁证。队列完成不表示全游戏覆盖。启动时间与首次技能帧耗时一起看，避免只看到技能改善而忽略前移等待。
