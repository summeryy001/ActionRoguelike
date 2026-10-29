using UnrealBuildTool;

public class PSOStartupDiagnostics : ModuleRules
{
    public PSOStartupDiagnostics(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
        PublicDependencyModuleNames.Add("Core");
        PrivateDependencyModuleNames.AddRange(new[] { "RenderCore", "RHI" });
    }
}
