#include "Modules/ModuleManager.h"
#include "Containers/Ticker.h"
#include "Engine/Engine.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/CoreDelegates.h"
#include "Misc/ScopeLock.h"
#include "HAL/FileManager.h"
#include "ShaderPipelineCache.h"
#include "PipelineStateCache.h"
#include "ProfilingDebugging/MiscTrace.h"
#include "Serialization/JsonSerializer.h"
#include "Dom/JsonObject.h"

DEFINE_LOG_CATEGORY_STATIC(LogPSOWorkbench, Log, All);

class FPSOWorkbenchRuntimeModule : public IModuleInterface
{
    struct FBatch { uint32 Queued=0, Processed=0; double Begin=0, Wall=0; bool Complete=false; };
    FCriticalSection Mutex;
    TMap<FString, FBatch> Batches;
    FString Session;
    FDelegateHandle BeginHandle, CompleteHandle, ExitHandle;
    FTSTicker::FDelegateHandle TickHandle;
    bool Stopping=false;

    void Begin(uint32 Count, const FShaderPipelineCache::FShaderCachePrecompileContext& Context)
    {
        FScopeLock Lock(&Mutex);
        Batches.Add(Context.GetCacheName(), {Count,0,FPlatformTime::Seconds(),0,false});
        UE_LOG(LogPSOWorkbench, Display, TEXT("Begin cache=%s queued=%u"), *Context.GetCacheName(), Count);
        TRACE_BOOKMARK(TEXT("PSOWorkbench Begin %s queued=%u"), *Context.GetCacheName(), Count);
    }
    void Complete(uint32 Count, double Submission, const FShaderPipelineCache::FShaderCachePrecompileContext& Context)
    {
        FScopeLock Lock(&Mutex);
        if (FBatch* Batch=Batches.Find(Context.GetCacheName()))
        {
            Batch->Processed=Count; Batch->Wall=FPlatformTime::Seconds()-Batch->Begin; Batch->Complete=true;
            UE_LOG(LogPSOWorkbench, Display, TEXT("Complete cache=%s processed=%u wall=%.6f submission=%.6f"), *Context.GetCacheName(),Count,Batch->Wall,Submission);
        }
        TRACE_BOOKMARK(TEXT("PSOWorkbench Complete %s processed=%u"), *Context.GetCacheName(),Count);
    }
    void SaveSummary()
    {
        FScopeLock Lock(&Mutex);
        TSharedRef<FJsonObject> Root=MakeShared<FJsonObject>();
        TArray<TSharedPtr<FJsonValue>> Values;
        for(const auto& Pair:Batches)
        {
            TSharedRef<FJsonObject> Item=MakeShared<FJsonObject>();
            Item->SetStringField(TEXT("name"),Pair.Key);
            Item->SetNumberField(TEXT("queued"),Pair.Value.Queued);
            Item->SetNumberField(TEXT("processed"),Pair.Value.Processed);
            Item->SetNumberField(TEXT("wallSeconds"),Pair.Value.Wall);
            Item->SetBoolField(TEXT("complete"),Pair.Value.Complete);
            Values.Add(MakeShared<FJsonValueObject>(Item));
        }
        Root->SetArrayField(TEXT("batches"),Values);
        Root->SetBoolField(TEXT("stopRequested"),Stopping);
        FString Json;
        FJsonSerializer::Serialize(Root,TJsonWriterFactory<>::Create(&Json));
        IFileManager::Get().MakeDirectory(*Session,true);
        FFileHelper::SaveStringToFile(Json,*(Session/TEXT("runtime-summary.json")),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
    }
    bool Tick(float)
    {
        if(!Stopping && IFileManager::Get().FileExists(*(Session/TEXT("stop.request"))))
        {
            Stopping=true;
            UE_LOG(LogPSOWorkbench,Display,TEXT("Graceful stop requested by workbench"));
            PipelineStateCache::WaitForAllTasks();
            if(GEngine) { GEngine->Exec(nullptr,TEXT("r.ShaderPipelineCache.Save")); GEngine->Exec(nullptr,TEXT("Trace.Stop")); }
            SaveSummary();
            FPlatformMisc::RequestExit(false);
        }
        return true;
    }
public:
    void StartupModule() override
    {
        if(!FParse::Value(FCommandLine::Get(),TEXT("PSOWorkbenchSession="),Session)) return;
        BeginHandle=FShaderPipelineCache::GetPrecompilationBeginDelegate().AddRaw(this,&FPSOWorkbenchRuntimeModule::Begin);
        CompleteHandle=FShaderPipelineCache::GetPrecompilationCompleteDelegate().AddRaw(this,&FPSOWorkbenchRuntimeModule::Complete);
        ExitHandle=FCoreDelegates::OnPreExit.AddRaw(this,&FPSOWorkbenchRuntimeModule::SaveSummary);
        TickHandle=FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateRaw(this,&FPSOWorkbenchRuntimeModule::Tick),0.25f);
        UE_LOG(LogPSOWorkbench,Display,TEXT("Session observer registered: %s"),*Session);
    }
    void ShutdownModule() override
    {
        FShaderPipelineCache::GetPrecompilationBeginDelegate().Remove(BeginHandle);
        FShaderPipelineCache::GetPrecompilationCompleteDelegate().Remove(CompleteHandle);
        FCoreDelegates::OnPreExit.Remove(ExitHandle);
        FTSTicker::GetCoreTicker().RemoveTicker(TickHandle);
    }
};
IMPLEMENT_MODULE(FPSOWorkbenchRuntimeModule,PSOWorkbenchRuntime)
