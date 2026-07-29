extends Node

# Validation harness for src/Logic/moveGen.gd. Plays random self-play games
# across every board size and checks the generator against the rules that
# GameState already enforces.
#
#   godot --headless tools/moveGenTest.tscn
#
# Exits non-zero on the first failure. Run this with the *editor* binary, not an
# exported build: GameState's asserts are compiled out of release templates, so
# an illegal ply would slip through silently there.

# This runs as a scene rather than via --script on purpose. Under --script the
# base of a class_name hierarchy is not reliably initialised before its
# subclasses, so Ply's static helpers intermittently fail to resolve from
# Place/Spread -- which silently empties toPTN() and would mask the checks below.
const GAMES_PER_SIZE := 12

# Random play left to itself will happily shuffle stacks forever without ever
# spending a reserve, so games would never end and termination would be
# untestable. Biasing towards placement drains the reserves, which is what makes
# the "every game reaches a result" check meaningful.
const PLACE_BIAS := 0.7

var failures: Array[String] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 20260729

	var totalPlies := 0
	for size in range(3, 9):
		for game in GAMES_PER_SIZE:
			totalPlies += _playGame(size, game)

	print("")
	if failures.is_empty():
		print("PASS  %d plies across sizes 3-8" % totalPlies)
		get_tree().quit(0)
	else:
		print("FAIL  %d problem(s):" % failures.size())
		for f in failures:
			print("  - %s" % f)
		get_tree().quit(1)


func _pick(moves: Array[Ply]) -> Ply:
	var places: Array[Ply] = []
	var spreads: Array[Ply] = []
	for ply in moves:
		if ply is Place: places.append(ply)
		else: spreads.append(ply)
	if places.is_empty(): return spreads[rng.randi() % spreads.size()]
	if spreads.is_empty(): return places[rng.randi() % places.size()]
	var pool := places if rng.randf() < PLACE_BIAS else spreads
	return pool[rng.randi() % pool.size()]


func _fail(msg: String) -> void:
	if failures.size() < 20:
		failures.append(msg)


func _playGame(size: int, gameIndex: int) -> int:
	var flats: int = NewSeek.standardFlats[size - 3]
	var caps: int = NewSeek.standardCaps[size - 3]
	var state := GameState.emptyState(size, flats, caps, 0.0)

	# With PLACE_BIAS the reserves drain steadily, so a game that runs past this
	# points at a win-detection bug rather than an unlucky game.
	var plyCap: int = (flats + caps) * 8 + size * size * 4
	var plies := 0

	while state.win == GameState.ONGOING and plies < plyCap:
		var moves := MoveGen.legalPlies(state)

		if moves.is_empty():
			_fail("size %d game %d: no legal plies at ply %d, but win == ONGOING\nTPS: %s"
				% [size, gameIndex, state.ply, state.getTPS()])
			return plies

		_checkPtnRoundTrip(moves, size, gameIndex, state)
		_checkRandomPly(state, size, gameIndex)

		var chosen: Ply = _pick(moves)
		var before := state.getTPS()
		var next: GameState = state.apply(chosen)

		if next == null:
			_fail("size %d game %d: apply() returned null for %s (TPS %s)"
				% [size, gameIndex, chosen.toPTN(), before])
			return plies

		_checkReserves(next, size, gameIndex, chosen, before)

		state = next
		plies += 1

	if state.win == GameState.ONGOING:
		_fail("size %d game %d: still ONGOING after %d plies (cap %d)\nTPS: %s"
			% [size, gameIndex, plies, plyCap, state.getTPS()])

	return plies


# Every generated ply must survive PTN serialisation intact. This is the cheapest
# check that catches malformed drop sequences and mishandled smash flags, since
# the notation is what the bot seam and any engine integration exchange.
func _checkPtnRoundTrip(moves: Array[Ply], size: int, gameIndex: int, state: GameState) -> void:
	for ply in moves:
		var ptn := ply.toPTN()
		var parsed := Ply.fromPTN(ptn)
		if parsed == null:
			_fail("size %d game %d: Ply.fromPTN() rejected our own output %s (TPS %s)"
				% [size, gameIndex, ptn, state.getTPS()])
			continue
		if parsed.toPTN() != ptn:
			_fail("size %d game %d: PTN round-trip changed %s -> %s"
				% [size, gameIndex, ptn, parsed.toPTN()])


# randomPly() takes a separate, non-enumerating path, so it needs its own check
# that what it returns is actually in the legal set.
func _checkRandomPly(state: GameState, size: int, gameIndex: int) -> void:
	var sampled := MoveGen.randomPly(state, rng)
	if sampled == null:
		_fail("size %d game %d: randomPly() returned null at ply %d (TPS %s)"
			% [size, gameIndex, state.ply, state.getTPS()])
		return
	var legal := {}
	for ply in MoveGen.legalPlies(state):
		legal[ply.toPTN()] = true
	if not legal.has(sampled.toPTN()):
		_fail("size %d game %d: randomPly() produced illegal %s (TPS %s)"
			% [size, gameIndex, sampled.toPTN(), state.getTPS()])


# Reserves.getPiece() decrements unconditionally, so a placement generated
# without stock available goes negative rather than failing loudly.
func _checkReserves(state: GameState, size: int, gameIndex: int, ply: Ply, beforeTps: String) -> void:
	for color in [GameState.WHITE, GameState.BLACK]:
		if state.reserves.flats[color] < 0:
			_fail("size %d game %d: %s drove flats[%d] to %d (TPS before: %s)"
				% [size, gameIndex, ply.toPTN(), color, state.reserves.flats[color], beforeTps])
		if state.reserves.caps[color] < 0:
			_fail("size %d game %d: %s drove caps[%d] to %d (TPS before: %s)"
				% [size, gameIndex, ply.toPTN(), color, state.reserves.caps[color], beforeTps])
