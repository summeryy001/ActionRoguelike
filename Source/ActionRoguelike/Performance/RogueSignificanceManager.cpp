// Fill out your copyright notice in the Description page of Project Settings.


#include "RogueSignificanceManager.h"
#include "RogueSignificanceInterface.h"
#include "RogueSignificanceSettings.h"
#include "Components/ActorComponent.h"


void URogueSignificanceManager::Update(TArrayView<const FTransform> InViewpoints)
{
	// Base calculates and sorts the significance
	Super::Update(InViewpoints);

	// Fetch Buckets
	const URogueSignificanceSettings* Settings = GetDefault<URogueSignificanceSettings>();

	// Snapshot notifications before calling gameplay code, which may unregister
	// objects and invalidate the manager's sorted arrays.
	TArray<TPair<TWeakObjectPtr<UObject>, int32>> ChangedLODs;

	for (int TagIndex = 0; TagIndex < RegisteredTags.Num(); ++TagIndex)
	{
		const TArray<USignificanceManager::FManagedObjectInfo*>& SortedObjects = GetManagedObjects(RegisteredTags[TagIndex]);
		for (int Index = 0; Index < SortedObjects.Num(); ++Index)
		{
			int32 NewLOD = Settings->GetBucketIndex(RegisteredTags[TagIndex], Index);

			UObject* Object = SortedObjects[Index]->GetObject();
			if (!IsValid(Object))
			{
				continue;
			}
			const TWeakObjectPtr<UObject> ObjectKey(Object);
			int32* PreviousLOD = ObjectLODs.Find(ObjectKey);
			if (PreviousLOD == nullptr || *PreviousLOD != NewLOD)
			{
				ObjectLODs.Add(ObjectKey, NewLOD);
				ChangedLODs.Emplace(ObjectKey, NewLOD);
			}
		}
	}

	for (const TPair<TWeakObjectPtr<UObject>, int32>& Change : ChangedLODs)
	{
		UObject* ObjectInst = Change.Key.Get();
		const int32* CurrentLOD = ObjectLODs.Find(Change.Key);
		if (!IsValid(ObjectInst) || CurrentLOD == nullptr || *CurrentLOD != Change.Value)
		{
			continue;
		}
		if (UActorComponent* Component = Cast<UActorComponent>(ObjectInst))
		{
			ObjectInst = Component->GetOwner();
		}
		if (IRogueSignificanceInterface* ObjInterface = Cast<IRogueSignificanceInterface>(ObjectInst))
		{
			ObjInterface->SignificanceLODChanged(Change.Value);
		}
	}
}


void URogueSignificanceManager::RegisterObject(UObject* Object, FName Tag, FManagedObjectSignificanceFunction SignificanceFunction, EPostSignificanceType InPostSignificanceType,
	FManagedObjectPostSignificanceFunction InPostSignificanceFunction)
{
	Super::RegisterObject(Object, Tag, SignificanceFunction, InPostSignificanceType, InPostSignificanceFunction);
	ObjectLODs.Remove(TWeakObjectPtr<UObject>(Object));

	// Bookkeeping for iterating the sorted lists easily
	RegisteredTags.AddUnique(Tag);

	// @todo: verify that there is a bucket available for this "Tag"
	// const URogueSignificanceSettings* Settings = GetDefault<URogueSignificanceSettings>();
}


void URogueSignificanceManager::UnregisterObject(UObject* Object)
{
	ObjectLODs.Remove(TWeakObjectPtr<UObject>(Object));
	Super::UnregisterObject(Object);

	// @todo: Cleanup the RegisteredTags array
}
