extends Node


const rPTN = "^([FCS])?([A-Ha-h][1-8])$|^([1-8])?([A-Ha-h][1-8])([<>+-])([1-8]*)(\\*)?$"
const rPlayTak = "^P ([A-Ha-h][1-8]) ?([CW])?$|^M ([A-Ha-h][1-8]) ([A-Ha-h][1-8])((?: [1-8])+)$"
var ptnRegex: RegEx = RegEx.new()
var playTakRegex: RegEx = RegEx.new()

func _ready():
	ptnRegex.compile(rPTN)
	playTakRegex.compile(rPlayTak)


func isMobile():
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


# Builds exported with the "local_bot" feature open straight on the Vs Bot tab
# and hide the online tabs. `godot -- --local-bot` does the same from the editor.
func isLocalBotOnly() -> bool:
	return OS.has_feature("local_bot") or "--local-bot" in OS.get_cmdline_user_args()
