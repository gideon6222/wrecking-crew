extends Node3D

## The shell. Reads `Sim` and draws it; never decides anything.
##
## Everything visible is built here in code rather than laid out in the editor:
## a procedural game's world is built at runtime anyway, so an editor layout
## would be a second source of truth, and building it here keeps the whole
## project reviewable as text.
##
## AXES. The simulation works in a 2D plane - `x` across the deck and `y` INTO
## it. The world maps that to (x, height, -y), so depth runs along -Z and the
## camera sits behind the machine looking along its own forward. The chase
## camera turns with the machine, which is fine here in a way it was not in the
## runner versions of this game: both controls are relative to the MACHINE
## rather than to the world, so there is no axis for a mirrored camera to
## invert. `run_smoke.gd` still asserts the camera is behind and facing in.

const COLUMN_POOL := 24
const WALL_POOL := 24
const DEBRIS_POOL := 240
const SLAB_POOL := 48
const SAVE_PATH := "user://wrecking-crew.save"

var sim: Sim

var _cam: Camera3D
var _rig: Node3D
var _boom: MeshInstance3D
var _chain: MeshInstance3D
var _ball: MeshInstance3D
var _columns: MultiMeshInstance3D
var _walls: MultiMeshInstance3D
var _debris: MultiMeshInstance3D
var _slab: MultiMeshInstance3D
var _dust: GPUParticles3D

var _ui: Control
var _stick: Control
var _slew: Control
var _readout: Label
var _hud: Label
var _banner: Label
var _gauge_back: ColorRect
var _gauge_fill: ColorRect

var _stick_grab := -1
var _stick_vec := Vector2.ZERO
var _slew_grab := -1

var _shake := 0.0
var _hitstop := 0.0
var _cam_yaw := 0.0

const INTERLUDE_SECONDS := 3.0
var _interlude := 0.0
var _interlude_won := false
var _interlude_text := ""

## Cosmetic only. Nothing in `Sim` can see a chunk and no decision depends on
## one - which is what allows them to exist at all. A debris chunk that could
## nudge a score would put the outcome of a demolition inside a particle system.
var _chunks: Array[Dictionary] = []
var _slabs: Array[Dictionary] = []
var _fx_rng := SimRng.new(20260908)

var best_rubble := 0
var best_site := 1

var frozen := false
var _booted := false


func _ready() -> void:
	_ensure_booted()


## `_ready` does not run at `add_child()` - it is deferred to the first
## processed frame - so a headless harness that adds this node and immediately
## calls `advance()` finds `sim` still null. A guard rather than a rule about
## call order, because a rule about call order is something every future test
## has to remember.
func _ensure_booted() -> void:
	if _booted:
		return
	_booted = true
	sim = Sim.new()
	_load_save()
	_build_world()
	sim.target_hit.connect(_on_target_hit)
	sim.target_broken.connect(_on_target_broken)
	sim.collapse_started.connect(_on_collapse_started)
	sim.escaped.connect(_on_escaped)
	sim.crushed.connect(_on_crushed)
	sim.level_finished.connect(_on_level_finished)
	_sync()


## Sim depth counts up; the world's counts down. One function, called
## everywhere, so the two can never be mixed by accident.
static func wz(sim_y: float) -> float:
	return -sim_y


static func to_world(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, wz(p.y))


# --- world ----------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()

	# A real captured environment, and it is doing three jobs at once rather
	# than being decoration. It lights the room, because a basement lit only by
	# a directional light is a flat grey box. It gives the wrecking ball
	# something to reflect - a metal has no diffuse term of its own, so with
	# nothing to reflect it renders as specular hotspots on black, and the
	# instinct to fix that by lowering metalness is the wrong one. And it is
	# what you see through the ramp, which is the only daylight in the level
	# and therefore the thing the player drives toward.
	var pano: Texture2D = load("res://assets/abandoned_parking_1k.hdr")
	if pano != null:
		var sky_mat := PanoramaSkyMaterial.new()
		sky_mat.panorama = pano
		var sky := Sky.new()
		sky.sky_material = sky_mat
		e.background_mode = Environment.BG_SKY
		e.sky = sky
		e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		e.ambient_light_energy = 0.30
		e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.10, 0.11, 0.13)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.35, 0.37, 0.42)
		e.ambient_light_energy = 0.5

	# Dust hanging in the air. Thin, because the room is small and the point is
	# depth rather than obscurity.
	e.fog_enabled = true
	e.fog_light_color = Color(0.42, 0.44, 0.48)
	e.fog_density = 0.010
	e.fog_sky_affect = 0.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.4
	env.environment = e
	add_child(env)

	# Daylight coming IN through the ramp. Angled down the room so it rakes
	# across the columns, which is what gives a flat concrete box any shape.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-24, 8, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 68
	_cam.far = 160
	add_child(_cam)

	_build_shell()
	_build_lights()
	_build_rig()

	# Columns and panels are instanced, so the draw count does not move with
	# how much of the room is still standing - and `visible_instance_count` is
	# a number the smoke test can compare against the model. A render path that
	# silently stops drawing and a subsystem that does not exist look identical
	# from outside.
	var col_mesh := CylinderMesh.new()
	col_mesh.top_radius = Tuning.COLUMN_RADIUS
	col_mesh.bottom_radius = Tuning.COLUMN_RADIUS
	col_mesh.height = Tuning.CEILING
	col_mesh.radial_segments = 12
	_columns = _make_multimesh(col_mesh, COLUMN_POOL, true)
	_columns.material_override = _concrete(Color.WHITE, 2.0)
	_columns.material_override.vertex_color_use_as_albedo = true
	_columns.name = "Columns"

	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(1.0, Tuning.CEILING * 0.86, Tuning.WALL_THICK * 2.0)
	_walls = _make_multimesh(wall_mesh, WALL_POOL, true)
	_walls.material_override = _concrete(Color.WHITE, 3.0)
	_walls.material_override.vertex_color_use_as_albedo = true
	_walls.name = "Walls"

	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.5, 0.5, 0.5)
	_debris = _make_multimesh(chunk, DEBRIS_POOL, true)
	_debris.material_override = _concrete(Color.WHITE, 1.0)
	_debris.material_override.vertex_color_use_as_albedo = true
	_debris.name = "Debris"

	# Slab sections, for the collapse. They are drawn out of the same layer the
	# ceiling is, so a piece coming down is the ceiling coming down.
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(Tuning.BAY * 0.9, 0.5, Tuning.BAY * 0.9)
	_slab = _make_multimesh(slab_mesh, SLAB_POOL, true)
	_slab.material_override = _concrete(Color.WHITE, 2.5)
	_slab.material_override.vertex_color_use_as_albedo = true
	_slab.name = "Slab"

	_build_dust()
	_build_hud()


## Concrete, with a real normal map on it.
##
## The one import that has paid off twice across these games: a normal map
## carries no colour, so the hand-tuned palette survives intact and every
## surface gains relief. Take the normal out of a CC0 PBR set and leave the
## colour map behind - that half is style-neutral, and the other half is the
## join that shows in the first frame.
##
## `uv1_scale` matters more than it looks. The maps are one square metre of
## concrete; tiled per-object they would restart at every column and the room
## would read as a stack of identical props.
func _concrete(c: Color, tile: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.92
	m.metallic = 0.0
	m.uv1_scale = Vector3(tile, tile, tile)
	var n: Texture2D = load("res://assets/concrete_normal.webp")
	if n != null:
		m.normal_enabled = true
		m.normal_texture = n
		# Far higher than looks reasonable on a still. Spreading one tile over
		# several metres leaves only the low-frequency component, so the value
		# that looks wrong is the correct one - and it has to be judged under a
		# moving light, not on a flat-lit screenshot.
		m.normal_scale = 1.1
	var r: Texture2D = load("res://assets/concrete_rough.webp")
	if r != null:
		# Roughness is DATA, not colour, so it must not be sRGB-decoded. Godot
		# handles that through the texture channel, but the mistake is the same
		# family as the one that makes a canvas env map four times too bright.
		m.roughness_texture = r
	return m


## The room: floor, ceiling slab, and the perimeter with a gap at the ramp.
func _build_shell() -> void:
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(Tuning.DECK_W + 6.0, 0.6, Tuning.DECK_D + Tuning.RAMP_DEPTH * 2.0 + 6.0)
	var deck := MeshInstance3D.new()
	deck.mesh = floor_mesh
	deck.material_override = _concrete(Color(0.30, 0.30, 0.31), 12.0)
	deck.position = Vector3(0, -0.3, wz(-Tuning.RAMP_DEPTH * 0.5))
	deck.name = "Deck"
	add_child(deck)

	# The slab overhead is DOWNSTAND BEAMS rather than a solid lid, and that is
	# a camera decision as much as an art one.
	#
	# A 4.6-metre ceiling leaves nowhere for a camera to go: at 15 metres back
	# it is through the wall, and pulled inside it sits on top of the machine.
	# Every framing tried under a solid roof was either inside the concrete or
	# two metres from the cab. Looking down THROUGH the structure solves it
	# outright - and a grid of beams is what the underside of a parking deck
	# actually looks like, so the room still reads as a room from above.
	var beam_mat := _concrete(Color(0.26, 0.26, 0.27), 4.0)
	var roof := Node3D.new()
	roof.name = "Roof"
	add_child(roof)
	for row in Tuning.GRID_Z:
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(Tuning.DECK_W, 0.6, 0.9)
		b.mesh = bm
		b.material_override = beam_mat
		b.position = Vector3(0, Tuning.CEILING - 0.3, wz(Tuning.column_z(row)))
		roof.add_child(b)
	# One direction only. Beams both ways made a grid the camera had to look
	# through from above, and half the floor was behind concrete at any moment -
	# a ceiling the player cannot see past is a ceiling that has taken the level
	# away from them.

	# Perimeter. The back wall is in two pieces with the ramp mouth between
	# them, which is the only opening in the room and therefore the only light.
	var hw := Tuning.DECK_W * 0.5
	var hd := Tuning.DECK_D * 0.5
	_wall_slab(Vector3(-hw - 0.4, Tuning.CEILING * 0.5, 0), Vector3(0.8, Tuning.CEILING, Tuning.DECK_D))
	_wall_slab(Vector3(hw + 0.4, Tuning.CEILING * 0.5, 0), Vector3(0.8, Tuning.CEILING, Tuning.DECK_D))
	_wall_slab(Vector3(0, Tuning.CEILING * 0.5, wz(hd) - 0.4), Vector3(Tuning.DECK_W, Tuning.CEILING, 0.8))
	var side := (Tuning.DECK_W - Tuning.RAMP_W) * 0.5
	for s in [-1.0, 1.0]:
		_wall_slab(Vector3(s * (Tuning.RAMP_W + side) * 0.5, Tuning.CEILING * 0.5, wz(-hd) + 0.4),
			Vector3(side, Tuning.CEILING, 0.8))


func _wall_slab(at: Vector3, size: Vector3) -> void:
	var m := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	m.mesh = mesh
	m.material_override = _concrete(Color(0.27, 0.27, 0.28), 6.0)
	m.position = at
	add_child(m)


## Strip lights on the ceiling. No shadows on any of them: a handful of
## shadow-casting omnis is the fastest way to lose a phone's frame budget, and
## the shape in the room comes from the raking daylight and the normal maps.
func _build_lights() -> void:
	for row in Tuning.GRID_Z:
		for col in Tuning.GRID_X:
			if (row + col) % 2 == 1:
				continue
			var l := OmniLight3D.new()
			l.position = Vector3(Tuning.column_x(col), Tuning.CEILING - 0.5, wz(Tuning.column_z(row)))
			l.light_energy = 1.9
			l.light_color = Color(1.0, 0.92, 0.78)
			l.omni_range = Tuning.BAY * 1.5
			l.shadow_enabled = false
			add_child(l)


func _build_dust() -> void:
	_dust = GPUParticles3D.new()
	_dust.amount = 90
	_dust.lifetime = 7.0
	_dust.visibility_aabb = AABB(
		Vector3(-Tuning.DECK_W * 0.5, 0, -Tuning.DECK_D * 0.5),
		Vector3(Tuning.DECK_W, Tuning.CEILING, Tuning.DECK_D))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(Tuning.DECK_W * 0.5, Tuning.CEILING * 0.5, Tuning.DECK_D * 0.5)
	pm.gravity = Vector3(0, -0.05, 0)
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.scale_min = 0.02
	pm.scale_max = 0.06
	pm.color = Color(0.85, 0.82, 0.74, 0.30)
	_dust.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.5, 0.5)
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dm.vertex_color_use_as_albedo = true
	dm.albedo_color = Color(0.8, 0.78, 0.7, 0.25)
	qm.material = dm
	_dust.draw_pass_1 = qm
	_dust.position = Vector3(0, Tuning.CEILING * 0.5, 0)
	_dust.name = "Dust"
	add_child(_dust)


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)

	var tracks := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(2.7, 0.8, 4.2)
	tracks.mesh = tm
	tracks.material_override = _mat(Color(0.11, 0.11, 0.12), 0.85, 0.2)
	tracks.position.y = 0.4
	_rig.add_child(tracks)

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 1.3, 3.1)
	body.mesh = bm
	# Plant yellow, dulled and dusted. A saturated one reads as a toy, and the
	# whole art direction is a machine that has been working all week.
	body.material_override = _mat(Color(0.55, 0.42, 0.10), 0.72, 0.25)
	body.position = Vector3(0, 1.4, -0.3)
	_rig.add_child(body)

	var cab := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.4, 1.2, 1.4)
	cab.mesh = cm
	cab.material_override = _mat(Color(0.14, 0.15, 0.17), 0.35, 0.1)
	cab.position = Vector3(-0.35, 2.6, -0.7)
	_rig.add_child(cab)

	_boom = MeshInstance3D.new()
	var boom_mesh := BoxMesh.new()
	boom_mesh.size = Vector3(0.4, 0.4, 1.0)
	_boom.mesh = boom_mesh
	_boom.material_override = _mat(Color(0.52, 0.40, 0.10), 0.75, 0.25)
	add_child(_boom)

	_chain = MeshInstance3D.new()
	var chain_mesh := BoxMesh.new()
	chain_mesh.size = Vector3(0.12, 0.12, 1.0)
	_chain.mesh = chain_mesh
	_chain.material_override = _mat(Color(0.22, 0.21, 0.20), 0.5, 0.8)
	add_child(_chain)

	_ball = MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = Tuning.BALL_RADIUS
	ball_mesh.height = Tuning.BALL_RADIUS * 2.0
	ball_mesh.radial_segments = 24
	ball_mesh.rings = 14
	_ball.mesh = ball_mesh
	_ball.material_override = _mat(Color(0.16, 0.15, 0.15), 0.32, 0.9)
	_ball.name = "Ball"
	add_child(_ball)


func _mat(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _make_multimesh(mesh: Mesh, pool: int, colours: bool) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colours
	mm.mesh = mesh
	mm.instance_count = pool
	mm.visible_instance_count = 0
	mmi.multimesh = mm
	add_child(mmi)
	return mmi


# --- HUD ------------------------------------------------------------------

## THE LAYOUT RULE, learned by shipping it wrong.
##
## `window/stretch/aspect = "expand"` keeps the base WIDTH and extends the
## HEIGHT to the device's aspect. The base is 1080x1920; the phone is about
## 19.5:9, so the canvas is roughly 1080x2340. Laying anything out against the
## number 1920 puts it hundreds of pixels off, and the report was "the icons
## are about half an inch too high".
##
## So: NOTHING is positioned against a literal screen size. One Control fills
## the viewport, everything anchors to it, and every interactive control
## handles its OWN input - position and hit box are then the same object.
## How far back and how high the camera sits. Both are bounded by the room:
## the ceiling is 4.6 metres, so there is no "pull back and up" available and
## the distance has to do all the work.
## Above the beams, looking down into the deck. The height is what makes the
## whole room legible at once - which is what the player needs, because the
## thing being judged is the ARC the ball sweeps and which columns it will pass
## through.
const CAM_BACK := 11.0
const CAM_HEIGHT := 23.0

const PAD := 210.0
const PAD_MARGIN := 60.0
const PAD_BOTTOM := 200.0

## The boom control is a horizontal SLIDER, not a dial.
##
## It was a dial for two builds, and Gideon's note retired it: "the controls
## don't need to be a dial look. since we are only controlling the turning, it
## could just be a left and right joystick or slider." He is right, and the
## reason is that a dial offers two dimensions to a control that has one - so
## the thumb has to be placed precisely on a circle to say a thing a line could
## have said, and the vertical half of every drag is thrown away.
##
## Wide, because width IS precision here: the whole slew range is mapped across
## it, so more pixels per radian is a steadier boom.
const SLEW_W := 470.0
const SLEW_H := 150.0


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Hud"
	add_child(layer)

	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.name = "Ui"
	layer.add_child(_ui)

	_readout = Label.new()
	_readout.position = Vector2(46, 52)
	_readout.add_theme_font_size_override("font_size", 60)
	_readout.add_theme_color_override("font_color", Color(1, 0.96, 0.88))
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_readout.add_theme_constant_override("outline_size", 12)
	_ui.add_child(_readout)

	# The support gauge. It empties as the room is taken apart, and it is the
	# only thing telling the player how close the slab is to letting go - so it
	# is a direct reading of `integrity` rather than a scaled one, and it
	# changes colour at the threshold the simulation actually uses.
	_gauge_back = ColorRect.new()
	_gauge_back.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_gauge_back.anchor_left = 0.5
	_gauge_back.anchor_right = 0.5
	_gauge_back.offset_left = -290
	_gauge_back.offset_right = 290
	_gauge_back.offset_top = 132
	_gauge_back.offset_bottom = 158
	_gauge_back.color = Color(0, 0, 0, 0.5)
	_ui.add_child(_gauge_back)

	_gauge_fill = ColorRect.new()
	_gauge_fill.position = Vector2(3, 3)
	_gauge_fill.color = Color(0.45, 0.85, 0.45)
	_gauge_back.add_child(_gauge_fill)

	_hud = Label.new()
	_hud.position = Vector2(46, 168)
	_hud.add_theme_font_size_override("font_size", 32)
	_hud.add_theme_color_override("font_color", Color(0.94, 0.92, 0.88))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("outline_size", 9)
	_ui.add_child(_hud)

	_banner = Label.new()
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.34
	_banner.anchor_bottom = 0.34
	_banner.offset_bottom = 130
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 76)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 16)
	_banner.visible = false
	_ui.add_child(_banner)

	# Left thumb drives, right thumb slews. Two controls, because there are two
	# things to do at once and one of them - keeping the ball moving - never
	# stops mattering.
	_stick = _make_pad("Stick", true)
	_ui.add_child(_stick)

	_slew = Control.new()
	_slew.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_slew.custom_minimum_size = Vector2(SLEW_W, SLEW_H)
	_slew.size = Vector2(SLEW_W, SLEW_H)
	_slew.offset_left = -PAD_MARGIN - SLEW_W
	_slew.offset_right = -PAD_MARGIN
	_slew.offset_top = -PAD_BOTTOM - SLEW_H * 0.5 - PAD * 0.25
	_slew.offset_bottom = -PAD_BOTTOM + SLEW_H * 0.5 - PAD * 0.25
	_slew.mouse_filter = Control.MOUSE_FILTER_STOP
	_slew.name = "Slew"
	_slew.gui_input.connect(_on_slew_input)
	_slew.draw.connect(_draw_slew)
	_ui.add_child(_slew)


func _make_pad(name: String, left: bool) -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_BOTTOM_LEFT if left else Control.PRESET_BOTTOM_RIGHT)
	c.custom_minimum_size = Vector2(PAD, PAD)
	c.size = Vector2(PAD, PAD)
	if left:
		c.offset_left = PAD_MARGIN
		c.offset_right = PAD_MARGIN + PAD
	else:
		c.offset_left = -PAD_MARGIN - PAD
		c.offset_right = -PAD_MARGIN
	c.offset_top = -PAD_BOTTOM - PAD
	c.offset_bottom = -PAD_BOTTOM
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.name = name
	c.gui_input.connect(_on_stick_input)
	c.draw.connect(_draw_stick)
	return c


## The drive stick. Drawn as a ring with a knob, because a control the player
## cannot see is one they have to be told about, and there is nobody here to
## tell them.
func _draw_stick() -> void:
	var r := PAD * 0.5
	var c := Vector2(r, r)
	var lit: float = 0.6 if _stick_grab >= 0 else 0.3
	_stick.draw_circle(c, r, Color(0.05, 0.05, 0.06, 0.32))
	_stick.draw_arc(c, r - 4.0, 0.0, TAU, 48, Color(1.0, 0.86, 0.42, lit), 4.0)
	_stick.draw_circle(c + _stick_vec * (r * 0.55), r * 0.28, Color(0.95, 0.85, 0.55, 0.85))


## The slew slider. A track, a centre mark, and a knob that sits where the boom
## actually points - so the control shows STATE and not just input, and a
## glance at it says where the boom is without looking away from the room.
##
## The ball is drawn on it too, as a small mark at its own bearing. The gap
## between the knob and that mark is the lag, which is the whole feel of the
## game, and this is the one place it can be read without tracking two things
## in the 3D view at once.
func _draw_slew() -> void:
	var mid := SLEW_H * 0.5
	var track := Rect2(14, mid - 9, SLEW_W - 28, 18)
	_slew.draw_rect(track, Color(0.05, 0.05, 0.06, 0.42), true)
	var lit: float = 0.65 if _slew_grab >= 0 else 0.32
	_slew.draw_rect(track, Color(1.0, 0.86, 0.42, lit), false, 3.0)

	# Straight ahead, marked, so the player can find centre without hunting.
	_slew.draw_line(Vector2(SLEW_W * 0.5, mid - 22), Vector2(SLEW_W * 0.5, mid + 22),
		Color(1, 1, 1, 0.45), 3.0)

	var span := (SLEW_W - 28.0) * 0.5
	var knob := Vector2(SLEW_W * 0.5 + (sim.turret / Tuning.TURRET_MAX) * span, mid)
	_slew.draw_circle(knob, 30.0, Color(0.86, 0.68, 0.20, 0.9))
	_slew.draw_circle(knob, 22.0, Color(0.16, 0.15, 0.14, 0.9))

	# And the ball, at the bearing it is really at, in the machine's own frame.
	var rel := (sim.ball - sim.pos).rotated(sim.heading)
	var bearing: float = atan2(rel.x, rel.y)
	var at := Vector2(SLEW_W * 0.5 + clampf(bearing / Tuning.TURRET_MAX, -1.0, 1.0) * span, mid)
	_slew.draw_circle(at, 11.0, Color(0.92, 0.86, 0.72, 0.95))


func _on_slew_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_slew_grab = event.index if event is InputEventScreenTouch else 0
			_read_slew(event.position)
		else:
			_slew_grab = -1
		_slew.accept_event()
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		if _slew_grab >= 0:
			_read_slew(event.position)
			_slew.accept_event()


## Absolute: where the thumb is along the track IS where the boom is asked to
## point. On a one-dimensional control that is unambiguous, and it means the
## boom can be put back to centre by putting the thumb on the centre mark.
func _read_slew(local: Vector2) -> void:
	var span := (SLEW_W - 28.0) * 0.5
	var t: float = clampf((local.x - SLEW_W * 0.5) / span, -1.0, 1.0)
	sim.aim_to(t * Tuning.TURRET_MAX)


func _on_stick_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_stick_grab = event.index if event is InputEventScreenTouch else 0
			_read_stick(event.position)
		else:
			_stick_grab = -1
			_stick_vec = Vector2.ZERO
			sim.drive_dir(Vector2.ZERO, 0.0)
		_stick.accept_event()
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		if _stick_grab >= 0:
			_read_stick(event.position)
			_stick.accept_event()


## The stick says WHERE ON SCREEN to go, not what to do with the tracks.
##
## It set a throttle and a steer for one build, and Gideon's report was that
## "the driving controls almost feel backward". They were, half the time: the
## camera holds a fixed orientation, so whenever the machine happened to be
## facing back toward it, forward on the stick drove the machine DOWN the
## screen and right on the stick turned it left. Vehicle-relative controls
## under a fixed camera are tank controls.
##
## Push the stick where you want the machine to go. The screen's up is the
## room's far end, so the stick's direction maps straight onto the world with
## no dependence on which way the machine happens to be pointing.
func _read_stick(local: Vector2) -> void:
	var r := PAD * 0.5
	_stick_vec = ((local - Vector2(r, r)) / (r * 0.78)).limit_length(1.0)
	var power := _stick_vec.length()
	if power < Tuning.STICK_DEADZONE:
		sim.drive_dir(Vector2.ZERO, 0.0)
		return
	# Screen up is -y on the stick and +y in the simulation, which is into the
	# room. One negation, in one place, next to the sentence explaining it.
	sim.drive_dir(Vector2(_stick_vec.x, -_stick_vec.y), power)


# --- loop -----------------------------------------------------------------

func _process(delta: float) -> void:
	if frozen:
		return
	_tick(delta)


func _tick(dt: float) -> void:
	# Hit stop. Freezing for a few dozen milliseconds on an impact makes the
	# same animation read as a different game, and it is the highest value per
	# line of code in the whole toolbox.
	if _hitstop > 0.0:
		_hitstop -= dt
	else:
		sim.advance(dt)
	_advance_interlude(dt)
	_advance_fx(dt)
	_sync()


## The headless seam. Freeze first, or every recorded number is a function of
## how fast the machine boots.
func advance(seconds: float, step: float = 1.0 / 60.0) -> void:
	_ensure_booted()
	var n := maxi(1, int(round(seconds / step)))
	for i in n:
		_tick(step)


func freeze(start_level: int = 1) -> void:
	_ensure_booted()
	frozen = true
	sim.restart(start_level)
	_chunks.clear()
	_slabs.clear()
	_shake = 0.0
	_hitstop = 0.0
	_interlude = 0.0
	_cam_yaw = sim.heading
	_sync()


# --- feedback -------------------------------------------------------------

## Three channels on every impact - something you see, something that moves the
## frame, and a freeze. Any one alone reads as cheap. All of them are scaled to
## the ball's SPEED, so a hard hit and a glancing one are told apart before the
## damage number is.
func _on_target_hit(kind: int, index: int, speed: float, at: Vector2) -> void:
	var force: float = clampf(speed / Tuning.HIT_FULL_SPEED, 0.1, 1.4)
	_burst(at, 1.4, int(6.0 + 16.0 * force), force)
	_shake = maxf(_shake, 0.12 + 0.45 * force)
	_hitstop = maxf(_hitstop, 0.02 + 0.05 * force)


func _on_target_broken(kind: int, index: int, at: Vector2) -> void:
	var n := 30 if kind == Sim.COLUMN else 18
	for h in 4:
		_burst(at, 0.8 + float(h) * 1.1, n / 4, 1.2)
	_shake = maxf(_shake, 0.9)
	_hitstop = maxf(_hitstop, 0.10)
	if kind == Sim.COLUMN:
		_drop_slab_over(at)


func _on_collapse_started() -> void:
	_interlude_text = ""
	_shake = maxf(_shake, 1.2)


func _on_escaped(seconds_left: float) -> void:
	_interlude_text = "OUT WITH %.1fs" % maxf(0.0, seconds_left)


func _on_crushed() -> void:
	_interlude_text = "CRUSHED"
	_shake = maxf(_shake, 1.6)


func _on_level_finished(won: bool) -> void:
	best_rubble = maxi(best_rubble, sim.rubble)
	best_site = maxi(best_site, sim.level)
	_save()
	_interlude = INTERLUDE_SECONDS
	_interlude_won = won


## The only place the world can be started again. An earlier build of this game
## recorded the score here and did nothing else, so `over` stayed true,
## `advance()` returned early forever, and it sat frozen with a live HUD.
func _advance_interlude(dt: float) -> void:
	if _interlude <= 0.0:
		return
	_interlude -= dt
	if _interlude > 0.0:
		return
	if _interlude_won:
		sim.next_site()
	else:
		sim.restart(1)
	_chunks.clear()
	_slabs.clear()


## Debris comes off a SEEDED stream, not randf().
##
## It is cosmetic and it still must not be random: the smoke test asserts the
## count drawn against the count that exists, and a chunk whose lifetime came
## from randf() makes that assertion flake. Anything deciding *when* something
## happens is simulation however decorative it looks.
func _burst(at: Vector2, y: float, n: int, force: float) -> void:
	for i in n:
		if _chunks.size() >= DEBRIS_POOL:
			return
		var span := _fx_rng.range_f(0.8, 2.2)
		_chunks.append({
			"pos": to_world(at, y) + Vector3(
				_fx_rng.range_f(-0.7, 0.7), 0.0, _fx_rng.range_f(-0.7, 0.7)),
			"vel": Vector3(
				_fx_rng.range_f(-5.0, 5.0) * force,
				_fx_rng.range_f(1.5, 7.0) * force,
				_fx_rng.range_f(-5.0, 5.0) * force),
			"ang": Vector3(_fx_rng.range_f(0.0, TAU), _fx_rng.range_f(0.0, TAU), 0.0),
			"spin": _fx_rng.range_f(-8.0, 8.0),
			"life": span, "span": span,
			"size": _fx_rng.range_f(0.4, 1.5),
		})


## A section of ceiling comes down where a column used to be. Cosmetic: the
## slab has no say in anything, which is exactly why it is allowed to be
## spectacular.
func _drop_slab_over(at: Vector2) -> void:
	if _slabs.size() >= SLAB_POOL:
		return
	_slabs.append({
		"pos": to_world(at, Tuning.CEILING),
		"vel": Vector3(0, -0.4, 0),
		"tilt": Vector3(_fx_rng.range_f(-0.25, 0.25), _fx_rng.range_f(0.0, TAU), _fx_rng.range_f(-0.25, 0.25)),
		"spin": _fx_rng.range_f(-0.8, 0.8),
		"life": 9.0, "span": 9.0,
	})


func _advance_fx(dt: float) -> void:
	_shake = maxf(0.0, _shake - dt * 2.2)

	var keep: Array[Dictionary] = []
	for c in _chunks:
		c.life -= dt
		if c.life <= 0.0:
			continue
		c.vel.y -= 20.0 * dt
		c.pos += c.vel * dt
		if c.pos.y < 0.25:
			c.pos.y = 0.25
			c.vel.y = absf(c.vel.y) * 0.3
			c.vel.x *= 0.65
			c.vel.z *= 0.65
		c.ang.x += c.spin * dt
		c.ang.y += c.spin * 0.7 * dt
		keep.append(c)
	_chunks = keep

	var slabs_keep: Array[Dictionary] = []
	for sl in _slabs:
		sl.life -= dt
		if sl.life <= 0.0:
			continue
		sl.vel.y -= 9.0 * dt
		sl.pos += sl.vel * dt
		if sl.pos.y < 0.4:
			sl.pos.y = 0.4
			sl.vel = Vector3.ZERO
		else:
			sl.tilt.y += sl.spin * dt
		slabs_keep.append(sl)
	_slabs = slabs_keep


# --- drawing --------------------------------------------------------------

func _sync() -> void:
	_rig.position = to_world(sim.pos, 0.0)
	# The machine's heading is a rotation about the world's vertical. The sim's
	# 0 is "into the room", which the world draws as -Z, so the two agree with
	# no sign flip.
	_rig.rotation = Vector3(0.0, sim.heading, 0.0)

	var turret_dir := sim.heading + sim.turret
	var tip := to_world(sim.boom_tip(), Tuning.BOOM_HEIGHT)
	var base := to_world(sim.pos, 2.4) + Vector3(sin(turret_dir), 0, -cos(turret_dir)) * 0.6
	var ball := to_world(sim.ball, sim.ball_y())
	_span(_boom, base, tip)
	_span(_chain, tip, ball)
	_ball.position = ball

	if _stick != null:
		_stick.queue_redraw()
	if _slew != null:
		_slew.queue_redraw()

	_write_camera()
	_write_room()
	_write_debris()
	_write_hud()


## Stretch a unit-length box between two points.
##
## `Transform3D.looking_at`, never `Node3D.look_at`. The node method requires
## the node to be inside the tree and errors when it is not - which is exactly
## the headless case, because add_child() during SceneTree._initialize() does
## not put anything in the tree until the first processed frame.
func _span(node: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.001:
		node.visible = false
		return
	node.visible = true
	var up := Vector3.UP if absf(delta.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	node.transform = Transform3D(Basis.IDENTITY, (from + to) * 0.5).looking_at(to, up)
	node.scale = Vector3(1.0, 1.0, length)


## A follow camera with a FIXED orientation.
##
## It chased the machine's heading for two builds and both were unusable. A
## rotating camera in a low bounded room has nowhere to retreat to: drive at a
## wall and the lens ends up behind it, and the shot becomes the inside of the
## concrete. Clamping the position fixed the worst of it and left the camera
## pressed against a wall staring at it.
##
## Holding the orientation still solves it outright, and it is the better shot
## anyway. What the player is reading in this game is the ARC the ball sweeps
## around the room - which columns it will pass through, and whether the orbit
## is wide enough. An over-the-shoulder view hides exactly that; a fixed angle
## looking down the room shows the whole floor plan and the ball's path across
## it. The machine turns inside the frame instead of the frame turning with it.
func _write_camera() -> void:
	var eye := to_world(sim.pos, 0.0) + Vector3(0, CAM_HEIGHT, CAM_BACK)
	if _shake > 0.0:
		# Cosmetic, and the one place randf() is legitimate: this moves the
		# lens, not the game. Nothing reads it back.
		eye += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.3

	# Held inside the room. A camera that leaves is a camera looking at the
	# back of a wall, and the ceiling clamp is the same problem upward - the
	# first framing put the lens 6.4 metres up in a 4.6-metre room.
	# Held over the deck rather than inside it. Above the beams there is room to
	# move, so the clamp only stops the view sliding off the site entirely.
	var hw := Tuning.DECK_W * 0.5 + 4.0
	var hd := Tuning.DECK_D * 0.5 + 8.0
	eye.x = clampf(eye.x, -hw, hw)
	eye.z = clampf(eye.z, -hd, hd)

	# Look at a point a little ahead of the machine, so the room it is driving
	# into gets more of the frame than the room it has left.
	var focus := to_world(sim.pos, 1.0) + Vector3(0, 0, -1.5)
	_cam.transform = Transform3D(Basis.IDENTITY, eye).looking_at(focus, Vector3.UP)


func _write_room() -> void:
	var n := 0
	var mm := _columns.multimesh
	for c in sim.columns:
		if not c.standing or n >= COLUMN_POOL:
			continue
		mm.set_instance_transform(n, Transform3D(Basis.IDENTITY,
			to_world(c.at, Tuning.CEILING * 0.5)))
		# Damage shows on the column itself: a battered one goes darker and
		# warmer, so the player can read what they have already worked without
		# a health bar floating over it.
		var wear: float = clampf(float(c.hp) / maxf(float(c.max_hp), 0.001), 0.0, 1.0)
		mm.set_instance_color(n, Color(0.46, 0.45, 0.44).lerp(Color(0.34, 0.22, 0.16), 1.0 - wear))
		n += 1
	mm.visible_instance_count = n

	var wn := 0
	var wmm := _walls.multimesh
	for w in sim.walls:
		if not w.standing or wn >= WALL_POOL:
			continue
		var span: Vector2 = w.b - w.a
		var basis := Basis(Vector3.UP, atan2(span.x, -span.y)).scaled(
			Vector3(span.length(), 1.0, 1.0))
		wmm.set_instance_transform(wn, Transform3D(basis,
			to_world(w.at, Tuning.CEILING * 0.43)))
		var wear: float = clampf(float(w.hp) / maxf(float(w.max_hp), 0.001), 0.0, 1.0)
		wmm.set_instance_color(wn, Color(0.40, 0.39, 0.38).lerp(Color(0.30, 0.21, 0.17), 1.0 - wear))
		wn += 1
	wmm.visible_instance_count = wn


func _write_debris() -> void:
	var n := 0
	var mm := _debris.multimesh
	for c in _chunks:
		if n >= DEBRIS_POOL:
			break
		var fade: float = clampf(c.life / c.span, 0.0, 1.0)
		# Typed explicitly: a value read out of a Dictionary is a Variant, and
		# `:=` cannot infer a type from one.
		var ang: Vector3 = c.ang
		var pos: Vector3 = c.pos
		var grow: float = float(c.size) * (0.35 + fade * 0.65)
		mm.set_instance_transform(n, Transform3D(
			Basis.from_euler(ang).scaled(Vector3.ONE * grow), pos))
		mm.set_instance_color(n, Color(0.48, 0.46, 0.43, fade))
		n += 1
	mm.visible_instance_count = n

	var sn := 0
	var smm := _slab.multimesh
	for sl in _slabs:
		if sn >= SLAB_POOL:
			break
		var tilt: Vector3 = sl.tilt
		var spos: Vector3 = sl.pos
		smm.set_instance_transform(sn, Transform3D(Basis.from_euler(tilt), spos))
		smm.set_instance_color(sn, Color(0.34, 0.33, 0.32))
		sn += 1
	smm.visible_instance_count = sn


func _write_hud() -> void:
	_readout.text = SimUtil.fmt(sim.rubble)

	var frac: float = clampf(sim.integrity, 0.0, 1.0)
	_gauge_fill.size = Vector2(574.0 * frac, 20)
	if sim.collapsing:
		_gauge_fill.color = Color(0.95, 0.25, 0.15)
	elif sim.integrity <= Tuning.COLLAPSE_AT + 0.12:
		_gauge_fill.color = Color(0.95, 0.70, 0.20)
	else:
		_gauge_fill.color = Color(0.45, 0.85, 0.45)

	if _interlude > 0.0 and _interlude_text != "":
		_banner.text = _interlude_text
		_banner.visible = true
	elif sim.collapsing:
		_banner.text = "GET OUT  %.1f" % maxf(0.0, sim.escape_left)
		_banner.visible = true
	else:
		_banner.visible = false

	_hud.text = "LEVEL %d    SUPPORT %d%%    %d COLUMNS LEFT\nBEST %s at level %d\n%s" % [
		sim.level, int(round(sim.integrity * 100.0)), sim.columns_standing(),
		SimUtil.fmt(best_rubble), best_site, BuildStamp.line(),
	]


# --- save -----------------------------------------------------------------

func _load_save() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		best_rubble = int(data.get("best_rubble", 0))
		best_site = int(data.get("best_site", 1))


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"best_rubble": best_rubble, "best_site": best_site}))
	f.close()
