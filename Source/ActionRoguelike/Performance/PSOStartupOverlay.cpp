#include "Performance/PSOStartupOverlay.h"
#include "Engine/Engine.h"
#include "HAL/IConsoleManager.h"

// Preserve the old command for existing local input configurations.
// The portable PSOWorkbench Runtime module now owns drawing and Ctrl+F7.
namespace PSOStartupOverlay
{
#if !UE_BUILD_SHIPPING
    static void Toggle()
    {
        if(GEngine)GEngine->Exec(nullptr,TEXT("PSOWB.CycleOverlay"));
    }
    static FAutoConsoleCommand ToggleCommand(TEXT("PSO.ToggleStartupCheck"),
        TEXT("Compatibility alias for PSOWB.CycleOverlay (Ctrl+F7)."),FConsoleCommandDelegate::CreateStatic(&Toggle));
#endif
    void Startup() {}
    void Shutdown() {}
}