class_name Unit
extends Node2D

@export var unit_name: String = "Unit"
@export var move_range: int = 3
@export var max_hp: int = 10
@export var attack: int = 3
## 爆擊機率（0~1）
@export_range(0.0, 1.0) var crit_chance: float = 0.0
@export var radius: float = 26.0
@export var is_enemy: bool = false
@export var icon: Texture2D

const HP_BAR_HEIGHT := 7.0
const HP_BAR_MIN_WIDTH := 48.0
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
	if icon:
		var icon_size := Vector2.ONE * radius * 2.0
		# 已結束行動的單位以暗色顯示
		var tint := Color(0.5, 0.5, 0.5) if has_acted else Color.WHITE
		draw_texture_rect(icon, Rect2(-icon_size / 2.0, icon_size), false, tint)
	_draw_hp_bar()

func _draw_hp_bar() -> void:
	# 體型較大的單位（如小王）血條也較寬
	var bar_size := Vector2(maxf(HP_BAR_MIN_WIDTH, radius * 1.9), HP_BAR_HEIGHT)
	var origin := Vector2(-bar_size.x / 2.0, -radius - HP_BAR_GAP - bar_size.y)
	var back := Rect2(origin, bar_size)
	draw_rect(back.grow(1.0), Color.BLACK)
	draw_rect(back, Color(0.2, 0.2, 0.2))
	var ratio := float(hp) / float(max_hp) if max_hp > 0 else 0.0
	var fill_color := Color(0.9, 0.3, 0.25) if is_enemy else Color(0.35, 0.85, 0.35)
	draw_rect(Rect2(origin, Vector2(bar_size.x * ratio, bar_size.y)), fill_color)
