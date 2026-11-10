extends Control
## The captain's desk: a sea chart on top, controls below, and a 3D view
## that takes over the screen for a fight. Built in code so it all lives in
## readable files.

const INK := Color(0.16, 0.11, 0.07)
const PAPER := Color(0.93, 0.88, 0.76)
const GOOD := Color(0.15, 0.45, 0.15)
const BAD := Color(0.6, 0.12, 0.08)

var state: GameState
var map: MapView
var status: RichTextLabel
var panel: VBoxContainer
var journal: RichTextLabel
var bg: ColorRect
var desk: MarginContainer
var view: BattleView
var orders := {"range": "close", "shot": "round", "board": true, "ram": false}
var pick_nation := "England"

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
		var font := ThemeDB.fallback_font
		if s != null and s.at_sea() and not s.voyage.is_empty() and not s.voyage.get("cruise", false):
			var a := World.port_by_id(s.voyage["from"])
			var b := World.port_by_id(s.voyage["to"])
			draw_dashed_line(project(a["lat"], a["lon"]), project(b["lat"], b["lon"]), Color(0.2, 0.15, 0.1, 0.7), 2.0, 8.0)
		for p in World.PORTS:
			var pos := project(p["lat"], p["lon"])
			var c: Color = World.COLOUR.get(p["nation"], Color.WHITE)
			var blocked: bool = s != null and p["id"] != s.location and Sim.port_open(s, p["id"]) != ""
			draw_circle(pos, 9.0, Color(0, 0, 0, 0.5))
			draw_circle(pos, 7.0, c.darkened(0.55) if blocked else c)
			if blocked:
				draw_line(pos + Vector2(-6, -6), pos + Vector2(6, 6), Color(0.1, 0.05, 0.0), 2.0)
			var label: String = p["name"].split(",")[0]
			if p["haven"]:
				label += " ☠"
			draw_string(font, pos + Vector2(11, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.16, 0.11, 0.07))
		if s == null:
			return
		var sp := Vector2.ZERO
		if s.at_sea() and not s.voyage.is_empty():
			var a2 := World.port_by_id(s.voyage["from"])
			var b2 := World.port_by_id(s.voyage["to"])
			var t: float = clamp(float(s.voyage["done_nm"]) / max(1.0, float(s.voyage["total_nm"])), 0.0, 1.0)
			sp = project(a2["lat"], a2["lon"]).lerp(project(b2["lat"], b2["lon"]), t)
			if s.voyage.get("cruise", false):
				var c2 := project(a2["lat"], a2["lon"])
				sp = c2 + Vector2(cos(t * TAU), sin(t * TAU)) * 60.0 * sin(t * PI) + Vector2(0, -16) * (1.0 - sin(t * PI))
		else:
			var here := World.port_by_id(s.location)
			sp = project(here["lat"], here["lon"]) + Vector2(0, -16)
		var pts := PackedVector2Array([sp + Vector2(0, -10), sp + Vector2(8, 6), sp + Vector2(-8, 6)])
		draw_colored_polygon(pts, Color.BLACK if s.role == "Pirate" else World.COLOUR.get(s.flag(), Color.WHITE))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.16, 0.11, 0.07), 1.5)

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
	bg = ColorRect.new()
	bg.color = PAPER
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	desk = MarginContainer.new()
	desk.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		desk.add_theme_constant_override("margin_" + side, 10)
	add_child(desk)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	desk.add_child(root)

	map = MapView.new()
	map.main = self
	map.custom_minimum_size = Vector2(0, 170)
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	journal.custom_minimum_size = Vector2(0, 110)
	journal.scroll_following = true
	journal.add_theme_color_override("default_color", INK)
	journal.add_theme_font_size_override("normal_font_size", 13)
	root.add_child(journal)

	get_viewport().size_changed.connect(_layout)
	_layout()
	refresh()

## On a phone held upright, the chart gets less of the screen.
func _layout() -> void:
	# A phone held upright gets a narrow logical canvas, so text stays a
	# readable size instead of a whole 1280-wide desk shrunk onto it.
	get_window().content_scale_size = Vector2i(520, 760)
	var sz := get_viewport_rect().size
	var portrait := sz.y > sz.x
	map.size_flags_stretch_ratio = 0.45 if portrait else 0.9
	journal.custom_minimum_size.y = 90 if portrait else 120

# ------------------------------------------------------------------ helpers

func _btn(parent: Control, text: String, cb: Callable, disabled := false, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _row(parent: Control) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 6)
	h.add_theme_constant_override("v_separation", 4)
	parent.add_child(h)
	return h

func _label(parent: Control, text: String, bold := false, colour := INK) -> Label:
	var l := Label.new()
	l.text = text
	if parent is HFlowContainer:
		l.custom_minimum_size = Vector2(290 if text.length() > 12 else 0, 0)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", colour)
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

func _role_line(s: GameState) -> String:
	match s.role:
		"Privateer":
			return "%s privateer, %s marque" % [World.ADJ[s.nation], World.ADJ.get(s.patron, "?")]
		"Navy":
			return "%s, %s navy" % [s.navy_rank, World.ADJ[s.nation]]
		"Pirate":
			return "Pirate (%s-born)" % World.ADJ[s.nation]
	return "%s trader" % World.ADJ[s.nation]

func _status() -> void:
	var s := state
	var where: String = World.port_by_id(s.location)["name"] if not s.at_sea() else \
		("Cruising" if s.voyage.get("cruise", false) else "At sea → %s" % World.port_by_id(s.voyage["to"])["name"]) + \
		" (%d of %d nm)" % [s.voyage["done_nm"], s.voyage["total_nm"]]
	var lines := []
	lines.append("[b]%s[/b], %s, aged %d — %s — %s" % [s.captain_name, _role_line(s), s.age, Sim.date_string(s), where])
	lines.append("%s [i]%s[/i]%s: hull %d/%d, rig %d%%, %d guns, hold %d/%d t" % [
		s.ship["name"], s.ship["label"], "" if s.owns_ship else " (the King's)", s.ship["hull"], s.ship["hull_max"], s.ship["rig"],
		s.ship["guns"], s.cargo_used(), s.ship["cargo"]])
	lines.append("Crew %d/%d · health %d · morale %d%s · food %d days · water %d days · powder %.1f t" % [
		s.crew, s.ship["crew_cap"], s.health, s.morale,
		(" · wages owed %d" % s.pay_owed) if s.pay_owed > 0.0 else "",
		Sim.days_of(s, "food"), Sim.days_of(s, "water"), float(s.stores.get("powder", 0.0))])
	var st := []
	for n in World.POWERS:
		st.append("%s %d" % [n, s.rep(n)])
	lines.append("Chest %d · purse %d%s · prizes %d · pirates taken %d · standing: %s" % [s.chest, s.purse,
		(" · bounty %d" % s.bounty) if s.bounty > 0.0 else "", s.prizes_taken, s.pirates_taken, ", ".join(st)])
	status.text = "\n".join(lines)

func _title_screen() -> void:
	_label(panel, "Pirates! meets the Mayflower meets the Oregon Trail. The eastern Caribbean, 1675: France is at war with the Dutch and Spain; England sits it out — for now.")
	var r := _row(panel)
	_label(r, "Your nationality")
	_option(r, World.POWERS, pick_nation, func(v): pick_nation = v)
	_label(panel, "Trader — a fat fluyt, a small crew on wages, honest ports. Fire on a ship of a nation at peace and you're a pirate.")
	_btn(panel, "Begin as a Trader", func(): _start("Trader"))
	var pat := Sim._default_patron(pick_nation, 0)
	_label(panel, "Privateer — a fast sloop, a crew on shares, and a letter of marque: prizes are lawful only against your patron's enemies. In 1675 that means a %s commission against %s." % [
		World.ADJ[pat], " and ".join(World.enemies_of(pat, 0))])
	_btn(panel, "Begin as a Privateer", func(): _start("Privateer"))
	_label(panel, "Navy — a lieutenant with a brigantine of the King's, pay, free stores at home, and orders to take enemies and pirates. Prize money is a captain's 3/8.")
	_btn(panel, "Begin in the Navy", func(): _start("Navy"))
	_label(panel, "Pirate — a sloop, a hungry crew and one sure harbour (St Thomas ☠). Brethren of your own nation leave you be; navies don't. Win a nation's favour by preying on its enemies and its ports may open to you.")
	_btn(panel, "Begin as a Pirate", func(): _start("Pirate"))
	_label(panel, "Still to come: colonists and the Atlantic crossing, fleets, and your own island as governor.")

func _start(role: String) -> void:
	state = Sim.new_game(role, pick_nation)
	refresh()

func _new_career() -> void:
	state = null
	refresh()

func _nations_panel() -> void:
	var s := state
	_label(panel, "Nations", true)
	for n in World.POWERS:
		var rel := World.relation(n, s.flag(), s.day) if s.flag() != "" else ""
		var tag := ""
		match rel:
			"self":
				tag = "your flag"
			"war":
				tag = "AT WAR with you"
			"ally":
				tag = "your ally"
			"peace":
				tag = "at peace with you"
		var enemies := World.enemies_of(n, s.day)
		var col := GOOD if s.rep(n) >= 25 else (BAD if s.rep(n) <= -25 else INK)
		_label(panel, "%s — %s (%d)%s · %s" % [n, World.standing(s.rep(n)), s.rep(n), (" · " + tag) if tag != "" else "",
			("at war with " + ", ".join(enemies)) if enemies.size() > 0 else "at peace"], false, col)

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
		var cost := Sim.store_price(s, st) * amt
		_btn(sr, "%s +%.1ft (%s)" % [World.STORES[st]["name"], amt, "free" if cost == 0.0 else str(int(cost))],
			func(): note(Sim.buy_store(s, st, amt)))

	_label(panel, "Ashore", true)
	var ar := _row(panel)
	_btn(ar, "Pressed men +5" if s.role == "Navy" else "Sign on 5 hands", func(): note(Sim.recruit(s, 5)))
	if s.role == "Trader":
		_btn(ar, "Pay wages", func(): note(Sim.pay_wages(s)), s.pay_owed <= 0.0)
	if s.role in ["Pirate", "Privateer"]:
		_btn(ar, "Share out the plunder", func(): note(Sim.share_out(s)))
	if s.role != "Pirate":
		_btn(ar, "Bank 500", func(): note(Sim.bank(s, 500.0)), s.chest < 1.0)
	_btn(ar, "Draw 500", func(): note(Sim.withdraw(s, 500.0)), s.purse < 1.0)
	_btn(ar, "Rest 3 days", func(): note(Sim.rest(s, 3)))
	var damaged: bool = float(s.ship["hull"]) < float(s.ship["hull_max"]) or float(s.ship["rig"]) < 100.0
	var rc := Sim.repair_cost(s)
	_btn(ar, "Repair (%s)" % ("free" if rc == 0.0 else str(int(rc))), func(): note(Sim.repair(s)), not damaged)
	_btn(ar, "Retire", func(): note(Sim.retire(s)["text"]))

	var office := Sim.office_options(s)
	if office.size() > 0:
		_label(panel, "The governor's office", true)
		for o in office:
			var b := _btn(panel, o["label"], func(): note(Sim.office(s, o["id"])), not o["ok"], o["why"])
			if not o["ok"]:
				_label(panel, "   " + o["why"])

	var yard := Sim.ship_offers(s)
	if yard.size() > 0:
		_label(panel, "Shipyard (your %s fetches %d in trade)" % [s.ship["name"].to_lower(), Sim.trade_in(s)], true)
		var yr := _row(panel)
		for o in yard:
			var c: Dictionary = World.SHIPS[o["cls"]]
			_btn(yr, "%s — %d guns, %d crew, %d t, %.1f kn: %d" % [c["name"], c["guns"], c["crew_cap"], c["cargo"], c["knots"], o["cost"]],
				func(): note(Sim.buy_ship(s, o["cls"])), not o["ok"], o["why"])

	_nations_panel()

	_label(panel, "Set sail", true)
	var cr := _row(panel)
	_btn(cr, "Cruise the sea lanes (20 days)", func(): note(Sim.cruise(s, 20)))
	_label(panel, "…or for a port (or tap one on the chart):")
	var dr := _row(panel)
	for p in World.PORTS:
		if p["id"] == s.location:
			continue
		var why := Sim.can_sail_to(s, p["id"])
		_btn(dr, "%s (~%.0f d)" % [p["name"].split(",")[0], Sim.est_days(s, p["id"])],
			func(): sail_to(p["id"]), why != "", why)

func sail_to(id: String) -> void:
	note(Sim.set_sail(state, id))

func _sea_screen() -> void:
	var s := state
	var r := _row(panel)
	_label(r, "Pace")
	_option(r, ["easy", "steady", "crowd"], s.pace, _set_pace)
	_label(r, "Rations")
	_option(r, ["full", "half", "short"], s.rations, _set_rations)
	var rum := _check("Rum ration", s.rum_ration)
	rum.toggled.connect(func(v): s.rum_ration = v)
	r.add_child(rum)
	var r2 := _row(panel)
	_btn(r2, "Sail one day", _sail_one)
	_btn(r2, "Sail until something happens", _sail_until)
	if s.voyage.get("cruise", false):
		_btn(r2, "Make for port", func(): note(Sim.head_home(s)))
	if s.role != "Pirate":
		_label(panel, "Desperate measures", true)
		_btn(panel, "Run up the black flag (turn pirate)", func(): note(Sim.turn_pirate(s)))
	_nations_panel()

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
	var n: String = e["nation"]
	var who := "Her crew are %s" % World.ADJ[n] if e["kind"] == "pirate" else "She flies the %s flag" % World.ADJ[n]
	var rel := World.relation(n, s.flag(), s.day) if s.flag() != "" else "—"
	var reltxt: String = {"war": "at war with your flag", "ally": "allied with your flag", "peace": "at peace with your flag",
		"self": "your own flag", "—": "you fly no flag"}[rel]
	_label(panel, "%s — %s. Your standing with %s: %s (%d)." % [who, reltxt, n, World.standing(s.rep(n)), s.rep(n)])
	var fx := Sim.attack_effects(s, e, "prize")
	_label(panel, "If you take her: " + Sim.effects_text(fx), false, GOOD if fx["legal"] and not fx["becomes_pirate"] else BAD)

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
	_label(panel, "Round shot smashes hulls, chain cuts rigging so she can't run, grape clears decks before boarding. Ramming hurts you too, but locks the hulls.")
	var a := _row(panel)
	_btn(a, "Sail on", func(): _act("sail_on"))
	_btn(a, "Flee", func(): _act("flee"))
	_btn(a, "Trade", func(): _act("trade"), e["hostile"] or e["kind"] != "merchant")
	_btn(a, "Attack!", func(): _act("attack"))
	_btn(a, "Strike colours", func(): _act("surrender"), not e["hostile"])
	_btn(a, "Attack (quick, no battle view)", func(): _act("attack", true))

func _act(action: String, quick := false) -> void:
	if action in ["trade", "surrender"]:
		Sim.resolve(state, action, orders)
		refresh()
		return
	var b := Sim.start_battle(state, action, orders)
	if b == null:
		Sim.resolve(state, action, orders)
		refresh()
		return
	if quick:
		b.run()
		_battle_done(b)
		return
	view = BattleView.new()
	add_child(view)
	view.setup(b)
	view.finished.connect(func(): _battle_done(b))
	bg.visible = false
	desk.visible = false

func _battle_done(b: Battle) -> void:
	if view != null:
		view.queue_free()
		view = null
	bg.visible = true
	desk.visible = true
	var res := Sim.finish_battle(state, b)
	refresh()

func _end_screen() -> void:
	_label(panel, state.end_reason, true)
	_label(panel, "Net worth at the end: %d" % Sim.net_worth(state))
	_btn(panel, "New career", _new_career)
