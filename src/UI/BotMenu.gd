extends Control
## The "Vs Bot" tab: play an engine bundled with the app (BundledEngines),
## through the TEI tab's own TEI client. Only shown when an engine is
## bundled. Sizes and komi come from the engine's manifest entry, so only games
## the engine actually plays can be started.

@onready var engineEntry: OptionButton = $GridContainer/Engine2
@onready var colorEntry: OptionButton = $GridContainer/Color2
@onready var sizeEntry: OptionButton = $GridContainer/Size2
@onready var komiLabel: Label = $GridContainer/Komi2
@onready var timeEntry: SpinBox = $GridContainer/Time2
@onready var incEntry: SpinBox = $GridContainer/Incr2

# Shared with the TEI tab rather than a second instance: only one engine game
# runs at a time, and an idle TEInterface (pid 0) would OS.kill(0) -- its whole
# process group -- on exit while another instance's engine is still running.
@onready var tei: TEI = $"../TEI/TEI"

var engines: Array[Dictionary] = []


func _ready():
	engines = BundledEngines.list()
	$"../tabBar/Play/SubTabs/Bot".visible = not engines.is_empty()
	if engines.is_empty(): return
	
	for e in engines:
		engineEntry.add_item(e["name"])
	engineEntry.item_selected.connect(engineSelected)
	engineSelected(0)
	$Button.pressed.connect(start)


func engine() -> Dictionary:
	return engines[engineEntry.selected]


func komi() -> float:
	return engine().get("komi", [0.0])[0]


func engineSelected(_index: int):
	sizeEntry.clear()
	for s in engine().get("sizes", range(3, 9)):
		sizeEntry.add_item("%dx%d" % [s, s], s)
	komiLabel.text = str(komi()).trim_suffix(".0")


func start():
	if GameLogic.active:
		if GameLogic.gameData.playerWhite == GameData.BOT or GameLogic.gameData.playerBlack == GameData.BOT:
			GameLogic.end.emit(GameState.ONGOING)
		elif not (GameLogic.gameData.isObserver() or GameLogic.gameData.isScratch()):
			Notif.message("Can't start a new game while you're still playing!")
			return
	
	var playerName = PlayTakI.activeUsername if not PlayTakI.activeUsername.is_empty() else "Player"
	var size = sizeEntry.get_selected_id()
	var white = colorEntry.get_selected_id() == GameState.WHITE
	
	if not await tei.startConnection(engine()["path"]):
		Notif.message("Detected fatal error starting bot, restart Attak and try again")
		return
	
	var game = GameData.new(
		"", size,
		GameData.LOCAL if white else GameData.BOT,
		GameData.BOT if white else GameData.LOCAL,
		playerName if white else tei.botName,
		tei.botName if white else playerName,
		timeEntry.value * 60, incEntry.value, 0, 0, komi() * 2,
		NewSeek.standardFlats[size-3], NewSeek.standardCaps[size-3], SeekData.UNRATED
	)
	
	tei.startGame(game)
