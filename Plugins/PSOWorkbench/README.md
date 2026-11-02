# PSO 工作台 0.1

入口：AR2 编辑器“工具 → 渲染工作流 → PSO 工作台”。Windows DX12/SM6 Development 首版，Android仅预留，不会执行不完整流程。

## 使用流程

1. 设置方案名称、缓存组、运行地图与Cook地图。AR2默认TestLevel和现有自动路线；其他C++项目默认手动采集，Game目标默认工程名，可在高级设置覆盖。
2. 保存方案。逻辑方案保存在Config/PSOWorkbench/Profiles；引擎和Insights本机路径保存在编辑器用户配置，不随方案提交。
3. 点击检查配置。需要时应用构建配置：备份DefaultEngine.ini/DefaultGame.ini，仅启用Stable Keys、共享Shader代码和Native Libraries。未更改项目默认PSO运行模式。
4. 构建采集包：自动构建Game、Cook、归档EXE与匹配SHK。编辑器可以保持打开，不链接Editor DLL。构建前会提示保存脏资源。
5. 运行采集：选择完整/补缺/隔离策略。手动模式正常游玩覆盖，结束时点击“结束当前游戏并保存记录”；自动模式使用项目适配路线及完成标记。每次独立用户目录、日志和Trace。
6. 转换：自动筛选当前采集包的有效会话，核对记录与SHK Hash，调用引擎expand。安装：按方案/缓存组命名SPC，备份同名旧输入，保留项目其他输入。
7. 构建Bundled包：Cook合并项目匹配输入，保存运行时缓存与数量，核对PAK清单。
8. 运行验收：选择关闭/自动/Bundled/Combined模式，可选Fast或后台目标预算。驱动清理默认关闭，勾选后启动前会确认。检查实际设置、退出及目标缓存批次，不把队列0当作完成证明。
9. Insights分析：高级设置选择UnrealInsights.exe，或首次启动编辑器前设置PSOWORKBENCH_INSIGHTS环境变量。后台解析最近验收（或最近采集）Trace并导出前15秒相关CPU Scope。

任务互斥，同一项目仅允许一个工作台后台任务。编辑器显示阶段状态、原始日志尾部、成功产物摘要及具体错误。失败不替换上一次成功产物，可修正后重试该步骤。关闭面板不主动终止后台构建；重新打开编辑器后可读取方案成功产物。首版不提供构建强制中止或后台任务重连UI。

## 产物与平台

任务及完整证据：项目/Saved/PSOWorkbench/Jobs。方案状态：项目/Saved/PSOWorkbench/Profiles/<方案>/state.json。路径基于uproject，不受启动编辑器的UserDir影响。

Runtime模块仅在带PSOWorkbenchSession启动参数时记录Begin/Complete和退出摘要，并响应stop.request进行保存、停止Trace与正常退出。它不增加正常游戏Loading门控，也不实现“未就绪自动隐藏”。

缓存组当前用于输入命名和来源记录，所有匹配SPC仍按引擎默认规则合并。按场景/玩家进度过滤、Chunk/UsageMask、CDN挂载和Runtime分组调度尚未实现。补缺集合不能未经覆盖验证就当作BundledOnly的完整集合。

Android已保留平台选项和任务入口边界，但设备选择、部署、采集回收、移动Shader格式及APK构建尚未实现，UI明确禁用。当前未验收SM5、其他RHI、Shipping或蓝图-only项目的构建目标推导。

## 移植与依赖

复制插件到目标C++项目Plugins并启用，重新编译该项目Editor/Game。后端脚本随插件携带，不依赖AR2旧Scripts目录；运行时记录不依赖AR2的PSOStartupDiagnostics模块。目标地图、动态资源Cook输入与自动路线需要按业务在UI配置，AR2缓存不能直接复制使用。

本地UE5.8引擎已包含Epic aa697db65d45a27da969b4b4aa850df732b2325f线程池销毁修复；未修复引擎在Auto+Trace退出上有已知风险。其他引擎版本需单独验证。PowerShell后端使用UTF-8 BOM以支持Windows PowerShell5，读取请求/INI显式按UTF-8，Launch包装器保留启动错误。

所有性能数据仅对当次构建/运行配置成立。驱动清理为请求，不保证完全成功；批次完成不是全局就绪或全游戏覆盖；并行CPU Scope数量和耗时之和不是独立PSO数量或墙钟时间。
