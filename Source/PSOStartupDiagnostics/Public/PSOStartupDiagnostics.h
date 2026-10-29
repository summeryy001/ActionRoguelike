#pragma once

#include "CoreMinimal.h"

struct FPSOStartupCacheStatus
{
    FString Name;
    uint32 Queued = 0;
    uint32 Completed = 0;
    double BeginSeconds = 0;
    double EndSeconds = 0;
    bool bFinished = false;
};

namespace PSOStartupDiagnostics
{
    // Snapshots are copied under a lock; callbacks can arrive on the rendering thread.
    PSOSTARTUPDIAGNOSTICS_API TArray<FPSOStartupCacheStatus> GetSnapshot();
    // -1: disabled/no observed nonempty batch; 0: all observed batches finished;
    // positive: pending count (at least one until completion is confirmed).
    PSOSTARTUPDIAGNOSTICS_API int32 GetRemainingBundledPSOs();
}
