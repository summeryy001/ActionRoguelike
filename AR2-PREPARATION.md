# AR2 preparation baseline

Prepared 2026-10-29 from the local ActionRoguelike working tree, including its uncommitted gameplay fixes. This is a separate filesystem copy, not a new Git repository or remote branch. Internal project/module names remain ActionRoguelike.

Excluded: .git, Binaries, Intermediate, Saved, DerivedDataCache, CollectedPSOs, Build, old Scripts, and all *.spc / *.shk / *.upipelinecache files. Original AR is unchanged.

DefaultEngine.ini now explicitly disables automatic PSO precaching, global shader precaching, bundled pipeline cache, validation and fallback strategy. Stable shader key generation is false for this initial preparation stage. Existing diagnostics and opt-in test actors remain available; they are not evidence that precaching is enabled. Shared shader code packaging remains enabled as normal shader infrastructure.

Use Scripts/StartEditor.local.bat and Scripts/StartGame.local.bat to isolate user data. Launching the identically named project/game outside these scripts may share default user directories with AR. System GPU driver cache and engine/shared DDC are not isolated or cleared.

Next workflow: build baseline -> enable NeedsShaderStableKeys for first collection Cook -> record packaged gameplay with -logPSO and recording enabled -> convert matching .rec.upipelinecache + .shk to .spc -> second Cook generates runtime .stable.upipelinecache -> compare disabled / automatic / bundled / combined with verified effective CVars.

No prior AR report or package is copied. No AR2 Cook or cold-cache performance measurements have been performed at preparation time.

Preparation verification: all 1,949 copied Content/Source files matched the original AR byte-for-byte (SHA256). Removed the old fallback-demo MapsToCook and Materials AlwaysCook additions; demo source/assets remain available but are no longer explicitly included by packaging settings. Baseline packaging is available through Scripts/PackageBaseline.local.bat after Build.local.bat; it does not automatically enable stable keys or record PSOs.

Build validation: Editor and Win64 Development game targets both succeeded with the local UE engine (458.24 seconds). See Saved/Preparation/Build.log. Native EXE exists under Binaries/Win64 but is not a distributable package: no Cook/stage has been run. Final PSO artifact scan found zero .spc/.shk/.upipelinecache files. Interactive editor launch and packaged runtime validation are pending the next phase.

Git update (2026-10-29): initialized a local repository on branch pso-workflow after preparation. No remote configured. See PSO-WORKFLOW.md and AGENTS.md for staged local-commit policy.
