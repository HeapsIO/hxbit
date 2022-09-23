package hxbit;

#if hxbit_visibility
typedef VisibilityGroup = haxe.macro.MacroType<[hxbit.Macros.buildVisibilityGroups()]>;
#else
enum VisibilityGroup {
}
#end