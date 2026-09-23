class_name HexMap
extends Node2D

enum Terrain { GRASS, FOREST, MOUNTAIN, WATER }

const TERRAIN_NAME := {
	Terrain.GRASS: "Grass",
	Terrain.FOREST: "Forest",
	Terrain.MOUNTAIN: "Mountain",
	Terrain.WATER: "Water",
}

## 移動花費；小於 0 代表無法通行
const TERRAIN_COST := {
	Terrain.GRASS: 1,
	Terrain.FOREST: 2,
	Terrain.MOUNTAIN: -1,
	Terrain.WATER: -1,
}

## 站在該地形上的單位獲得的閃避率
const TERRAIN_EVASION := {
	Terrain.FOREST: 0.15,
}

## 高亮層的內縮，讓外框不會壓到相鄰格
const OVERLAY_INSET := 3.0

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

var terrain_layer: TerrainLayer

func _ready() -> void:
	terrain_layer = TerrainLayer.new()
	terrain_layer.hex_map = self
	# 地形畫在本節點（高亮層）之下
	terrain_layer.show_behind_parent = true
	add_child(terrain_layer)

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
	if terrain_layer:
		terrain_layer.queue_redraw()
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

func evasion(coord: Vector2i) -> float:
	return TERRAIN_EVASION.get(get_terrain(coord), 0.0)

## 地形說明，例如 "Forest · Move 2 · Evade +15%"
func describe(coord: Vector2i) -> String:
	var terrain := get_terrain(coord)
	var text: String = TERRAIN_NAME[terrain]
	if not is_walkable(coord):
		return text + " · Impassable"
	text += " · Move %d" % movement_cost(coord)
	var eva := evasion(coord)
	if eva > 0.0:
		text += " · Evade +%d%%" % roundi(eva * 100)
	return text

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
	# 只畫高亮；地形底圖由 TerrainLayer 負責
	for coord in tiles.keys():
		var fill := Color(0, 0, 0, 0)
		var border := Color(0, 0, 0, 0)
		var border_width := 0.0
		if show_deploy_zone and deploy_zone.has(coord):
			fill = Color(0.3, 0.6, 1.0, 0.32)
			border = Color(0.6, 0.82, 1.0, 0.85)
			border_width = 2.0
		if reachable.has(coord):
			fill = Color(1, 1, 1, 0.22)
			border = Color(1, 1, 1, 0.5)
			border_width = 1.5
		if path.has(coord):
			fill = Color(1.0, 0.85, 0.3, 0.4)
			border = Color(1.0, 0.9, 0.45, 0.9)
			border_width = 2.0
		if attack_targets.has(coord):
			fill = Color(1.0, 0.25, 0.2, 0.2)
			border = Color(1.0, 0.25, 0.2, 1.0)
			border_width = 3.5
		if coord == hovered_coord:
			border = Color(1, 1, 1, 0.95)
			border_width = maxf(border_width, 2.5)
			if drop_state == DropState.VALID:
				border = Color(0.35, 1.0, 0.45)
				border_width = 3.0
			elif drop_state == DropState.INVALID:
				border = Color(1.0, 0.35, 0.35)
				border_width = 3.0
		if coord == selected_coord:
			border = Color(1, 0.85, 0.2)
			border_width = 3.0
		if fill.a <= 0.0 and border_width <= 0.0:
			continue
		var center := axial_to_pixel(coord)
		var points := PackedVector2Array()
		for i in 6:
			points.append(center + HexUtils.corner_offset(hex_size - OVERLAY_INSET, i))
		if fill.a > 0.0:
			draw_colored_polygon(points, fill)
		if border_width > 0.0:
			points.append(points[0])
			draw_polyline(points, border, border_width, true)
