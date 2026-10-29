#pragma once

#include "CoreMinimal.h"
#include "Async/TaskGraphInterfaces.h"
#include "Components/StaticMeshComponent.h"
#include "GameFramework/Actor.h"
#include "RoguePSOFallbackDemo.generated.h"

class UCameraComponent;
class UTextRenderComponent;

// Observes real component precaching; never inserts completion prerequisites.
UCLASS()
class URoguePSOFallbackDemoMesh : public UStaticMeshComponent
{
	GENERATED_BODY()
public:
	virtual void PrecachePSOs() override;
	virtual FPrimitiveSceneProxy* CreateSceneProxy() override;
private:
	uint32 ProxyGeneration = 0;
};

UCLASS()
class ARoguePSOFallbackDemo : public AActor
{
	GENERATED_BODY()
public:
	ARoguePSOFallbackDemo();
	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;
	void Replay();
private:
	UPROPERTY()
	TObjectPtr<UStaticMeshComponent> ReferenceSphere;
	UPROPERTY()
	TObjectPtr<URoguePSOFallbackDemoMesh> DelayedSphere;
	UPROPERTY()
	TObjectPtr<UCameraComponent> Camera;
	UPROPERTY()
	TObjectPtr<UTextRenderComponent> StatusText;
	UPROPERTY()
	TSoftObjectPtr<UMaterialInterface> RuntimeMaterial;
	FTimerHandle StartTimer;
	bool bObservedState = false;
	bool bLastFallback = false;
};
