extends Node2D

var _player_nearby: bool = false

@onready var _interact: Area2D = $InteractArea

func setup(data: ItemData) -> void:
	var sprite: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
	if sprite != null:
		sprite.texture = data.placeable_sprite if data.placeable_sprite != null else data.icon

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_interact.body_entered.connect(_on_body_entered)
	_interact.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = true
		Global.player_near_station = true

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("Player"):
		_player_nearby = false
		Global.player_near_station = false
