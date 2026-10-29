// Fill out your copyright notice in the Description page of Project Settings.

#include "ActionRoguelike.h"
#include "Modules/ModuleManager.h"
#include "Performance/PSOStartupOverlay.h"

class FActionRoguelikeModule : public FDefaultGameModuleImpl
{
public:
	virtual void StartupModule() override { PSOStartupOverlay::Startup(); }
	virtual void ShutdownModule() override { PSOStartupOverlay::Shutdown(); }
};

IMPLEMENT_PRIMARY_GAME_MODULE( FActionRoguelikeModule, ActionRoguelike, "ActionRoguelike" );

DEFINE_LOG_CATEGORY(LogGame);
