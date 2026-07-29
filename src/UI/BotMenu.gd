extends VBoxContainer

# The "Vs Bot" tab: start an offline game against the built-in bot.
#
# Modelled on TEIMenu, minus the engine file picker and the komi/time/increment
# controls -- board size, colour and difficulty are the only things worth
# choosing here. Unlike the TEI tab this is not gated behind the experimental
# setting, since it is the offline play mode rather than a developer tool.
#
# Nothing here touches PlayTakI beyond borrowing the username for a label, so it
# works with no account and no network.

@onready var colorEntry: OptionButton = $GridContainer/Color2
@onready var sizeEntry: OptionButton = $GridContainer/Size2
@onready var diffEntry: OptionButton = $GridContainer/Difficulty2

@onready var bot: LocalBot = $Bot


func _ready() -> void:
	$Button.pressed.connect(start)


func start() -> void:
	# Same guard as TEIMenu: replace a bot game silently, but refuse to abandon a
	# real game in progress.
	if GameLogic.active:
		if GameLogic.gameData.playerWhite == GameData.BOT or GameLogic.gameData.playerBlack == GameData.BOT:
			GameLogic.end.emit(GameState.ONGOING)
		elif not (GameLogic.gameData.isObserver() or GameLogic.gameData.isScratch()):
			Notif.message("Can't start a new game while you're still playing!")
			return

	var playerName := PlayTakI.activeUsername if not PlayTakI.activeUsername.is_empty() else "Player"
	var size: int = sizeEntry.get_selected_id()
	var iAmWhite: bool = colorEntry.get_selected_id() == GameState.WHITE

	bot.setDifficulty(diffEntry.get_selected_id())

	var game := GameData.new(
		"", size,
		GameData.LOCAL if iAmWhite else GameData.BOT,
		GameData.BOT if iAmWhite else GameData.LOCAL,
		playerName if iAmWhite else bot.botName,
		bot.botName if iAmWhite else playerName,
		0, 0, 0, 0, 0,  # untimed, no increment, no komi
		NewSeek.standardFlats[size - 3], NewSeek.standardCaps[size - 3],
		SeekData.UNRATED
	)

	bot.startGame(game)
