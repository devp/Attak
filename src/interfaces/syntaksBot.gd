extends BotInterface
class_name SyntaksBot

# Bot backed by the syntaks engine, via the GDExtension in addons/syntaks.
#
# syntaks is MIT licensed, so unlike the GPL engine this replaces it puts no
# conditions on how Attak itself is licensed or distributed. See
# LICENSE-THIRD-PARTY.md.
#
# The engine class is only ever reached through ClassDB, never named as a type.
# Naming a GDExtension class statically makes the *script* fail to parse wherever
# the extension is absent -- the Web export, or any architecture we did not build
# the library for -- which would take the whole Bot tab down with it.

const ENGINE_CLASS := "SyntaksEngine"

enum STRENGTH {
	FAST,    # fixed node budget: quick and reproducible
	STRONG,  # time budget: scales with whatever device this is running on
}

const FAST_NODES := 40000
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
	botName = "Syntaks"


func _engineInstance():
	if not available(): return null
	if _engine == null:
		_engine = ClassDB.instantiate(ENGINE_CLASS)
	return _engine


# Returns false when the engine cannot take this game, so the caller can fall
# back to LocalBot instead. syntaks plays 6x6 at one fixed komi and nothing else.
func newGame(size: int, halfKomi: int) -> bool:
	var engine = _engineInstance()
	if engine == null: return false
	return engine.new_game(size, halfKomi)


func setStrength(s: int) -> void:
	strength = s
	botName = "Syntaks" if s == STRENGTH.FAST else "Syntaks (strong)"


func supportsSize(size: int) -> bool:
	var engine = _engineInstance()
	return engine != null and engine.supports_size(size)


# The komi a game has to use for this engine to be worth asking. Read from the
# engine rather than hard-coded here so the two cannot drift apart.
func requiredHalfKomi() -> int:
	var engine = _engineInstance()
	return engine.required_half_komi() if engine != null else 0


func _chooseMove(state: GameState) -> Ply:
	if _engine == null:
		return await _fallback(state)

	var nodes: int = FAST_NODES if strength == STRENGTH.FAST else 0
	var millis: int = 0 if strength == STRENGTH.FAST else STRONG_MILLIS

	if not _engine.start_search(state.getTPS(), nodes, millis):
		push_warning("syntaks refused the position, falling back to the built-in bot")
		return await _fallback(state)

	# The search runs on its own thread inside the extension; poll it from here so
	# the frame keeps ticking.
	var deadline := Time.get_ticks_msec() + int(SEARCH_TIMEOUT_SECONDS * 1000.0)
	while _engine.is_searching() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	var ptn: String = _engine.take_result()
	if ptn.is_empty():
		push_warning("syntaks returned no move, falling back to the built-in bot")
		return await _fallback(state)

	var ply := Ply.fromPTN(ptn)
	if ply == null:
		push_warning("could not parse syntaks' move '%s', falling back" % ptn)
		return await _fallback(state)

	return ply


# Any engine failure degrades to a legal random move rather than forfeiting the
# game or stalling the board.
func _fallback(state: GameState) -> Ply:
	await get_tree().process_frame
	return MoveGen.randomPly(state, _rng)
