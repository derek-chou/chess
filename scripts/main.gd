extends Node2D

const UnitScene := preload("res://scenes/Unit.tscn")

@onready var hex_map: HexMap = $HexMap
@onready var units_container: Node2D = $Units
@onready var camera: Camera2D = $Camera2D
@onready var info_label: Label = $UI/InfoLabel
@onready var bench: Control = $UI/Bench
@onready var bench_slots: HBoxContainer = $UI/Bench/Row/Slots
@onready var start_button: Button = $UI/Bench/Row/StartButton
@onready var end_turn_button: Button = $UI/EndTurnButton
@onready var version_label: Label = $UI/VersionLabel
@onready var game_over_panel: Control = $UI/GameOver
@onready var game_over_title: Label = $UI/GameOver/Center/Box/Title
@onready var game_over_subtitle: Label = $UI/GameOver/Center/Box/Subtitle
@onready var restart_button: Button = $UI/GameOver/Center/Box/RestartButton

enum Phase { DEPLOY, PLAYER_TURN, ENEMY_TURN, GAME_OVER }
var phase: Phase = Phase.DEPLOY
var turn_number: int = 0

## 拖曳佈署中的單位與其原位置（NO_COORD 代表從佈署欄拖出）
var drag_unit: Unit = null
var drag_origin: Vector2i = HexMap.NO_COORD

var selected_unit: Unit = null
var reachable_data: Dictionary = {}
var is_animating: bool = false
var is_dragging: bool = false
var drag_start_mouse: Vector2
var drag_start_cam: Vector2

const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const ZOOM_STEP := 0.1
const DEFAULT_INFO := "Select a unit, click a highlighted tile to move, then attack or wait. Middle-drag to pan, wheel to zoom."
const DEPLOY_INFO := "Drag your unit from the bench onto the blue deploy zone. Drag it again to reposition, or back to the bench to undeploy."
const ATTACK_INFO := "Click a red enemy to attack, or click elsewhere to wait."
const VICTORY_INFO := "Victory! All enemies defeated."
const DEFEAT_INFO := "Defeat! All your units have fallen."
## 爆擊傷害倍率
const CRIT_MULTIPLIER := 2
## 敵方回合中每個動作之間的停頓（秒）
const ENEMY_STEP_DELAY := 0.35

## 佈署區為地圖最下方幾列
const DEPLOY_ROWS := 3
const ENEMY_COUNT := 3
const ENEMY_STATS := {"name": "Enemy", "icon": preload("res://icons/monster.svg"), "color": Color(0.85, 0.25, 0.25), "move_range": 3, "max_hp": 12, "attack": 4, "crit_chance": 0.1}
const PLAYER_ROSTER := [
	{"name": "Warrior", "icon": preload("res://icons/warrior.svg"), "color": Color(0.2, 0.45, 0.85), "move_range": 3, "max_hp": 30, "attack": 6, "crit_chance": 0.2},
]
## 佈署階段將鏡頭縮小，讓整張地圖與佈署欄同時可見
const DEPLOY_ZOOM := 0.6

func _ready() -> void:
	version_label.text = "v%s" % ProjectSettings.get_setting("application/config/version", "0.0.0")
	restart_button.pressed.connect(func() -> void: get_tree().reload_current_scene())
	hex_map.generate_map()
	hex_map.setup_deploy_zone(DEPLOY_ROWS)
	_spawn_enemies()
	_setup_bench()
	_enter_deploy_phase()

func _spawn_enemies() -> void:
	# 敵人隨機分布在佈署區以外、地圖上半部的可通行格
	var candidates: Array[Vector2i] = []
	for coord in hex_map.tiles.keys():
		if coord.y < 0 and hex_map.is_walkable(coord) and not hex_map.is_deploy_tile(coord):
			candidates.append(coord)
	candidates.shuffle()
	for i in range(min(ENEMY_COUNT, candidates.size())):
		var enemy := _create_unit(ENEMY_STATS)
		enemy.is_enemy = true
		units_container.add_child(enemy)
		enemy.place(candidates[i], hex_map)

func _create_unit(stats: Dictionary) -> Unit:
	var unit := UnitScene.instantiate() as Unit
	unit.unit_name = stats["name"]
	unit.team_color = stats["color"]
	unit.icon = stats["icon"]
	unit.move_range = stats["move_range"]
	unit.max_hp = stats["max_hp"]
	unit.attack = stats["attack"]
	unit.crit_chance = stats["crit_chance"]
	return unit

func _setup_bench() -> void:
	for i in PLAYER_ROSTER.size():
		var slot := BenchSlot.new()
		slot.roster_index = i
		slot.unit_name = PLAYER_ROSTER[i]["name"]
		slot.team_color = PLAYER_ROSTER[i]["color"]
		slot.icon = PLAYER_ROSTER[i]["icon"]
		slot.drag_requested.connect(_on_slot_drag_requested)
		bench_slots.add_child(slot)
	start_button.pressed.connect(_on_start_pressed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)

func _enter_deploy_phase() -> void:
	phase = Phase.DEPLOY
	hex_map.show_deploy_zone = true
	bench.visible = true
	camera.zoom = Vector2(DEPLOY_ZOOM, DEPLOY_ZOOM)
	# 讓地圖置中於佈署欄上方的可視區域
	camera.position = Vector2(0, -bench.offset_top / 2.0 / DEPLOY_ZOOM)
	_refresh_deploy_ui()
	_update_info(DEPLOY_INFO)

func _on_start_pressed() -> void:
	hex_map.show_deploy_zone = false
	hex_map.drop_state = HexMap.DropState.NONE
	bench.visible = false
	hex_map.queue_redraw()
	_start_player_turn()

func _refresh_deploy_ui() -> void:
	start_button.disabled = _get_player_units().is_empty()
	for slot in bench_slots.get_children():
		var bench_slot := slot as BenchSlot
		bench_slot.available = _find_player_unit_by_roster(bench_slot.roster_index) == null

func _get_player_units() -> Array[Unit]:
	return _get_team(false)

func _find_player_unit_by_roster(index: int) -> Unit:
	for child in units_container.get_children():
		var unit := child as Unit
		if _is_active(unit) and not unit.is_enemy and unit.roster_index == index:
			return unit
	return null

func get_unit_at(coord: Vector2i) -> Unit:
	for child in units_container.get_children():
		var unit := child as Unit
		if _is_active(unit) and unit != drag_unit and unit.axial_coord == coord:
			return unit
	return null

func _is_active(unit: Unit) -> bool:
	return not unit.is_queued_for_deletion()

# ---- 佈署拖曳 ----

func _on_slot_drag_requested(slot: BenchSlot) -> void:
	if phase != Phase.DEPLOY or drag_unit != null:
		return
	var unit := _create_unit(PLAYER_ROSTER[slot.roster_index])
	unit.roster_index = slot.roster_index
	units_container.add_child(unit)
	_begin_drag(unit, HexMap.NO_COORD)
	slot.available = false

func _begin_drag(unit: Unit, origin: Vector2i) -> void:
	drag_unit = unit
	drag_origin = origin
	unit.z_index = 10
	unit.modulate.a = 0.75
	unit.position = get_global_mouse_position()
	_update_drop_preview()

func _update_drop_preview() -> void:
	drag_unit.position = get_global_mouse_position()
	var coord := hex_map.pixel_to_axial(get_global_mouse_position())
	if _is_mouse_over_bench() or not hex_map.has_tile(coord):
		hex_map.hovered_coord = HexMap.NO_COORD
		hex_map.drop_state = HexMap.DropState.NONE
	else:
		hex_map.hovered_coord = coord
		hex_map.drop_state = HexMap.DropState.VALID if _can_drop_at(coord) else HexMap.DropState.INVALID
	hex_map.queue_redraw()

func _can_drop_at(coord: Vector2i) -> bool:
	if not hex_map.is_deploy_tile(coord):
		return false
	var occupant := get_unit_at(coord)
	return occupant == null or not occupant.is_enemy

func _is_mouse_over_bench() -> bool:
	return bench.visible and bench.get_global_rect().has_point(get_viewport().get_mouse_position())

func _end_drag() -> void:
	var unit := drag_unit
	var coord := hex_map.pixel_to_axial(get_global_mouse_position())
	drag_unit = null
	unit.z_index = 0
	unit.modulate.a = 1.0

	if _is_mouse_over_bench():
		unit.queue_free()
	elif _can_drop_at(coord):
		var occupant := get_unit_at(coord)
		if occupant != null:
			# 與佔據該格的我方單位交換；從佈署欄拖入時則把對方送回佈署欄
			if drag_origin == HexMap.NO_COORD:
				occupant.queue_free()
			else:
				occupant.place(drag_origin, hex_map)
		unit.place(coord, hex_map)
	elif drag_origin != HexMap.NO_COORD:
		unit.place(drag_origin, hex_map)
	else:
		unit.queue_free()

	drag_origin = HexMap.NO_COORD
	hex_map.drop_state = HexMap.DropState.NONE
	hex_map.queue_redraw()
	_refresh_deploy_ui()

func _input(event: InputEvent) -> void:
	# 拖曳期間在 _input 處理，滑鼠移到 UI 上放開也能接到
	if drag_unit == null:
		return
	if event is InputEventMouseMotion:
		_update_drop_preview()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			_end_drag()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_handle_hover()
		if is_dragging:
			var delta: Vector2 = (drag_start_mouse - get_viewport().get_mouse_position()) / camera.zoom
			camera.position = drag_start_cam + delta
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and not is_animating:
			if phase == Phase.DEPLOY:
				_handle_deploy_press()
			elif phase == Phase.PLAYER_TURN:
				_handle_click()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			is_dragging = mb.pressed
			if mb.pressed:
				drag_start_mouse = get_viewport().get_mouse_position()
				drag_start_cam = camera.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1.0 - ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0 + ZOOM_STEP)

func _zoom(factor: float) -> void:
	var new_zoom: Vector2 = camera.zoom / factor
	camera.zoom = new_zoom.clamp(Vector2(ZOOM_MIN, ZOOM_MIN), Vector2(ZOOM_MAX, ZOOM_MAX))

func _handle_hover() -> void:
	var world_pos := get_global_mouse_position()
	var coord := hex_map.pixel_to_axial(world_pos)
	hex_map.hovered_coord = coord if hex_map.has_tile(coord) else HexMap.NO_COORD

	if phase == Phase.DEPLOY:
		hex_map.queue_redraw()
		return

	if selected_unit != null and reachable_data.has("came_from"):
		var came_from: Dictionary = reachable_data["came_from"]
		var new_path := hex_map.reconstruct_path(came_from, selected_unit.axial_coord, coord)
		hex_map.set_highlight(reachable_data["cost"], new_path)
	else:
		hex_map.queue_redraw()

func _handle_deploy_press() -> void:
	var coord := hex_map.pixel_to_axial(get_global_mouse_position())
	var unit := get_unit_at(coord)
	if unit != null and not unit.is_enemy:
		_begin_drag(unit, unit.axial_coord)

func _handle_click() -> void:
	var world_pos := get_global_mouse_position()
	var coord := hex_map.pixel_to_axial(world_pos)
	var clicked_unit := get_unit_at(coord) if hex_map.has_tile(coord) else null

	# 已移動的單位只能攻擊或待命
	if selected_unit != null and selected_unit.has_moved:
		if clicked_unit != null and hex_map.attack_targets.has(coord):
			_player_attack(selected_unit, clicked_unit)
		else:
			_end_unit_action(selected_unit)
		return

	if clicked_unit != null and clicked_unit.is_enemy:
		if selected_unit != null and hex_map.attack_targets.has(coord):
			_player_attack(selected_unit, clicked_unit)
		return

	if clicked_unit != null:
		if clicked_unit == selected_unit or clicked_unit.has_acted:
			_deselect()
		else:
			_select_unit(clicked_unit)
		return

	var cost_map: Dictionary = reachable_data.get("cost", {})
	if selected_unit != null and cost_map.has(coord) and coord != selected_unit.axial_coord:
		var came_from: Dictionary = reachable_data["came_from"]
		var move_path := hex_map.reconstruct_path(came_from, selected_unit.axial_coord, coord)
		_player_move(selected_unit, move_path)
	else:
		_deselect()

func _select_unit(unit: Unit) -> void:
	selected_unit = unit
	hex_map.selected_coord = unit.axial_coord
	reachable_data = hex_map.compute_reachable(unit.axial_coord, unit.move_range, _occupied_tiles(unit))
	hex_map.set_highlight(reachable_data["cost"], [])
	var targets := _get_attack_targets(unit)
	hex_map.set_attack_targets(targets)
	var info := "%s selected (HP %d/%d, ATK %d, CRIT %d%%, MOV %d). Click a highlighted tile to move" % [
		unit.unit_name, unit.hp, unit.max_hp, unit.attack, roundi(unit.crit_chance * 100), unit.move_range]
	if not targets.is_empty():
		info += ", or a red enemy to attack"
	_update_info(info + ".")

func _deselect() -> void:
	selected_unit = null
	reachable_data = {}
	hex_map.clear_highlight()
	if phase == Phase.PLAYER_TURN:
		_update_info("Turn %d - Player. %s" % [turn_number, DEFAULT_INFO])

## 除了 except 以外所有單位佔據的格子
func _occupied_tiles(except: Unit) -> Dictionary:
	var result: Dictionary = {}
	for child in units_container.get_children():
		var unit := child as Unit
		if _is_active(unit) and unit != except:
			result[unit.axial_coord] = true
	return result

func _get_attack_targets(unit: Unit) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for n in HexUtils.neighbors(unit.axial_coord):
		var other := get_unit_at(n)
		if other != null and other.is_enemy != unit.is_enemy:
			result.append(n)
	return result

func _get_team(enemy: bool) -> Array[Unit]:
	var result: Array[Unit] = []
	for child in units_container.get_children():
		var unit := child as Unit
		if _is_active(unit) and unit.is_enemy == enemy and unit != drag_unit:
			result.append(unit)
	return result

# ---- 我方回合 ----

func _start_player_turn() -> void:
	turn_number += 1
	phase = Phase.PLAYER_TURN
	for unit in _get_team(false):
		unit.has_moved = false
		unit.has_acted = false
	end_turn_button.visible = true
	end_turn_button.disabled = false
	_deselect()

func _on_end_turn_pressed() -> void:
	if phase != Phase.PLAYER_TURN or is_animating:
		return
	_deselect()
	_start_enemy_turn()

func _player_move(unit: Unit, move_path: Array[Vector2i]) -> void:
	is_animating = true
	hex_map.set_highlight({}, [])
	hex_map.set_attack_targets([])
	await _animate_move(unit, move_path)
	is_animating = false
	unit.has_moved = true
	# 移動後若旁邊有敵人，提供攻擊選項；否則直接結束行動
	var targets := _get_attack_targets(unit)
	if targets.is_empty():
		_end_unit_action(unit)
		return
	selected_unit = unit
	reachable_data = {}
	hex_map.selected_coord = unit.axial_coord
	hex_map.set_attack_targets(targets)
	_update_info(ATTACK_INFO)

func _player_attack(attacker: Unit, target: Unit) -> void:
	is_animating = true
	hex_map.clear_highlight()
	await _perform_attack(attacker, target)
	is_animating = false
	if _check_game_over():
		return
	if _is_active(attacker):
		_end_unit_action(attacker)
	else:
		_deselect()
		_check_player_turn_done()

func _end_unit_action(unit: Unit) -> void:
	unit.has_moved = true
	unit.has_acted = true
	_deselect()
	_check_player_turn_done()

func _check_player_turn_done() -> void:
	for unit in _get_team(false):
		if not unit.has_acted:
			return
	_start_enemy_turn()

# ---- 敵方回合 ----

func _start_enemy_turn() -> void:
	phase = Phase.ENEMY_TURN
	end_turn_button.disabled = true
	_update_info("Turn %d - Enemy." % turn_number)
	for enemy in _get_team(true):
		# 可能已在先前的反擊中陣亡並被釋放
		if not is_instance_valid(enemy) or not _is_active(enemy):
			continue
		await get_tree().create_timer(ENEMY_STEP_DELAY).timeout
		await _enemy_act(enemy)
		if _check_game_over():
			return
	await get_tree().create_timer(ENEMY_STEP_DELAY).timeout
	_start_player_turn()

## 敵人 AI：朝最近的我方單位前進，相鄰時發動攻擊
func _enemy_act(enemy: Unit) -> void:
	var target := _nearest_opponent(enemy)
	if target == null:
		return
	if HexUtils.distance(enemy.axial_coord, target.axial_coord) > 1:
		var data := hex_map.compute_reachable(enemy.axial_coord, enemy.move_range, _occupied_tiles(enemy))
		var cost_map: Dictionary = data["cost"]
		var best := enemy.axial_coord
		var best_dist := HexUtils.distance(best, target.axial_coord)
		var best_cost := 0
		for coord in cost_map.keys():
			var dist := HexUtils.distance(coord, target.axial_coord)
			if dist < best_dist or (dist == best_dist and cost_map[coord] < best_cost):
				best = coord
				best_dist = dist
				best_cost = cost_map[coord]
		if best != enemy.axial_coord:
			await _animate_move(enemy, hex_map.reconstruct_path(data["came_from"], enemy.axial_coord, best))
	# 移動後攻擊相鄰的我方單位中血量最低者
	var victim: Unit = null
	for coord in _get_attack_targets(enemy):
		var unit := get_unit_at(coord)
		if victim == null or unit.hp < victim.hp:
			victim = unit
	if victim != null:
		await _perform_attack(enemy, victim)

func _nearest_opponent(unit: Unit) -> Unit:
	var best: Unit = null
	var best_dist := 0
	for other in _get_team(not unit.is_enemy):
		var dist := HexUtils.distance(unit.axial_coord, other.axial_coord)
		if best == null or dist < best_dist:
			best = other
			best_dist = dist
	return best

# ---- 戰鬥共用 ----

## 攻擊；目標存活且仍相鄰時立即反擊
func _perform_attack(attacker: Unit, target: Unit) -> void:
	await _strike(attacker, target)
	if target.is_dead():
		await _kill(target)
		return
	if HexUtils.distance(attacker.axial_coord, target.axial_coord) == 1:
		await get_tree().create_timer(0.15).timeout
		await _strike(target, attacker)
		if attacker.is_dead():
			await _kill(attacker)

func _strike(attacker: Unit, target: Unit) -> void:
	var home := attacker.position
	var lunge := home.lerp(target.position, 0.4)
	var is_crit := randf() < attacker.crit_chance
	var damage := attacker.attack * (CRIT_MULTIPLIER if is_crit else 1)
	attacker.z_index = 5
	var tween := create_tween()
	tween.tween_property(attacker, "position", lunge, 0.1).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void:
		target.hp -= damage
		_spawn_damage_number(target.position, damage, is_crit)
		_flash(target)
		if is_crit:
			_shake_camera()
	)
	tween.tween_property(attacker, "position", home, 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(0.2)
	await tween.finished
	attacker.z_index = 0

func _flash(unit: Unit) -> void:
	var tween := create_tween()
	tween.tween_property(unit, "modulate", Color(1, 0.4, 0.4), 0.08)
	tween.tween_property(unit, "modulate", Color.WHITE, 0.15)

func _shake_camera() -> void:
	var tween := create_tween()
	for i in 4:
		var offset := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 8.0 / camera.zoom.x
		tween.tween_property(camera, "offset", offset, 0.04)
	tween.tween_property(camera, "offset", Vector2.ZERO, 0.04)

func _spawn_damage_number(pos: Vector2, amount: int, is_crit: bool) -> void:
	var label := Label.new()
	label.text = ("CRIT! -%d" if is_crit else "-%d") % amount
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 40 if is_crit else 30)
	label.add_theme_color_override("font_color", Color(1, 0.45, 0.1) if is_crit else Color(1, 0.9, 0.3))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6 if is_crit else 5)
	label.z_index = 20
	# 固定寬度並置中，讓不同長度的文字都對齊單位中心
	label.size = Vector2(200, 0)
	label.position = pos + Vector2(-100, -80 if is_crit else -70)
	add_child(label)
	var tween := label.create_tween()
	tween.set_parallel()
	tween.tween_property(label, "position:y", label.position.y - 30, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)

func _kill(unit: Unit) -> void:
	var tween := create_tween()
	tween.tween_property(unit, "modulate:a", 0.0, 0.3)
	await tween.finished
	unit.queue_free()

func _check_game_over() -> bool:
	var won := _get_team(true).is_empty()
	var lost := _get_team(false).is_empty()
	if not won and not lost:
		return false
	phase = Phase.GAME_OVER
	end_turn_button.visible = false
	selected_unit = null
	reachable_data = {}
	hex_map.clear_highlight()
	_update_info(VICTORY_INFO if won else DEFEAT_INFO)
	_show_game_over(won)
	return true

## 結算畫面：背景淡入、標題彈跳放大，最後顯示重新開始按鈕
func _show_game_over(won: bool) -> void:
	game_over_title.text = "VICTORY" if won else "DEFEAT"
	game_over_title.add_theme_color_override("font_color",
		Color(1, 0.85, 0.3) if won else Color(0.9, 0.25, 0.2))
	game_over_subtitle.text = "All enemies defeated in %d %s." % [turn_number, "turn" if turn_number == 1 else "turns"] if won \
		else "Your units have fallen."
	# 等最後一擊的動畫播完再顯示
	await get_tree().create_timer(0.5).timeout
	game_over_panel.modulate.a = 0.0
	game_over_title.scale = Vector2.ZERO
	game_over_subtitle.modulate.a = 0.0
	restart_button.modulate.a = 0.0
	restart_button.disabled = true
	game_over_panel.visible = true
	# 等版面配置完成，標題才能以自身中心縮放
	await get_tree().process_frame
	game_over_title.pivot_offset = game_over_title.size / 2.0

	var tween := create_tween()
	tween.tween_property(game_over_panel, "modulate:a", 1.0, 0.3)
	tween.tween_property(game_over_title, "scale", Vector2.ONE, 0.6) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(game_over_subtitle, "modulate:a", 1.0, 0.25)
	tween.parallel().tween_property(restart_button, "modulate:a", 1.0, 0.25)
	await tween.finished
	restart_button.disabled = false
	restart_button.grab_focus()

func _animate_move(unit: Unit, move_path: Array[Vector2i]) -> void:
	if move_path.is_empty():
		return
	var tween := create_tween()
	for step_coord in move_path:
		var target_pos := hex_map.axial_to_pixel(step_coord)
		tween.tween_property(unit, "position", target_pos, 0.15).set_trans(Tween.TRANS_SINE)
		tween.tween_callback(func() -> void: unit.axial_coord = step_coord)
	await tween.finished

func _update_info(text: String) -> void:
	if info_label:
		info_label.text = text
