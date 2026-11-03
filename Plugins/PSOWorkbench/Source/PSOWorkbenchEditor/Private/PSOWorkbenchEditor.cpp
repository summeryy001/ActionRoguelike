#include "PSOWorkbenchSettings.h"
#include "Modules/ModuleManager.h"
#include "ToolMenus.h"
#include "Framework/Docking/TabManager.h"
#include "Widgets/Docking/SDockTab.h"
#include "Widgets/Layout/SSplitter.h"
#include "Widgets/Layout/SScrollBox.h"
#include "Widgets/Layout/SBox.h"
#include "Widgets/Layout/SBorder.h"
#include "Widgets/Input/SButton.h"
#include "Widgets/Input/SMultiLineEditableTextBox.h"
#include "Widgets/Input/SComboBox.h"
#include "Widgets/Text/STextBlock.h"
#include "PropertyEditorModule.h"
#include "IDetailsView.h"
#include "Interfaces/IPluginManager.h"
#include "Misc/App.h"
#include "Misc/Paths.h"
#include "Misc/FileHelper.h"
#include "Misc/MessageDialog.h"
#include "Misc/ConfigCacheIni.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "HAL/FileManager.h"
#include "HAL/PlatformProcess.h"
#include "HAL/PlatformMisc.h"
#include "Containers/Ticker.h"
#include "Serialization/JsonSerializer.h"
#include "JsonObjectConverter.h"
#include "FileHelpers.h"
#include "Styling/AppStyle.h"

#define LOCTEXT_NAMESPACE "PSOWorkbench"
static const FName WorkbenchTab(TEXT("PSOWorkbench"));

UPSOWorkbenchSettings::UPSOWorkbenchSettings()
{
    EngineRoot=FPaths::ConvertRelativePathToFull(FPaths::RootDir());
    GameTarget=FApp::GetProjectName();
    InsightsExecutable.FilePath=FPaths::ConvertRelativePathToFull(FPaths::EngineDir()/TEXT("Binaries/Win64/UnrealInsights.exe"));
    const FString InsightsOverride=FPlatformMisc::GetEnvironmentVariable(TEXT("PSOWORKBENCH_INSIGHTS"));
    if(!InsightsOverride.IsEmpty())InsightsExecutable.FilePath=InsightsOverride;
    FString Map;
    if(GConfig) GConfig->GetString(TEXT("/Script/EngineSettings.GameMapsSettings"),TEXT("GameDefaultMap"),Map,GEngineIni);
    CaptureMap=FSoftObjectPath(Map); if(!Map.IsEmpty()) CookMaps.Add(CaptureMap);
}

static TSharedPtr<FJsonObject> ReadJson(const FString& Path)
{
    FString Text; TSharedPtr<FJsonObject> Object;
    if(FFileHelper::LoadFileToString(Text,*Path)) FJsonSerializer::Deserialize(TJsonReaderFactory<>::Create(Text),Object);
    return Object;
}
static void WriteJson(const FString& Path,const TSharedRef<FJsonObject>& Object)
{
    FString Text; FJsonSerializer::Serialize(Object,TJsonWriterFactory<>::Create(&Text));
    IFileManager::Get().MakeDirectory(*FPaths::GetPath(Path),true);
    FFileHelper::SaveStringToFile(Text,*Path,FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
}
static FString Field(const TSharedPtr<FJsonObject>& Object,const TCHAR* Name)
{
    FString Result; if(Object) Object->TryGetStringField(Name,Result); return Result;
}

static TSharedRef<FJsonObject> CurrentRequest(const FString& Action)
{
    const auto* Settings=GetDefault<UPSOWorkbenchSettings>();
    TSharedRef<FJsonObject> Request=MakeShared<FJsonObject>();
    Request->SetStringField(TEXT("Action"),Action);
    Request->SetStringField(TEXT("ProjectFile"),FPaths::ConvertRelativePathToFull(FPaths::GetProjectFilePath()));
    Request->SetStringField(TEXT("EngineRoot"),Settings->EngineRoot);
    Request->SetStringField(TEXT("GameTarget"),Settings->GameTarget);
    Request->SetStringField(TEXT("ProfileName"),Settings->ProfileName);
    Request->SetStringField(TEXT("GroupName"),Settings->GroupName);
    Request->SetNumberField(TEXT("Platform"),(int32)Settings->Platform);
    Request->SetStringField(TEXT("CaptureMap"),Settings->CaptureMap.GetLongPackageName());
    TArray<TSharedPtr<FJsonValue>> Maps;
    for(const auto& Map:Settings->CookMaps) Maps.Add(MakeShared<FJsonValueString>(Map.GetLongPackageName()));
    Request->SetArrayField(TEXT("CookMaps"),Maps);
    Request->SetNumberField(TEXT("CaptureStrategy"),(int32)Settings->CaptureStrategy);
    Request->SetNumberField(TEXT("RuntimeMode"),(int32)Settings->RuntimeMode);
    Request->SetBoolField(TEXT("AutomaticRoute"),Settings->bAutomaticRoute);
    Request->SetStringField(TEXT("AutomaticArguments"),Settings->AutomaticArguments);
    Request->SetStringField(TEXT("CompletionMarker"),Settings->CompletionMarker);
    Request->SetNumberField(TEXT("ExpectedActions"),Settings->ExpectedActions);
    Request->SetStringField(TEXT("SuccessPattern"),Settings->SuccessPattern);
    Request->SetStringField(TEXT("OutputArgument"),Settings->OutputArgument);
    Request->SetStringField(TEXT("MapOptions"),Settings->MapOptions);
    Request->SetStringField(TEXT("PrepareScript"),Settings->PrepareScript.FilePath);
    for(const auto& Pair:TArray<TPair<FString,TArray<FString>>>{{TEXT("PrepareArguments"),Settings->PrepareArguments},{TEXT("LaunchArguments"),Settings->LaunchArguments}})
    {
        TArray<TSharedPtr<FJsonValue>> Values;for(const auto& Value:Pair.Value)Values.Add(MakeShared<FJsonValueString>(Value));
        Request->SetArrayField(Pair.Key,Values);
    }
    Request->SetBoolField(TEXT("ClearDriverCache"),Settings->bClearDriverCache);
    Request->SetBoolField(TEXT("Background"),Settings->bBackground);
    Request->SetNumberField(TEXT("BackgroundBudgetMs"),Settings->BackgroundBudgetMs);
    Request->SetNumberField(TEXT("AnalysisStartSeconds"),Settings->AnalysisStartSeconds);
    Request->SetNumberField(TEXT("AnalysisEndSeconds"),Settings->AnalysisEndSeconds);
    Request->SetStringField(TEXT("InsightsExecutable"),Settings->InsightsExecutable.FilePath);
    return Request;
}

class FWorkbenchSession:public TSharedFromThis<FWorkbenchSession>
{
    FProcHandle Process;
    FTSTicker::FDelegateHandle TickHandle;
    FString Job, Session, ActiveLog, Phase;
    FString LogText;
    bool Busy=false;
public:
    FString Message=TEXT("就绪。先检查或应用构建配置，再依次执行工作流。");
    void Initialize(){TickHandle=FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateSP(AsShared(),&FWorkbenchSession::Tick),0.5f);}
    ~FWorkbenchSession(){FTSTicker::GetCoreTicker().RemoveTicker(TickHandle);if(Process.IsValid()) FPlatformProcess::CloseProc(Process);}
    bool IsBusy()const{return Busy;}
    FString GetLog()const{return LogText;}
    FString ProfileRoot()const{return FPaths::ConvertRelativePathToFull(FPaths::GetPath(FPaths::GetProjectFilePath())/TEXT("Saved/PSOWorkbench/Profiles")/GetMutableDefault<UPSOWorkbenchSettings>()->ProfileName);}
    FString JobRoot()const{return Job;}
    bool CanStop()const{return Busy && Phase==TEXT("GameRunning") && !Session.IsEmpty();}
    bool Tick(float)
    {
        if(!Busy) return true;
        const auto Status=ReadJson(Job/TEXT("status.json"));
        if(Status){Message=Field(Status,TEXT("message"));Session=Field(Status,TEXT("session"));ActiveLog=Field(Status,TEXT("log"));Phase=Field(Status,TEXT("phase"));}
        FString Text;
        if(!ActiveLog.IsEmpty() && FFileHelper::LoadFileToString(Text,*ActiveLog)) LogText=Text.Right(24000);
        if(!FPlatformProcess::IsProcRunning(Process))
        {
            int32 Code=-1;FPlatformProcess::GetProcReturnCode(Process,&Code);FPlatformProcess::CloseProc(Process);Process.Reset();Busy=false;
            auto Result=ReadJson(Job/TEXT("result.json"));bool Success=false;
            if(!Result || !Result->TryGetBoolField(TEXT("success"),Success) || !Success || Code!=0)
            {
                Message=TEXT("失败：")+(Result?Field(Result,TEXT("error")):TEXT("后台未写入完成记录，请查看任务日志。"));
                if(!Result)FFileHelper::LoadFileToString(LogText,*(Job/TEXT("launcher.log")));
            }
            else Message=TEXT("任务成功。可以进入下一步，或打开本次产物查看记录。");
        }
        return true;
    }
    void Start(const FString& Action)
    {
        if(Busy) return;
        auto* Settings=GetMutableDefault<UPSOWorkbenchSettings>();
        if(Settings->Platform!=EPSOWBPlatform::Windows){Message=TEXT("Android 扩展预留：设备部署、采集回收及打包闭环尚未实现。");return;}
        if(Action==TEXT("BuildCollector") || Action==TEXT("BuildBundled"))
            if(!FEditorFileUtils::SaveDirtyPackages(true,true,true,false,false,false)) {Message=TEXT("已取消保存，不启动构建。");return;}
        if(Action==TEXT("ApplyConfig"))
            if(FMessageDialog::Open(EAppMsgType::YesNo,LOCTEXT("ApplyQuestion","将备份并设置 NeedsShaderStableKeys、共享 Shader 代码及 Native Libraries。不会修改项目默认运行模式。继续？"))!=EAppReturnType::Yes)return;
        if(Action==TEXT("Validate") && Settings->bClearDriverCache)
            if(FMessageDialog::Open(EAppMsgType::YesNo,LOCTEXT("ClearQuestion","本次验收将请求清理本机显卡驱动缓存。清理可能影响其他应用的首次运行体验，且不保证完全成功。继续？"))!=EAppReturnType::Yes)return;
        Job=FPaths::ConvertRelativePathToFull(FPaths::GetPath(FPaths::GetProjectFilePath())/TEXT("Saved/PSOWorkbench/Jobs")/(FDateTime::Now().ToString(TEXT("%Y%m%d_%H%M%S"))+TEXT("_")+FGuid::NewGuid().ToString(EGuidFormats::Digits).Left(6)));
        TSharedRef<FJsonObject> Request=CurrentRequest(Action);
        WriteJson(Job/TEXT("request.json"),Request);
        const FString Script=IPluginManager::Get().FindPlugin(TEXT("PSOWorkbench"))->GetBaseDir()/TEXT("Scripts/Launch.ps1");
        const FString Params=FString::Printf(TEXT("-NoProfile -ExecutionPolicy Bypass -File \"%s\" -Request \"%s\""),*FPaths::ConvertRelativePathToFull(Script),*(Job/TEXT("request.json")));
        Process=FPlatformProcess::CreateProc(TEXT("powershell.exe"),*Params,true,true,true,nullptr,0,nullptr,nullptr);
        Busy=Process.IsValid();Phase.Empty();Session.Empty();LogText.Empty();
        Message=Busy?TEXT("后台任务已启动，正在读取配置……"):TEXT("无法启动 PowerShell，请检查本机工具环境。");
        Settings->SaveConfig();
    }
    void Stop(){if(CanStop()) {FFileHelper::SaveStringToFile(TEXT("stop"),*(Session/TEXT("stop.request")));Message=TEXT("已请求游戏保存记录并正常退出，请等待。");}}
    FString Artifacts()const
    {
        auto State=ReadJson(ProfileRoot()/TEXT("state.json"));
        if(!State)return TEXT("本方案尚无产物。每个方案有独立记录，失败任务不会替换上一次成功产物。");
        FString Result;
        const auto Current=CurrentRequest(TEXT("Inspect"));
        TMap<FString,bool> Stale;
        for(const auto& Pair:TArray<TPair<FString,FString>>{{TEXT("collector"),TEXT("采集包")},{TEXT("conversion"),TEXT("Stable 清单")},{TEXT("installed"),TEXT("已安装输入")},{TEXT("bundled"),TEXT("Bundled 包")},{TEXT("validation"),TEXT("运行验收")},{TEXT("analysis"),TEXT("Insights 分析")}})
        {
            const TSharedPtr<FJsonObject>* Item=nullptr;
            if(State->TryGetObjectField(Pair.Key,Item))
            {
                double Count=0;
                FString Reason=Field(*Item,TEXT("staleReason"));
                const TSharedPtr<FJsonObject>* Recorded=nullptr;
                if(!(*Item)->TryGetObjectField(TEXT("settings"),Recorded))Reason=TEXT("旧记录缺少依赖身份，请重新生成");
                else for(const auto& Setting:(*Recorded)->Values)
                {
                    const auto* Value=Current->Values.Find(Setting.Key);
                    if(!Value || !FJsonValue::CompareEqual(*Setting.Value,*(*Value))) {Reason=TEXT("当前方案配置已变化");break;}
                }
                const TArray<TSharedPtr<FJsonValue>>* Parents=nullptr;
                if((*Item)->TryGetArrayField(TEXT("parentKeys"),Parents))for(const auto& Parent:*Parents)
                    if(Stale.FindRef(Parent->AsString()))Reason=TEXT("上游产物待更新");
                Stale.Add(Pair.Key,!Reason.IsEmpty());
                Result+=Pair.Value+(Reason.IsEmpty()?TEXT("：已完成（上次依赖检查有效）"):TEXT("：待更新 — ")+Reason);
                if((*Item)->TryGetNumberField(TEXT("count"),Count))Result+=FString::Printf(TEXT("（%.0f 项/组合）"),Count);
                Result+=TEXT("\n");
            }
        }
        const TArray<TSharedPtr<FJsonValue>>* Captures=nullptr;
        if(State->TryGetArrayField(TEXT("captures"),Captures))Result+=FString::Printf(TEXT("采集会话：%d 次（后台按依赖筛选）；文件变更请点击检查产物依赖。"),Captures->Num());
        return Result;
    }
};

class SPSOWorkbenchPanel:public SCompoundWidget
{
    TSharedPtr<FWorkbenchSession> Session;
    TSharedPtr<IDetailsView> Details;
    TArray<TSharedPtr<FString>> Profiles;
    TSharedPtr<SComboBox<TSharedPtr<FString>>> ProfileBox;
    FString ProfilesDir()const{return FPaths::ProjectConfigDir()/TEXT("PSOWorkbench/Profiles");}
    void RefreshProfiles()
    {
        Profiles.Empty();TArray<FString> Files;IFileManager::Get().FindFiles(Files,*(ProfilesDir()/TEXT("*.json")),true,false);
        for(const FString& File:Files)Profiles.Add(MakeShared<FString>(FPaths::GetBaseFilename(File)));
        if(ProfileBox)ProfileBox->RefreshOptions();
    }
    FReply SaveProfile()
    {
        auto* Settings=GetMutableDefault<UPSOWorkbenchSettings>();
        if(Settings->ProfileName.IsEmpty() || Settings->ProfileName!=FPaths::MakeValidFileName(Settings->ProfileName) || Settings->ProfileName.Contains(TEXT(".")))return FReply::Handled();
        TSharedRef<FJsonObject> Profile=MakeShared<FJsonObject>();
        FJsonObjectConverter::UStructToJsonObject(Settings->GetClass(),Settings,Profile);
        Profile->RemoveField(TEXT("engineRoot"));Profile->RemoveField(TEXT("insightsExecutable"));
        FString Text;FJsonSerializer::Serialize(Profile,TJsonWriterFactory<>::Create(&Text));
        IFileManager::Get().MakeDirectory(*ProfilesDir(),true);
        FFileHelper::SaveStringToFile(Text,*(ProfilesDir()/(Settings->ProfileName+TEXT(".json"))),FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
        Settings->SaveConfig();RefreshProfiles();Session->Message=TEXT("方案已保存；任务运行时使用该方案当前设置的独立快照。");return FReply::Handled();
    }
    TSharedRef<SWidget> Task(const TCHAR* Label,const TCHAR* Action,const TCHAR* Tip)
    {
        const FString TaskName=Action;
        return SNew(SButton).Text(FText::FromString(Label)).ToolTipText(FText::FromString(Tip))
            .IsEnabled_Lambda([this]{return !Session->IsBusy() && GetMutableDefault<UPSOWorkbenchSettings>()->Platform==EPSOWBPlatform::Windows;})
            .OnClicked_Lambda([this,TaskName]{Session->Start(TaskName);return FReply::Handled();});
    }
public:
    SLATE_BEGIN_ARGS(SPSOWorkbenchPanel){}SLATE_ARGUMENT(TSharedPtr<FWorkbenchSession>,Session)SLATE_END_ARGS()
    void Construct(const FArguments& Args)
    {
        Session=Args._Session;RefreshProfiles();
        FDetailsViewArgs DetailArgs;DetailArgs.bAllowSearch=true;DetailArgs.bHideSelectionTip=true;
        Details=FModuleManager::LoadModuleChecked<FPropertyEditorModule>(TEXT("PropertyEditor")).CreateDetailView(DetailArgs);
        Details->SetObject(GetMutableDefault<UPSOWorkbenchSettings>());
        ChildSlot[
            SNew(SVerticalBox)
            +SVerticalBox::Slot().AutoHeight().Padding(8)[SNew(STextBlock).Text(LOCTEXT("Title","PSO 工作台 · Windows DX12 / SM6")).Font(FAppStyle::GetFontStyle(TEXT("HeadingExtraSmall")))]
            +SVerticalBox::Slot().AutoHeight().Padding(8,0)[SNew(STextBlock).AutoWrapText(true).Text(LOCTEXT("Scope","方案 → 配置 → 采集包 → 运行采集 → 转换安装 → Bundled 包 → 运行验收。Android 与运行时分阶段调度尚未实现；缓存组目前用于命名和追溯。"))]
            +SVerticalBox::Slot().AutoHeight().Padding(8)[SNew(SHorizontalBox)
                +SHorizontalBox::Slot().FillWidth(1)[SAssignNew(ProfileBox,SComboBox<TSharedPtr<FString>>).OptionsSource(&Profiles)
                    .IsEnabled_Lambda([this]{return !Session->IsBusy();})
                    .OnGenerateWidget_Lambda([](TSharedPtr<FString> Item){return SNew(STextBlock).Text(FText::FromString(*Item));})
                    .OnSelectionChanged_Lambda([this](TSharedPtr<FString> Item,ESelectInfo::Type){if(Item){auto Profile=ReadJson(ProfilesDir()/(*Item+TEXT(".json")));if(Profile){auto* Settings=GetMutableDefault<UPSOWorkbenchSettings>();FJsonObjectConverter::JsonObjectToUStruct(Profile.ToSharedRef(),Settings->GetClass(),Settings);Details->SetObject(Settings,true);Settings->SaveConfig();}}})
                    [SNew(STextBlock).Text_Lambda([]{return FText::FromString(TEXT("选择已保存方案：")+GetMutableDefault<UPSOWorkbenchSettings>()->ProfileName);})]]
                +SHorizontalBox::Slot().AutoWidth().Padding(6,0)[SNew(SButton).Text(LOCTEXT("Save","保存当前方案")).IsEnabled_Lambda([this]{return !Session->IsBusy();}).OnClicked(this,&SPSOWorkbenchPanel::SaveProfile)]]
            +SVerticalBox::Slot().FillHeight(1).Padding(8)[SNew(SSplitter)
                +SSplitter::Slot().Value(0.46f)[SNew(SBox).IsEnabled_Lambda([this]{return !Session->IsBusy();})[Details.ToSharedRef()]]
                +SSplitter::Slot().Value(0.54f)[SNew(SScrollBox)+SScrollBox::Slot()[SNew(SVerticalBox)
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[SNew(STextBlock).Text(LOCTEXT("Steps","按顺序完成构建；步骤可独立重试"))]
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[Task(TEXT("1  检查配置与前置条件"),TEXT("Preflight"),TEXT("检查平台、地图列表与构建设置"))]
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[Task(TEXT("检查产物依赖 / 标记待更新"),TEXT("Inspect"),TEXT("核对配置、来源、文件 Hash 及上游身份；旧记录须重新生成"))]
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[Task(TEXT("应用构建配置（自动备份）"),TEXT("ApplyConfig"),TEXT("仅修改3项 Stable Keys / Shader 库配置；会先显示确认"))]
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[Task(TEXT("2  构建 Windows 采集包"),TEXT("BuildCollector"),TEXT("构建独立 Game，Cook 并归档匹配 SHK"))]
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[Task(TEXT("3  启动采集（手动 / 自动路线）"),TEXT("Capture"),TEXT("使用采集策略运行；手动模式完成后点结束游戏"))]
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[Task(TEXT("4  转换匹配记录 → Stable 清单"),TEXT("Convert"),TEXT("自动筛选当前采集包记录和映射，检查 Hash"))]
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[Task(TEXT("5  安装本方案缓存输入"),TEXT("Install"),TEXT("以方案/缓存组命名；备份同名旧文件，保留其他输入"))]
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[Task(TEXT("6  构建 Bundled PSO 包"),TEXT("BuildBundled"),TEXT("Cook 合并项目缓存输入，核对生成数量与包内清单"))]
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[Task(TEXT("7  运行并验收所选模式"),TEXT("Validate"),TEXT("检查实际配置、Runtime 批次与退出；冷缓存勾选会确认"))]
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[Task(TEXT("8  Insights 离线分析"),TEXT("Analyze"),TEXT("使用高级设置选择的 UnrealInsights.exe 导出 CPU Scope"))]
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[SNew(SButton).Text(LOCTEXT("Stop","结束当前游戏并保存记录")).IsEnabled_Lambda([this]{return Session->CanStop();}).OnClicked_Lambda([this]{Session->Stop();return FReply::Handled();})]
                    +SVerticalBox::Slot().AutoHeight().Padding(4)[SNew(STextBlock).AutoWrapText(true).Text_Lambda([this]{return FText::FromString(Session->Artifacts());})]
                ]]]
            +SVerticalBox::Slot().AutoHeight().Padding(8)[SNew(STextBlock).AutoWrapText(true).Text_Lambda([this]{return FText::FromString(Session->Message);})]
            +SVerticalBox::Slot().FillHeight(0.45f).Padding(8,0)[SNew(SMultiLineEditableTextBox).IsReadOnly(true).Text_Lambda([this]{return FText::FromString(Session->GetLog());})]
            +SVerticalBox::Slot().AutoHeight().Padding(8)[SNew(SHorizontalBox)
                +SHorizontalBox::Slot().AutoWidth()[SNew(SButton).Text(LOCTEXT("Evidence","打开本次任务产物")).OnClicked_Lambda([this]{FPlatformProcess::ExploreFolder(*Session->JobRoot());return FReply::Handled();})]
                +SHorizontalBox::Slot().AutoWidth().Padding(6,0)[SNew(SButton).Text(LOCTEXT("History","打开方案产物历史")).OnClicked_Lambda([this]{FPlatformProcess::ExploreFolder(*Session->ProfileRoot());return FReply::Handled();})]
                +SHorizontalBox::Slot().AutoWidth().Padding(6,0)[Task(TEXT("恢复最近构建配置备份"),TEXT("RestoreConfig"),TEXT("只有配置未被其他操作修改时才恢复"))]]
        ];
    }
};

class FPSOWorkbenchEditorModule:public IModuleInterface
{
    TSharedPtr<FWorkbenchSession> Session;
    FDelegateHandle InitHandle;
    TSharedRef<SDockTab> Spawn(const FSpawnTabArgs&){return SNew(SDockTab).TabRole(ETabRole::NomadTab)[SNew(SPSOWorkbenchPanel).Session(Session)];}
    void Open(){FGlobalTabmanager::Get()->TryInvokeTab(WorkbenchTab);}
    void Menus()
    {
        FToolMenuOwnerScoped Owner(this);
        UToolMenu* Menu=UToolMenus::Get()->ExtendMenu(TEXT("LevelEditor.MainMenu.Tools"));
        Menu->AddSection(TEXT("PSOWorkbench"),LOCTEXT("MenuSection","渲染工作流")).AddMenuEntry(TEXT("PSOWorkbench.Open"),LOCTEXT("Open","PSO 工作台"),LOCTEXT("OpenTip","打开 PSO 配置、采集、构建和验收工作台"),FSlateIcon(FAppStyle::GetAppStyleSetName(),TEXT("Profiler.Tab")),FUIAction(FExecuteAction::CreateRaw(this,&FPSOWorkbenchEditorModule::Open)));
    }
public:
    void StartupModule()override
    {
        Session=MakeShared<FWorkbenchSession>();Session->Initialize();
        FGlobalTabmanager::Get()->RegisterNomadTabSpawner(WorkbenchTab,FOnSpawnTab::CreateRaw(this,&FPSOWorkbenchEditorModule::Spawn)).SetDisplayName(LOCTEXT("Tab","PSO 工作台")).SetIcon(FSlateIcon(FAppStyle::GetAppStyleSetName(),TEXT("Profiler.Tab"))).SetMenuType(ETabSpawnerMenuType::Hidden);
        UToolMenus::RegisterStartupCallback(FSimpleMulticastDelegate::FDelegate::CreateRaw(this,&FPSOWorkbenchEditorModule::Menus));
        InitHandle=FCoreDelegates::OnPostEngineInit.AddLambda([this]{if(FParse::Param(FCommandLine::Get(),TEXT("PSOWorkbenchOpen")))Open();});
    }
    void ShutdownModule()override
    {
        FCoreDelegates::OnPostEngineInit.Remove(InitHandle);
        UToolMenus::UnRegisterStartupCallback(this);UToolMenus::UnregisterOwner(this);
        FGlobalTabmanager::Get()->UnregisterNomadTabSpawner(WorkbenchTab);Session.Reset();
    }
};
IMPLEMENT_MODULE(FPSOWorkbenchEditorModule,PSOWorkbenchEditor)
#undef LOCTEXT_NAMESPACE
