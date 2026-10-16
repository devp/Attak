extends Node
## Spawns a TEI engine through the same path the app uses and checks it answers:
## handshake (teiok, readyok), then a short search (bestmove).
##
## Desktop:  godot --headless tools/teiSmokeTest.tscn -- --engine=/path/to/syntaks
## Android:  the "Android x86_64 (TEI smoke test)" preset launches straight into
##           this scene and tests the first bundled engine, then hands over to
##           tools/teiGameTest.tscn for a full game.
##
## Prints one "TEI_SMOKE PASS" or "TEI_SMOKE FAIL: <why>" line, which CI looks
## for (on Android, in logcat), and exits non-zero on failure.

const MOVETIME_MS := 1000


func _ready() -> void:
	var why: String = await run()
	for line in _probe.transcript:
		print("  ", line)
	if why.is_empty():
		print("TEI_SMOKE PASS")
	else:
		print("TEI_SMOKE FAIL: ", why)
	# On Android this is the smoke APK's whole run, so go on to a full game
	# through the TEI tab (tools/teiGameTest.tscn) once the engine answers.
	if why.is_empty() and OS.get_name() == "Android":
		get_tree().change_scene_to_file.call_deferred("res://tools/teiGameTest.tscn")
		return
	get_tree().quit(0 if why.is_empty() else 1)


var _probe := EngineProbe.new()


func run() -> String:
	print("platform: %s %s" % [OS.get_name(), Engine.get_architecture_name()])
	var path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--engine="):
			path = arg.trim_prefix("--engine=")
	if path.is_empty():
		var dir := BundledEngines.directory()
		print("bundled engine directory: '%s'" % dir)
		if not dir.is_empty():
			var ls := []
			OS.execute("ls", ["-l", dir], ls, true)
			print("ls -l: ", "".join(ls).strip_edges())
		var engines := BundledEngines.list()
		if engines.is_empty():
			return "no --engine given and no bundled engine found"
		path = engines[0]["path"]
	if not BundledEngines.exists(path):
		return "no such file: " + path
	print("can_execute: %d" % BundledEngines.can_execute(path))

	var err := _probe.start(path)
	if not err.is_empty():
		return err
	if not await _probe.handshake():
		_probe.stop()
		return "handshake failed"
	var best := await _probe.think(MOVETIME_MS)
	print("bestmove line: '%s', nps %s" % [best, _probe.info_field("nps")])
	_probe.stop()
	if not best.begins_with("bestmove "):
		return "no bestmove"
	return ""
