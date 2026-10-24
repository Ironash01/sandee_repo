extends Node2D
class_name DungeonTrap

# ── Dungeon trap ─────────────────────────────────────────────────────
# A persistent stone pressure-plate on a corridor tile. Each time the player
# STEPS onto its exact tile it detonates a DungeonExplosion (3x3 AoE) at the
# plate — but only once every RETRIGGER_COOLDOWN, so stepping on and off it
# can't chain-detonate. Standing on it does NOT keep re-firing. Unlike
# DungeonFlare it never despawns and cannot be destroyed. It does not block
# movement (a flat floor plate).

const TRAP_TEX: Texture2D = preload("res://sprites/dungeon/dungeon_trap.png")
const EXPLOSION_SCRIPT: GDScript = preload("res://scripts/dungeon_explosion.gd")

# Minimum seconds between detonations — the step trigger's 5s timer.
const RETRIGGER_COOLDOWN: float = 5.0
# Floor-plate layer: above the dungeon tilemap (-300) but below the player and
# walls (their y-sorted z is ~ -32..32), so the player always stands on top.
const PLATE_Z: int = -200

var _cooldown: float = 0.0

func _ready() -> void:
	add_to_group("DungeonTrap")
	z_index = PLATE_Z
	_add_visual()
	_add_trigger()

func _add_visual() -> void:
	var s := Sprite2D.new()
	s.texture = TRAP_TEX
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(s)

func _add_trigger() -> void:
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask  = 4   # player is on layer 4 (see player.tscn)
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32, 32)   # exactly this tile
	shape.shape = rect
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)

# Fires only on STEP (entering the tile), and only once the 5s timer is up.
func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("Player"):
		return
	if Global.is_player_in_safe_zone():
		return
	if _cooldown > 0.0:
		return
	_cooldown = RETRIGGER_COOLDOWN
	_detonate()

func _detonate() -> void:
	var ex: Node2D = EXPLOSION_SCRIPT.new() as Node2D
	if ex == null:
		return
	get_parent().add_child(ex)
	ex.global_position = global_position
