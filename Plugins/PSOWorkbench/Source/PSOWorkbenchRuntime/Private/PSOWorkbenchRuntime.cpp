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
#include "CanvasItem.h"
#include "Debug/DebugDrawService.h"
#include "Engine/Canvas.h"
#include "Engine/GameViewportClient.h"
#include "Engine/World.h"
#include "HAL/IConsoleManager.h"
#include "Framework/Application/IInputProcessor.h"
#include "Framework/Application/SlateApplication.h"
#include "UnrealClient.h"
#include "GameFramework/PlayerController.h"

#if !UE_BUILD_SHIPPING
static TAutoConsoleVariable<int32> OverlayMode(TEXT("PSOWB.Overlay"), 1,
    TEXT("PSO diagnostics: 0 hidden, 1 summary, 2 details. Ctrl+F7 cycles display only."));

static void CycleOverlay()
{
    const int32 Next=(FMath::Clamp(OverlayMode.GetValueOnGameThread(),0,2)+1)%3;
    OverlayMode.AsVariable()->Set(Next,ECVF_SetByConsole);
    UE_LOG(LogTemp,Display,TEXT("PSOWorkbench Overlay mode=%d (display only)"),Next);
    TRACE_BOOKMARK(TEXT("PSOWorkbench Overlay mode=%d"),Next);
}

class FPSOWorkbenchInput:public IInputProcessor
{
public:
    virtual void Tick(const float,FSlateApplication&,TSharedRef<ICursor>)override {}
    virtual bool HandleKeyDownEvent(FSlateApplication&,const FKeyEvent& Event)override
    {
        if(Event.GetKey()!=EKeys::F7 || !Event.IsControlDown() || Event.IsAltDown() || Event.IsShiftDown() || Event.IsRepeat() || !GEngine)return false;
        for(const FWorldContext& Context:GEngine->GetWorldContexts())
        {
            UWorld* World=Context.World();
            UGameViewportClient* Viewport=World ? World->GetGameViewport() : nullptr;
            // PIE must own keyboard focus; standalone UI menus also receive this shortcut.
            if(World && World->IsGameWorld() && Viewport && Viewport->Viewport &&
                (!GIsEditor || Viewport->Viewport->HasFocus()))
            {
                CycleOverlay();return true;
            }
        }
        return false;
    }
};
#endif

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
    FDelegateHandle InitHandle,DrawHandle;
#if !UE_BUILD_SHIPPING
    TSharedPtr<FPSOWorkbenchInput> Input;
    TUniquePtr<FAutoConsoleCommand> ToggleCommand;

    static int32 CVar(const TCHAR* Name)
    {
        // Engine CVars have process lifetime. Avoid repeated console-registry lookups per frame.
        static TMap<FName,const IConsoleVariable*> Variables;
        const IConsoleVariable** Found=Variables.Find(FName(Name));
        const IConsoleVariable* Value=Found ? *Found : IConsoleManager::Get().FindConsoleVariable(Name);
        if(!Found)Variables.Add(FName(Name),Value);
        return Value ? Value->GetInt() : -1;
    }
    void Draw(UCanvas* Canvas,APlayerController* Controller)
    {
        const int32 Mode=FMath::Clamp(OverlayMode.GetValueOnGameThread(),0,2);
        UWorld* World=Controller ? Controller->GetWorld() : nullptr;
        if(!Mode || !Canvas || !Canvas->Canvas || !GEngine || !World || !World->IsGameWorld())return;
        const int32 Auto=CVar(TEXT("r.PSOPrecaching"));
        const int32 Bundled=CVar(TEXT("r.ShaderPipelineCache.Enabled"));
        const uint32 Pending=PipelineStateCache::NumActivePrecacheRequests();
        const uint32 Remaining=FShaderPipelineCache::NumPrecompilesRemaining();
        TMap<FString,FBatch> Snapshot;
        {FScopeLock Lock(&Mutex);Snapshot=Batches;}
        TArray<FString> Lines;
        Lines.Add(FString::Printf(TEXT("PSO | Ctrl+F7: Summary > Details > Hidden | %s"),Mode==1 ? TEXT("SUMMARY") : TEXT("DETAILS")));
        Lines.Add(FString::Printf(TEXT("Effective: Auto=%d (%s)  Bundled switch=%d  Validation=%d"),Auto,
            PipelineStateCache::IsPSOPrecachingEnabled() ? TEXT("supported/enabled") : TEXT("OFF/unsupported"),Bundled,CVar(TEXT("r.PSOPrecache.Validation"))));
        Lines.Add(FString::Printf(TEXT("Selected switches: %s | -1 = unavailable"),
            Auto>0 ? (Bundled>0 ? TEXT("Combined") : TEXT("Auto only")) : (Bundled>0 ? TEXT("Bundled only") : TEXT("Both OFF"))));
        const TCHAR* State=Bundled==0 ? TEXT("DISABLED") : Snapshot.IsEmpty() ? TEXT("NO OBSERVED BATCH (not proof of completion)") : TEXT("OBSERVED");
        Lines.Add(FString::Printf(TEXT("Bundled: %s | engine remaining=%u | auto/shared pending=%u"),State,Remaining,Pending));
        TArray<FString> Names;Snapshot.GetKeys(Names);Names.Sort();
        for(const FString& Name:Names)
        {
            const FBatch& Batch=Snapshot[Name];
            Lines.Add(FString::Printf(TEXT("  %s: %s  processed=%u / queued=%u%s"),*Name,
                Batch.Complete ? TEXT("COMPLETE") : TEXT("RUNNING"),Batch.Processed,Batch.Queued,
                Batch.Complete ? TEXT("") : TEXT(" (processed updated on Complete)")));
            if(Mode==2)Lines.Add(FString::Printf(TEXT("  Batch wall=%.3fs"),Batch.Complete ? Batch.Wall : FPlatformTime::Seconds()-Batch.Begin));
        }
        if(Mode==2)
        {
            const FPSORuntimeCreationStats Stats=PipelineStateCache::GetPSORuntimeCreationStats();
            Lines.Add(FString::Printf(TEXT("Proxy: gate=%d strategy=%d | Bundle startup mode=%d"),
                CVar(TEXT("r.PSOPrecache.ProxyCreationWhenPSOReady")),CVar(TEXT("r.PSOPrecache.ProxyCreationStrategy")),CVar(TEXT("r.ShaderPipelineCache.StartupMode"))));
            Lines.Add(FString::Printf(TEXT("Renderer-requested creates=%u | slow G/C=%u/%u (not frame hitches)"),Stats.TotalPSOCreations,Stats.GraphicsPSOHitches,Stats.ComputePSOHitches));
            Lines.Add(FString::Printf(TEXT("Slow previously precached=%u | driver cache suspected unhealthy=%s"),Stats.PreviouslyPrecachedPSOHitches,Stats.bDriverCacheSuspectedUnhealthy ? TEXT("YES") : TEXT("NO")));
            Lines.Add(TEXT("Hit / Miss / TooLate: stat PSOPrecache (requires validation; zero may mean untracked)"));
            Lines.Add(TEXT("Counters are process-wide/cumulative. PIE shares editor history; not an isolated game run."));
        }
        Lines.Add(TEXT("Queue zero != full coverage. Display only; switches are NOT changed by this key."));
        const float Scale=FMath::Clamp((Canvas->ClipX-24.f)/940.f,0.35f,1.f);
        const float X=12.f,Y=140.f;
        FCanvasTileItem Background(FVector2D(X-4,Y-4),FVector2D(940*Scale,(Lines.Num()*19+8)*Scale),FLinearColor(0.01f,0.02f,0.03f,0.88f));
        Background.BlendMode=SE_BLEND_Translucent;Canvas->DrawItem(Background);
        for(int32 Index=0;Index<Lines.Num();++Index)
        {
            FCanvasTextItem Text(FVector2D(X,Y+Index*19*Scale),FText::FromString(Lines[Index]),GEngine->GetSmallFont(),Index==0 ? FLinearColor(0.3f,0.9f,1.f) : FLinearColor::White);
            Text.Scale=FVector2D(Scale,Scale);Text.EnableShadow(FLinearColor::Black);Canvas->DrawItem(Text);
        }
    }
    void StartUI()
    {
        if(IsRunningCommandlet() || IsRunningDedicatedServer())return;
        DrawHandle=UDebugDrawService::Register(TEXT("Game"),FDebugDrawDelegate::CreateRaw(this,&FPSOWorkbenchRuntimeModule::Draw));
        if(FSlateApplication::IsInitialized())
        {
            Input=MakeShared<FPSOWorkbenchInput>();FSlateApplication::Get().RegisterInputPreProcessor(Input);
        }
    }
#endif

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
        if(Session.IsEmpty())return;
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
        FParse::Value(FCommandLine::Get(),TEXT("PSOWorkbenchSession="),Session);
#if !UE_BUILD_SHIPPING
        ToggleCommand=MakeUnique<FAutoConsoleCommand>(TEXT("PSOWB.CycleOverlay"),TEXT("Cycle PSO overlay; does not change PSO switches."),FConsoleCommandDelegate::CreateStatic(&CycleOverlay));
        InitHandle=FCoreDelegates::GetOnPostEngineInit().AddRaw(this,&FPSOWorkbenchRuntimeModule::StartUI);
#else
        if(Session.IsEmpty())return;
#endif
        BeginHandle=FShaderPipelineCache::GetPrecompilationBeginDelegate().AddRaw(this,&FPSOWorkbenchRuntimeModule::Begin);
        CompleteHandle=FShaderPipelineCache::GetPrecompilationCompleteDelegate().AddRaw(this,&FPSOWorkbenchRuntimeModule::Complete);
        if(!Session.IsEmpty())
        {
            ExitHandle=FCoreDelegates::OnPreExit.AddRaw(this,&FPSOWorkbenchRuntimeModule::SaveSummary);
            TickHandle=FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateRaw(this,&FPSOWorkbenchRuntimeModule::Tick),0.25f);
        }
        UE_LOG(LogPSOWorkbench,Display,TEXT("Session observer registered: %s"),*Session);
    }
    void ShutdownModule() override
    {
#if !UE_BUILD_SHIPPING
        if(Input.IsValid() && FSlateApplication::IsInitialized())FSlateApplication::Get().UnregisterInputPreProcessor(Input);
        Input.Reset();ToggleCommand.Reset();UDebugDrawService::Unregister(DrawHandle);
        FCoreDelegates::GetOnPostEngineInit().Remove(InitHandle);
#endif
        FShaderPipelineCache::GetPrecompilationBeginDelegate().Remove(BeginHandle);
        FShaderPipelineCache::GetPrecompilationCompleteDelegate().Remove(CompleteHandle);
        FCoreDelegates::OnPreExit.Remove(ExitHandle);
        FTSTicker::GetCoreTicker().RemoveTicker(TickHandle);
    }
};
IMPLEMENT_MODULE(FPSOWorkbenchRuntimeModule,PSOWorkbenchRuntime)
