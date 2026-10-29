#include "Development/RoguePSOFallbackDemo.h"
#include "Camera/CameraComponent.h"
#include "Components/InputComponent.h"
#include "Components/TextRenderComponent.h"
#include "Components/PointLightComponent.h"
#include "Engine/StaticMesh.h"
#include "GameFramework/PlayerController.h"
#include "Kismet/GameplayStatics.h"
#include "Materials/Material.h"
#include "PSOPrecacheSettings.h"
#include "PSOPrecacheMaterial.h"
#include "PSOPrecacheComponent.h"
#include "ProfilingDebugging/MiscTrace.h"
#include "TimerManager.h"
#include "UObject/ConstructorHelpers.h"

void URoguePSOFallbackDemoMesh::PrecachePSOs()
{
	// Same real collection and completion path; no artificial prerequisite.
	if (!FApp::CanEverRender() || !IsComponentPSOPrecachingEnabled()) { return; }
	TRACE_CPUPROFILER_EVENT_SCOPE(PSOFallbackReal_Submit);
	GetPSOPrecacheComponentData().Reset();
	FPSOPrecacheParams Params;
	SetupPrecachePSOParams(Params);
	FMaterialInterfacePSOPrecacheParamsList Materials;
	CollectPSOPrecacheData(Params, Materials);
	TArray<FMaterialPSOPrecacheRequestID> Requests;
	FGraphEventArray Events;
	const double Start = FPlatformTime::Seconds();
	PrecacheMaterialPSOs(Materials, Requests, Events);
	const FString Path = GetPathName();
	FString IDs;
	for (FMaterialPSOPrecacheRequestID ID : Requests) { IDs += FString::Printf(TEXT("%d,"), ID); }
	UE_LOG(LogTemp, Display, TEXT("PSOFallbackReal: Submit component=%s material=%s requests=%s compileEvents=%d clock=%.6f"), *Path, *GetNameSafe(GetMaterial(0)), *IDs, Events.Num(), Start);
	TRACE_BOOKMARK(TEXT("PSOFallbackReal Submit %s events=%d"), *Path, Events.Num());
	SetMaterialPSOPrecacheData(Requests, Events);
	if (!Events.IsEmpty())
	{
		FFunctionGraphTask::CreateAndDispatchWhenReady([Path, Start]()
		{
			TRACE_CPUPROFILER_EVENT_SCOPE(PSOFallbackReal_CompileComplete);
			UE_LOG(LogTemp, Display, TEXT("PSOFallbackReal: CompileEventsComplete component=%s elapsedMs=%.3f clock=%.6f"), *Path, (FPlatformTime::Seconds()-Start)*1000.0, FPlatformTime::Seconds());
			TRACE_BOOKMARK(TEXT("PSOFallbackReal CompileEventsComplete %s"), *Path);
		}, TStatId(), &Events, ENamedThreads::GameThread);
	}
}

FPrimitiveSceneProxy* URoguePSOFallbackDemoMesh::CreateSceneProxy()
{
	TRACE_CPUPROFILER_EVENT_SCOPE(PSOFallbackReal_CreateSceneProxy);
	const bool bFallback = GetPSOPrecacheComponentData().UsePSOPrecacheFallbackMaterial();
	FPrimitiveSceneProxy* Proxy = Super::CreateSceneProxy();
	++ProxyGeneration;
	UE_LOG(LogTemp, Display, TEXT("PSOFallbackReal: ProxyCreated component=%s generation=%u fallback=%d proxyExists=%d material=%s clock=%.6f"), *GetPathName(), ProxyGeneration, bFallback, Proxy!=nullptr, *GetNameSafe(GetMaterial(0)), FPlatformTime::Seconds());
	TRACE_BOOKMARK(TEXT("PSOFallbackReal Proxy generation=%u fallback=%d exists=%d %s"), ProxyGeneration, bFallback, Proxy!=nullptr, *GetPathName());
	return Proxy;
}

ARoguePSOFallbackDemo::ARoguePSOFallbackDemo()
{
	PrimaryActorTick.bCanEverTick = true;
	RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	UPointLightComponent* Light = CreateDefaultSubobject<UPointLightComponent>(TEXT("DemoLight"));
	Light->SetupAttachment(RootComponent);
	Light->SetMobility(EComponentMobility::Movable);
	Light->SetRelativeLocation(FVector(-400,0,350));
	Light->SetIntensity(100000);
	Light->SetAttenuationRadius(2000);
	static ConstructorHelpers::FObjectFinder<UStaticMesh> Sphere(TEXT("/Engine/BasicShapes/Sphere.Sphere"));
	static ConstructorHelpers::FObjectFinder<UMaterialInterface> Red(TEXT("/Game/ActionRoguelike/Materials/M_PSOFallbackDemoRed.M_PSOFallbackDemoRed"));
	ReferenceSphere = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ReferenceSphere"));
	ReferenceSphere->SetupAttachment(RootComponent);
	ReferenceSphere->SetStaticMesh(Sphere.Object);
	ReferenceSphere->SetMaterial(0, Red.Object);
	ReferenceSphere->SetRelativeLocation(FVector(0,-180,120));
	ReferenceSphere->SetRelativeScale3D(FVector(1.8));
	ReferenceSphere->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	DelayedSphere = CreateDefaultSubobject<URoguePSOFallbackDemoMesh>(TEXT("DelayedSphere"));
	DelayedSphere->SetupAttachment(RootComponent);
	DelayedSphere->SetStaticMesh(Sphere.Object);
	DelayedSphere->SetMaterial(0, Red.Object);
	DelayedSphere->SetRelativeLocation(FVector(0,180,120));
	DelayedSphere->SetRelativeScale3D(FVector(1.8));
	DelayedSphere->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	Camera = CreateDefaultSubobject<UCameraComponent>(TEXT("Camera"));
	Camera->SetupAttachment(RootComponent);
	Camera->SetRelativeLocation(FVector(-850,0,320));
	Camera->SetRelativeRotation((FVector(0,0,140)-Camera->GetRelativeLocation()).Rotation());
	Camera->FieldOfView = 55;
	StatusText = CreateDefaultSubobject<UTextRenderComponent>(TEXT("Status"));
	StatusText->SetupAttachment(RootComponent);
	StatusText->SetRelativeLocation(FVector(0,0,280));
	StatusText->SetRelativeRotation(FRotator(0,180,0));
	StatusText->SetHorizontalAlignment(EHTA_Center);
	StatusText->SetWorldSize(16);
	StatusText->SetText(FText::FromString(TEXT("REAL PSO compilation | No artificial wait\nRuntime material loads after 5 seconds\nF9 repeats (warm cache expected)")));
	RuntimeMaterial = TSoftObjectPtr<UMaterialInterface>(FSoftObjectPath(TEXT("/Game/ActionRoguelike/Materials/M_PSOFallbackRuntimeRed.M_PSOFallbackRuntimeRed")));
}

void ARoguePSOFallbackDemo::BeginPlay()
{
	Super::BeginPlay();
	if (APlayerController* Controller = UGameplayStatics::GetPlayerController(this,0))
	{
		Controller->SetViewTarget(this);
		EnableInput(Controller);
		InputComponent->BindKey(EKeys::F9,IE_Pressed,this,&ThisClass::Replay);
	}
	UE_LOG(LogTemp, Display, TEXT("PSOFallbackReal: Begin strategy=%d fallback=%s artificialWait=0"), (int32)GetPSOPrecacheProxyCreationStrategy(), *GetNameSafe(UPSOPrecacheSettingsManager::GetFallbackMaterial()));
	GetWorldTimerManager().SetTimer(StartTimer,this,&ThisClass::Replay,5.0f,false);
}

void ARoguePSOFallbackDemo::Replay()
{
	TRACE_CPUPROFILER_EVENT_SCOPE(PSOFallbackReal_LoadAndSpawn);
	TRACE_BOOKMARK(TEXT("PSOFallbackReal LoadAndSpawn"));
	UE_LOG(LogTemp, Display, TEXT("PSOFallbackReal: LoadAndSpawn alreadyLoaded=%d clock=%.6f"), RuntimeMaterial.IsValid(), FPlatformTime::Seconds());
	UMaterialInterface* Material = RuntimeMaterial.LoadSynchronous();
	if (!Material) { UE_LOG(LogTemp, Error, TEXT("PSOFallbackReal: runtime material missing")); return; }
	if (DelayedSphere) { DelayedSphere->DestroyComponent(); }
	DelayedSphere = NewObject<URoguePSOFallbackDemoMesh>(this);
	DelayedSphere->SetupAttachment(RootComponent);
	DelayedSphere->SetStaticMesh(ReferenceSphere->GetStaticMesh());
	DelayedSphere->SetMaterial(0,Material);
	DelayedSphere->SetRelativeLocation(FVector(0,180,120));
	DelayedSphere->SetRelativeScale3D(FVector(1.8));
	DelayedSphere->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	DelayedSphere->RegisterComponent();
	bObservedState = false;
}

void ARoguePSOFallbackDemo::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (!DelayedSphere) { return; }
	const bool bFallback = DelayedSphere->GetPSOPrecacheComponentData().UsePSOPrecacheFallbackMaterial();
	if (!bObservedState || bFallback != bLastFallback)
	{
		UE_LOG(LogTemp, Display, TEXT("PSOFallbackReal: Observed fallback=%d proxyExists=%d component=%s clock=%.6f"), bFallback,DelayedSphere->SceneProxy!=nullptr,*DelayedSphere->GetPathName(),FPlatformTime::Seconds());
		TRACE_BOOKMARK(TEXT("PSOFallbackReal Observed fallback=%d"), bFallback);
		StatusText->SetText(FText::FromString(FString::Printf(TEXT("REAL PSO compilation | No artificial wait\nRIGHT: %s | F9: repeat (warm cache)"),bFallback ? TEXT("engine fallback") : TEXT("real material"))));
		bObservedState = true;
		bLastFallback = bFallback;
	}
}

void ARoguePSOFallbackDemo::EndPlay(const EEndPlayReason::Type Reason)
{
	GetWorldTimerManager().ClearTimer(StartTimer);
	Super::EndPlay(Reason);
}
