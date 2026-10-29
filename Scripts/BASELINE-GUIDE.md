# AR2 阶段 1：关闭预缓存的冷／热基线

## 使用

CMD 预览（默认三对，不启动游戏、不清缓存）：

```bat
call "F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\RunBaseline.local.bat"
```

保存并关闭 UE 编辑器和游戏后，执行三对测试：

```bat
call "F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\RunBaseline.local.bat" -Execute -Pairs 3
```

建议首次先用 `-Execute -Pairs 1` 验证整个采样链路。每轮约 56 秒游戏流程加启动和退出时间。脚本按 Cold01 → Warm01 → Cold02 → Warm02 顺序执行。使用包内实际游戏 EXE，避免外层启动器退出被误判为游戏结束。无需重新编译或 Cook。

## 条件与边界

- DX12 / SM6、1280×720、关闭 VSync 和帧率上限；Auto / Global precache / Bundled / Validation / ProxyStrategy 均显式设为 0，并从日志检查实际值。
- 直接进入 TestLevel?listen，调用已有 PSOValidation actor。不是从主菜单点击 Host Game 的启动计时。
- 5/10/16 秒首次释放 Primary / Blackhole / Dash；23/28/34 秒重复；随后有敌人死亡、拾取、角色死亡和复活检查，56 秒结束。
- 不注入按键；使用现有 Gameplay Action 调用。角色按最近敌人瞄准，AI 和目标选择并不完全确定，不能宣称场景逐帧一致。
- 每轮使用独立 UserDir，隔离存档与应用用户缓存。Cold 请求 `-clearPSODriverCache`，Warm 不请求；两者共享驱动缓存。目录前后快照不证明清理彻底成功，manifest 始终明确 `DriverCacheClearVerified=false`。
- 自动检测常见 UE 进程；其他 GPU 应用需要操作者自行关闭。不要在批次中途打开编辑器、修改包或操作测试游戏。后台模式不等同于手工前台操作环境。
- 本轮无 `-logPSO`。已有测试 actor 结束时会调用 Save，但 Bundled 缓存处于关闭状态；本阶段不作为 PSO 采集步骤。

## 输出与验收

每个批次位于 `Saved/PSOBaseline/<时间_唯一编号>`，不进入 Git：

- `package.json`：整个运行包文件 SHA256（排除 Saved 和 PDB），每轮前及批次结束重新核对。
- 每轮 `manifest.json`：参数、源码 revision、工作区状态、预期配置和缓存限制。
- `game.log`、`capture.utrace`、`frames.csv`：日志、Insights Trace 和 actor Tick DeltaSeconds 帧数据。
- `cache-before.json` / `cache-after.json`：三个 NVIDIA 缓存候选目录的文件名、大小、UTC 时间快照，不修改这些目录。
- `acceptance.json`：退出码、六次技能是否成功、配置实际值、初始化日志计时（无法解析则 null）。缺失 Trace、技能失败、复活失败或 Ensure/Fatal 时停止批次，不悄悄替换失败样本。
- `skill-frames.csv`：每次技能书签后两秒窗口相交帧的最大 Tick DeltaSeconds。这是游戏 Tick 采样，不等同于 GPU 帧时间，也不能直接归因于 PSO。须结合 Insights 的 CPU Frame、PSO 创建及等待事件分析。

`ProcessWallSeconds` 是整个测试进程生存时间，不是启动耗时。`EngineReportedInitSeconds` 是引擎日志报告的初始化时间，也不是严格的进程到可交互耗时。整体启动应结合 Trace 的初始化范围与 MapReady 书签另行分析。

300 秒超时会终止脚本自己启动的测试进程并标记失败。正式报告必须保留失败记录、说明冷缓存限制，并核对包 Hash、实际配置与 Trace 后再给结论。

## 本次验证状态

已通过 PowerShell 语法解析和一对 Cold/Warm 的 dry run。尚未运行真实自动批次；因此实际 CVar 日志解析、自动动作及 Trace 内容仍需首次执行确认。只准备脚本，没有清理驱动缓存。

## 阶段 2 自动预缓存对照

配置已开启 r.PSOPrecaching=1、GlobalShaders=1、Validation=2、ProxyCreationStrategy=1；Bundled 仍为 0。重新打包后先执行一对验证：

```bat
call "F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\RunBaseline.local.bat" -Execute -Pairs 1 -Profile Auto
```

验收后正式三对将 Pairs 改为 3。未指定 Profile 时仍使用 Baseline 全关闭覆盖值；必须显式指定 Auto。ProxyCreationStrategy=1 允许未就绪对象延迟代理创建，不能把画面暂时缺失当成完整覆盖；需结合 Validation、日志与 Insights。
