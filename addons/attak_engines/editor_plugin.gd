@tool
extends EditorPlugin
## Hands the AttakEngines AAR (built by tools/build-plugin.sh) to Godot's Gradle
## Android build.

var _export_plugin: AndroidExport


func _enter_tree() -> void:
	_export_plugin = AndroidExport.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExport extends EditorExportPlugin:
	## Relative to res://addons/, as _get_android_libraries expects.
	const AAR := "attak_engines/bin/AttakEngines.aar"

	func _get_name() -> String:
		return "AttakEngines"

	# Godot 4.4 refuses a non-Gradle Android export while any export plugin
	# supports Android, and asks without saying which preset is being exported.
	# So only claim Android when there's an AAR to hand over, and let
	# tools/build-apk.sh switch this off (ATTAK_SKIP_ENGINE_PLUGIN=1) for the
	# non-Gradle presets. Without the AAR, Gradle builds just lack the engines;
	# build-apk.sh's EXPECT_LIBS check catches that where they're required.
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform.get_os_name() == "Android" \
			and OS.get_environment("ATTAK_SKIP_ENGINE_PLUGIN").is_empty() \
			and FileAccess.file_exists("res://addons/" + AAR)

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray([AAR])
