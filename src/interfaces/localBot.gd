extends BotInterface
class_name LocalBot

# The built-in GDScript opponent. Deliberately weak: it plays legally, it will
# take a win it can see and avoid handing you one, and that is all. It exists so
# that offline play works everywhere -- including the Web export, where
# GDExtension is unavailable, and on board sizes a native engine may not support.

enum DIFFICULTY {
	RANDOM,      # legal moves, nothing more
	CASUAL,      # takes wins, avoids immediate losses
	THOUGHTFUL,  # as CASUAL, plus a crude flat-count preference
}

# Ceiling on how many candidate moves get evaluated. Full enumeration on a large
# board with tall stacks runs to thousands of plies, and each evaluation copies
# the whole board via GameState.apply(). Sampling keeps a turn near-instant at
# the cost of strength we do not have anyway.
const MAX_CANDIDATES := 120

var difficulty: int = DIFFICULTY.CASUAL

var _rng := RandomNumberGenerator.new()

const NAMES := {
	DIFFICULTY.RANDOM: "Scatterbrain",
	DIFFICULTY.CASUAL: "Novice Bot",
	DIFFICULTY.THOUGHTFUL: "Careful Bot",
}


func _init() -> void:
	_rng.randomize()


func setDifficulty(d: int) -> void:
	difficulty = d
	botName = NAMES.get(d, "Bot")


func _chooseMove(state: GameState) -> Ply:
	if difficulty == DIFFICULTY.RANDOM:
		await _breathe()
		return MoveGen.randomPly(state, _rng)

	var candidates := _candidates(state)
	if candidates.is_empty(): return null

	var best: Array[Ply] = []
	var bestScore := -INF

	for ply in candidates:
		await _breathe()

		var after: GameState = state.apply(ply)
		if after == null: continue

		var score := _score(after)

		# An immediate win ends the search -- there is nothing better.
		if score >= WIN_SCORE:
			return ply

		if score > bestScore:
			bestScore = score
			best = [ply] as Array[Ply]
		elif score == bestScore:
			best.append(ply)

	if best.is_empty(): return null
	return best[_rng.randi() % best.size()]


const WIN_SCORE := 1000000.0
const LOSS_SCORE := -1000000.0


func _candidates(state: GameState) -> Array[Ply]:
	var all := MoveGen.legalPlies(state)
	if all.size() <= MAX_CANDIDATES: return all
	all.shuffle()
	return all.slice(0, MAX_CANDIDATES)


# Scores a position from this bot's point of view.
func _score(after: GameState) -> float:
	if after.win != GameState.ONGOING:
		return _terminalScore(after.win)

	# Does this hand the opponent a win they can take right now? Checking every
	# reply is far too slow in GDScript, so sample -- which means the bot misses
	# threats. That is acceptable, and on RANDOM/CASUAL it is the point.
	if difficulty >= DIFFICULTY.CASUAL:
		if _opponentHasImmediateWin(after):
			return LOSS_SCORE

	if difficulty >= DIFFICULTY.THOUGHTFUL:
		return _flatAdvantage(after)

	return 0.0


func _terminalScore(win: int) -> float:
	var whiteWins := win in [GameState.ROAD_WIN_WHITE, GameState.FLAT_WIN_WHITE,
		GameState.DEFAULT_WIN_WHITE]
	var blackWins := win in [GameState.ROAD_WIN_BLACK, GameState.FLAT_WIN_BLACK,
		GameState.DEFAULT_WIN_BLACK]
	if not whiteWins and not blackWins: return 0.0  # draw
	var weWon := whiteWins if myColor == GameState.WHITE else blackWins
	return WIN_SCORE if weWon else LOSS_SCORE


const THREAT_SAMPLE := 24


func _opponentHasImmediateWin(after: GameState) -> bool:
	var replies := MoveGen.legalPlies(after)
	if replies.size() > THREAT_SAMPLE:
		replies.shuffle()
		replies = replies.slice(0, THREAT_SAMPLE)
	for reply in replies:
		var result: GameState = after.apply(reply)
		if result == null: continue
		if result.win == GameState.ONGOING: continue
		if _terminalScore(result.win) <= LOSS_SCORE: return true
	return false


# Flats on top of stacks, counted from our side. Deliberately crude: it gives the
# bot a reason to keep flats on the board rather than only building walls.
func _flatAdvantage(state: GameState) -> float:
	var mine := 0
	var theirs := 0
	for x in state.size:
		for y in state.size:
			var pile: GameState.Pile = state.board[x][y]
			if pile.is_empty() or pile.type != GameState.FLAT: continue
			if pile.pieces[-1] % 2 == myColor: mine += 1
			else: theirs += 1
	return float(mine - theirs)
