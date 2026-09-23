class_name BenchSlot
extends Control

## 佈署欄中的一個待命單位；按下左鍵時發出 drag_requested 由 Main 接手拖曳

signal drag_requested(slot: BenchSlot)

const SLOT_SIZE := Vector2(76, 76)

var roster_index: int = -1
var unit_name: String = ""
var team_color: Color = Color.WHITE
var icon: Texture2D
var available: bool = true:
	set(value):
		available = value
		mouse_default_cursor_shape = CURSOR_DRAG if available else CURSOR_ARROW
		queue_redraw()

func _ready() -> void:
	custom_minimum_size = SLOT_SIZE
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_DRAG

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and available:
		drag_requested.emit(self)
		accept_event()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0, 0, 0, 0.35))
	draw_rect(rect, Color(1, 1, 1, 0.3), false, 1.0)
	var center := size / 2.0 - Vector2(0, 6)
	if available:
		draw_circle(center, 24.0, team_color)
		draw_arc(center, 24.0, 0, TAU, 32, Color.BLACK, 2.0, true)
		if icon:
			draw_texture_rect(icon, Rect2(center - Vector2(20, 20), Vector2(40, 40)), false)
	else:
		draw_arc(center, 24.0, 0, TAU, 32, Color(1, 1, 1, 0.25), 2.0, true)
	var font := get_theme_default_font()
	draw_string(font, Vector2(0, size.y - 4), unit_name, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13,
		Color(1, 1, 1, 0.9 if available else 0.35))
