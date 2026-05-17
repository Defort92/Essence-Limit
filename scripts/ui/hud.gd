extends CanvasLayer

@onready var hp_bar: ProgressBar = $Control/HPContainer/HPBar
@onready var hp_text: Label = $Control/HPContainer/HPText
@onready var gold_label: Label = $Control/GoldLabel
@onready var level_label: Label = $Control/LevelLabel

func _ready() -> void:
	GameManager.gold_changed.connect(_on_gold_changed)
	_on_gold_changed(GameManager.gold)
	XPSystem.level_up.connect(_on_level_up)
	_on_level_up(XPSystem.current_level)
	call_deferred("_connect_player")

func _connect_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		# Player ещё не добавлен в сцену — ждём через scene tree signal.
		get_tree().node_added.connect(_on_node_added_to_tree)
		return
	_subscribe_to_player(players[0] as Player)

func _on_node_added_to_tree(node: Node) -> void:
	if not node.is_in_group("player"):
		return
	get_tree().node_added.disconnect(_on_node_added_to_tree)
	_subscribe_to_player(node as Player)

func _subscribe_to_player(player: Player) -> void:
	if player == null:
		return
	player.health_changed.connect(_on_health_changed)
	_on_health_changed(player.health, player.max_health)

func _on_health_changed(current: int, maximum: int) -> void:
	hp_bar.max_value = maximum
	hp_bar.value = current
	hp_text.text = "%d / %d" % [current, maximum]

func _on_gold_changed(amount: int) -> void:
	gold_label.text = "Золото: %d" % amount

func _on_level_up(new_level: int) -> void:
	level_label.text = "Ур. %d" % new_level
