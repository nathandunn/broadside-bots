extends Control
## v0 UI: a sea chart on top, the captain's controls below. Built in code so
## the whole thing lives in one readable file.

const NATION_COLOURS := {
	"England": Color(0.80, 0.20, 0.20), "France": Color(0.25, 0.40, 0.90),
	"Dutch": Color(0.95, 0.55, 0.15), "Spain": Color(0.95, 0.85, 0.20),
	"Denmark": Color(0.85, 0.85, 0.85),
}
const INK := Color(0.16, 0.11, 0.07)
const PAPER := Color(0.93, 0.88, 0.76)

var state: GameState
var map: MapView
var status: RichTextLabel
var panel: VBoxContainer
var journal: RichTextLabel
var orders := {"range": "close", "shot": "round", "board": true, "ram": false}

class MapView extends Control:
	var main: Node
	const LON0 := -70.0
	const LON1 := -58.0
	const LAT0 := 9.5
	const LAT1 := 19.0

	func project(lat: float, lon: float) -> Vector2:
		var x := (lon - LON0) / (LON1 - LON0) * size.x
		var y := (1.0 - (lat - LAT0) / (LAT1 - LAT0)) * size.y
		return Vector2(x, y)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.55, 0.70, 0.75))
		var s: GameState = main.state
		if s == null:
			return
		var font := ThemeDB.fallback_font
		# Route
		if s.at_sea() and not s.voyage.is_empty():
			var a := World.port_by_id(s.voyage["from"])
			var b := World.port_by_id(s.voyage["to"])
			var pa := project(a["lat"], a["lon"])
			var pb := project(b["lat"], b["lon"])
			draw_dashed_line(pa, pb, Color(0.2, 0.15, 0.1, 0.7), 2.0, 8.0)
		# Ports
		for p in World.PORTS:
			var pos := project(p["lat"], p["lon"])
			var c: Color = NATION_COLOURS.get(p["nation"], Color.WHITE)
			var blocked: bool = Sim.can_sail_to(s, p["id"]) != "" and p["id"] != s.location
			draw_circle(pos, 9.0, Color(0, 0, 0, 0.5))
			draw_circle(pos, 7.0, c.darkened(0.5) if blocked else c)
			var label: String = p["name"].split(",")[0]
			if p["haven"]:
				label += " ☠"
			draw_string(font, pos + Vector2(11, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, INK)
		# Ship
		var sp := Vector2.ZERO
		if s.at_sea() and not s.voyage.is_empty():
			var a2 := World.port_by_id(s.voyage["from"])
			var b2 := World.port_by_id(s.voyage["to"])
			var t: float = clamp(float(s.voyage["done_nm"]) / max(1.0, float(s.voyage["total_nm"])), 0.0, 1.0)
			sp = project(a2["lat"], a2["lon"]).lerp(project(b2["lat"], b2["lon"]), t)
			if s.voyage.get("cruise", false):
				# Cruising: show her standing out to sea and back.
				var c := project(a2["lat"], a2["lon"])
				sp = c + Vector2(cos(t * TAU), sin(t * TAU)).normalized() * 60.0 * sin(t * PI) + Vector2(0, -16) * (1.0 - sin(t * PI))
		else:
			var here := World.port_by_id(s.location)
			sp = project(here["lat"], here["lon"]) + Vector2(0, -16)
		var pts := PackedVector2Array([sp + Vector2(0, -10), sp + Vector2(8, 6), sp + Vector2(-8, 6)])
		draw_colored_polygon(pts, Color.BLACK if s.role == "Pirate" else Color.WHITE)
		draw_polyline(pts + PackedVector2Array([pts[0]]), INK, 1.5)

	func _gui_input(event: InputEvent) -> void:
		var s: GameState = main.state
		if s == null or s.ended or s.at_sea():
			return
		if event is InputEventMouseButton and event.pressed:
			for p in World.PORTS:
				if project(p["lat"], p["lon"]).distance_to(event.position) < 18.0:
					main.sail_to(p["id"])
					return

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = PAPER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	map = MapView.new()
	map.main = self
	map.custom_minimum_size = Vector2(0, 300)
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.size_flags_stretch_ratio = 0.9
	root.add_child(map)

	status = RichTextLabel.new()
	status.bbcode_enabled = true
	status.fit_content = true
	status.add_theme_color_override("default_color", INK)
	root.add_child(status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	panel = VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)

	journal = RichTextLabel.new()
	journal.custom_minimum_size = Vector2(0, 130)
	journal.scroll_following = true
	journal.add_theme_color_override("default_color", INK)
	journal.add_theme_font_size_override("normal_font_size", 13)
	root.add_child(journal)

	refresh()

# ------------------------------------------------------------------ helpers

func _btn(parent: Control, text: String, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _row(parent: Control) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 4)
	parent.add_child(h)
	return h

func _label(parent: Control, text: String, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	if parent is HFlowContainer:
		l.custom_minimum_size = Vector2(290 if text.length() > 12 else 0, 0)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", INK)
	if bold:
		l.add_theme_font_size_override("font_size", 18)
	parent.add_child(l)
	return l

func _check(text: String, on: bool) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	for k in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		c.add_theme_color_override(k, INK)
	return c

func _option(parent: Control, items: Array, current: String, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(String(items[i]))
		if items[i] == current:
			o.select(i)
	o.item_selected.connect(func(i): cb.call(items[i]))
	parent.add_child(o)
	return o

func note(msg: String) -> void:
	if msg != "" and state != null:
		state.say(msg)
	refresh()

# ------------------------------------------------------------------ screens

func refresh() -> void:
	for c in panel.get_children():
		c.queue_free()
	map.queue_redraw()
	if state == null:
		_title_screen()
		status.text = "[b]Broadside Bots[/b] v%s — choose your life, Captain." % World.VERSION
		journal.text = ""
		return
	_status()
	journal.text = "\n".join(state.journal.slice(max(0, state.journal.size() - 40)))
	if state.ended:
		_end_screen()
	elif not state.encounter.is_empty():
		_encounter_screen()
	elif state.at_sea():
		_sea_screen()
	else:
		_port_screen()

func _status() -> void:
	var s := state
	var where: String = World.port_by_id(s.location)["name"] if not s.at_sea() else \
		"At sea → %s (%d of %d nm)" % [World.port_by_id(s.voyage["to"])["name"], s.voyage["done_nm"], s.voyage["total_nm"]]
	var lines := []
	lines.append("[b]%s %s[/b], aged %d — %s — %s" % [s.role, s.captain_name, s.age, Sim.date_string(s), where])
	lines.append("%s [i]%s[/i]: hull %d/%d, rig %d%%, %d guns, hold %d/%d t" % [
		s.ship["name"], s.ship["label"], s.ship["hull"], s.ship["hull_max"], s.ship["rig"],
		s.ship["guns"], s.cargo_used(), s.ship["cargo"]])
	lines.append("Crew %d/%d · health %d · morale %d%s · food %d days · water %d days · powder %.1f t" % [
		s.crew, s.ship["crew_cap"], s.health, s.morale,
		(" · wages owed %d" % s.pay_owed) if s.pay_owed > 0.0 else "",
		Sim.days_of(s, "food"), Sim.days_of(s, "water"), float(s.stores.get("powder", 0.0))])
	lines.append("Chest %d · purse %d%s · prizes %d" % [s.chest, s.purse,
		(" · bounty %d" % s.bounty) if s.bounty > 0.0 else "", s.prizes_taken])
	status.text = "\n".join(lines)

func _title_screen() -> void:
	_label(panel, "Pirates! meets the Mayflower meets the Oregon Trail. Make your fortune in the eastern Caribbean, 1675, and retire alive.", false)
	_label(panel, "Trader: a fat fluyt, small crew, honest ports. Wages are owed daily. Attack a ship of a nation at peace and you're a pirate.")
	_label(panel, "Pirate: a fast sloop, a hungry crew, and one friendly harbour (St Thomas ☠). No wages — plunder or mutiny.")
	var r := _row(panel)
	_btn(r, "Begin as Trader", func(): _start("Trader"))
	_btn(r, "Begin as Pirate", func(): _start("Pirate"))
	_label(panel, "Coming in later versions: 3D sea battles, Navy and Privateer careers, the Atlantic crossing with colonists, and your own island.")

func _start(role: String) -> void:
	state = Sim.new_game(role)
	refresh()

func _new_career() -> void:
	state = null
	refresh()

func _port_screen() -> void:
	var s := state
	var port := World.port_by_id(s.location)
	_label(panel, "%s (%s)" % [port["name"], port["nation"]], true)

	_label(panel, "Market — price per ton (buy / sell)", true)
	for g in World.GOODS:
		var r := _row(panel)
		var held := float(s.cargo.get(g, 0.0))
		_label(r, "%s: %d / %d  (aboard %d t)" % [World.GOODS[g]["name"], Sim.buy_price(s, s.location, g),
			Sim.sell_price(s, s.location, g), held])
		_btn(r, "Buy 10", func(): note(Sim.buy_good(s, g, 10.0)))
		_btn(r, "Sell 10", func(): note(Sim.sell_good(s, g, 10.0)), held <= 0.0)
		_btn(r, "Sell all", func(): note(Sim.sell_good(s, g, held)), held <= 0.0)

	_label(panel, "Ship's stores", true)
	var sr := _row(panel)
	for st in World.STORES:
		var amt := 0.5 if st == "medicine" else 1.0
		_btn(sr, "%s +%.1ft (%d)" % [World.STORES[st]["name"], amt, Sim.store_price(s, st) * amt],
			func(): note(Sim.buy_store(s, st, amt)))

	_label(panel, "Ashore", true)
	var ar := _row(panel)
	_btn(ar, "Sign on 5 hands", func(): note(Sim.recruit(s, 5)))
	if s.role == "Trader":
		_btn(ar, "Pay wages", func(): note(Sim.pay_wages(s)), s.pay_owed <= 0.0)
		_btn(ar, "Bank 500", func(): note(Sim.bank(s, 500.0)), s.chest < 1.0)
		_btn(ar, "Draw 500", func(): note(Sim.withdraw(s, 500.0)), s.purse < 1.0)
	else:
		_btn(ar, "Share out the plunder", func(): note(Sim.share_out(s)), not port["haven"])
	_btn(ar, "Rest 3 days", func(): note(Sim.rest(s, 3)))
	var rc := Sim.repair_cost(s)
	_btn(ar, "Repair (%d)" % rc, func(): note(Sim.repair(s)), rc <= 0.0)
	_btn(ar, "Retire", func(): note(Sim.retire(s)["text"]))
	_btn(ar, "Cruise 20 days" if s.role == "Pirate" else "Cruise for prizes (20 days)", func(): note(Sim.cruise(s, 20)))

	_label(panel, "Set sail for… (or tap a port on the chart)", true)
	var dr := _row(panel)
	for p in World.PORTS:
		if p["id"] == s.location:
			continue
		var why := Sim.can_sail_to(s, p["id"])
		var b := _btn(dr, "%s (~%.0f d)" % [p["name"].split(",")[0], Sim.est_days(s, p["id"])],
			func(): sail_to(p["id"]), why != "")
		b.tooltip_text = why

func sail_to(id: String) -> void:
	var why := Sim.set_sail(state, id)
	note(why)

func _sea_screen() -> void:
	var s := state
	var r := _row(panel)
	_label(r, "Pace")
	_option(r, ["easy", "steady", "crowd"], s.pace, func(v): _set_pace(v))
	_label(r, "Rations")
	_option(r, ["full", "half", "short"], s.rations, func(v): _set_rations(v))
	var rum := _check("Rum ration", s.rum_ration)
	rum.toggled.connect(func(v): s.rum_ration = v)
	r.add_child(rum)
	var r2 := _row(panel)
	_btn(r2, "Sail one day", _sail_one)
	_btn(r2, "Sail until something happens", _sail_until)
	if s.voyage.get("cruise", false):
		_btn(r2, "Make for port", func(): note(Sim.head_home(s)))

func _set_pace(v: String) -> void:
	state.pace = v
	refresh()

func _set_rations(v: String) -> void:
	state.rations = v
	refresh()

func _sail_one() -> void:
	Sim.sail_day(state)
	refresh()

func _sail_until() -> void:
	for i in 60:
		var ev := Sim.sail_day(state)
		if state.ended or not state.at_sea() or not ev.is_empty():
			break
	refresh()

func _encounter_screen() -> void:
	var s := state
	var e: Dictionary = s.encounter
	_label(panel, e["text"], true)
	var tr: Dictionary = e["traits"]
	_label(panel, "Her captain: aggression %.1f, caution %.1f, greed %.1f, honour %.1f" % [
		tr["aggression"], tr["caution"], tr["greed"], tr["honour"]])
	if s.role == "Trader" and e["kind"] != "pirate" and not World.at_war(Sim.flag(s), e["nation"]):
		_label(panel, "⚠ Attacking her makes you a pirate.")
	_label(panel, "Standing orders", true)
	var o := _row(panel)
	_label(o, "Range")
	_option(o, ["close", "long"], orders["range"], func(v): orders["range"] = v)
	_label(o, "Shot")
	_option(o, ["round", "chain", "grape"], orders["shot"], func(v): orders["shot"] = v)
	var board := _check("Board", orders["board"])
	board.toggled.connect(func(v): orders["board"] = v)
	o.add_child(board)
	var ram := _check("Ram", orders["ram"])
	ram.toggled.connect(func(v): orders["ram"] = v)
	o.add_child(ram)
	var a := _row(panel)
	_btn(a, "Sail on", func(): _act("sail_on"))
	_btn(a, "Flee", func(): _act("flee"))
	_btn(a, "Trade", func(): _act("trade"), e["hostile"] or e["kind"] != "merchant")
	_btn(a, "Attack!", func(): _act("attack"))
	_btn(a, "Strike colours", func(): _act("surrender"), not e["hostile"])

func _act(action: String) -> void:
	var res := Sim.resolve(state, action, orders)
	if res.has("lines"):
		for l in res["lines"]:
			state.journal.append("    " + l)
	refresh()

func _end_screen() -> void:
	_label(panel, state.end_reason, true)
	_label(panel, "Net worth at the end: %d" % Sim.net_worth(state))
	_btn(panel, "New career", _new_career)
