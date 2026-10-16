extends RefCounted
class_name BundledEngines
## TEI engines shipped inside the app, as opposed to ones the user picks a file for.
##
## On Android, user-picked files can't be executed (W^X since targetSdk 29), but
## the app's nativeLibraryDir can: Android extracts lib/<abi>/lib*.so from the APK
## there with exec permission. So engines are packaged as lib<name>.so (still
## ordinary executables) by the AttakEngines plugin, and found again here.

## name: shown in the TEI tab.  file: inside the bundled-engine directory.
## sizes / komi (optional): the only board sizes and komi the engine plays. An
## engine given anything else may carry on regardless (syntaks does), leaving it
## and the board disagreeing about the game, so the TEI tab refuses to start.
const MANIFEST: Array[Dictionary] = [
	{"name": "syntaks", "file": "libsyntaks.so", "sizes": [6], "komi": [2.0]},
]

## Name of the Android plugin singleton (see android-plugin/).
const PLUGIN := "AttakEngines"


static func plugin():
	return Engine.get_singleton(PLUGIN) if Engine.has_singleton(PLUGIN) else null


## Where bundled engines live on this platform, or "" if nowhere.
## Desktop builds bundle nothing; ATTAK_ENGINE_DIR stands in for nativeLibraryDir
## there, so tests can run the bundled-engine path.
static func directory() -> String:
	if OS.get_name() == "Android":
		var p = plugin()
		return p.getNativeLibraryDir() if p != null else ""
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


## Why `engine` (a list() entry) can't play this game, or "" if it can.
static func unsupported(engine: Dictionary, size: int, komi: float) -> String:
	var sizes: Array = engine.get("sizes", [])
	var komis: Array = engine.get("komi", [])
	if (sizes.is_empty() or size in sizes) and (komis.is_empty() or komi in komis):
		return ""
	var parts := PackedStringArray()
	if not sizes.is_empty():
		parts.append("/".join(sizes.map(func(s): return "%dx%d" % [s, s])))
	if not komis.is_empty():
		parts.append("komi " + " or ".join(komis.map(func(k): return str(int(k)) if k == int(k) else str(k))))
	return "%s only plays %s." % [engine["name"], " with ".join(parts)]


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
