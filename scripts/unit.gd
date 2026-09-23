class_name Unit
extends Node2D

@export var unit_name: String = "Unit"
@export var move_range: int = 3
@export var max_hp: int = 10
@export var attack: int = 3
@export var team_color: Color = Color(0.2, 0.45, 0.85)
@export var radius: float = 26.0
@export var is_enemy: bool = false
@export var icon: Texture2D

const HP_BAR_SIZE := Vector2(48, 7)
const HP_BAR_GAP := 6.0

var axial_coord: Vector2i = Vector2i.ZERO
## 對應佈署欄位的索引；敵人為 -1
var roster_index: int = -1
## 本回合是否已移動／已結束行動
var has_moved: bool = false
var has_acted: bool = false:
	set(value):
		has_acted = value
		queue_redraw()
var hp: int = 10:
	set(value):
		hp = clampi(value, 0, max_hp)
		queue_redraw()

func _ready() -> void:
	hp = max_hp

func place(coord: Vector2i, hex_map: HexMap) -> void:
	axial_coord = coord
	position = hex_map.axial_to_pixel(coord)

func is_dead() -> bool:
	return hp <= 0

func _draw() -> void:
	# 已結束行動的單位以暗色顯示
	draw_circle(Vector2.ZERO, radius, team_color.darkened(0.5) if has_acted else team_color)
	draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color.BLACK, 2.0, true)
	if icon:
		var icon_size := Vector2.ONE * radius * 1.7
		var tint := Color(0.5, 0.5, 0.5) if has_acted else Color.WHITE
		draw_texture_rect(icon, Rect2(-icon_size / 2.0, icon_size), false, tint)
	_draw_hp_bar()

func _draw_hp_bar() -> void:
	var origin := Vector2(-HP_BAR_SIZE.x / 2.0, -radius - HP_BAR_GAP - HP_BAR_SIZE.y)
	var back := Rect2(origin, HP_BAR_SIZE)
	draw_rect(back.grow(1.0), Color.BLACK)
	draw_rect(back, Color(0.2, 0.2, 0.2))
	var ratio := float(hp) / float(max_hp) if max_hp > 0 else 0.0
	var fill_color := Color(0.9, 0.3, 0.25) if is_enemy else Color(0.35, 0.85, 0.35)
	draw_rect(Rect2(origin, Vector2(HP_BAR_SIZE.x * ratio, HP_BAR_SIZE.y)), fill_color)
