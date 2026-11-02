using UnrealBuildTool;
public class PSOWorkbenchRuntime : ModuleRules
{
    public PSOWorkbenchRuntime(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PrivateDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "RenderCore", "RHI", "Json", "Slate", "SlateCore", "InputCore" });
    }
}
