#include "PSOStartupDiagnostics.h"
#include "Modules/ModuleManager.h"
#include "Misc/ScopeLock.h"
#include "ProfilingDebugging/MiscTrace.h"
#include "ShaderPipelineCache.h"
#include "HAL/IConsoleManager.h"

DEFINE_LOG_CATEGORY_STATIC(LogPSOStartupCheck, Log, All);

namespace
{
    FCriticalSection StatusMutex;
    TMap<FString, FPSOStartupCacheStatus> Statuses;
}

TArray<FPSOStartupCacheStatus> PSOStartupDiagnostics::GetSnapshot()
{
    FScopeLock Lock(&StatusMutex);
    TArray<FPSOStartupCacheStatus> Result;
    Statuses.GenerateValueArray(Result);
    Result.Sort([](const auto& A, const auto& B) { return A.Name < B.Name; });
    return Result;
}

int32 PSOStartupDiagnostics::GetRemainingBundledPSOs()
{
    const IConsoleVariable* Enabled = IConsoleManager::Get().FindConsoleVariable(TEXT("r.ShaderPipelineCache.Enabled"));
    if (!Enabled || Enabled->GetInt() == 0)
    {
        return -1;
    }
    // Do not hold StatusMutex when querying the engine: its callbacks acquire
    // this mutex while the engine's pipeline-cache mutex is held.
    const auto Snapshot = GetSnapshot();
    bool bHadTasks = false;
    bool bWaitingForCompletion = false;
    for (const FPSOStartupCacheStatus& Status : Snapshot)
    {
        if (Status.Queued > 0)
        {
            bHadTasks = true;
            bWaitingForCompletion |= !Status.bFinished;
        }
    }
    if (!bHadTasks)
    {
        return -1;
    }
    const int32 Remaining = static_cast<int32>(FShaderPipelineCache::NumPrecompilesRemaining());
    return bWaitingForCompletion ? FMath::Max(1, Remaining) : Remaining;
}

class FPSOStartupDiagnosticsModule : public IModuleInterface
{
    FDelegateHandle BeginHandle;
    FDelegateHandle CompleteHandle;

    void OnBegin(uint32 Count, const FShaderPipelineCache::FShaderCachePrecompileContext& Context)
    {
        const double Now = FPlatformTime::Seconds();
        {
            FScopeLock Lock(&StatusMutex);
            FPSOStartupCacheStatus& Status = Statuses.FindOrAdd(Context.GetCacheName());
            Status = {Context.GetCacheName(), Count, 0, Now, 0, false};
        }
        UE_LOG(LogPSOStartupCheck, Display, TEXT("Begin cache=%s queued=%u clock=%.6f"), *Context.GetCacheName(), Count, Now);
        TRACE_BOOKMARK(TEXT("PSOStartupCheck: Begin %s count=%u"), *Context.GetCacheName(), Count);
    }

    void OnComplete(uint32 Count, double SubmissionSeconds, const FShaderPipelineCache::FShaderCachePrecompileContext& Context)
    {
        const double Now = FPlatformTime::Seconds();
        double WallSeconds = -1;
        {
            FScopeLock Lock(&StatusMutex);
            if (FPSOStartupCacheStatus* Status = Statuses.Find(Context.GetCacheName()))
            {
                Status->Completed = Count;
                Status->EndSeconds = Now;
                Status->bFinished = true;
                WallSeconds = Now - Status->BeginSeconds;
            }
        }
        UE_LOG(LogPSOStartupCheck, Display, TEXT("Complete cache=%s processed=%u wallSeconds=%.6f submissionSeconds=%.6f clock=%.6f"),
            *Context.GetCacheName(), Count, WallSeconds, SubmissionSeconds, Now);
        TRACE_BOOKMARK(TEXT("PSOStartupCheck: Complete %s count=%u wall=%.3fs"), *Context.GetCacheName(), Count, WallSeconds);
    }

public:
    virtual void StartupModule() override
    {
        // PostConfigInit is earlier than shader-library open and PSO compilation.
        BeginHandle = FShaderPipelineCache::GetPrecompilationBeginDelegate().AddRaw(this, &FPSOStartupDiagnosticsModule::OnBegin);
        CompleteHandle = FShaderPipelineCache::GetPrecompilationCompleteDelegate().AddRaw(this, &FPSOStartupDiagnosticsModule::OnComplete);
        UE_LOG(LogPSOStartupCheck, Display, TEXT("Observer registered before shader libraries; observation only, no loading gate."));
    }

    virtual void ShutdownModule() override
    {
        FShaderPipelineCache::GetPrecompilationBeginDelegate().Remove(BeginHandle);
        FShaderPipelineCache::GetPrecompilationCompleteDelegate().Remove(CompleteHandle);
    }
};

IMPLEMENT_MODULE(FPSOStartupDiagnosticsModule, PSOStartupDiagnostics)
