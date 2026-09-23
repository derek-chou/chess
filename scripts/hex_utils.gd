class_name HexUtils
extends RefCounted

const SQRT3 := 1.7320508075688772

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

static func axial_to_pixel(coord: Vector2i, size: float) -> Vector2:
	var q := float(coord.x)
	var r := float(coord.y)
	var x := size * (SQRT3 * q + SQRT3 / 2.0 * r)
	var y := size * (1.5 * r)
	return Vector2(x, y)

static func pixel_to_axial(pos: Vector2, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * pos.x - 1.0 / 3.0 * pos.y) / size
	var r := (2.0 / 3.0 * pos.y) / size
	return cube_round(q, r)

static func cube_round(q: float, r: float) -> Vector2i:
	var x := q
	var z := r
	var y := -x - z
	var rx: float = round(x)
	var ry: float = round(y)
	var rz: float = round(z)
	var dx: float = abs(rx - x)
	var dy: float = abs(ry - y)
	var dz: float = abs(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))

static func neighbors(coord: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dir in DIRECTIONS:
		result.append(coord + dir)
	return result

static func distance(a: Vector2i, b: Vector2i) -> int:
	return (abs(a.x - b.x) + abs(a.x + a.y - b.x - b.y) + abs(a.y - b.y)) / 2

static func corner_offset(size: float, i: int) -> Vector2:
	var angle_deg := 60.0 * i - 30.0
	var angle_rad := deg_to_rad(angle_deg)
	return Vector2(size * cos(angle_rad), size * sin(angle_rad))
