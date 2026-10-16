extends RefCounted
class_name BundledEngines
## TEI engines shipped inside the app, as opposed to ones the user picks a file for.
##
## On Android, user-picked files can't be executed (W^X since targetSdk 29), but
## the app's nativeLibraryDir can: Android extracts lib/<abi>/lib*.so from the APK
## there with exec permission. So engines are packaged as lib<name>.so (still
## ordinary executables) by the AttakEngines plugin, and found again here.

## display name -> filename inside the bundled-engine directory.
const MANIFEST: Array[Dictionary] = [
	{"name": "syntaks", "file": "libsyntaks.so"},
]

## Name of the Android plugin singleton (see android-plugin/).
const PLUGIN := "AttakEngines"


static func plugin():
	return Engine.get_singleton(PLUGIN) if Engine.has_singleton(PLUGIN) else null


## Where bundled engines live on this platform, or "" if nowhere.
static func directory() -> String:
	if OS.get_name() == "Android":
		var p = plugin()
		return p.getNativeLibraryDir() if p != null else ""
	return ""


## Engines from the manifest that are actually present: [{name, path}].
static func list() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := directory()
	if dir.is_empty():
		return found
	for entry in MANIFEST:
		var path := dir.path_join(entry["file"])
		if exists(path):
			found.append({"name": entry["name"], "path": path})
	return found


## Whether a file exists. On Android, Godot's FileAccess reports every path
## outside app/shared storage as missing -- nativeLibraryDir included -- so ask
## Java there.
static func exists(path: String) -> bool:
	var p = plugin()
	if p != null:
		return p.fileExists(path)
	return FileAccess.file_exists(path)


## Whether the OS would let this process exec the file. FileAccess can't answer
## this on Android (its permission query returns 0 there), so ask Java.
## Returns -1 when it can't tell.
static func can_execute(path: String) -> int:
	var p = plugin()
	if p != null:
		return 1 if p.canExecute(path) else 0
	if OS.get_name() != "Android":
		return 1 if FileAccess.get_unix_permissions(path) & 0x49 else 0 # 0o111
	return -1


## A second, plugin-free way to find nativeLibraryDir: the directory Godot's own
## libgodot_android.so was mapped from. Only meaningful when native libraries are
## extracted; when they're loaded straight from the APK, this names the APK.
static func directory_from_maps() -> String:
	var out := []
	OS.execute("/system/bin/grep", ["-m1", "libgodot_android.so", "/proc/%d/maps" % OS.get_process_id()], out)
	if out.is_empty():
		return ""
	var line: String = out[0].strip_edges()
	var at := line.find("/")
	return line.substr(at).get_base_dir() if at >= 0 else ""
