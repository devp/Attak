extends Node

# Integration test for the syntaks GDExtension: size and komi gating, and a
# search whose move comes back as PTN that Attak parses and writes back the same
# way. That pins down that our TPS output and PTN notation match what the engine
# expects, which is what the integration rides on.
#
#   godot --headless tools/syntaksTest.tscn
#
# Skips cleanly (exit 0) when the GDExtension is not built for this platform, so
# it can sit in CI on platforms without the native library.

const SIZES := [6]  # syntaks plays 6x6 and nothing else
const SEARCH_NODES := 400
const SEARCH_TIMEOUT_SECONDS := 30.0

var failures: Array[String] = []
# syntaks is built around one fixed komi; anything else it refuses.
const HALF_KOMI := 4


func _ready() -> void:
	# Skipping exits 0, so on its own a green run cannot distinguish "the engine
	# agreed with us" from "the engine never loaded". Set REQUIRE_SYNTAKS=1 wherever
	# the library is supposed to be present -- CI does -- to turn that into a
	# failure.
	var required := OS.get_environment("REQUIRE_SYNTAKS") == "1"

	if not ClassDB.class_exists("SyntaksEngine"):
		if required:
			print("FAIL  REQUIRE_SYNTAKS=1 but SyntaksEngine did not load.")
			print("  - the GDExtension is missing, or failed to dlopen for this platform")
			get_tree().quit(1)
			return
		print("SKIP  SyntaksEngine is not available (GDExtension not built for this platform)")
		get_tree().quit(0)
		return

	var engine = ClassDB.instantiate("SyntaksEngine")

	var sizes: PackedInt32Array = engine.supported_sizes()
	if Array(sizes) != SIZES:
		_fail("engine reports supported sizes %s, expected %s" % [Array(sizes), SIZES])

	# Sizes Attak offers but syntaks cannot play must be refused, not crashed on --
	# syntaks panics internally on unsupported sizes.
	for size in [3, 4, 5, 7, 8]:
		if engine.new_game(size, HALF_KOMI):
			_fail("engine accepted unsupported size %d" % size)

	await _checkSearch(engine)

	print("")
	if failures.is_empty():
		print("PASS  syntaks loads, gates sizes, and searches (sizes %s)" % [SIZES])
		get_tree().quit(0)
	else:
		print("FAIL  %d problem(s):" % failures.size())
		for f in failures:
			print("  - %s" % f)
		get_tree().quit(1)


func _fail(msg: String) -> void:
	if failures.size() < 12:
		failures.append(msg)


# PTN has some optional spelling. A plain flat placement may be written "a1" or
# "Fa1"; a single-piece spread may carry an explicit count; and the "*" smash
# marker is derivable from the position rather than part of the move's identity.
# Normalising these away compares moves, not notation preferences.
func _normalise(ptn: String) -> String:
	var s := ptn.strip_edges().replace("*", "")
	if s.begins_with("F"): s = s.substr(1)
	if s.length() > 1 and s[0] == "1" and not s.contains("<") and not s.contains(">") \
			and not s.contains("+") and not s.contains("-"):
		# not a spread, so a leading "1" would be a file/rank -- leave it alone
		pass
	elif s.length() > 1 and s[0] == "1":
		# leading carry count of 1 is implicit
		s = s.substr(1)
	return s


func _checkSearch(engine) -> void:
	# A search from the opening position must return a move that Attak parses and
	# writes back as the same PTN, on every supported size.
	for size in SIZES:
		if not engine.new_game(size, HALF_KOMI):
			continue

		var state := GameState.emptyState(size, NewSeek.standardFlats[size - 3],
			NewSeek.standardCaps[size - 3], HALF_KOMI / 2.0)
		var tps := state.getTPS()

		if not engine.start_search(tps, SEARCH_NODES, 0):
			_fail("size %d: start_search refused TPS %s" % [size, tps])
			continue

		var deadline := Time.get_ticks_msec() + int(SEARCH_TIMEOUT_SECONDS * 1000.0)
		while engine.is_searching() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame

		if engine.is_searching():
			_fail("size %d: search did not finish within %.0fs" % [size, SEARCH_TIMEOUT_SECONDS])
			continue

		var ptn: String = engine.take_result()
		if ptn.is_empty():
			_fail("size %d: search returned no move" % size)
			continue

		var parsed := Ply.fromPTN(ptn)
		if parsed == null:
			_fail("size %d: could not parse syntaks's move %s" % [size, ptn])
			continue

		if _normalise(parsed.toPTN()) != _normalise(ptn):
			_fail("size %d: syntaks played %s, which we read back as %s" % [size, ptn, parsed.toPTN()])
