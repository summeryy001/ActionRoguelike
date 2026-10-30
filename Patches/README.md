# UE 5.8 PSO thread pool ownership 修复

## 当前采用官方修复（2026-10-30）

Epic 官方提交：aa697db65d45a27da969b4b4aa850df732b2325f（PSO thread pool tears down inner thread pool also.）。本地公司引擎分支 fix/pso-thread-pool-official，移植提交 04e066ad1c。通过 cherry-pick --no-commit 引入，再用中文说明提交；保留官方作者及原 SHA。

当前补丁快照为 UE58-PSOPrecache-official-aa697db.diff。与旧方案相同，先销毁 Wrapper，再销毁底层线程池；官方还增加 ShutdownThreadPool 的 LockCS 和 bHasShutdown 检查。不要与旧补丁叠加应用。当前本机引擎已替换为官方实现。

旧补丁只作为阶段 2 历史保留，下面的 TUniquePtr 描述和“当前已应用”表述仅指当时状态。后续部署优先通过公司引擎修复分支/MR；手工补丁仅用于缺少提交对象时的回移。验证结果见 ../PSO-WORKFLOW.md。

## 阶段 2 历史补丁

补丁：UE58-PSOPrecache-owned-thread-pool.patch。

本地引擎基线：5067c2640998f39caf2960b88727d8938a863a55，目录 F:/Git_Repository/4399-unreal/unrealengine-4399。仅修改 Runtime/RHI/Private/PipelineStateCache.cpp。

PSO 系统自行创建底层线程池，FQueuedThreadPoolWrapper 并不拥有其底层池。原 ShutdownThreadPool 仅销毁 wrapper，留下 PSO 工作线程；CPU Trace 动态事件名称缓冲区所用的两页 MemStack 内存未被 TLS 清理，最终触发 FPageAllocator 静态析构检查。随后 crash reporting thread 再次异常，进程返回 777003，普通日志无法显示最初检查。

修复使用 TUniquePtr 保存 PSO 私有底层池，先销毁 wrapper 排空任务，再释放底层池并等待线程退出。未修改通用 wrapper 的非 owning 约定，不禁用 CPU Trace 或检查。

在匹配引擎工作区用 git apply --check 检查后应用，重新编译 Editor 和 Game，再打包。当前本机已应用；不要重复应用。git apply --reverse --check 可验证该补丁是否已完整应用，只有明确需要回退时才执行 reverse。共享引擎的后续构建会包含补丁，现有 Client2 包没有被更新。

验证记录和运行批次见 ../PSO-WORKFLOW.md。临时分配栈诊断与无效候选修复均未保留在引擎功能代码中。
