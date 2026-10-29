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
#include "HAL/PlatformMisc.h"
#include "ProfilingDebugging/MiscTrace.h"
#include "SharedGameplayTags.h"
#include "PipelineStateCache.h"
#include "ShaderPipelineCache.h"

ARoguePSOValidation::ARoguePSOValidation()
{
	PrimaryActorTick.bCanEverTick = true;
}

void ARoguePSOValidation::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);
	if (StartTime == 0)
	{
		StartTime = FPlatformTime::Seconds();
		TRACE_BOOKMARK(TEXT("PSOValidation: MapReady"));
	}
	const double Elapsed = FPlatformTime::Seconds() - StartTime;
	FrameCSV += FString::Printf(TEXT("%.6f,%.4f,%d\n"), Elapsed, DeltaSeconds * 1000.0, Step);

	APawn* Player = UGameplayStatics::GetPlayerPawn(this, 0);
	// Keep natural AI damage from interrupting the skill route. Death is tested explicitly.
	if (Player && Step < 9)
	{
		URogueActionComponent* Actions = URogueActionComponent::GetActionComponent(Player);
		if (Actions && URogueGameplayFunctionLibrary::IsAlive(Player))
		{
			Actions->ApplyAttributeChange(SharedGameplayTags::Attribute_Health, 100.0f, Player, EAttributeModifyType::AddBase);
		}
	}

	const double Times[] = {5, 10, 16, 23, 28, 34, 38, 40, 44, 50, 56};
	if (Step >= UE_ARRAY_COUNT(Times) || Elapsed < Times[Step])
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
