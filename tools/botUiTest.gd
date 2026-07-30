extends Node

# Smoke test for the "Vs Bot" tab wiring, driving the real Menu scene.
#
#   godot --headless tools/botUiTest.tscn
#
# Checks the things that only break once the tab is mounted in Menu.tscn: that
# the panel is a direct child of the Selector root (Selector.select asserts it),
# that the tab button is connected, and that pressing Start Game actually gets a
# game going with the bot on one side and a reply coming back.

const MENU := "res://scenes/UI/Menu.tscn"
const REPLY_TIMEOUT_SECONDS := 20.0

var failures: Array[String] = []


func _ready() -> void:
	var menu: Node = load(MENU).instantiate()
	add_child(menu)
	await get_tree().process_frame

	var panel: Node = menu.get_node_or_null("Bot")
	var button: Node = menu.get_node_or_null("tabBar/Play/SubTabs/Bot")

	if panel == null:
		_fail("Menu.tscn has no 'Bot' panel as a direct child of the Selector root")
	if button == null:
		_fail("Menu.tscn has no 'Bot' button under tabBar/Play/SubTabs")

	if panel != null and button != null:
		# Selector.select() asserts its target is a direct child, so a wrong
		# parent shows up here rather than at runtime on the device.
		button.pressed.emit()
		await get_tree().process_frame
		if not panel.visible:
			_fail("pressing the Bot tab did not show the Bot panel")

		await _startGameAndCheckReply(panel)
		await _checkTiltakOption(panel)

	print("")
	if failures.is_empty():
		print("PASS  Vs Bot tab is wired up and starts a playable game")
		get_tree().quit(0)
	else:
		print("FAIL  %d problem(s):" % failures.size())
		for f in failures:
			print("  - %s" % f)
		get_tree().quit(1)


func _fail(msg: String) -> void:
	failures.append(msg)


func _startGameAndCheckReply(panel: Node) -> void:
	var bot = panel.get_node_or_null("Bot")
	if bot == null:
		_fail("Bot panel has no LocalBot child node")
		return
	bot.thinkDelay = 0.0

	# Play as Black so the bot has to open, which exercises the "bot moves first"
	# branch of startGame.
	panel.colorEntry.select(1)
	panel.sizeEntry.select(2)   # 5x5
	panel.diffEntry.select(1)   # Novice

	panel.start()
	await get_tree().process_frame

	if not GameLogic.active:
		_fail("no game is active after pressing Start Game")
		return
	if GameLogic.gameData.size != 5:
		_fail("expected a 5x5 game, got %dx%d" % [GameLogic.gameData.size, GameLogic.gameData.size])
	if GameLogic.gameData.playerWhite != GameData.BOT:
		_fail("expected the bot to be White, got playerWhite=%d" % GameLogic.gameData.playerWhite)
	if GameLogic.gameData.playerBlack != GameData.LOCAL:
		_fail("expected the human to be Black, got playerBlack=%d" % GameLogic.gameData.playerBlack)

	# The bot opens. Then we reply, and it must answer again.
	if not await _waitForHistory(1):
		_fail("bot never played its opening move")
		return

	var state := GameLogic.activeState()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var reply := MoveGen.randomPly(state, rng)
	if reply == null:
		_fail("no legal reply available after the bot's opening")
		return
	GameLogic.doMove(self, reply)

	if not await _waitForHistory(3):
		_fail("bot did not answer our move")


# The tiltak difficulties are only meaningful when the GDExtension is present.
# When it is, playing through the tab is the end-to-end check that the native
# engine actually answers; when it isn't, the options must be gone rather than
# offered and broken.
func _checkTiltakOption(panel: Node) -> void:
	var available: bool = TiltakBot.available()
	var idx: int = panel.diffEntry.get_item_index(BotMenu.DIFFICULTY.TILTAK_FAST)

	if not available:
		if idx != -1:
			_fail("tiltak is unavailable but the Tiltak difficulty is still offered")
		else:
			print("note: TiltakEngine not built for this platform, tiltak path skipped")
		return

	if idx == -1:
		_fail("tiltak is available but the Tiltak difficulty is missing from the dropdown")
		return

	# 5x5 is inside tiltak's supported set, so this must actually use the engine.
	panel.diffEntry.select(idx)
	panel.sizeEntry.select(2)
	panel.colorEntry.select(1)   # bot opens as White

	panel.start()
	await get_tree().process_frame

	if panel.tiltakBot == null:
		_fail("no TiltakBot was created despite the engine being available")
		return
	panel.tiltakBot.thinkDelay = 0.0

	if GameLogic.gameData.playerWhiteName.find("Tiltak") == -1:
		_fail("expected tiltak to be named as White, got '%s'" % GameLogic.gameData.playerWhiteName)

	if not await _waitForHistory(1):
		_fail("tiltak never played its opening move")
		return

	var opening: Ply = GameLogic.history[0]
	if opening == null:
		_fail("tiltak's opening move did not land in the history")


func _waitForHistory(target: int) -> bool:
	var deadline := Time.get_ticks_msec() + int(REPLY_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		if GameLogic.history.size() >= target: return true
		if not GameLogic.active: return false
	return false
