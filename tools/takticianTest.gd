extends Node

# Differential test: Attak's GDScript move generator against Taktician's.
#
#   godot --headless tools/takticianTest.tscn
#
# This is the most valuable test in the project. Taktician is a mature,
# independently written engine, so agreeing with its move list on thousands of
# positions is much stronger evidence that src/Logic/moveGen.gd is correct than
# any self-consistency check can be. It also pins down that our TPS output and PTN
# notation match what a real engine expects, which is what any engine integration
# rides on.
#
# Taktician plays every size Attak offers, so unlike the engine this replaced the
# comparison covers the whole range rather than the middle of it -- 3x3, 7x7 and
# 8x8 were never checked against anything before.
#
# Skips cleanly (exit 0) when the GDExtension is not built for this platform, so
# it can sit in CI on platforms without the native library.

const SIZES := [3, 4, 5, 6, 7, 8]
const GAMES_PER_SIZE := 6

# The search check below only needs a legal move, not a good one, and it runs on
# every size -- so keep it shallow.
const SEARCH_DEPTH := 3
const SEARCH_TIMEOUT_SECONDS := 30.0

var failures: Array[String] = []
var rng := RandomNumberGenerator.new()
var positionsCompared := 0


func _ready() -> void:
	# Skipping exits 0, so on its own a green run cannot distinguish "the engine
	# agreed with us" from "the engine never loaded". Set REQUIRE_TAKTICIAN=1
	# wherever the library is supposed to be present -- CI does -- to turn that
	# into a failure.
	var required := OS.get_environment("REQUIRE_TAKTICIAN") == "1"

	if not ClassDB.class_exists("TakticianEngine"):
		if required:
			print("FAIL  REQUIRE_TAKTICIAN=1 but TakticianEngine did not load.")
			print("  - the GDExtension is missing, or failed to dlopen for this platform")
			get_tree().quit(1)
			return
		print("SKIP  TakticianEngine is not available (GDExtension not built for this platform)")
		get_tree().quit(0)
		return

	rng.seed = 909090

	var engine = ClassDB.instantiate("TakticianEngine")

	var sizes: PackedInt32Array = engine.supported_sizes()
	if Array(sizes) != SIZES:
		_fail("engine reports supported sizes %s, expected %s" % [Array(sizes), SIZES])

	# Every size the menu offers must be playable, and anything outside the range
	# must be refused rather than crashed on -- Taktician indexes per-size tables
	# and panics past their end.
	for size in SIZES:
		if not engine.new_game(size, 0):
			_fail("engine refused supported size %d" % size)
	for size in [2, 9]:
		if engine.new_game(size, 0):
			_fail("engine accepted out-of-range size %d" % size)

	# Taktician has no komi. Refusing is what lets BotMenu fall back rather than
	# play a subtly different game to the one shown on the board.
	if engine.new_game(5, 4):
		_fail("engine accepted a komi game it cannot actually play")

	for size in SIZES:
		for game in GAMES_PER_SIZE:
			_compareGame(engine, size, game)

	await _checkSearch(engine)

	print("")
	if failures.is_empty():
		print("PASS  move lists agree with Taktician across %d positions (sizes %s)"
			% [positionsCompared, SIZES])
		get_tree().quit(0)
	else:
		print("FAIL  %d problem(s):" % failures.size())
		for f in failures:
			print("  - %s" % f)
		get_tree().quit(1)


func _fail(msg: String) -> void:
	if failures.size() < 12:
		failures.append(msg)


func _compareGame(engine, size: int, gameIndex: int) -> void:
	if not engine.new_game(size, 0):
		_fail("engine refused a %dx%d game" % [size, size])
		return

	var flats: int = NewSeek.standardFlats[size - 3]
	var caps: int = NewSeek.standardCaps[size - 3]
	var state := GameState.emptyState(size, flats, caps, 0.0)

	var plyCap: int = (flats + caps) * 4 + size * size * 2
	var plies := 0

	while state.win == GameState.ONGOING and plies < plyCap:
		var ours := MoveGen.legalPlies(state)
		if ours.is_empty(): return

		# Taktician's own opening handling is built in, so the swap plies are compared
		# too -- they are exactly where our placedColor rule could be wrong.
		var tps := state.getTPS()
		var theirs: PackedStringArray = engine.legal_moves(tps)

		if theirs.is_empty():
			_fail("size %d game %d: Taktician returned no moves for TPS %s" % [size, gameIndex, tps])
			return

		_compare(ours, theirs, size, gameIndex, tps)
		positionsCompared += 1

		var chosen: Ply = ours[rng.randi() % ours.size()]
		var next: GameState = state.apply(chosen)
		if next == null: return
		state = next
		plies += 1


func _compare(ours: Array[Ply], theirs: PackedStringArray, size: int, gameIndex: int, tps: String) -> void:
	var mine := {}
	for ply in ours:
		mine[_normalise(ply.toPTN())] = true

	var yours := {}
	for ptn in theirs:
		yours[_normalise(ptn)] = true

	var missing: Array[String] = []
	for ptn in yours:
		if not mine.has(ptn): missing.append(ptn)

	var extra: Array[String] = []
	for ptn in mine:
		if not yours.has(ptn): extra.append(ptn)

	if not missing.is_empty():
		missing.sort()
		_fail("size %d game %d: we miss %d legal move(s) Taktician found: %s\n    TPS: %s"
			% [size, gameIndex, missing.size(), ", ".join(missing.slice(0, 8)), tps])

	if not extra.is_empty():
		extra.sort()
		_fail("size %d game %d: we generate %d move(s) Taktician considers illegal: %s\n    TPS: %s"
			% [size, gameIndex, extra.size(), ", ".join(extra.slice(0, 8)), tps])


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
	# A search must return a move that our own generator agrees is legal, from the
	# opening position on every supported size.
	for size in SIZES:
		if not engine.new_game(size, 0):
			continue

		var state := GameState.emptyState(size, NewSeek.standardFlats[size - 3],
			NewSeek.standardCaps[size - 3], 0.0)
		var tps := state.getTPS()

		if not engine.start_search(tps, SEARCH_DEPTH, 0, 0):
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
			_fail("size %d: could not parse Taktician's move %s" % [size, ptn])
			continue

		var legal := {}
		for ply in MoveGen.legalPlies(state):
			legal[_normalise(ply.toPTN())] = true
		if not legal.has(_normalise(ptn)):
			_fail("size %d: Taktician played %s, which we consider illegal" % [size, ptn])
