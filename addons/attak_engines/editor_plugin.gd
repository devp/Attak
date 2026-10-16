@tool
extends EditorPlugin
## Puts the bundled TEI engines (src/interfaces/BundledEngines.gd) into Android
## exports, as lib/<abi>/lib<name>.so. Android extracts those to the app's
## nativeLibraryDir with exec permission -- the one place it lets an app run its
## own executables from -- because Godot's prebuilt APK template uses legacy
## (extracted) native-library packaging. No Gradle build is needed.

var _export_plugin: AndroidExport


func _enter_tree() -> void:
	_export_plugin = AndroidExport.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExport extends EditorExportPlugin:
	## Built by tools/build-syntaks.sh and copied here (gitignored): <abi>/lib*.so.
	const BIN_DIR := "res://addons/attak_engines/bin"

	func _get_name() -> String:
		return "AttakEngines"

	func _export_begin(features: PackedStringArray, is_debug: bool, path: String, flags: int) -> void:
		if get_export_platform().get_os_name() != "Android":
			return
		for abi in ["arm64-v8a", "x86_64"]:
			# Only for the ABIs this preset ships, so an engine never sits beside
			# an app build that can't load the rest of the ABI's libraries.
			if not get_option("architectures/" + abi):
				continue
			var dir := BIN_DIR.path_join(abi)
			for file in DirAccess.get_files_at(dir):
				if file.begins_with("lib") and file.ends_with(".so"):
					add_shared_object(dir.path_join(file), PackedStringArray([abi]), "")
