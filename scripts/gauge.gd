class_name Gauge
extends Control
## A labelled bar: how full something is. An optional "after" value shows
## where a pending change (the market basket) would leave it, as a hatched
## band; red when it runs past the end.

var title := ""
var value := 0.0
var top := 1.0
var after := -1.0
var colour := Color(0.25, 0.45, 0.25)
var text := ""

static func make(t: String, v: float, m: float, col: Color, txt := "", aft := -1.0, w := 118.0) -> Gauge:
	var g := Gauge.new()
	g.title = t
	g.value = v
	g.top = maxf(m, 0.001)
	g.colour = col
	g.text = txt
	g.after = aft
	g.custom_minimum_size = Vector2(w, 30)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g

func _draw() -> void:
	var ink := Color(0.16, 0.11, 0.07)
	var font := ThemeDB.fallback_font
	var bar := Rect2(Vector2(0, 14), Vector2(size.x - 4.0, 13))
	draw_rect(bar, Color(0.82, 0.76, 0.62))
	var f := clampf(value / top, 0.0, 1.0)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * f, bar.size.y)), colour)
	if after >= 0.0:
		var fa := clampf(after / top, 0.0, 1.0)
		var over := after > top + 0.001
		var a0 := minf(f, fa)
		var a1 := maxf(f, fa)
		var band := Rect2(bar.position + Vector2(bar.size.x * a0, 0), Vector2(bar.size.x * (a1 - a0), bar.size.y))
		var col := Color(0.7, 0.15, 0.1, 0.75) if over else (colour.lightened(0.45) if fa > f else Color(0.93, 0.88, 0.76, 0.8))
		draw_rect(band, col)
		draw_line(bar.position + Vector2(bar.size.x * fa, -2), bar.position + Vector2(bar.size.x * fa, bar.size.y + 2), ink, 2.0)
		if over:
			draw_rect(bar, Color(0.7, 0.15, 0.1), false, 2.0)
	draw_rect(bar, ink, false, 1.0)
	draw_string(font, Vector2(0, 11), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, ink)
	if text != "":
		draw_string(font, Vector2(0, 11), text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4.0, 11, ink)
