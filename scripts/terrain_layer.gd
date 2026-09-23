class_name TerrainLayer
extends Node2D

## 繪製地形底圖與裝飾；只在地圖生成時重畫，與頻繁更新的高亮層分開

const GAP := 1.5

const GRASS_BASE := Color(0.47, 0.70, 0.36)
const GRASS_TUFT := Color(0.33, 0.55, 0.25)
const FOREST_BASE := Color(0.36, 0.56, 0.30)
const FOREST_CANOPY := Color(0.17, 0.40, 0.19)
const FOREST_CANOPY_LIGHT := Color(0.27, 0.53, 0.25)
const TRUNK := Color(0.40, 0.27, 0.16)
const MOUNTAIN_BASE := Color(0.50, 0.47, 0.43)
const ROCK_LIGHT := Color(0.66, 0.63, 0.59)
const ROCK_DARK := Color(0.45, 0.43, 0.40)
const SNOW := Color(0.95, 0.96, 0.98)
const WATER_BASE := Color(0.25, 0.50, 0.76)
const WATER_DEEP := Color(0.20, 0.42, 0.68)
const WAVE := Color(0.62, 0.82, 0.96, 0.85)

var hex_map: HexMap

func _draw() -> void:
	if hex_map == null:
		return
	# 由上往下畫，讓下方格子的裝飾（樹、山）能自然疊在上方格子前面
	var coords: Array = hex_map.tiles.keys()
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	for coord in coords:
		_draw_tile(coord, hex_map.tiles[coord])

func _draw_tile(coord: Vector2i, terrain: HexMap.Terrain) -> void:
	var center := hex_map.axial_to_pixel(coord)
	var size := hex_map.hex_size - GAP
	# 以座標為種子，讓每格的色差與裝飾位置固定
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(coord)
	var points := _hex_points(center, size)

	var base: Color
	match terrain:
		HexMap.Terrain.GRASS: base = GRASS_BASE
		HexMap.Terrain.FOREST: base = FOREST_BASE
		HexMap.Terrain.MOUNTAIN: base = MOUNTAIN_BASE
		HexMap.Terrain.WATER: base = WATER_BASE
	base = base.lightened(rng.randf_range(0.0, 0.05)) if rng.randf() < 0.5 else base.darkened(rng.randf_range(0.0, 0.05))
	draw_colored_polygon(points, base)

	match terrain:
		HexMap.Terrain.GRASS: _draw_grass(center, rng)
		HexMap.Terrain.FOREST: _draw_forest(center, rng)
		HexMap.Terrain.MOUNTAIN: _draw_mountain(center, rng)
		HexMap.Terrain.WATER: _draw_water(center, size, rng)

	_draw_bevel(center, size)

## 左上緣亮、右下緣暗，營造微微隆起的立體感
func _draw_bevel(center: Vector2, size: float) -> void:
	var inset := _hex_points(center, size - 1.5)
	# 尖頂六角形角點：0 右上、1 右下、2 底、3 左下、4 左上、5 頂
	draw_polyline(PackedVector2Array([inset[3], inset[4], inset[5], inset[0]]), Color(1, 1, 1, 0.16), 2.0, true)
	draw_polyline(PackedVector2Array([inset[0], inset[1], inset[2], inset[3]]), Color(0, 0, 0, 0.22), 2.0, true)

func _draw_grass(center: Vector2, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(3, 5):
		var p := center + Vector2(rng.randf_range(-20, 20), rng.randf_range(-16, 18))
		for dx in [-3.0, 0.0, 3.0]:
			draw_line(p, p + Vector2(dx * 0.6, -5.0 + absf(dx) * 0.3), GRASS_TUFT, 1.4, true)
	if rng.randf() < 0.3:
		var flower := center + Vector2(rng.randf_range(-16, 16), rng.randf_range(-12, 14))
		draw_circle(flower, 2.0, Color(1, 0.95, 0.6) if rng.randf() < 0.5 else Color(1, 1, 1))

func _draw_forest(center: Vector2, rng: RandomNumberGenerator) -> void:
	var spots: Array[Vector2] = [Vector2(-11, -6), Vector2(11, -8), Vector2(0, 9)]
	for spot in spots:
		var p := center + spot + Vector2(rng.randf_range(-3, 3), rng.randf_range(-2, 2))
		var r := rng.randf_range(8.0, 10.5)
		_draw_ellipse(p + Vector2(2, r * 0.9), Vector2(r * 0.9, r * 0.35), Color(0, 0, 0, 0.22))
		draw_rect(Rect2(p + Vector2(-1.5, r * 0.3), Vector2(3, r * 0.6)), TRUNK)
		draw_circle(p, r, FOREST_CANOPY)
		draw_circle(p + Vector2(-r * 0.3, -r * 0.3), r * 0.5, FOREST_CANOPY_LIGHT)

func _draw_mountain(center: Vector2, rng: RandomNumberGenerator) -> void:
	var shift := rng.randf_range(-3, 3)
	_draw_peak(center + Vector2(11 + shift, 9), 15.0, 21.0)
	_draw_peak(center + Vector2(-6 + shift, 14), 21.0, 32.0)

## 以底部中點、半寬與高度畫一座山：亮面、暗面與雪頂
func _draw_peak(base_mid: Vector2, half_w: float, height: float) -> void:
	var top := base_mid + Vector2(0, -height)
	var left := base_mid + Vector2(-half_w, 0)
	var right := base_mid + Vector2(half_w, 0)
	draw_colored_polygon(PackedVector2Array([left, top, base_mid]), ROCK_LIGHT)
	draw_colored_polygon(PackedVector2Array([base_mid, top, right]), ROCK_DARK)
	var snow_t := 0.35
	var snow_left := top.lerp(left, snow_t)
	var snow_right := top.lerp(right, snow_t)
	var snow_mid := top.lerp(base_mid, snow_t * 1.2)
	draw_colored_polygon(PackedVector2Array([snow_left, top, snow_right, snow_mid + Vector2(3, -2), snow_mid + Vector2(-3, 1)]), SNOW)
	draw_polyline(PackedVector2Array([left, top, right]), Color(0, 0, 0, 0.25), 1.2, true)

func _draw_water(center: Vector2, size: float, rng: RandomNumberGenerator) -> void:
	draw_colored_polygon(_hex_points(center + Vector2(0, 3), size * 0.62), WATER_DEEP)
	for i in 3:
		var p := center + Vector2(rng.randf_range(-15, 15), -12 + i * 11 + rng.randf_range(-2, 2))
		draw_arc(p + Vector2(-4, 0), 4.0, PI * 1.1, PI * 1.9, 6, WAVE, 1.6, true)
		draw_arc(p + Vector2(4, 0), 4.0, PI * 1.1, PI * 1.9, 6, WAVE, 1.6, true)

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, color)

func _hex_points(center: Vector2, size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		pts.append(center + HexUtils.corner_offset(size, i))
	return pts
