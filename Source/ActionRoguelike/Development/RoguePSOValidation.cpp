#include "Development/RoguePSOValidation.h"
#include "Engine/Engine.h"
#include "EngineUtils.h"
#include "AI/RogueAICharacter.h"
#include "GameFramework/PlayerController.h"
#include "Pickups/RoguePickupSubsystem.h"

#include "ActionSystem/RogueActionComponent.h"
#include "Core/RogueGameplayFunctionLibrary.h"
#include "Kismet/GameplayStatics.h"
#include "Misc/CommandLine.h"
#include "Misc/FileHelper.h"
#include "Misc/Paths.h"
#include "UObject/UObjectGlobals.h"
#include "HAL/PlatformMisc.h"
#include "ProfilingDebugging/MiscTrace.h"
#include "SharedGameplayTags.h"
#include "PipelineStateCache.h"
#include "ShaderPipelineCache.h"
#include "NiagaraFunctionLibrary.h"
#include "NiagaraSystem.h"
#include "Camera/CameraActor.h"
#include "Camera/CameraComponent.h"
#include "Core/RogueGameplayInterface.h"

ARoguePSOValidation::ARoguePSOValidation()
{
	PrimaryActorTick.bCanEverTick = true;
}

void ARoguePSOValidation::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
    const double Now = FPlatformTime::Seconds();
	const bool bCoverage = FParse::Param(FCommandLine::Get(), TEXT("PSOCoverage"));
    if (MapReadyTime == 0)
    {
        MapReadyTime = Now;
        TRACE_BOOKMARK(TEXT("PSOValidation: MapReady"));
        UE_LOG(LogTemp, Display, TEXT("PSOValidation gateBegin enabled=%d"), FParse::Param(FCommandLine::Get(), TEXT("PSOValidationWaitForReady")));
    }

	APawn* Player = UGameplayStatics::GetPlayerPawn(this, 0);
	// Keep natural AI damage from interrupting the skill route. Death is tested explicitly.
	if (Player && (Step < 9 || bCoverage))
	{
		URogueActionComponent* Actions = URogueActionComponent::GetActionComponent(Player);
		if (Actions && URogueGameplayFunctionLibrary::IsAlive(Player))
		{
			Actions->ApplyAttributeChange(SharedGameplayTags::Attribute_Health, 100.0f, Player, EAttributeModifyType::AddBase);
		}
	}

	    if (StartTime == 0)
    {
        const bool bWait = FParse::Param(FCommandLine::Get(), TEXT("PSOValidationWaitForReady"));
        const uint32 Pending = PipelineStateCache::NumActivePrecacheRequests();
        PeakPending = FMath::Max(PeakPending, Pending);
        const bool bResourcesReady = Player && URogueGameplayFunctionLibrary::IsAlive(Player) && !IsAsyncLoading();
        const double WaitSeconds = Now - MapReadyTime;
        if (bWait)
        {
            if (WaitSeconds - LastGateLog >= 1.0)
            {
                LastGateLog = WaitSeconds;
                UE_LOG(LogTemp, Display, TEXT("PSOValidation gateWaiting seconds=%.3f pendingAuto=%u asyncLoading=%d playerReady=%d"), WaitSeconds, Pending, IsAsyncLoading(), bResourcesReady);
            }
            ReadySince = (bResourcesReady && Pending == 0) ? (ReadySince == 0 ? Now : ReadySince) : 0;
            if (WaitSeconds > 180.0)
            {
                UE_LOG(LogTemp, Error, TEXT("PSOValidation gateTimeout seconds=%.3f pendingAuto=%u"), WaitSeconds, Pending);
                FPlatformMisc::RequestExitWithStatus(false, 2);
                SetActorTickEnabled(false);
                return;
            }
            if (ReadySince == 0 || Now - ReadySince < 0.5) return;
        }
        StartTime = Now;
        TRACE_BOOKMARK(TEXT("PSOValidation: ReadyForSkills"));
        UE_LOG(LogTemp, Display, TEXT("PSOValidation gateComplete enabled=%d waitSeconds=%.3f pendingAuto=%u peakPending=%u asyncLoading=%d"), bWait, WaitSeconds, Pending, PeakPending, IsAsyncLoading());
    }
    const double Elapsed = Now - StartTime;
	if (bCoverage && Player && Elapsed >= 52.0)
	{
		const int32 NextCoverageStep = FMath::FloorToInt((Elapsed - 52.0) / 4.0);
		if (NextCoverageStep > CoverageStep && NextCoverageStep < 20)
		{
			CoverageStep = NextCoverageStep;
			static const TCHAR* Effects[] = {
				TEXT("NS_Treasure_Burst"), TEXT("NS_Skill_Leap_Base_Velocity_Impact"),
				TEXT("NS_Portal_Teleport_Exit"), TEXT("NS_Portal_Teleport_Enter"),
				TEXT("NS_Portal_Entrance_Close"), TEXT("NS_Portal_Cast"),
				TEXT("NS_Gideon_Ultimate"), TEXT("NS_Gideon_TravelMode_Hands"),
				TEXT("NS_Gideon_Primary_Projectile"), TEXT("NS_Gideon_Primary_MuzzleFlash"),
				TEXT("NS_Gideon_Primary_HitWorld"), TEXT("NS_Gideon_Burden_Projectile"),
				TEXT("NS_Gideon_Burden_MuzzleFlash"), TEXT("NS_Flames"), TEXT("NS_Explosion"),
				TEXT("NS_DroppedBuff_Health_Light"), TEXT("NS_DroppedBuff_HealthRegen"),
				TEXT("NS_DroppedBuff_Gold"), TEXT("NS_CarriedBuff_Received_Black"), TEXT("NS_Burning")};
			const FVector Origin = Player->GetActorLocation();
			const FString EffectPath = FString::Printf(TEXT("/Game/tharlevfx_tutorials/CharacterFX/ParagonSourceAssets/Niagara/%s.%s"), Effects[CoverageStep], Effects[CoverageStep]);
			UNiagaraSystem* System = LoadObject<UNiagaraSystem>(nullptr, *EffectPath);
			const bool bSpawned = System && UNiagaraFunctionLibrary::SpawnSystemAtLocation(this, System, Origin + FVector(0, 0, 130)) != nullptr;
			CoverageEffectsLoaded += bSpawned ? 1 : 0;
			// A view-only camera leaves gameplay/physics in place, changing distance and angle.
			ACameraActor* Camera = GetWorld()->SpawnActor<ACameraActor>();
			if (Camera && Player->GetController())
			{
				const double Angle = CoverageStep * PI / 4.0;
				const double Distance = CoverageStep % 2 ? 900.0 : 350.0;
				Camera->SetActorLocation(Origin + FVector(FMath::Cos(Angle)*Distance, FMath::Sin(Angle)*Distance, 250));
				Camera->SetActorRotation((Origin + FVector(0,0,130) - Camera->GetActorLocation()).Rotation());
				CastChecked<APlayerController>(Player->GetController())->SetViewTarget(Camera);
				Camera->SetLifeSpan(12.0f);
			}
			if (CoverageStep < 7)
			{
				static const TCHAR* Props[] = {TEXT("BonfireBP"), TEXT("LeverBP"), TEXT("TreasureChest"), TEXT("ExplosiveBarrel_Assignment"), TEXT("Powerup_HealthPotion"), TEXT("SineWaveBlueprint"), TEXT("TargetDummyBP")};
				const FString ClassPath = FString::Printf(TEXT("/Game/ActionRoguelike/%s.%s_C"), Props[CoverageStep], Props[CoverageStep]);
				UClass* PropClass = LoadClass<AActor>(nullptr, *ClassPath);
				FActorSpawnParameters SpawnParams;
				SpawnParams.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;
				AActor* Prop = PropClass ? GetWorld()->SpawnActor<AActor>(PropClass, Origin+FVector(120,0,100), FRotator::ZeroRotator, SpawnParams) : nullptr;
				if (Prop) Prop->SetLifeSpan(12.0f);
				if (Prop && Player->GetController() && Prop->Implements<URogueGameplayInterface>())
				{
					IRogueGameplayInterface::Execute_Interact(Prop, Player->GetController());
					UE_LOG(LogTemp, Display, TEXT("PSOCoverage interacted=%s"), *ClassPath);
				}
				UE_LOG(LogTemp, Display, TEXT("PSOCoverage prop=%s spawned=%d"), *ClassPath, Prop != nullptr);
			}
			TRACE_BOOKMARK(TEXT("PSOCoverage effect=%s spawned=%d"), Effects[CoverageStep], bSpawned);
			UE_LOG(LogTemp, Display, TEXT("PSOCoverage step=%d effect=%s spawned=%d"), CoverageStep, *EffectPath, bSpawned);
		}
	}
    FrameCSV += FString::Printf(TEXT("%.6f,%.4f,%d\n"), Elapsed, DeltaSeconds * 1000.0, Step);

	const double Times[] = {5, 10, 16, 23, 28, 34, 38, 40, 44, 50, 56};
	if (Step >= UE_ARRAY_COUNT(Times) || Elapsed < Times[Step] || (bCoverage && Step == 10 && Elapsed < 136.0))
	{
		return;
	}

	const TCHAR* Labels[] = {TEXT("Primary_First"), TEXT("Blackhole_First"), TEXT("Dash_First"),
		TEXT("Primary_Repeat"), TEXT("Blackhole_Repeat"), TEXT("Dash_Repeat"), TEXT("EnemyDeath"), TEXT("Pickup"), TEXT("PlayerDeath"),
		TEXT("RespawnCheck"), TEXT("Complete")};
	TRACE_BOOKMARK(TEXT("PSOValidation: %s"), Labels[Step]);
	UE_LOG(LogTemp, Display, TEXT("PSOValidation step=%d label=%s elapsed=%.3f pawn=%s"), Step, Labels[Step], Elapsed, *GetNameSafe(Player));
	UE_LOG(LogTemp, Display, TEXT("PSOValidation pendingAuto=%u pendingBundled=%u"), PipelineStateCache::NumActivePrecacheRequests(), FShaderPipelineCache::NumPrecompilesRemaining());

	if (Player && Step < 6)
	{
		// Aim at the nearest living enemy, rather than firing into the starting wall.
		ARogueAICharacter* Target = nullptr;
		double NearestDistance = TNumericLimits<double>::Max();
		for (ARogueAICharacter* Enemy : TActorRange<ARogueAICharacter>(GetWorld()))
		{
			const double Distance = FVector::DistSquared(Player->GetActorLocation(), Enemy->GetActorLocation());
			if (Distance < NearestDistance && URogueGameplayFunctionLibrary::IsAlive(Enemy))
			{
				Target = Enemy;
				NearestDistance = Distance;
			}
		}
		if (Target && Player->GetController())
		{
			Player->GetController()->SetControlRotation((Target->GetActorLocation() - Player->GetPawnViewLocation()).Rotation());
		}
		const FGameplayTag AbilityTags[] = {SharedGameplayTags::Action_PrimaryAttack.GetTag(),
			SharedGameplayTags::Action_Blackhole.GetTag(), SharedGameplayTags::Action_Dash.GetTag()};
		const bool bStarted = URogueActionComponent::GetActionComponent(Player)->StartActionByName(Player, AbilityTags[Step % 3]);
		UE_LOG(LogTemp, Display, TEXT("PSOValidation action=%s started=%d"), *AbilityTags[Step % 3].ToString(), bStarted);
	}
	else if (Step == 6)
	{
		for (ARogueAICharacter* Enemy : TActorRange<ARogueAICharacter>(GetWorld()))
		{
			if (URogueGameplayFunctionLibrary::IsAlive(Enemy))
			{
				URogueGameplayFunctionLibrary::KillActor(Enemy);
				break;
			}
		}
	}
	else if (Player && Step == 7)
	{
		// Fixed pickup fixture uses the same production subsystem as enemy drops.
		GetWorld()->GetSubsystem<URoguePickupSubsystem>()->AddCoinsPickup({Player->GetActorLocation()}, {1});
	}
	else if (Player && Step == 8)
	{
		URogueGameplayFunctionLibrary::KillActor(Player);
	}
	else if (Step == 9)
	{
		UE_LOG(LogTemp, Display, TEXT("PSOValidation respawnAlive=%d"), Player && URogueGameplayFunctionLibrary::IsAlive(Player));
	}
	else if (Step == 10)
	{
		if (bCoverage)
		{
			UE_LOG(LogTemp, Display, TEXT("PSOCoverage complete effects=%d expected=20"), CoverageEffectsLoaded);
			if (CoverageEffectsLoaded != 20) { FPlatformMisc::RequestExitWithStatus(false, 3); return; }
		}
		FString Output;
		FParse::Value(FCommandLine::Get(), TEXT("PSOValidationOutput="), Output);
		if (!Output.IsEmpty())
		{
			FFileHelper::SaveStringToFile(FrameCSV, *FPaths::Combine(Output, TEXT("frames.csv")), FFileHelper::EEncodingOptions::ForceUTF8WithoutBOM);
		}
		const FPSORuntimeCreationStats Stats = PipelineStateCache::GetPSORuntimeCreationStats();
		UE_LOG(LogTemp, Display, TEXT("PSOValidation runtimeCreated=%u graphicsHitches=%u computeHitches=%u precachedHitches=%u"), Stats.TotalPSOCreations, Stats.GraphicsPSOHitches, Stats.ComputePSOHitches, Stats.PreviouslyPrecachedPSOHitches);
		GEngine->Exec(GetWorld(), TEXT("Trace.Stop"));
		// Drain before world/component destruction. Keep shutdown outside the measured route.
		const double DrainStart = FPlatformTime::Seconds();
		PipelineStateCache::WaitForAllTasks();
		UE_LOG(LogTemp, Display, TEXT("PSOValidation drainSeconds=%.3f"), FPlatformTime::Seconds() - DrainStart);
		GEngine->Exec(GetWorld(), TEXT("r.ShaderPipelineCache.Save"));
		FPlatformMisc::RequestExit(false);
	}
	++Step;
}
