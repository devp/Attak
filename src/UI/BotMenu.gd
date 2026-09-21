extends VBoxContainer
class_name BotMenu

# The "Vs Bot" tab: start an offline game against the syntaks engine.
#
# Modelled on TEIMenu, minus the engine file picker and the komi/time/increment
# controls -- colour and difficulty are the only things worth choosing here.
# Unlike the TEI tab this is not gated behind the experimental setting, since it
# is the offline play mode rather than a developer tool. It is hidden instead
# where the syntaks GDExtension is not available (the Web export, and any
# platform we do not build the library for).
#
# Nothing here touches PlayTakI beyond borrowing the username for a label, so it
# works with no account and no network.

# Difficulty option ids.
enum DIFFICULTY {
	FAST = 0,
	STRONG = 1,
}

# syntaks plays 6x6 and nothing else.
const SIZE := 6

@onready var colorEntry: OptionButton = $GridContainer/Color2
@onready var diffEntry: OptionButton = $GridContainer/Difficulty2

var syntaksBot: SyntaksBot = null


func _ready() -> void:
	$Button.pressed.connect(start)

	if SyntaksBot.available():
		syntaksBot = SyntaksBot.new()
		add_child(syntaksBot)
	else:
		$"../tabBar/Play/SubTabs/Bot".visible = false


func start() -> void:
	# Same guard as TEIMenu: replace a bot game silently, but refuse to abandon a
	# real game in progress.
	if GameLogic.active:
		if GameLogic.gameData.playerWhite == GameData.BOT or GameLogic.gameData.playerBlack == GameData.BOT:
			GameLogic.end.emit(GameState.ONGOING)
		elif not (GameLogic.gameData.isObserver() or GameLogic.gameData.isScratch()):
			Notif.message("Can't start a new game while you're still playing!")
			return

	syntaksBot.setStrength(SyntaksBot.STRENGTH.FAST if diffEntry.get_selected_id() == DIFFICULTY.FAST \
		else SyntaksBot.STRENGTH.STRONG)

	# Komi is the one the engine is built around; any other would have it
	# evaluating against the wrong target.
	var halfKomi: int = syntaksBot.requiredHalfKomi()
	if not syntaksBot.newGame(SIZE, halfKomi):
		Notif.message("The bot could not start a game.")
		return

	var playerName := PlayTakI.activeUsername if not PlayTakI.activeUsername.is_empty() else "Player"
	var iAmWhite: bool = colorEntry.get_selected_id() == GameState.WHITE

	var game := GameData.new(
		"", SIZE,
		GameData.LOCAL if iAmWhite else GameData.BOT,
		GameData.BOT if iAmWhite else GameData.LOCAL,
		playerName if iAmWhite else syntaksBot.botName,
		syntaksBot.botName if iAmWhite else playerName,
		0, 0, 0, 0, halfKomi,  # untimed, no increment
		NewSeek.standardFlats[SIZE - 3], NewSeek.standardCaps[SIZE - 3],
		SeekData.UNRATED
	)

	syntaksBot.startGame(game)
