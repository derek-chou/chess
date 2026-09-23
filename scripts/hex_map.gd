class_name HexMap
extends Node2D

enum Terrain { GRASS, FOREST, MOUNTAIN, WATER }

const TERRAIN_COLOR := {
	Terrain.GRASS: Color(0.49, 0.72, 0.38),
	Terrain.FOREST: Color(0.27, 0.48, 0.25),
	Terrain.MOUNTAIN: Color(0.55, 0.52, 0.48),
	Terrain.WATER: Color(0.29, 0.51, 0.73),
}

## 移動花費；小於 0 代表無法通行
const TERRAIN_COST := {
	Terrain.GRASS: 1,
	Terrain.FOREST: 2,
	Terrain.MOUNTAIN: -1,
	Terrain.WATER: -1,
}

const NO_COORD := Vector2i(999999, 999999)

@export var hex_size: float = 40.0
@export var map_radius: int = 6
@export var random_seed: int = 12345

var tiles: Dictionary = {} # Vector2i -> Terrain

var hovered_coord: Vector2i = NO_COORD
var selected_coord: Vector2i = NO_COORD
var reachable: Dictionary = {} # Vector2i -> int cost
var path: Array[Vector2i] = []
## 可攻擊的敵人所在格
var attack_targets: Dictionary = {} # Vector2i -> true

## 玩家佈署區
var deploy_zone: Dictionary = {} # Vector2i -> true
var show_deploy_zone: bool = false
## 拖曳時懸停格的放置狀態
enum DropState { NONE, VALID, INVALID }
var drop_state: DropState = DropState.NONE

func generate_map(radius: int = map_radius) -> void:
	map_radius = radius
	tiles.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	for q in range(-radius, radius + 1):
		var r1: int = max(-radius, -q - radius)
		var r2: int = min(radius, -q + radius)
		for r in range(r1, r2 + 1):
			var coord := Vector2i(q, r)
			var terrain: Terrain = Terrain.GRASS
			if coord != Vector2i.ZERO:
				var roll := rng.randf()
				if roll < 0.12:
					terrain = Terrain.MOUNTAIN
				elif roll < 0.24:
					terrain = Terrain.WATER
				elif roll < 0.40:
					terrain = Terrain.FOREST
			tiles[coord] = terrain
	queue_redraw()

func axial_to_pixel(coord: Vector2i) -> Vector2:
	return HexUtils.axial_to_pixel(coord, hex_size)

func pixel_to_axial(pos: Vector2) -> Vector2i:
	return HexUtils.pixel_to_axial(pos, hex_size)

func has_tile(coord: Vector2i) -> bool:
	return tiles.has(coord)

func get_terrain(coord: Vector2i) -> Terrain:
	return tiles.get(coord, Terrain.GRASS)

func is_walkable(coord: Vector2i) -> bool:
	return tiles.has(coord) and TERRAIN_COST[tiles[coord]] > 0

func movement_cost(coord: Vector2i) -> int:
	return TERRAIN_COST[tiles[coord]]

## 以地圖最下方 rows 列可通行格作為佈署區
func setup_deploy_zone(rows: int) -> void:
	deploy_zone.clear()
	for coord in tiles.keys():
		if coord.y > map_radius - rows and is_walkable(coord):
			deploy_zone[coord] = true
	queue_redraw()

func is_deploy_tile(coord: Vector2i) -> bool:
	return deploy_zone.has(coord)

func get_neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for n in HexUtils.neighbors(coord):
		if tiles.has(n):
			result.append(n)
	return result

## 以權重花費做範圍搜尋（Dijkstra 鬆弛法），回傳 {"cost": {座標:花費}, "came_from": {座標:前一格}}
## blocked 中的格子（例如被單位佔據）無法進入或穿越
func compute_reachable(start: Vector2i, max_cost: int, blocked: Dictionary = {}) -> Dictionary:
	var cost_so_far: Dictionary = {start: 0}
	var came_from: Dictionary = {start: start}
	var frontier: Array[Vector2i] = [start]
	while frontier.size() > 0:
		var current: Vector2i = frontier.pop_front()
		for neighbor in get_neighbors(current):
			if not is_walkable(neighbor) or blocked.has(neighbor):
				continue
			var new_cost: int = cost_so_far[current] + movement_cost(neighbor)
			if new_cost <= max_cost and (not cost_so_far.has(neighbor) or new_cost < cost_so_far[neighbor]):
				cost_so_far[neighbor] = new_cost
				came_from[neighbor] = current
				frontier.append(neighbor)
	return {"cost": cost_so_far, "came_from": came_from}

func reconstruct_path(came_from: Dictionary, start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not came_from.has(end):
		return result
	var current: Vector2i = end
	while current != start:
		result.push_front(current)
		current = came_from[current]
	return result

func set_highlight(new_reachable: Dictionary, new_path: Array[Vector2i]) -> void:
	reachable = new_reachable
	path = new_path
	queue_redraw()

func set_attack_targets(coords: Array[Vector2i]) -> void:
	attack_targets.clear()
	for coord in coords:
		attack_targets[coord] = true
	queue_redraw()

func clear_highlight() -> void:
	reachable = {}
	path = []
	attack_targets.clear()
	selected_coord = NO_COORD
	queue_redraw()

func _draw() -> void:
	for coord in tiles.keys():
		var terrain: Terrain = tiles[coord]
		var center := axial_to_pixel(coord)
		var points := PackedVector2Array()
		for i in range(6):
			points.append(center + HexUtils.corner_offset(hex_size - 1.0, i))

		var color: Color = TERRAIN_COLOR[terrain]
		if show_deploy_zone and deploy_zone.has(coord):
			color = color.lerp(Color(0.35, 0.6, 1.0), 0.45)
		if reachable.has(coord):
			color = color.lerp(Color.WHITE, 0.35)
		if path.has(coord):
			color = color.lerp(Color.YELLOW, 0.4)
		if attack_targets.has(coord):
			color = color.lerp(Color(1.0, 0.15, 0.1), 0.55)
		draw_colored_polygon(points, color)

		var outline_color := Color(0, 0, 0, 0.25)
		var outline_width := 1.0
		if coord == hovered_coord:
			outline_color = Color(1, 1, 1, 0.9)
			outline_width = 2.0
			if drop_state == DropState.VALID:
				outline_color = Color(0.3, 1.0, 0.4, 1.0)
				outline_width = 3.0
			elif drop_state == DropState.INVALID:
				outline_color = Color(1.0, 0.3, 0.3, 1.0)
				outline_width = 3.0
		if coord == selected_coord:
			outline_color = Color(1, 0.85, 0.2, 1.0)
			outline_width = 3.0

		var closed_points := points.duplicate()
		closed_points.append(points[0])
		draw_polyline(closed_points, outline_color, outline_width)
