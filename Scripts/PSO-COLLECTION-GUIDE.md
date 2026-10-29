# AR2 Bundled PSO 采集工作流

第一步启用 Config/DefaultEngine.ini 的 DevOptions.Shaders/NeedsShaderStableKeys=true，bShareMaterialShaderCode 保持 true。使用本地 UE 5.8：

```bat
call "F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\PackageCollection.local.bat" -Execute
```

不传 Execute 只准备命令。采集包单独保存在 Saved/PSOCollection/Package，Cook日志、SHK快照、SHA256和来源保存在 Saved/PSOCollection/Cooks。current-cook.json 关联最新成功 Cook。阶段2包保留在原 PSOValidation/Package 位置。

第二步退出其他 UE 编辑器/游戏，再执行：

```bat
call "F:\Git_Repository\summeryy001\ActionRoguelike2\Scripts\CollectPSO.local.bat" -Execute
```

脚本校验匹配的EXE和SHK，运行DX12 SM6固定路线，以独立UserDir录制。自动预缓存关闭；ShaderPipelineCache.Enabled=1是为了记录，StartupMode=0暂停预编译；LogPSO/SaveBoundPSOLog开启、ExcludePrecachePSO=0。本步骤不是冷缓存性能测试，不请求删除驱动缓存。验收需正常退出、六项动作成功、实际配置一致及非空 .rec.upipelinecache。

原始记录、匹配的SM6 SHK、日志、Trace和SHA256位于 Saved/PSOCollection/Recordings。初次路线样本不代表全游戏覆盖。转换时必须同时使用匹配的 Global 与 ActionRoguelike SM6 SHK，不能混用其他Cook、其他引擎格式或SM5键。下一步通过 ShaderPipelineCacheTools expand 转为 .spc，再作为 Build/Windows/PipelineCaches 输入重新Cook。
