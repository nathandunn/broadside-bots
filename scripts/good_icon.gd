class_name GoodIcon
extends Control
## A small drawn picture of a good or a ship's store, with an optional
## price mark: green ▼ when it's cheap here, red ▲ when it's dear.

var kind := ""
var mark := 0      # -1 cheap here, +1 dear here, 0 neither

static func make(k: String, m := 0) -> GoodIcon:
	var i := GoodIcon.new()
	i.kind = k
	i.mark = m
	i.custom_minimum_size = Vector2(34, 30)
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i

func _draw() -> void:
	var c := Vector2(15, 15)
	var ink := Color(0.16, 0.11, 0.07)
	match kind:
		"sugar":   _sack(c, Color(0.95, 0.93, 0.85), ink)
		"food":    _sack(c, Color(0.80, 0.66, 0.42), ink)
		"tobacco": _leaf(c, Color(0.55, 0.40, 0.15), ink)
		"rum":     _barrel(c, Color(0.55, 0.32, 0.15), ink)
		"water":   _barrel(c, Color(0.45, 0.60, 0.70), ink)
		"powder":  _barrel(c, Color(0.20, 0.18, 0.16), ink)
		"cloth":   _bolt(c, Color(0.65, 0.20, 0.25), ink)
		"timber":  _logs(c, Color(0.60, 0.42, 0.22), ink)
		"spares":  _logs(c, Color(0.75, 0.62, 0.40), ink)
		"spices":  _jar(c, Color(0.85, 0.45, 0.15), ink)
		"medicine": _jar(c, Color(0.35, 0.55, 0.35), ink)
		"silver":  _ingot(c, Color(0.78, 0.80, 0.84), ink)
		_:         draw_circle(c, 9.0, Color(0.6, 0.6, 0.6))
	if mark != 0:
		var p := Vector2(29, 8)
		var col := Color(0.15, 0.5, 0.15) if mark < 0 else Color(0.7, 0.15, 0.1)
		var tri := PackedVector2Array([p + Vector2(-4, -3), p + Vector2(4, -3), p + Vector2(0, 4)]) if mark < 0 \
			else PackedVector2Array([p + Vector2(-4, 3), p + Vector2(4, 3), p + Vector2(0, -4)])
		draw_colored_polygon(tri, col)

func _outline(pts: PackedVector2Array, ink: Color) -> void:
	draw_polyline(pts + PackedVector2Array([pts[0]]), ink, 1.2)

func _sack(c: Vector2, col: Color, ink: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-5, -10), c + Vector2(5, -10), c + Vector2(3, -7), c + Vector2(10, 2),
		c + Vector2(8, 11), c + Vector2(-8, 11), c + Vector2(-10, 2), c + Vector2(-3, -7)])
	draw_colored_polygon(pts, col)
	_outline(pts, ink)
	draw_line(c + Vector2(-4, -7), c + Vector2(4, -7), ink, 1.5)

func _barrel(c: Vector2, col: Color, ink: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-7, -11), c + Vector2(7, -11), c + Vector2(10, 0), c + Vector2(7, 11),
		c + Vector2(-7, 11), c + Vector2(-10, 0)])
	draw_colored_polygon(pts, col)
	_outline(pts, ink)
	for y in [-6.0, 6.0]:
		draw_line(c + Vector2(-9, y), c + Vector2(9, y), ink, 1.5)

func _leaf(c: Vector2, col: Color, ink: Color) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		pts.append(c + Vector2(sin(t * PI) * 8.0, -11.0 + t * 22.0))
	for i in range(11, 0, -1):
		var t := float(i) / 12.0
		pts.append(c + Vector2(-sin(t * PI) * 8.0, -11.0 + t * 22.0))
	draw_colored_polygon(pts, col)
	_outline(pts, ink)
	draw_line(c + Vector2(0, -11), c + Vector2(0, 11), ink, 1.2)

func _bolt(c: Vector2, col: Color, ink: Color) -> void:
	var r := Rect2(c + Vector2(-10, -7), Vector2(18, 14))
	draw_rect(r, col)
	draw_rect(r, ink, false, 1.2)
	draw_circle(c + Vector2(8, 0), 7.0, col.darkened(0.2))
	draw_arc(c + Vector2(8, 0), 7.0, 0.0, TAU, 20, ink, 1.2)
	draw_arc(c + Vector2(8, 0), 3.0, 0.0, TAU, 12, ink, 1.0)

func _logs(c: Vector2, col: Color, ink: Color) -> void:
	for o in [Vector2(-5, 5), Vector2(5, 5), Vector2(0, -4)]:
		draw_circle(c + o, 5.5, col)
		draw_arc(c + o, 5.5, 0.0, TAU, 16, ink, 1.2)
		draw_arc(c + o, 2.5, 0.0, TAU, 10, ink.lightened(0.3), 1.0)

func _jar(c: Vector2, col: Color, ink: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-4, -11), c + Vector2(4, -11), c + Vector2(4, -7), c + Vector2(9, -2),
		c + Vector2(8, 11), c + Vector2(-8, 11), c + Vector2(-9, -2), c + Vector2(-4, -7)])
	draw_colored_polygon(pts, col)
	_outline(pts, ink)
	draw_rect(Rect2(c + Vector2(-5, -12), Vector2(10, 3)), ink)

func _ingot(c: Vector2, col: Color, ink: Color) -> void:
	for off in [Vector2(0, 4), Vector2(0, -4)]:
		var pts := PackedVector2Array([c + off + Vector2(-7, -4), c + off + Vector2(7, -4), c + off + Vector2(10, 4),
			c + off + Vector2(-10, 4)])
		draw_colored_polygon(pts, col)
		_outline(pts, ink)
