using UnrealBuildTool;
public class PSOWorkbenchEditor : ModuleRules
{
    public PSOWorkbenchEditor(ReadOnlyTargetRules Target) : base(Target)
    {
        PCHUsage=PCHUsageMode.UseExplicitOrSharedPCHs;
        PrivateDependencyModuleNames.AddRange(new string[]{"Core","CoreUObject","Engine","InputCore","Slate","SlateCore","UnrealEd","ToolMenus","PropertyEditor","Projects","Json","JsonUtilities"});
    }
}
