extends BotInterface
class_name TakticianBot

# Bot backed by the Taktician engine, via the GDExtension in addons/taktician.
#
# Taktician is MIT licensed, so unlike the engine this replaced there is nothing
# to quarantine: it can ship in a public build without a licensing decision. See
# LICENSE-THIRD-PARTY.md. It also plays every board size Attak offers (3x3 to
# 8x8), so there is no size that silently drops back to LocalBot.
#
# The engine class is only ever reached through ClassDB, never named as a type.
# Naming a GDExtension class statically makes the *script* fail to parse wherever
# the extension is absent -- the Web export, or any architecture we did not build
# the library for -- which would take the whole Bot tab down with it.

const ENGINE_CLASS := "TakticianEngine"

# Rough budgets. Taktician is far stronger than anything here needs, so the low
# end is a shallow, reproducible search rather than a short clock.
enum STRENGTH {
	FAST,    # fixed depth: quick, reproducible, still well beyond LocalBot
	STRONG,  # time budget: scales with whatever device this is running on
}

# Taktician deepens iteratively and decides between depths whether the next one
# fits in what is left, so both limits below are checked at that boundary rather
# than interrupting a search underway. Whatever stops it, the move played is the
# best from the last depth it finished -- never a random one.
#
# Depth is what bounds FAST; MAX_EVALS is a backstop for the rare position where a
# shallow search still explodes on a slow device.
const FAST_DEPTH := 4
const FAST_MAX_EVALS := 300000

# STRONG leaves the depth open (0 means Taktician's own ceiling) and stops on the
# clock instead. It often answers well inside this, having judged the next depth
# too expensive to start.
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
	botName = "Taktician"


# Returns false when the engine cannot take this game, so the caller can fall
# back to LocalBot instead. Taktician plays every size Attak offers, but it has
# no notion of komi, so a komi game is refused.
func newGame(size: int, halfKomi: int) -> bool:
	if not available(): return false
	if _engine == null:
		_engine = ClassDB.instantiate(ENGINE_CLASS)
	if _engine == null: return false
	return _engine.new_game(size, halfKomi)


func setStrength(s: int) -> void:
	strength = s
	botName = "Taktician" if s == STRENGTH.FAST else "Taktician (strong)"


func supportsSize(size: int) -> bool:
	if not available(): return false
	if _engine == null:
		_engine = ClassDB.instantiate(ENGINE_CLASS)
	return _engine != null and _engine.supports_size(size)


func _chooseMove(state: GameState) -> Ply:
	if _engine == null:
		return await _fallback(state)

	var fast := strength == STRENGTH.FAST
	var depth: int = FAST_DEPTH if fast else 0
	var millis: int = 0 if fast else STRONG_MILLIS
	var maxEvals: int = FAST_MAX_EVALS if fast else 0

	if not _engine.start_search(state.getTPS(), depth, millis, maxEvals):
		push_warning("Taktician refused the position, falling back to the built-in bot")
		return await _fallback(state)

	# The search runs on its own thread inside the extension; poll it from here so
	# the frame keeps ticking.
	var deadline := Time.get_ticks_msec() + int(SEARCH_TIMEOUT_SECONDS * 1000.0)
	while _engine.is_searching() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame

	var ptn: String = _engine.take_result()
	if ptn.is_empty():
		push_warning("Taktician returned no move, falling back to the built-in bot")
		return await _fallback(state)

	var ply := Ply.fromPTN(ptn)
	if ply == null:
		push_warning("could not parse Taktician's move '%s', falling back" % ptn)
		return await _fallback(state)

	return ply


# Any engine failure degrades to a legal random move rather than forfeiting the
# game or stalling the board.
func _fallback(state: GameState) -> Ply:
	await get_tree().process_frame
	return MoveGen.randomPly(state, _rng)
