#include "Performance/PSOStartupOverlay.h"
#include "PSOStartupDiagnostics.h"
#include "CanvasItem.h"
#include "Debug/DebugDrawService.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "Engine/GameViewportClient.h"
#include "Engine/World.h"
#include "HAL/IConsoleManager.h"
#include "PipelineStateCache.h"
#include "ShaderPipelineCache.h"

namespace PSOStartupOverlay
{
#if !UE_BUILD_SHIPPING
    static TAutoConsoleVariable<int32> ShowPanel(TEXT("pso.StartupCheck"), 1,
        TEXT("AR development PSO startup diagnostics: 0 hidden, 1 visible. Does not block loading."));
    static FDelegateHandle DrawHandle;
    static bool bLoggedVisible = false;

    static int32 ReadCVar(const TCHAR* Name)
    {
        const IConsoleVariable* Variable = IConsoleManager::Get().FindConsoleVariable(Name);
        return Variable ? Variable->GetInt() : -1;
    }

    static void Toggle()
    {
        ShowPanel.AsVariable()->Set(ShowPanel.GetValueOnGameThread() ? 0 : 1, ECVF_SetByConsole);
    }
    static FAutoConsoleCommand ToggleCommand(TEXT("PSO.ToggleStartupCheck"), TEXT("Toggle AR PSO startup self-check panel (Ctrl+F7)."),
        FConsoleCommandDelegate::CreateStatic(&Toggle));

    static void Draw(UCanvas* Canvas, APlayerController*)
    {
        if (!ShowPanel.GetValueOnGameThread() || !Canvas || !Canvas->Canvas || !GEngine ||
            !GEngine->GameViewport || !GEngine->GameViewport->GetWorld() || !GEngine->GameViewport->GetWorld()->IsGameWorld())
        {
            return;
        }
        const auto Snapshot = PSOStartupDiagnostics::GetSnapshot();
        const int32 PendingBundled = PSOStartupDiagnostics::GetRemainingBundledPSOs();
        const uint32 PendingPrecache = PipelineStateCache::NumActivePrecacheRequests();
        const FPSORuntimeCreationStats Runtime = PipelineStateCache::GetPSORuntimeCreationStats();
        const int32 Auto = ReadCVar(TEXT("r.PSOPrecaching"));
        const int32 Bundled = ReadCVar(TEXT("r.ShaderPipelineCache.Enabled"));
        TArray<FString> Lines;
        Lines.Add(TEXT("PSO STARTUP CHECK  |  Ctrl+F7 / PSO.ToggleStartupCheck"));
        Lines.Add(FString::Printf(TEXT("Config: Auto=%d  Bundled=%d  Validation=%d  ProxyStrategy=%d"), Auto, Bundled,
            ReadCVar(TEXT("r.PSOPrecache.Validation")), ReadCVar(TEXT("r.PSOPrecache.ProxyCreationStrategy"))));
        if (!Bundled)
        {
            Lines.Add(TEXT("Bundled: DISABLED (not a completed-cache result)"));
        }
        else if (Snapshot.IsEmpty())
        {
            Lines.Add(TEXT("Bundled: NO BEGIN EVENT / no observed eligible cache"));
        }
        for (const FPSOStartupCacheStatus& Status : Snapshot)
        {
            const double Wall = (Status.bFinished ? Status.EndSeconds : FPlatformTime::Seconds()) - Status.BeginSeconds;
            Lines.Add(FString::Printf(TEXT("%s: %s  processed=%u / queued=%u  wall=%.3fs"), *Status.Name,
                Status.bFinished ? TEXT("FINISHED") : TEXT("COMPILING"), Status.Completed, Status.Queued, Wall));
        }
        Lines.Add(FString::Printf(TEXT("Queues: bundled remaining=%d  auto/shared precache pending=%u"), PendingBundled, PendingPrecache));
        Lines.Add(FString::Printf(TEXT("Runtime creates=%u  slow creates G/C=%u/%u (excludes auto jobs)"),
            Runtime.TotalPSOCreations, Runtime.GraphicsPSOHitches, Runtime.ComputePSOHitches));
        Lines.Add(TEXT("Queue finished != full coverage. Hit/Miss/TooLate: stat PSOPrecache"));

        const float Scale = FMath::Clamp((Canvas->ClipX - 32.f) / 740.f, 0.5f, 1.f);
        // Leave room for the main menu's existing on-screen compile message.
        const float X = 16.f, Y = 140.f;
        FCanvasTileItem Background(FVector2D(X - 6, Y - 6), FVector2D(740 * Scale, (Lines.Num() * 20 + 12) * Scale), FLinearColor(0.015f, 0.02f, 0.03f, 0.88f));
        Background.BlendMode = SE_BLEND_Translucent;
        Canvas->DrawItem(Background);
        for (int32 Index = 0; Index < Lines.Num(); ++Index)
        {
            FCanvasTextItem Text(FVector2D(X, Y + Index * 20 * Scale), FText::FromString(Lines[Index]), GEngine->GetSmallFont(),
                Index == 0 ? FLinearColor(0.3f, 0.9f, 1.f) : FLinearColor::White);
            Text.Scale = FVector2D(Scale, Scale);
            Text.EnableShadow(FLinearColor::Black);
            Canvas->DrawItem(Text);
        }
        if (!bLoggedVisible)
        {
            bLoggedVisible = true;
            UE_LOG(LogTemp, Display, TEXT("PSOStartupCheck: ScreenVisible caches=%d bundledPending=%d precachePending=%u"), Snapshot.Num(), PendingBundled, PendingPrecache);
        }
    }
#endif

    void Startup()
    {
#if !UE_BUILD_SHIPPING
        DrawHandle = UDebugDrawService::Register(TEXT("Game"), FDebugDrawDelegate::CreateStatic(&Draw));
#endif
    }

    void Shutdown()
    {
#if !UE_BUILD_SHIPPING
        UDebugDrawService::Unregister(DrawHandle);
#endif
    }
}
