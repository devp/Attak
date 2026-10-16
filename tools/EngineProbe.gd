extends RefCounted
class_name EngineProbe
## Spawns a TEI engine and records every line exchanged with it, for tests.
##
## tools/teiGameTest uses one as the stand-in human. It spawns the same way
## TEInterface does (OS.execute_with_pipe), but isn't tied to GameLogic.

## Each entry is "> sent", "< stdout", "! stderr" or "# note".
var transcript := PackedStringArray()
var pid := -1

var _stdio: FileAccess
var _stderr: FileAccess
var _queue: Array = [] # [tag, line], filled by the reader threads
var _mutex := Mutex.new()
var _threads: Array[Thread] = []


## Starts the engine. Returns "" on success, or what went wrong.
func start(path: String) -> String:
	note("spawning %s" % path)
	var d := OS.execute_with_pipe(path, PackedStringArray())
	if d.is_empty():
		return note("execute_with_pipe returned nothing (pipe or fork failed)")
	_stdio = d["stdio"]
	_stderr = d["stderr"]
	pid = d["pid"]
	note("pid %d" % pid)
	for pair in [[_stdio, "<"], [_stderr, "!"]]:
		var t := Thread.new()
		t.start(_read.bind(pair[0], pair[1]))
		_threads.append(t)
	return ""


func running() -> bool:
	return pid > 0 and OS.is_process_running(pid)


func send(line: String) -> void:
	if not running():
		note("not sent, engine not running: %s" % line)
		return
	transcript.append("> " + line)
	_stdio.store_line(line)


func note(s: String) -> String:
	transcript.append("# " + s)
	return s


## Waits for a stdout line starting with `prefix`. Returns it, or "" on timeout
## or if the engine exits first.
func wait_for(prefix: String, timeout_s: float) -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var deadline := Time.get_ticks_msec() + int(timeout_s * 1000)
	while Time.get_ticks_msec() < deadline:
		var exited := not running()
		for entry in _drain():
			if entry[0] == "<" and entry[1].begins_with(prefix):
				return entry[1]
		if exited:
			note("engine exited while waiting for '%s'%s" % [prefix, _exit_code_text()])
			return ""
		await tree.process_frame
	note("timed out after %.0fs waiting for '%s'" % [timeout_s, prefix])
	return ""


## tei -> teiok, then isready -> readyok.
func handshake(timeout_s := 10.0) -> bool:
	send("tei")
	if (await wait_for("teiok", timeout_s)).is_empty():
		return false
	send("isready")
	return not (await wait_for("readyok", timeout_s)).is_empty()


func stop() -> void:
	if running():
		send("quit")
		var deadline := Time.get_ticks_msec() + 2000
		while running() and Time.get_ticks_msec() < deadline:
			OS.delay_msec(20)
		if running():
			note("engine ignored quit; killing it")
			OS.kill(pid)
	# The reader threads see EOF once the engine has gone.
	for t in _threads:
		t.wait_to_finish()
	_threads.clear()
	_drain()
	if _stdio != null:
		_stdio.close()
	if _stderr != null:
		_stderr.close()


func _exit_code_text() -> String:
	if pid > 0 and OS.has_method("get_process_exit_code"):
		return " (exit code %d)" % OS.get_process_exit_code(pid)
	return ""


func _drain() -> Array:
	_mutex.lock()
	var got := _queue
	_queue = []
	_mutex.unlock()
	for entry in got:
		transcript.append("%s %s" % entry)
	return got


func _read(f: FileAccess, tag: String) -> void:
	while f.is_open():
		var s := f.get_line()
		var err := f.get_error()
		if not s.is_empty():
			_mutex.lock()
			_queue.append([tag, s])
			_mutex.unlock()
		if err != OK:
			return
