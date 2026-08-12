extends Node

# End-to-end check of the local bot seam: LocalBot driving real games through the
# GameLogic autoload, with random play standing in for the human.
#
#   godot --headless tools/botTest.tscn
#
# This exercises what the move generator test cannot -- turn alternation, the
# GameLogic.move/end/resign wiring, and that the bot actually answers when it is
# its turn rather than stalling. Exits non-zero on failure.

const SIZES := [4, 6]
const DIFFICULTIES := [
	LocalBot.DIFFICULTY.RANDOM,
	LocalBot.DIFFICULTY.CASUAL,
	LocalBot.DIFFICULTY.THOUGHTFUL,
]

# Generous: a stalled bot shows up as this expiring, so it only needs to be long
# enough that a legitimately slow search never trips it.
const REPLY_TIMEOUT_SECONDS := 20.0

var failures: Array[String] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 4242

	for size in SIZES:
		for difficulty in DIFFICULTIES:
			for botIsWhite in [true, false]:
				await _playGame(size, difficulty, botIsWhite)

	print("")
	if failures.is_empty():
		print("PASS  bot seam OK across sizes %s, all difficulties, both colours" % [SIZES])
		get_tree().quit(0)
	else:
		print("FAIL  %d problem(s):" % failures.size())
		for f in failures:
			print("  - %s" % f)
		get_tree().quit(1)


func _fail(msg: String) -> void:
	if failures.size() < 20:
		failures.append(msg)


func _playGame(size: int, difficulty: int, botIsWhite: bool) -> void:
	var bot := LocalBot.new()
	bot.thinkDelay = 0.0
	bot.setDifficulty(difficulty)
	add_child(bot)

	var label := "size %d diff %d bot=%s" % [size, difficulty, "white" if botIsWhite else "black"]

	var game := GameData.new(
		"", size,
		GameData.BOT if botIsWhite else GameData.LOCAL,
		GameData.LOCAL if botIsWhite else GameData.BOT,
		bot.botName if botIsWhite else "Tester",
		"Tester" if botIsWhite else bot.botName,
		0, 0, 0, 0, 0,
		NewSeek.standardFlats[size - 3], NewSeek.standardCaps[size - 3],
		SeekData.UNRATED
	)

	bot.startGame(game)

	var botColor: int = GameState.WHITE if botIsWhite else GameState.BLACK
	var plyCap: int = (game.flats + game.caps) * 8 + size * size * 4
	var plies := 0

	while GameLogic.active and plies < plyCap:
		if GameLogic.currentPly() % 2 == botColor:
			# The bot owns this turn. Wait for it to land a move.
			var before := GameLogic.history.size()
			if not await _waitForBot(before):
				_fail("%s: bot did not reply within %.0fs at ply %d"
					% [label, REPLY_TIMEOUT_SECONDS, GameLogic.currentPly()])
				break
		else:
			var state := GameLogic.activeState()
			var ply := MoveGen.randomPly(state, rng)
			if ply == null:
				_fail("%s: no legal move for the human side at ply %d (TPS %s)"
					% [label, state.ply, state.getTPS()])
				break
			GameLogic.doMove(self, ply)
		plies += 1

	if GameLogic.active:
		_fail("%s: game never ended (%d plies, cap %d)" % [label, plies, plyCap])
	elif plies == 0:
		_fail("%s: no plies were played at all" % label)

	# The bot must let go of GameLogic once the game is over, or the next game
	# would get two bots answering on the same signal.
	if GameLogic.move.is_connected(bot.sendMove):
		_fail("%s: bot stayed connected to GameLogic.move after the game ended" % label)

	bot.queue_free()
	await get_tree().process_frame


func _waitForBot(historyBefore: int) -> bool:
	var deadline := Time.get_ticks_msec() + int(REPLY_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if GameLogic.history.size() != historyBefore: return true
		if not GameLogic.active: return true
	return false
