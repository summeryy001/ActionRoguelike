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
