## Экран создания персонажа: выбор расы и имени перед стартом новой игры.
extends Control


@onready var _name_input: LineEdit = $Body/Columns/CenterColumn/NameSlot/NameInput
@onready var _race_name_label: Label = $Body/Columns/InfoColumn/RaceNameLabel
@onready var _race_role_label: Label = $Body/Columns/InfoColumn/RaceRoleLabel
@onready var _description_label: Label = $Body/Columns/InfoColumn/DescriptionLabel
@onready var _unique_label: Label = $Body/Columns/InfoColumn/UniqueBlock/UniqueVBox/UniqueLabel
@onready var _confirm_button: Button = $Footer/Margin/ButtonsRow/ConfirmButton

@onready var _race_buttons: Dictionary = {
	GameManager.Race.HUMAN: $Body/Columns/RaceColumn/HumanButton,
	GameManager.Race.BARBARIAN: $Body/Columns/RaceColumn/BarbarianButton,
	GameManager.Race.ELF: $Body/Columns/RaceColumn/ElfButton,
	GameManager.Race.DEMON: $Body/Columns/RaceColumn/DemonButton,
	GameManager.Race.ANGEL: $Body/Columns/RaceColumn/AngelButton,
}

var _selected_race: GameManager.Race = GameManager.Race.HUMAN
var _race_selected: bool = false

func _ready() -> void:
	for race: GameManager.Race in _race_buttons:
		var button: Button = _race_buttons[race]
		button.pressed.connect(_on_race_pressed.bind(race))
	_name_input.text_changed.connect(_on_name_changed)
	_update_confirm_enabled()

func _on_race_pressed(race: GameManager.Race) -> void:
	_selected_race = race
	_race_selected = true
	_race_name_label.text = CharacterCreationConstants.RACE_NAMES.get(race, "")
	_race_role_label.text = CharacterCreationConstants.RACE_ROLES.get(race, "")
	_description_label.text = CharacterCreationConstants.RACE_DESCRIPTIONS.get(race, "")
	_unique_label.text = CharacterCreationConstants.RACE_UNIQUES.get(race, "—")
	_update_confirm_enabled()

func _on_name_changed(_new_text: String) -> void:
	_update_confirm_enabled()

func _update_confirm_enabled() -> void:
	_confirm_button.disabled = not _race_selected or _name_input.text.strip_edges().is_empty()

func _on_confirm_pressed() -> void:
	GameManager.new_game(_selected_race, _name_input.text.strip_edges())
	SceneManager.go_to_city()

func _on_back_pressed() -> void:
	SceneManager.go_to_main_menu()
