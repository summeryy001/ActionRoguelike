#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "RoguePSOValidation.generated.h"

// Opt-in packaged profiling route. Never spawned during normal gameplay.
UCLASS(NotBlueprintable)
class ARoguePSOValidation : public AActor
{
	GENERATED_BODY()

public:
	ARoguePSOValidation();
	virtual void Tick(float DeltaSeconds) override;

private:
	int32 Step = 0;
	int32 CoverageStep = -1;
	int32 CoverageEffectsLoaded = 0;
	double StartTime = 0;
    double MapReadyTime = 0;
    double ReadySince = 0;
    double LastGateLog = -1;
    uint32 PeakPending = 0;
	FString FrameCSV = TEXT("ElapsedSeconds,FrameMs,Step\n");
};
