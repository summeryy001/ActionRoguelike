#pragma once
#include "CoreMinimal.h"
#include "UObject/Object.h"
#include "Engine/EngineTypes.h"
#include "PSOWorkbenchSettings.generated.h"

UENUM()
enum class EPSOWBPlatform:uint8 { Windows UMETA(DisplayName="Windows EXE"), Android UMETA(DisplayName="Android（扩展预留，暂不执行）") };
UENUM()
enum class EPSOWBMode:uint8 { Disabled UMETA(DisplayName="全部关闭"), Auto UMETA(DisplayName="仅自动预缓存"), Bundled UMETA(DisplayName="仅 Bundled"), Combined UMETA(DisplayName="自动 + Bundled") };
UENUM()
enum class EPSOWBCapture:uint8 { Full UMETA(DisplayName="完整采集（自动开启，不排除）"), Gap UMETA(DisplayName="补缺采集（自动开启，排除已覆盖）"), Isolated UMETA(DisplayName="隔离采集（自动关闭）") };

UCLASS(Config=EditorPerProjectUserSettings)
class UPSOWorkbenchSettings:public UObject
{
    GENERATED_BODY()
public:
    UPSOWorkbenchSettings();
    UPROPERTY(Config,EditAnywhere,Category="方案",meta=(DisplayName="方案名称")) FString ProfileName=TEXT("Default");
    UPROPERTY(Config,EditAnywhere,Category="方案",meta=(DisplayName="缓存组名称",ToolTip="首版用于输入命名及来源追溯；运行时按阶段加载尚未实现")) FString GroupName=TEXT("Startup");
    UPROPERTY(Config,EditAnywhere,Category="平台",meta=(DisplayName="目标平台")) EPSOWBPlatform Platform=EPSOWBPlatform::Windows;
    UPROPERTY(Config,EditAnywhere,Category="平台",meta=(DisplayName="引擎根目录",AdvancedDisplay)) FString EngineRoot;
    UPROPERTY(Config,EditAnywhere,Category="平台",meta=(DisplayName="Game 构建目标",AdvancedDisplay)) FString GameTarget;
    UPROPERTY(Config,EditAnywhere,Category="工具",meta=(DisplayName="Unreal Insights 程序",FilePathFilter="exe",AdvancedDisplay)) FFilePath InsightsExecutable;
    UPROPERTY(Config,EditAnywhere,Category="采集",meta=(DisplayName="运行地图",AllowedClasses="/Script/Engine.World")) FSoftObjectPath CaptureMap;
    UPROPERTY(Config,EditAnywhere,Category="采集",meta=(DisplayName="需要 Cook 的地图",AllowedClasses="/Script/Engine.World")) TArray<FSoftObjectPath> CookMaps;
    UPROPERTY(Config,EditAnywhere,Category="采集",meta=(DisplayName="采集策略")) EPSOWBCapture CaptureStrategy=EPSOWBCapture::Full;
    UPROPERTY(Config,EditAnywhere,Category="构建",meta=(DisplayName="构建前准备脚本",ToolTip="可选项目相对路径 .ps1；非交互执行，失败则停止构建。仅使用可信项目脚本。")) FFilePath PrepareScript;
    UPROPERTY(Config,EditAnywhere,Category="构建",meta=(DisplayName="准备脚本参数")) TArray<FString> PrepareArguments;
    UPROPERTY(Config,EditAnywhere,Category="采集",meta=(DisplayName="地图 URL 选项",ToolTip="默认空；项目确实需要 Listen Server 时填写 ?listen")) FString MapOptions;
    UPROPERTY(Config,EditAnywhere,Category="采集",meta=(DisplayName="通用启动参数",ToolTip="逐项填写，仅允许额外参数，不能覆盖工作台管理的地图、PSO、日志、Trace 或会话参数")) TArray<FString> LaunchArguments;
    UPROPERTY(Config,EditAnywhere,Category="采集",meta=(DisplayName="使用项目自动路线")) bool bAutomaticRoute=false;
    UPROPERTY(Config,EditAnywhere,Category="采集",meta=(DisplayName="自动路线启动参数",EditCondition="bAutomaticRoute",AdvancedDisplay)) FString AutomaticArguments;
    UPROPERTY(Config,EditAnywhere,Category="采集",meta=(DisplayName="自动路线完成标记",EditCondition="bAutomaticRoute",AdvancedDisplay)) FString CompletionMarker;
    UPROPERTY(Config,EditAnywhere,Category="采集",meta=(DisplayName="预期成功动作次数",ClampMin="0",EditCondition="bAutomaticRoute",AdvancedDisplay)) int32 ExpectedActions=0;
    UPROPERTY(Config,EditAnywhere,Category="采集",meta=(DisplayName="成功动作日志正则",EditCondition="bAutomaticRoute",AdvancedDisplay)) FString SuccessPattern;
    UPROPERTY(Config,EditAnywhere,Category="采集",meta=(DisplayName="项目结果输出参数名",ToolTip="可选：仅参数名，不带横线/等号。值为本次 Session 目录。",AdvancedDisplay)) FString OutputArgument;
    UPROPERTY(Config,EditAnywhere,Category="工具",meta=(DisplayName="分析开始时间（秒）",ClampMin="0")) float AnalysisStartSeconds=0;
    UPROPERTY(Config,EditAnywhere,Category="工具",meta=(DisplayName="分析结束时间（秒）",ClampMin="0.01")) float AnalysisEndSeconds=15;
    UPROPERTY(Config,EditAnywhere,Category="运行验收",meta=(DisplayName="运行模式")) EPSOWBMode RuntimeMode=EPSOWBMode::Bundled;
    UPROPERTY(Config,EditAnywhere,Category="运行验收",meta=(DisplayName="请求清理驱动缓存",ToolTip="仅验收运行使用；影响本机驱动缓存，清理成功不作保证")) bool bClearDriverCache=false;
    UPROPERTY(Config,EditAnywhere,Category="运行验收",meta=(DisplayName="后台批次模式")) bool bBackground=false;
    UPROPERTY(Config,EditAnywhere,Category="运行验收",meta=(DisplayName="后台每帧目标预算（毫秒）",ClampMin="0.1",ClampMax="16",EditCondition="bBackground")) float BackgroundBudgetMs=2;
};
