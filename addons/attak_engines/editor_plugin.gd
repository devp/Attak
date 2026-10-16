@tool
extends EditorPlugin
## Hands the AttakEngines AAR (built by tools/build-plugin.sh) to Godot's Gradle
## Android build. Presets without "Use Gradle Build" ignore it.

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

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform.get_os_name() == "Android"

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		if not FileAccess.file_exists("res://addons/" + AAR):
			# Not fatal here: a non-Gradle export never uses it. tools/build-apk.sh
			# checks the APK for the engines when they're expected.
			push_warning("AttakEngines: %s not built; exporting without bundled engines" % AAR)
			return PackedStringArray()
		return PackedStringArray([AAR])
