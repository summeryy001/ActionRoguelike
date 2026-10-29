#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "Engine/World.h"
#include "HAL/IConsoleManager.h"

#if !UE_BUILD_SHIPPING
namespace PerformanceOverlay
{
	void Toggle(UWorld* World)
	{
		if (World == nullptr || GEngine == nullptr)
		{
			return;
		}

		UGameViewportClient* const GameViewport = World->GetGameViewport();
		if (GameViewport == nullptr)
		{
			return;
		}

		const bool bShow = !(GameViewport->IsStatEnabled(TEXT("FPS"))
			&& GameViewport->IsStatEnabled(TEXT("Unit"))
			&& GameViewport->IsStatEnabled(TEXT("UnitGraph")));
		const TArray<FString> StatNames = {TEXT("FPS"), TEXT("Unit"), TEXT("UnitTime"), TEXT("UnitGraph")};
		GEngine->SetEngineStats(World, GameViewport, StatNames, bShow);
	}

	static FAutoConsoleCommandWithWorld ToggleCommand(
		TEXT("Perf.ToggleOverlay"),
		TEXT("Toggle FPS, unit timings/memory and unit graph for this game viewport (Ctrl+F8)."),
		FConsoleCommandWithWorldDelegate::CreateStatic(&PerformanceOverlay::Toggle));
}
#endif

