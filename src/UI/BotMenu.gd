extends VBoxContainer
class_name BotMenu

# The "Vs Bot" tab: start an offline game against a bot.
#
# Modelled on TEIMenu, minus the engine file picker and the komi/time/increment
# controls -- board size, colour and difficulty are the only things worth
# choosing here. Unlike the TEI tab this is not gated behind the experimental
# setting, since it is the offline play mode rather than a developer tool.
#
# Nothing here touches PlayTakI beyond borrowing the username for a label, so it
# works with no account and no network.

# Difficulty option ids. The first three run the built-in GDScript bot; the last
# two need the tiltak GDExtension and are hidden when it is unavailable.
enum DIFFICULTY {
	RANDOM = 0,
	NOVICE = 1,
	CAREFUL = 2,
	TILTAK_FAST = 3,
	TILTAK_STRONG = 4,
}

const TILTAK_IDS := [DIFFICULTY.TILTAK_FAST, DIFFICULTY.TILTAK_STRONG]

@onready var colorEntry: OptionButton = $GridContainer/Color2
@onready var sizeEntry: OptionButton = $GridContainer/Size2
@onready var diffEntry: OptionButton = $GridContainer/Difficulty2

@onready var localBot: LocalBot = $Bot

var tiltakBot: TiltakBot = null


func _ready() -> void:
	$Button.pressed.connect(start)

	if TiltakBot.available():
		tiltakBot = TiltakBot.new()
		add_child(tiltakBot)
	else:
		# No native engine on this platform (the Web export has no GDExtension at
		# all). Drop the options rather than offering something that cannot run.
		for id in TILTAK_IDS:
			var idx := diffEntry.get_item_index(id)
			if idx != -1: diffEntry.remove_item(idx)


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

	var bot: BotInterface = _pickBot(sizeEntry.get_selected_id(), diffEntry.get_selected_id())

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


# Chooses the engine, falling back to the built-in bot whenever tiltak cannot
# take the game -- it only implements 4x4, 5x5 and 6x6, while Attak offers 3-8.
func _pickBot(size: int, difficulty: int) -> BotInterface:
	if difficulty in TILTAK_IDS and tiltakBot != null:
		tiltakBot.setStrength(TiltakBot.STRENGTH.FAST if difficulty == DIFFICULTY.TILTAK_FAST \
			else TiltakBot.STRENGTH.STRONG)
		if tiltakBot.newGame(size, 0):
			return tiltakBot
		Notif.message("Tiltak doesn't play %dx%d - using the built-in bot." % [size, size])
		localBot.setDifficulty(LocalBot.DIFFICULTY.THOUGHTFUL)
		return localBot

	localBot.setDifficulty(difficulty)
	return localBot
