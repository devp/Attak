extends Control

@onready var entry: LineEdit = $HBoxContainer/LineEdit
@onready var fileRow: HBoxContainer = $HBoxContainer

@onready var colorEntry: OptionButton = $GridContainer/Color2
@onready var sizeEntry: OptionButton = $GridContainer/Size2
@onready var komiEntry: SpinBox = $GridContainer/Komi2
@onready var timeEntry: SpinBox = $GridContainer/Time2
@onready var incEntry: SpinBox = $GridContainer/Incr2

@onready var tei: TEI = $TEI

## Item metadata for the "Choose file…" entry; bundled engines use their index.
const CHOOSE_FILE := -1

var engineChoice: OptionButton
var noEngines: Label
var bundled: Array[Dictionary] = []


var count = 0
var games: Dictionary = {}

func _ready():
	$"../Settings".experimental.connect(toggle)
	toggle($"../Settings".saveData.experimental)
	
	$HBoxContainer/Button.pressed.connect($FileDialog.show)
	$FileDialog.file_selected.connect(select)
	$Button.pressed.connect(start)
	setupEngineChoice()


func toggle(a: bool):
	$"../tabBar/Play/SubTabs/TEI".visible = a


## Lists bundled engines, plus "Choose file…" where user-picked programs can run.
## Android won't exec a file the user picks (W^X), so it only offers bundled ones.
func setupEngineChoice():
	bundled = BundledEngines.list()
	engineChoice = OptionButton.new()
	for i in bundled.size():
		engineChoice.add_item(bundled[i]["name"])
		engineChoice.set_item_metadata(i, i)
	if OS.get_name() != "Android":
		engineChoice.add_item("Choose file…")
		engineChoice.set_item_metadata(engineChoice.item_count - 1, CHOOSE_FILE)
	add_child(engineChoice)
	move_child(engineChoice, fileRow.get_index())
	engineChoice.item_selected.connect(engineSelected)
	# Only worth showing when there is a choice to make.
	engineChoice.visible = engineChoice.item_count > 1
	
	noEngines = Label.new()
	noEngines.text = "No engines are bundled with this build."
	noEngines.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	noEngines.visible = engineChoice.item_count == 0
	add_child(noEngines)
	move_child(noEngines, fileRow.get_index())
	$Button.disabled = engineChoice.item_count == 0
	
	engineSelected(0)


func engineSelected(_index: int):
	fileRow.visible = selectedEngine().is_empty() and engineChoice.item_count > 0


## The chosen bundled engine, or {} for "Choose file…" (or when there's nothing).
func selectedEngine() -> Dictionary:
	if engineChoice.item_count == 0: return {}
	var i = engineChoice.get_item_metadata(engineChoice.selected)
	return {} if i == CHOOSE_FILE else bundled[i]


func select(path: String):
	entry.text = path


func start():
	var size = sizeEntry.get_selected_id()
	var engine := selectedEngine()
	var path: String
	if engine.is_empty():
		path = entry.text
		if not FileAccess.file_exists(path):
			Notif.message("Cant find file: %s" % path)
			return #TODO can we detect executability too?
	else:
		path = engine["path"]
		var why := BundledEngines.unsupported(engine, size, komiEntry.value)
		if not why.is_empty():
			Notif.message(why)
			return
	
	if GameLogic.active:
		if GameLogic.gameData.playerWhite == GameData.BOT or GameLogic.gameData.playerBlack == GameData.BOT:
			GameLogic.end.emit(GameState.ONGOING)
		elif not (GameLogic.gameData.isObserver() or GameLogic.gameData.isScratch()):
			Notif.message("Can't start a new game while you're still playing!")
			return
			
	var playerName = PlayTakI.activeUsername if not PlayTakI.activeUsername.is_empty() else "Player"

	if not await tei.startConnection(path):
		Notif.message("Detected fatal error starting bot, restart Attak and try again")
		return
	
	var game = GameData.new(
		"", size,
		GameData.LOCAL if colorEntry.get_selected_id() == GameState.WHITE else GameData.BOT,
		GameData.LOCAL if colorEntry.get_selected_id() == GameState.BLACK else GameData.BOT,
		playerName if colorEntry.get_selected_id() == GameState.WHITE else tei.botName,
		playerName if colorEntry.get_selected_id() == GameState.BLACK else tei.botName,
		timeEntry.value * 60, incEntry.value, 0, 0, komiEntry.value * 2, 
		NewSeek.standardFlats[size-3], NewSeek.standardCaps[size-3], SeekData.UNRATED
	)
	
	tei.startGame(game)
