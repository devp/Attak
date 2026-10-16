extends VBoxContainer
## Temporary on-device diagnostics for bundled TEI engines, shown in the TEI tab
## (itself behind the experimental setting). Replaces the adb checks: it reports
## where nativeLibraryDir is, whether the engine is there and executable, what
## happens when it's spawned, and the raw TEI handshake. "Copy report" puts the
## whole thing on the clipboard to paste back.

const THINK_MS := 5000

## Used when no engine is bundled (desktop): the TEI tab's file path.
@export var fallback_path_entry: LineEdit

var _out: TextEdit
var _buttons: Array[Button] = []
var _probe: EngineProbe
var _report := PackedStringArray()


func _ready() -> void:
	var toggle := Button.new()
	toggle.text = "Engine diagnostics"
	toggle.toggle_mode = true
	add_child(toggle)

	var body := VBoxContainer.new()
	body.visible = false
	add_child(body)
	toggle.toggled.connect(func(on): body.visible = on)

	var row := HBoxContainer.new()
	body.add_child(row)
	for spec in [["Run checks", _run_checks], ["Think 5s on 6x6 startpos", _think], ["Copy report", _copy]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		row.add_child(b)
		_buttons.append(b)

	_out = TextEdit.new()
	_out.editable = false
	_out.custom_minimum_size = Vector2(0, 600)
	_out.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.add_child(_out)


func _exit_tree() -> void:
	_stop_probe()


func _log(s: String) -> void:
	_report.append(s)
	_out.text = "\n".join(_report)
	_out.scroll_vertical = _out.get_line_count()


func _busy(on: bool) -> void:
	for b in _buttons:
		b.disabled = on


func _stop_probe() -> void:
	if _probe != null:
		_probe.stop()
		_probe = null


func _engine_path() -> String:
	var engines := BundledEngines.list()
	if not engines.is_empty():
		return engines[0]["path"]
	return fallback_path_entry.text if fallback_path_entry != null else ""


func _run_checks() -> void:
	_busy(true)
	_stop_probe()
	_report.clear()
	_log("Attak engine diagnostics  %s" % Time.get_datetime_string_from_system())
	_log("OS: %s %s, arch %s, Godot %s" % [OS.get_name(), OS.get_version(), Engine.get_architecture_name(), Engine.get_version_info()["string"]])

	var dir := BundledEngines.directory()
	_log("plugin %s: %s" % [BundledEngines.PLUGIN, "present" if BundledEngines.plugin() != null else "MISSING"])
	_log("nativeLibraryDir (plugin): '%s'" % dir)
	if OS.get_name() == "Android":
		_log("nativeLibraryDir (/proc maps): '%s'" % BundledEngines.directory_from_maps())
	if not dir.is_empty():
		var ls := []
		var code := OS.execute("ls", ["-l", dir], ls, true)
		_log("ls -l %s  (exit %d):\n%s" % [dir, code, "".join(ls).strip_edges()])
		for entry in BundledEngines.MANIFEST:
			var p := dir.path_join(entry["file"])
			_log("%s: exists=%s can_execute=%d" % [p, BundledEngines.exists(p), BundledEngines.can_execute(p)])

	var path := _engine_path()
	if path.is_empty():
		_log("No bundled engine, and no file chosen above. Nothing to spawn.")
		_busy(false)
		return

	_probe = EngineProbe.new()
	var err := _probe.start(path)
	if err.is_empty():
		var ok: bool = await _probe.handshake()
		_log("handshake: %s%s" % ["OK" if ok else "FAILED", (" (%s)" % _probe.bot_name) if ok else ""])
	_log("--- transcript ---")
	for line in _probe.transcript:
		_log(line)
	_busy(false)


func _think() -> void:
	if _probe == null or not _probe.running():
		await _run_checks()
		if _probe == null or not _probe.running():
			return
	_busy(true)
	var from := _probe.transcript.size()
	_log("--- think %d ms ---" % THINK_MS)
	var t0 := Time.get_ticks_msec()
	var best: String = await _probe.think(THINK_MS)
	var took := Time.get_ticks_msec() - t0
	for i in range(from, _probe.transcript.size()):
		var line := _probe.transcript[i]
		if not line.begins_with("< info"):
			_log(line)
	_log("last info: " + _probe.last_info)
	_log("RESULT: %s  nodes=%s nps=%s depth=%s  (%d ms wall)" % [
		best if not best.is_empty() else "NO BESTMOVE",
		_probe.info_field("nodes"), _probe.info_field("nps"), _probe.info_field("depth"), took])
	_busy(false)


func _copy() -> void:
	DisplayServer.clipboard_set("\n".join(_report))
	Notif.message("Diagnostics copied to clipboard")
