extends Node
## Plays a full 6x6 game through the real Vs Bot tab against the bundled engine.
##
## Loads the app's menu, checks the Vs Bot tab is shown and offers only what the
## engine plays (6x6, komi 2), then starts a game as White through
## BotMenu.start() -- so TEInterface, unchanged, drives the engine as Black. A
## second instance of the engine (via EngineProbe) stands in for the human.
## Every move goes through GameLogic/GameState, so an illegal or unparseable
## move fails the run (debug builds assert).
##
## Desktop:  ATTAK_ENGINE_DIR=<dir with libsyntaks.so> godot --headless tools/teiGameTest.tscn
## Android:  the CI-only "Android x86_64 (TEI smoke test)" preset (tools/smoke-preset.py)
##           launches straight into this scene.
##
## Prints "TEI_GAME PASS <result> <plies>" or "TEI_GAME FAIL: <why>" and exits
## non-zero on failure.

const TIMEOUT_S := 300
const HUMAN_MOVETIME_MS := 50

var menu: Node
var botMenu: Node
var human := EngineProbe.new()
var done := false


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_S).timeout.connect(func(): finish("timed out after %ds" % TIMEOUT_S))
	menu = load("res://scenes/UI/Menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	botMenu = menu.get_node("Bot")

	print("platform: %s %s, engine dir: '%s'" % [OS.get_name(), Engine.get_architecture_name(), BundledEngines.directory()])
	if botMenu.engines.is_empty():
		return finish("no bundled engine found (set ATTAK_ENGINE_DIR on desktop)")
	if not menu.get_node("tabBar/Play/SubTabs/Bot").visible:
		return finish("the Vs Bot tab is hidden although an engine is bundled")
	var engine: Dictionary = botMenu.engine()
	print("Vs Bot engine: %s at %s" % [engine["name"], engine["path"]])
	var sizes := range(botMenu.sizeEntry.item_count).map(func(i): return botMenu.sizeEntry.get_item_id(i))
	if sizes != [6] or botMenu.komi() != 2.0:
		return finish("Vs Bot offers sizes %s, komi %s; syntaks plays 6x6 komi 2 only" % [sizes, botMenu.komi()])

	_selectId(botMenu.colorEntry, GameState.WHITE)
	botMenu.timeEntry.value = 1.0
	botMenu.incEntry.value = 0.0

	var err := human.start(engine["path"])
	if not err.is_empty() or not await human.handshake():
		return finish("couldn't start the stand-in human engine: " + err)
	human.send("teinewgame 6")

	GameLogic.setup.connect(func(_g, _s): _humanMove.call_deferred(), CONNECT_ONE_SHOT)
	GameLogic.move.connect(_onMove)
	GameLogic.end.connect(_onEnd)
	await botMenu.start()
	if botMenu.tei.state == TEI.INACTIVE:
		return finish("BotMenu.start() did not start the engine")


func _selectId(button: OptionButton, id: int) -> void:
	button.select(button.get_item_index(id))


func _onMove(origin: Node, _ply: Ply) -> void:
	if origin == botMenu.tei and GameLogic.active:
		_humanMove()


func _humanMove() -> void:
	if done: return
	var pos := "position startpos moves"
	for ply in GameLogic.history:
		pos += " " + ply.toPTN()
	human.send(pos)
	human.send("go movetime %d" % HUMAN_MOVETIME_MS)
	var best: String = await human.wait_for("bestmove", 10.0)
	if best.is_empty():
		return finish("stand-in human engine gave no move")
	if done or not GameLogic.active: return
	GameLogic.doMove(self, Ply.fromPTN(best.split(" ")[1]))


func _onEnd(type: int) -> void:
	if type == GameState.ONGOING or done:
		return # doSetup ends the previous (idle) game this way
	var result: String = GameState.resultStrings[type]
	print(GameLogic.getPTN())
	print("game over: ", result)
	if type == GameState.DEFAULT_WIN_WHITE or type == GameState.DEFAULT_WIN_BLACK:
		return finish("game ended by default (%s): crash, timeout or resignation" % result)
	finish("", "%s %d" % [result, GameLogic.history.size()])


func finish(why: String, summary := "") -> void:
	if done: return
	done = true
	if why.is_empty():
		print("TEI_GAME PASS ", summary)
	else:
		print("TEI_GAME FAIL: ", why)
	human.stop()
	get_tree().quit(0 if why.is_empty() else 1)
