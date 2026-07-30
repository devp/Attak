extends BotInterface
class_name TiltakBot

# Bot backed by the tiltak engine, via the GDExtension in addons/tiltak.
#
# tiltak is GPL-3.0-or-later, so it is deliberately confined to this file and the
# native crate: LocalBot remains the default, licence-clean opponent, and builds
# without the extension lose nothing but strength. See LICENSE-THIRD-PARTY.md.
#
# The engine class is only ever reached through ClassDB, never named as a type.
# Naming a GDExtension class statically makes the *script* fail to parse wherever
# the extension is absent -- the Web export, or any architecture we did not build
# the library for -- which would take the whole Bot tab down with it.

const ENGINE_CLASS := "TiltakEngine"

# Rough budgets. tiltak is far stronger than anything here needs, so the low end
# is a deliberately small node count rather than a short clock.
enum STRENGTH {
	FAST,    # fixed node budget: quick, reproducible, still well beyond LocalBot
	STRONG,  # time budget: scales with whatever device this is running on
}

const FAST_NODES := 4000
const STRONG_MILLIS := 3000

# A search should never outlast this. If it does, something is wrong in the
# extension and falling back beats hanging the game.
const SEARCH_TIMEOUT_SECONDS := 30.0

var strength: int = STRENGTH.FAST

var _engine = null
var _rng := RandomNumberGenerator.new()


static func available() -> bool:
	return ClassDB.class_exists(ENGINE_CLASS)


func _init() -> void:
	_rng.randomize()
	botName = "Tiltak"


# Returns false when the engine cannot take this game, so the caller can fall
# back to LocalBot instead. tiltak only implements 4x4, 5x5 and 6x6.
func newGame(size: int, halfKomi: int) -> bool:
	if not available(): return false
	if _engine == null:
		_engine = ClassDB.instantiate(ENGINE_CLASS)
	if _engine == null: return false
	return _engine.new_game(size, halfKomi)


func setStrength(s: int) -> void:
	strength = s
	botName = "Tiltak" if s == STRENGTH.FAST else "Tiltak (strong)"


func supportsSize(size: int) -> bool:
	if not available(): return false
	if _engine == null:
		_engine = ClassDB.instantiate(ENGINE_CLASS)
	return _engine != null and _engine.supports_size(size)


func _chooseMove(state: GameState) -> Ply:
	if _engine == null:
		return await _fallback(state)

	var nodes: int = FAST_NODES if strength == STRENGTH.FAST else 0
	var millis: int = 0 if strength == STRENGTH.FAST else STRONG_MILLIS

	if not _engine.start_search(state.getTPS(), nodes, millis):
		push_warning("tiltak refused the position, falling back to the built-in bot")
		return await _fallback(state)

	# The search runs on its own thread inside the extension; poll it from here so
	# the frame keeps ticking.
	var deadline := Time.get_ticks_msec() + int(SEARCH_TIMEOUT_SECONDS * 1000.0)
	while _engine.is_searching() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	var ptn: String = _engine.take_result()
	if ptn.is_empty():
		push_warning("tiltak returned no move, falling back to the built-in bot")
		return await _fallback(state)

	var ply := Ply.fromPTN(ptn)
	if ply == null:
		push_warning("could not parse tiltak's move '%s', falling back" % ptn)
		return await _fallback(state)

	return ply


# Any engine failure degrades to a legal random move rather than forfeiting the
# game or stalling the board.
func _fallback(state: GameState) -> Ply:
	await get_tree().process_frame
	return MoveGen.randomPly(state, _rng)
