extends Node
## Plays a full 6x6 game through the real TEI tab against the bundled engine.
##
## Loads the app's menu, picks the bundled engine in the TEI tab, checks it
## refuses a game the engine can't play (5x5), then starts a 6x6 game as White
## through TEIMenu.start() -- so TEInterface, unchanged, drives the engine as
## Black. A second instance of the engine (via EngineProbe) stands in for the
## human. Every move goes through GameLogic/GameState, so an illegal or
## unparseable move fails the run (debug builds assert).
##
## Desktop:  ATTAK_ENGINE_DIR=<dir with libsyntaks.so> godot --headless tools/teiGameTest.tscn
##
## Prints "TEI_GAME PASS <result> <plies>" or "TEI_GAME FAIL: <why>" and exits
## non-zero on failure.

const TIMEOUT_S := 300
const HUMAN_MOVETIME_MS := 50

var menu: Node
var teiMenu: Node
var human := EngineProbe.new()
var done := false


func _ready() -> void:
	get_tree().create_timer(TIMEOUT_S).timeout.connect(func(): finish("timed out after %ds" % TIMEOUT_S))
	menu = load("res://scenes/UI/Menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	teiMenu = menu.get_node("TEI")

	if teiMenu.bundled.is_empty():
		return finish("no bundled engine listed in the TEI tab (set ATTAK_ENGINE_DIR on desktop)")
	var engine: Dictionary = teiMenu.selectedEngine()
	print("TEI tab engine: %s at %s" % [engine.get("name"), engine.get("path")])
	if engine.is_empty():
		return finish("the TEI tab didn't preselect the bundled engine")

	# An unsupported size must be refused before anything is spawned.
	_selectId(teiMenu.sizeEntry, 5)
	await teiMenu.start()
	if teiMenu.tei.state != TEI.INACTIVE:
		return finish("5x5 game was started against %s" % engine["name"])
	print("5x5 refused as expected")

	_selectId(teiMenu.sizeEntry, 6)
	teiMenu.komiEntry.value = 2.0
	_selectId(teiMenu.colorEntry, GameState.WHITE)
	teiMenu.timeEntry.value = 1.0
	teiMenu.incEntry.value = 0.0

	var err := human.start(engine["path"])
	if not err.is_empty() or not await human.handshake():
		return finish("couldn't start the stand-in human engine: " + err)
	human.send("teinewgame 6")

	GameLogic.setup.connect(func(_g, _s): _humanMove.call_deferred(), CONNECT_ONE_SHOT)
	GameLogic.move.connect(_onMove)
	GameLogic.end.connect(_onEnd)
	await teiMenu.start()
	if teiMenu.tei.state == TEI.INACTIVE:
		return finish("TEIMenu.start() did not start the engine")


func _selectId(button: OptionButton, id: int) -> void:
	button.select(button.get_item_index(id))


func _onMove(origin: Node, _ply: Ply) -> void:
	if origin == teiMenu.tei and GameLogic.active:
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
	if type == GameState.DEFAULT_WIN_WHITE or type == GameState.DEFAULT_WIN_BLACK:
		return finish("game ended by default (%s): crash, timeout or resignation" % result)
	finish("", "%s %d" % [result, GameLogic.history.size()])


func finish(why: String, summary := "") -> void:
	if done: return
	done = true
	human.stop()
	if why.is_empty():
		print("TEI_GAME PASS ", summary)
	else:
		print("TEI_GAME FAIL: ", why)
	get_tree().quit(0 if why.is_empty() else 1)
