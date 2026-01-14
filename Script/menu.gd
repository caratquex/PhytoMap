extends CanvasLayer

@onready var start_game_button: Button = $Control/MarginContainer/VBoxContainer/HBoxContainer/btn_statrGame
@onready var level_option: OptionButton = $Control/MarginContainer/VBoxContainer/HBoxContainer/OptionButton
@onready var story_button: Button = $Control/MarginContainer/VBoxContainer/btn_credits
@onready var credit_button: Button = $Control/MarginContainer/VBoxContainer/btn_credits2
@onready var quit_button: Button = $Control/MarginContainer/VBoxContainer/btn_qiut

const CUTSCENE_PATH: String = "res://Cut Scene/comic_cutscene.tscn"
const LEVEL_PATHS: Array[String] = [
	"res://Map/Level 1.tscn",
	"res://Map/Level 2.tscn",
	"res://Map/Level 3.tscn"
]


func _ready() -> void:
	# Connect button signals
	start_game_button.pressed.connect(_on_start_game_pressed)
	story_button.pressed.connect(_on_story_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	
	# Connect level selection dropdown
	level_option.item_selected.connect(_on_level_selected)


func _on_start_game_pressed() -> void:
	# Default flow: Menu -> Cutscene -> Level 1
	# The cutscene will handle transitioning to Level 1
	get_tree().change_scene_to_file(CUTSCENE_PATH)


func _on_story_pressed() -> void:
	# Story button also plays the cutscene
	get_tree().change_scene_to_file(CUTSCENE_PATH)


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_level_selected(index: int) -> void:
	# Load the selected level directly
	if index >= 0 and index < LEVEL_PATHS.size():
		get_tree().change_scene_to_file(LEVEL_PATHS[index])
