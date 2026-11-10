class_name BattleView
extends Node3D
## 3D view of a Battle. The battle sim owns the truth; this just draws it,
## plays it back at a chosen speed, and lets you change orders mid-fight.

signal finished

const SEA := Color(0.10, 0.33, 0.47)
const HULL := Color(0.36, 0.23, 0.13)
const SAIL := Color(0.93, 0.90, 0.80)
const INK := Color(0.16, 0.11, 0.07)

var battle: Battle
var speed := 8.0
var paused := false
var _accum := 0.0
var nodes: Array = []          # one Node3D per ship
var flags: Array = []
var labels: Array = []
var fx: Array = []             # {node, age, life, kind, from, to, vel}
var cam: Camera3D
var yaw := 0.7
var pitch := 0.45
var zoom := 1.0
var _target := Vector3.ZERO
var _dragging := false
var caps: MultiMeshInstance3D
var hud: CanvasLayer
var info: Label
var log_label: Label
var result_box: PanelContainer
var speed_buttons := {}
var order_buttons := {}
var pause_button: Button

# ------------------------------------------------------------------ setup

func setup(b: Battle) -> void:
	battle = b
	_build_world()
	for sh in battle.ships:
		_add_ship(sh)
	_build_hud()
	_target = _w(_mid())

func _w(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, -p.y)

func _mid() -> Vector2:
	return (battle.ships[0]["pos"] + battle.ships[1]["pos"]) * 0.5

func _mat(c: Color, rough := 0.8, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.35, 0.55, 0.85)
	sm.sky_horizon_color = Color(0.78, 0.85, 0.92)
	sm.ground_horizon_color = Color(0.5, 0.62, 0.7)
	sm.ground_bottom_color = SEA
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.fog_enabled = true
	e.fog_light_color = Color(0.75, 0.83, 0.9)
	e.fog_density = 0.00035
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.1
	add_child(sun)

	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40000, 40000)
	sea.mesh = pm
	sea.material_override = _mat(SEA, 0.25)
	add_child(sea)

	# Whitecaps: a field of small white flecks that gives the eye a sense of
	# motion over an otherwise flat sea. Re-centred as the fight drifts.
	caps = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(3.0, 0.8)
	q.orientation = PlaneMesh.FACE_Y
	mm.mesh = q
	mm.instance_count = 900
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in mm.instance_count:
		var t := Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)).scaled(Vector3.ONE * rng.randf_range(0.6, 1.6)),
			Vector3(rng.randf_range(-1500, 1500), 0.05, rng.randf_range(-1500, 1500)))
		mm.set_instance_transform(i, t)
	caps.multimesh = mm
	caps.material_override = _mat(Color(0.95, 0.97, 1.0, 0.55), 1.0, true)
	add_child(caps)

	cam = Camera3D.new()
	cam.far = 12000.0
	cam.fov = 55.0
	add_child(cam)
	cam.make_current()

func _add_ship(sh: Dictionary) -> void:
	var root := Node3D.new()
	var L: float = sh["length"]
	var beam := L * 0.27
	var hull_m := _mat(HULL)
	var sail_m := _mat(SAIL)
	sail_m.cull_mode = BaseMaterial3D.CULL_DISABLED

	var hull := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(beam, 2.4, L * 0.72)
	hull.mesh = hb
	hull.position = Vector3(0, 0.6, L * 0.08)
	hull.material_override = hull_m
	root.add_child(hull)
	var bow := MeshInstance3D.new()
	var pr := PrismMesh.new()
	pr.size = Vector3(beam, L * 0.3, 2.4)
	bow.mesh = pr
	bow.rotation_degrees = Vector3(-90, 0, 0)
	bow.position = Vector3(0, 0.6, L * 0.08 - L * 0.36 - L * 0.15)
	bow.material_override = hull_m
	root.add_child(bow)
	# A pale strake so you can read the hull at a distance.
	var strake := MeshInstance3D.new()
	var sb := BoxMesh.new()
	sb.size = Vector3(beam + 0.05, 0.35, L * 0.72)
	strake.mesh = sb
	strake.position = Vector3(0, 1.3, L * 0.08)
	strake.material_override = _mat(Color(0.75, 0.62, 0.35))
	root.add_child(strake)

	var masts: int = World.SHIPS[sh["ship"]["cls"]]["masts"]
	var h := L * 0.8
	var mast_m := _mat(Color(0.3, 0.2, 0.1))
	var first_top := Vector3.ZERO
	for i in masts:
		var z := lerpf(-L * 0.22, L * 0.25, float(i) / max(1, masts - 1)) if masts > 1 else -L * 0.05
		var mast := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.18
		cm.bottom_radius = 0.3
		cm.height = h * (1.0 if i == masts / 2 else 0.85)
		mast.mesh = cm
		mast.position = Vector3(0, 1.8 + cm.height / 2.0, z)
		mast.material_override = mast_m
		root.add_child(mast)
		if i == 0:
			first_top = Vector3(0, 1.8 + cm.height, z)
		if sh["rig_type"] == "fore_aft" and not (masts == 2 and i == 0):
			# Gaff mainsail fore-and-aft, abaft the mast.
			var s1 := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.12, cm.height * 0.62, L * 0.42)
			s1.mesh = bm
			s1.position = Vector3(0, 2.6 + cm.height * 0.33, z + L * 0.2)
			s1.material_override = sail_m
			root.add_child(s1)
		else:
			for k in 2:
				var s2 := MeshInstance3D.new()
				var bm2 := BoxMesh.new()
				bm2.size = Vector3(beam * (1.8 - 0.4 * k), cm.height * 0.27, 0.15)
				s2.mesh = bm2
				s2.position = Vector3(0, 2.8 + cm.height * (0.22 + 0.33 * k), z)
				s2.material_override = sail_m
				root.add_child(s2)
	# Jib
	var jib := MeshInstance3D.new()
	var jm := PrismMesh.new()
	jm.size = Vector3(L * 0.35, h * 0.55, 0.1)
	jm.left_to_right = 1.0
	jib.mesh = jm
	jib.rotation_degrees = Vector3(0, 90, 0)
	jib.position = Vector3(0, 2.2 + h * 0.28, -L * 0.42)
	jib.material_override = sail_m
	root.add_child(jib)

	var flag := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(3.2, 2.0)
	flag.mesh = fq
	var fc: Color = Color(0.05, 0.05, 0.05) if sh["pirate"] else World.COLOUR.get(sh["nation"], Color.WHITE)
	var fmat := _mat(fc, 1.0, true)
	fmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = fmat
	flag.position = first_top + Vector3(0, 1.0, 1.6)
	flag.rotation_degrees = Vector3(0, 90, 0)
	root.add_child(flag)

	var lab := Label3D.new()
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.font_size = 40
	lab.fixed_size = true          # same size on screen at any range
	lab.pixel_size = 0.0012
	lab.outline_size = 10
	lab.outline_modulate = Color(0.1, 0.07, 0.04)
	lab.modulate = Color.WHITE
	lab.no_depth_test = true
	lab.position = Vector3(0, h + 8.0, 0)
	root.add_child(lab)

	add_child(root)
	nodes.append(root)
	flags.append(flag)
	labels.append(lab)
	_place(root, sh, 1.0)

func _place(n: Node3D, sh: Dictionary, k: float) -> void:
	var p := _w(sh["pos"])
	var hd: float = sh["heading"]
	var fwd := Vector3(cos(hd), 0.0, -sin(hd))
	var target := Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(p.x, n.position.y, p.z))
	if Vector2(n.position.x, n.position.z).distance_to(Vector2(p.x, p.z)) > 60.0:
		k = 1.0   # skipped ahead: jump rather than slide across the sea
	n.transform = n.transform.interpolate_with(target, k)
	# Heel a little to leeward under sail.
	var off := wrapf(hd - battle.wind_from, -PI, PI)
	n.rotate_object_local(Vector3.FORWARD, clampf(-sign(off) * float(sh["speed"]) * 0.025, -0.12, 0.12))

# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.88, 0.76, 0.86)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	top.add_theme_stylebox_override("panel", sb)
	root.add_child(top)
	var tv := VBoxContainer.new()
	top.add_child(tv)
	info = Label.new()
	info.add_theme_color_override("font_color", INK)
	info.add_theme_font_size_override("font_size", 14)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(info)
	log_label = Label.new()
	log_label.add_theme_color_override("font_color", Color(0.3, 0.2, 0.1))
	log_label.add_theme_font_size_override("font_size", 12)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(log_label)

	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.add_theme_stylebox_override("panel", sb)
	root.add_child(bottom)
	var bv := VBoxContainer.new()
	bottom.add_child(bv)
	var r1 := HFlowContainer.new()
	bv.add_child(r1)
	pause_button = _btn(r1, "Pause", _toggle_pause)
	for sp in [1.0, 4.0, 16.0, 64.0]:
		speed_buttons[sp] = _btn(r1, "%dx" % sp, _set_speed.bind(sp))
	_btn(r1, "Skip to the end", _skip)
	var r2 := HFlowContainer.new()
	bv.add_child(r2)
	order_buttons["close"] = _btn(r2, "Close", func(): _order({"mode": "engage", "range": "close", "board": false}))
	order_buttons["long"] = _btn(r2, "Long range", func(): _order({"mode": "engage", "range": "long", "board": false}))
	order_buttons["board"] = _btn(r2, "Board!", func(): _order({"mode": "board", "board": true}))
	order_buttons["flee"] = _btn(r2, "Flee", func(): _order({"mode": "flee", "board": false}))
	for shot in ["round", "chain", "grape"]:
		order_buttons[shot] = _btn(r2, shot.capitalize(), func(): _order({"shot": shot}))
	_btn(r2, "Strike colours", func(): battle.player_strikes())
	_refresh_buttons()

func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = false
	b.pressed.connect(cb)
	b.custom_minimum_size = Vector2(44, 36)
	parent.add_child(b)
	return b

func _order(o: Dictionary) -> void:
	if battle.done() or battle.grappled:
		return
	battle.player()["orders"].merge(o, true)
	battle.player()["repelled"] = battle.player()["repelled"] and not o.get("board", false)
	battle.say("Orders: %s." % ", ".join(o.values().map(func(v): return str(v))))
	_refresh_buttons()

func _refresh_buttons() -> void:
	for sp in speed_buttons:
		speed_buttons[sp].modulate = Color(1, 1, 0.6) if sp == speed else Color.WHITE
	var o: Dictionary = battle.player()["orders"]
	var mode_key: String = o["mode"] if o["mode"] in ["board", "flee"] else String(o.get("range", "close"))
	for k in order_buttons:
		var on: bool = k == mode_key or k == o.get("shot", "")
		order_buttons[k].modulate = Color(1, 1, 0.6) if on else Color.WHITE

func _set_speed(sp: float) -> void:
	speed = sp
	_refresh_buttons()

func _toggle_pause() -> void:
	paused = not paused
	pause_button.text = "Play" if paused else "Pause"

func _skip() -> void:
	battle.run()

static func _compass(a: float) -> String:
	var deg := fposmod(90.0 - rad_to_deg(a), 360.0)
	var pts := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
	return pts[int(round(deg / 45.0)) % 8]

func _bar(v: float, mx: float) -> String:
	var n := int(round(clampf(v / mx, 0.0, 1.0) * 10.0))
	return "█".repeat(n) + "░".repeat(10 - n)

func _update_hud() -> void:
	var p := battle.player()
	var e := battle.enemy()
	var m := int(battle.t / 60.0)
	var d := battle.distance()
	var state := ""
	if battle.grappled:
		state = "  ⚔ BOARDING"
	elif d < 220.0:
		state = "  · pistol shot"
	info.text = "%d:%02d  ·  wind from %s  ·  range %d m (%.1f cables)%s%s\n" % [m / 60, m % 60, _compass(battle.wind_from),
		d, d / 185.0, state, "  · PAUSED" if paused else ""]
	info.text += "You  %s hull %d  rig %d%%  crew %d  morale %d  %.1f kn\n" % [_bar(p["ship"]["hull"], p["ship"]["hull_max"]),
		p["ship"]["hull"], p["ship"]["rig"], p["crew"], p["morale"], float(p["speed"]) / Battle.KNOT]
	info.text += "Her  %s hull %d  rig %d%%  crew %d  morale %d  %.1f kn  (%s)" % [_bar(e["ship"]["hull"], e["ship"]["hull_max"]),
		e["ship"]["hull"], e["ship"]["rig"], e["crew"], e["morale"], float(e["speed"]) / Battle.KNOT, e["label"]]
	log_label.text = "\n".join(battle.lines.slice(max(0, battle.lines.size() - 3)))
	for i in 2:
		var sh: Dictionary = battle.ships[i]
		labels[i].text = ("You" if i == 0 else String(sh["label"]).capitalize()) + (" ⚑" if sh["struck"] else "")

# ------------------------------------------------------------------ loop

func _process(delta: float) -> void:
	if battle == null:
		return
	if not paused and not battle.done():
		var sim_dt := delta * speed
		if battle.distance() > 900.0 and not battle.grappled and speed < 64.0:
			sim_dt *= 4.0   # nothing to see at long range: hurry the chase
		_accum += sim_dt
		var n := 0
		while _accum >= 1.0 and n < 600 and not battle.done():
			battle.step(1.0)
			_accum -= 1.0
			n += 1
	_consume_events()
	var k := 1.0 - exp(-8.0 * delta)
	for i in 2:
		var sh: Dictionary = battle.ships[i]
		_place(nodes[i], sh, k)
		flags[i].visible = not sh["struck"]
		if sh["sunk"]:
			nodes[i].position.y = maxf(-30.0, nodes[i].position.y - delta * 1.5)
			nodes[i].rotate_object_local(Vector3.RIGHT, delta * 0.08)
	_update_fx(delta)
	_update_camera(delta)
	_update_hud()
	if battle.done() and result_box == null:
		_show_result()

func _consume_events() -> void:
	for ev in battle.events:
		match ev["type"]:
			"broadside":
				_broadside_fx(ev)
			"ram":
				_splash(nodes[1 - int(ev["from"])].position + Vector3(0, 0, 0), 9.0)
			"melee":
				var mid: Vector3 = (nodes[0].position + nodes[1].position) * 0.5
				for j in 4:
					_puff(mid + Vector3(randf_range(-6, 6), 3.0, randf_range(-6, 6)), 1.0, 1.5, Color(0.95, 0.95, 0.9, 0.8))
	battle.events.clear()

func _side_vec(sh: Dictionary, side: int) -> Vector3:
	var a: float = float(sh["heading"]) + (PI / 2.0 if side == 0 else -PI / 2.0)
	return Vector3(cos(a), 0.0, -sin(a))

func _broadside_fx(ev: Dictionary) -> void:
	var sh: Dictionary = battle.ships[int(ev["from"])]
	var other: Dictionary = battle.ships[1 - int(ev["from"])]
	var n: Node3D = nodes[int(ev["from"])]
	var out := _side_vec(sh, int(ev["side"]))
	var fwd := Vector3(cos(sh["heading"]), 0.0, -sin(sh["heading"]))
	var L: float = sh["length"]
	var guns: int = ev["guns"]
	var hits: int = ev["hits"]
	var tgt := _w(other["pos"])
	for g in guns:
		var along := lerpf(-0.3, 0.3, float(g) / max(1, guns - 1)) * L
		var muzzle := Vector3(n.position.x, 1.6, n.position.z) + fwd * along + out * (L * 0.15)
		_puff(muzzle + out * 2.0, 1.6, 6.0 + randf() * 3.0, Color(0.88, 0.88, 0.86, 0.85))
		var hit := g < hits
		var land := tgt + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		if not hit:
			land += (tgt - muzzle).normalized() * randf_range(-40.0, 30.0) + Vector3(randf_range(-25, 25), 0, randf_range(-25, 25))
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.5
		sm.height = 1.0
		ball.mesh = sm
		ball.material_override = _mat(Color(0.05, 0.05, 0.05), 0.5, true)
		ball.position = muzzle
		add_child(ball)
		fx.append({"node": ball, "age": 0.0, "life": clampf(float(ev["dist"]) / 450.0, 0.25, 1.4), "kind": "ball",
			"from": muzzle, "to": land + Vector3(0, 1.5 if hit else 0.0, 0), "hit": hit})

func _puff(at: Vector3, r0: float, r1: float, c: Color) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 8
	sm.rings = 4
	m.mesh = sm
	m.material_override = _mat(c, 1.0, true)
	m.position = at
	m.scale = Vector3.ONE * r0
	add_child(m)
	fx.append({"node": m, "age": 0.0, "life": 4.0, "kind": "puff", "r0": r0, "r1": r1, "c": c})

func _splash(at: Vector3, h: float) -> void:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.6
	cm.bottom_radius = 1.4
	cm.height = 1.0
	m.mesh = cm
	var c := Color(0.95, 0.98, 1.0, 0.85)
	m.material_override = _mat(c, 1.0, true)
	m.position = Vector3(at.x, 0, at.z)
	add_child(m)
	fx.append({"node": m, "age": 0.0, "life": 1.2, "kind": "splash", "h": h, "c": c})

func _update_fx(delta: float) -> void:
	var keep := []
	for f in fx:
		f["age"] = float(f["age"]) + delta
		var t: float = float(f["age"]) / float(f["life"])
		var n: MeshInstance3D = f["node"]
		if t >= 1.0:
			if f["kind"] == "ball":
				if f["hit"]:
					_puff(f["to"], 0.8, 3.0, Color(0.55, 0.38, 0.2, 0.9))
				else:
					_splash(f["to"], randf_range(4.0, 8.0))
			n.queue_free()
			continue
		match f["kind"]:
			"ball":
				var p: Vector3 = (f["from"] as Vector3).lerp(f["to"], t)
				p.y += sin(t * PI) * 6.0
				n.position = p
			"puff":
				n.scale = Vector3.ONE * lerpf(f["r0"], f["r1"], 1.0 - pow(1.0 - t, 2.0))
				n.position.y += delta * 1.2
				var c: Color = f["c"]
				(n.material_override as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, c.a * (1.0 - t))
			"splash":
				var hh: float = f["h"] * sin(t * PI)
				n.scale = Vector3(1.0 + t, max(0.01, hh), 1.0 + t)
				n.position.y = hh / 2.0
				var c2: Color = f["c"]
				(n.material_override as StandardMaterial3D).albedo_color = Color(c2.r, c2.g, c2.b, c2.a * (1.0 - t))
		keep.append(f)
	fx = keep

# ------------------------------------------------------------------ camera

func _update_camera(delta: float) -> void:
	var mid := _w(_mid())
	_target = mid if _target.distance_to(mid) > 150.0 else _target.lerp(mid, 1.0 - exp(-3.0 * delta))
	var d := battle.distance()
	var dist := clampf(d * 0.75 + 70.0, 70.0, 1400.0) * zoom
	var off := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
	var vp := get_viewport().get_visible_rect().size
	cam.keep_aspect = Camera3D.KEEP_WIDTH if vp.y > vp.x else Camera3D.KEEP_HEIGHT
	cam.position = _target + off
	cam.look_at(_target + Vector3(0, 4, 0), Vector3.UP)
	# Keep the whitecaps under the camera, snapped so they don't swim.
	caps.position = Vector3(snappedf(_target.x, 200.0), 0.0, snappedf(_target.z, 200.0))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			zoom = clampf(zoom * 0.9, 0.25, 3.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			zoom = clampf(zoom * 1.1, 0.25, 3.0)
	elif event is InputEventMouseMotion and _dragging:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.004, 0.08, 1.35)
	elif event is InputEventScreenDrag:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.004, 0.08, 1.35)
	elif event is InputEventMagnifyGesture:
		zoom = clampf(zoom / event.factor, 0.25, 3.0)

# ------------------------------------------------------------------ result

func _show_result() -> void:
	var titles := {"prize": "Prize taken!", "sunk_them": "She goes down!", "escaped": "She got away.",
		"we_escaped": "Clean away!", "stalemate": "Night falls.", "we_struck": "You strike your colours.",
		"boarded_lost": "Your deck is carried.", "we_sank": "Your ship is sinking!"}
	result_box = PanelContainer.new()
	result_box.set_anchors_preset(Control.PRESET_CENTER)
	result_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_box.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.88, 0.76, 0.95)
	sb.set_content_margin_all(16)
	sb.set_corner_radius_all(6)
	result_box.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	result_box.add_child(v)
	var t := Label.new()
	t.text = titles.get(battle.outcome, battle.outcome)
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", INK)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var p := battle.player()
	var e := battle.enemy()
	var st := Label.new()
	st.text = "%d:%02d of fighting. Your guns: %d of %d hit, %d killed. Hers: %d of %d hit, %d killed." % [
		int(battle.t / 3600.0), int(battle.t / 60.0) % 60, p["hits_made"], p["shots_fired"], p["killed"],
		e["hits_made"], e["shots_fired"], e["killed"]]
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st.custom_minimum_size = Vector2(300, 0)
	st.add_theme_color_override("font_color", INK)
	v.add_child(st)
	var b := Button.new()
	b.text = "Continue"
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(func(): finished.emit())
	v.add_child(b)
	hud.add_child(result_box)
