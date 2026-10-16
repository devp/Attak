extends RefCounted
class_name BundledEngines
## TEI engines shipped inside the app, as opposed to ones the user picks a file for.
##
## On Android, user-picked files can't be executed (W^X since targetSdk 29), but
## the app's nativeLibraryDir can: Android extracts lib/<abi>/lib*.so from the APK
## there with exec permission. So engines are packaged as lib<name>.so (still
## ordinary executables; see addons/attak_engines) and found again here.

## name: shown in the Vs Bot tab.  file: inside the bundled-engine directory.
## sizes / komi: the board sizes and komi the engine plays. The Vs Bot tab only
## offers those -- an engine given anything else may carry on regardless
## (syntaks does), leaving it and the board disagreeing about the game.
const MANIFEST: Array[Dictionary] = [
	{"name": "syntaks", "file": "libsyntaks.so", "sizes": [6], "komi": [2.0]},
]


## Where bundled engines live on this platform, or "" if nowhere.
## Desktop builds bundle nothing; ATTAK_ENGINE_DIR stands in for nativeLibraryDir
## there, so tests can run the bundled-engine path.
static func directory() -> String:
	if OS.get_name() == "Android":
		return native_library_dir()
	return OS.get_environment("ATTAK_ENGINE_DIR")


## Manifest entries for the engines actually present, each with "path" added.
static func list() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var dir := directory()
	if dir.is_empty():
		return found
	for entry in MANIFEST:
		var path := dir.path_join(entry["file"])
		if exists(path):
			found.append(entry.merged({"path": path}))
	return found


## Android's nativeLibraryDir, read off where Godot's own library was loaded
## from. Godot has no API for it, and its Android FileAccess can't open /proc,
## so ask grep. "" if the libraries weren't extracted (then there is no such
## directory, and nothing could be executed from one anyway).
static func native_library_dir() -> String:
	var out := []
	OS.execute("grep", ["-m1", "libgodot_android.so", "/proc/%d/maps" % OS.get_process_id()], out)
	var line: String = out[0].strip_edges() if not out.is_empty() else ""
	var at := line.find("/")
	if at < 0 or ".apk" in line:
		return ""
	return line.substr(at).get_base_dir()


## Whether a file exists. On Android, Godot's FileAccess reports every path
## outside app/shared storage as missing -- nativeLibraryDir included -- so ask ls.
static func exists(path: String) -> bool:
	if OS.get_name() == "Android":
		return OS.execute("ls", [path]) == 0
	return FileAccess.file_exists(path)
