// Fill out your copyright notice in the Description page of Project Settings.

#pragma once

#include "CoreMinimal.h"
#include "SignificanceManager.h"
#include "RogueSignificanceManager.generated.h"



/**
 * 
 */
UCLASS()
class ACTIONROGUELIKE_API URogueSignificanceManager : public USignificanceManager
{
	GENERATED_BODY()
	
public:

	virtual void Update(TArrayView<const FTransform> InViewpoints) override;

	virtual void RegisterObject(UObject* Object, FName Tag, FManagedObjectSignificanceFunction SignificanceFunction, EPostSignificanceType InPostSignificanceType = EPostSignificanceType::None,
		FManagedObjectPostSignificanceFunction InPostSignificanceFunction = nullptr) override;

	virtual void UnregisterObject(UObject* Object) override;


protected:

	// The engine allocates FManagedObjectInfo, not a project-derived type.
	// Keep project state separately; weak keys must not keep registered objects alive.
	TMap<TWeakObjectPtr<UObject>, int32> ObjectLODs;
	
	TArray<FName> RegisteredTags;
};
