extends Node
class_name BotInterface

# Shared plumbing for an in-process bot opponent.
#
# This mirrors the contract TEInterface already implements against GameLogic --
# startGame / sendMove / onResign / endGame -- but without a subprocess, because
# Android forbids executing a bundled binary and Godot cannot spawn one there.
# Subclasses supply _chooseMove(); everything else is turn plumbing.
#
# TEInterface is deliberately left alone rather than refactored onto this base:
# it carries an unresolved crash bug (its own `FATAL` TODO) and it is the working
# desktop path, so reworking it while also landing Android would be two risks in
# one change.
#
# Thinking happens on the main thread as a coroutine, not on a Thread. The Web
# export is built with thread_support=false, where Godot runs a Thread's callable
# synchronously and would freeze the frame; yielding cooperatively behaves the
# same everywhere. It also means GameLogic.doMove can be called directly --
# TEInterface only needs call_deferred because its parser runs on a reader thread.

# How long to yield the frame for while searching. Anything much above a frame's
# worth makes the UI hitch.
const BUDGET_MS := 8

# A visible pause before replying. Instant answers read as a glitch rather than
# an opponent.
const MIN_THINK_SECONDS := 0.35

var botName: String = "Bot"
var myColor: int = -1

var thinking: bool = false

# Overridable so headless tests can play at full speed.
var thinkDelay: float = MIN_THINK_SECONDS

var _budgetStart: int = 0


func startGame(game: GameData) -> void:
	myColor = GameState.WHITE if game.playerWhite == GameData.BOT else GameState.BLACK
	if game.playerWhite == GameData.BOT:
		game.playerWhiteName = botName
	else:
		game.playerBlackName = botName

	# doSetup emits end(ONGOING) for any game already in progress, so connect
	# afterwards -- otherwise we would tear ourselves down immediately.
	GameLogic.doSetup(game)
	_connectSignals()

	if GameLogic.currentPly() % 2 == myColor:
		_think()


func _connectSignals() -> void:
	if not GameLogic.move.is_connected(sendMove): GameLogic.move.connect(sendMove)
	if not GameLogic.end.is_connected(endGame): GameLogic.end.connect(endGame)
	if not GameLogic.resign.is_connected(onResign): GameLogic.resign.connect(onResign)


func _disconnectSignals() -> void:
	if GameLogic.move.is_connected(sendMove): GameLogic.move.disconnect(sendMove)
	if GameLogic.end.is_connected(endGame): GameLogic.end.disconnect(endGame)
	if GameLogic.resign.is_connected(onResign): GameLogic.resign.disconnect(onResign)


func sendMove(origin: Node, _ply: Ply) -> void:
	if origin == self: return
	_think()


func onResign() -> void:
	# `resign` can only come from the human here, so the bot takes the win.
	GameLogic.endGame(GameState.DEFAULT_WIN_WHITE if myColor == GameState.WHITE \
		else GameState.DEFAULT_WIN_BLACK)


func endGame(type: int) -> void:
	if type == GameState.ONGOING and GameLogic.active: return
	thinking = false
	_disconnectSignals()


func _think() -> void:
	if thinking or not GameLogic.active: return
	if GameLogic.currentPly() % 2 != myColor: return

	thinking = true
	# The board we are about to reason about. If anything changes it while we're
	# thinking -- a new game, an undo -- the answer is stale and gets dropped.
	var token := GameLogic.history.size()

	if thinkDelay > 0.0:
		await get_tree().create_timer(thinkDelay).timeout
	else:
		await get_tree().process_frame

	if not _stillOurTurn(token):
		thinking = false
		return

	_budgetStart = Time.get_ticks_msec()
	var ply: Ply = await _chooseMove(GameLogic.activeState())
	thinking = false

	if ply == null:
		# No legal reply. Concede rather than hanging the game.
		GameLogic.endGame(GameState.DEFAULT_WIN_WHITE if myColor == GameState.BLACK \
			else GameState.DEFAULT_WIN_BLACK)
		return

	if not _stillOurTurn(token): return
	GameLogic.doMove(self, ply)


func _stillOurTurn(token: int) -> bool:
	return GameLogic.active \
		and GameLogic.history.size() == token \
		and GameLogic.currentPly() % 2 == myColor


# Subclasses call this inside long searches to keep the frame alive.
func _breathe() -> void:
	if Time.get_ticks_msec() - _budgetStart < BUDGET_MS: return
	await get_tree().process_frame
	_budgetStart = Time.get_ticks_msec()


# Abstract. Returns the ply to play, or null if there is none.
func _chooseMove(_state: GameState) -> Ply:
	await get_tree().process_frame
	return null
