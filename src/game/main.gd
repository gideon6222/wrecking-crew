extends Node3D

## The shell. Reads `Sim` and draws it; never decides anything.
##
## The scene file next to this is four lines on purpose - one node with this
## script. Everything visible is built here in code rather than laid out in the
## editor, for two reasons:
##
## 1. A procedural game's world is built at runtime anyway, so an editor layout
##    would be a second source of truth that has to agree with the first.
## 2. It keeps the whole project reviewable as text. A scene tree assembled by
##    clicking is invisible in a diff and cannot be written by anything that
##    does not have the editor open.
##
## If a game later wants hand-placed content, that content belongs in its own
## scene loaded from here - not merged into this one.

## THE AXIS DECISION, and it is load bearing.
##
## The simulation counts `distance` upward as the rig goes down the street. The
## world draws it as -Z, so the rig travels toward negative Z and the camera
## sits behind it at positive Z looking along its own default forward.
##
## That is not a preference. A chase camera placed BEHIND an object that
## travels toward +Z has to be turned around to look at it, and turning a
## camera 180 degrees about Y mirrors the X axis: world +X then projects to
## screen LEFT, so mapping a rightward drag to increasing X moves the rig the
## wrong way. A sibling game shipped with exactly that for its entire life and
## nobody noticed, because every test drove the steering seam in world
## coordinates - which is the layer the bug lives underneath.
##
## Travelling toward -Z means the camera is never turned around, its basis is a
## pure downward pitch, and screen right IS world +X by construction. There is
## still a test asserting it in normalised device coordinates, because "by
## construction" is what the last game thought too.
const FLOOR_POOL := 320
const BARRICADE_POOL := 24
const DEBRIS_POOL := 160

const SAVE_PATH := "user://wrecking-crew.save"

var sim: Sim

var _cam: Camera3D
var _road: MeshInstance3D
var _rig: Node3D
var _boom: MeshInstance3D
var _counterweight: MeshInstance3D
var _chain: MeshInstance3D
var _ball: MeshInstance3D
var _floors: MultiMeshInstance3D
var _barricades: MultiMeshInstance3D
var _debris: MultiMeshInstance3D

var _hud: Label
var _banner: Label
var _readout: Label
var _meter_back: ColorRect
var _meter_fill: ColorRect
var _ui: Control            ## fills the real viewport; everything anchors to it
var _stick: Control         ## the crane dial - drag it to slew the boom
var _stick_grab := -1       ## which touch index owns the dial, -1 for none
var _swipe_from := 0.0
var _swipe_id := -1
var _swipe_used := false

var _dragging := false
var _shake := 0.0
var _hitstop := 0.0

## Long enough to read what happened, short enough that it never feels like a
## menu. The game is playable again on the other side of it without a tap.
const INTERLUDE_SECONDS := 2.1
var _interlude := 0.0
var _interlude_won := false

## Cosmetic only. Each is {pos, vel, spin, ang, life, span, size}.
##
## These are drawn and never read back: nothing in `Sim` can see them, and no
## decision anywhere depends on one. That is what allows them to exist at all -
## a debris chunk that could nudge a score would put the outcome of a run
## inside a particle system.
var _chunks: Array[Dictionary] = []
var _fx_rng := SimRng.new(20260908)

var best_rubble := 0
var best_street := 1

## Set by the headless harness. When true the frame loop does not step the sim,
## so `advance()` is the only thing moving time and results do not depend on
## how fast the machine boots.
var frozen := false

var _booted := false


func _ready() -> void:
	_ensure_booted()


## Building the world is idempotent and callable before the first frame.
##
## `_ready` does not run at `add_child()` - it is deferred to the first
## processed frame - so a headless harness that adds this node and immediately
## calls `advance()` finds `sim` still null. That cost an hour on the template:
## the symptom was seven hundred identical "Nonexistent function 'advance' in
## base 'Nil'" errors and a run that never terminated, which reads like an
## engine problem and is really a lifecycle one.
##
## The fix is a guard rather than a rule about call order, because a rule about
## call order is something every future test has to remember.
func _ensure_booted() -> void:
	if _booted:
		return
	_booted = true
	sim = Sim.new()
	_load_save()
	_build_world()
	sim.floors_down.connect(_on_floors_down)
	sim.barricade_smashed.connect(_on_barricade_smashed)
	sim.rig_hit.connect(_on_rig_hit)
	sim.level_finished.connect(_on_level_finished)
	_sync()


## The simulation's Z counts up; the world's counts down. One function, called
## everywhere, so the two can never be mixed by accident.
static func wz(sim_z: float) -> float:
	return -sim_z


# --- world ----------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()

	# A real sky rather than a flat clear colour, and it is not decoration: a
	# metal has no diffuse term of its own, so its colour comes entirely from
	# what it reflects. With nothing to reflect, the wrecking ball renders as
	# specular hotspots on black - and the instinct is to reduce metalness,
	# which is the wrong fix. Ambient light from the sky is the right one.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.20, 0.25, 0.34)
	sky_mat.sky_horizon_color = Color(0.46, 0.48, 0.50)
	sky_mat.ground_horizon_color = Color(0.32, 0.31, 0.30)
	sky_mat.ground_bottom_color = Color(0.16, 0.15, 0.15)
	sky_mat.sun_angle_max = 24.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.24

	# Dust, not distance fog. A demolition street is full of it, and it is also
	# what stops the far end of the road ending in a hard edge.
	#
	# The first pass ran at nearly twice this density with the sky fogged too,
	# and the whole picture came out as one beige mush - buildings, road, sky
	# and rig all within a few percent of each other in lightness. Haze is not
	# grit.
	#
	# Lightness alone did not fix it either. What did was making the
	# ATMOSPHERE cool and the material warm: a warm sun on warm concrete
	# against a warm sky has nothing to separate against, however far apart the
	# two are in value. The dust is now grey-blue and the buildings keep their
	# sand tint, which is the same trick as separating a road from a sky by
	# lightness, run on the other axis.
	e.fog_enabled = true
	e.fog_light_color = Color(0.44, 0.46, 0.49)
	e.fog_density = 0.0072
	e.fog_sky_affect = 0.15
	# FILMIC at a white point of 2.0 lifts the midtones hard, and that - not
	# the albedo - was why three passes of darker concrete kept rendering as
	# pale boxes. Proved by forcing the instance colour to magenta, which came
	# through vividly: the colour pipeline was never the problem.
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.15
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	# Low and across the street, so every building casts its shadow along the
	# road rather than straight down. The skyline is the thing being read, and
	# a shadow is most of what says how tall something is.
	sun.rotation_degrees = Vector3(-34, 128, 0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 58
	_cam.far = 240
	add_child(_cam)

	# The road. One long slab moved with the rig rather than tiled, so the
	# ground is a single draw call for the whole street.
	_road = MeshInstance3D.new()
	var road_mesh := BoxMesh.new()
	road_mesh.size = Vector3(Tuning.KERB_X * 2.0, 0.4, 420.0)
	_road.mesh = road_mesh
	_road.material_override = _mat(Color(0.23, 0.23, 0.24), 0.94)
	_road.position.y = -0.2
	_road.name = "Road"
	add_child(_road)

	# Pavements, which are also what the buildings visibly stand on. Separated
	# from the road by LIGHTNESS, not by hue - a sibling game shipped a pink
	# runway under a pink sky and the track dissolved into the backdrop at
	# about the distance the player steers by.
	for side in [-1.0, 1.0]:
		var kerb := MeshInstance3D.new()
		var km := BoxMesh.new()
		km.size = Vector3(3.4, 0.55, 420.0)
		kerb.mesh = km
		kerb.material_override = _mat(Color(0.42, 0.40, 0.37), 0.92)
		kerb.position = Vector3(side * (Tuning.KERB_X + 1.5), -0.1, 0.0)
		kerb.name = "Kerb%d" % int(side)
		add_child(kerb)

	_build_rig()

	# Buildings are drawn one FLOOR at a time, which is what makes the health
	# bar and the silhouette the same object: knocking two floors off is not an
	# animation, it is two fewer instances. There is nothing to keep in sync
	# because there is only one thing.
	_floors = _make_multimesh(BoxMesh.new(), FLOOR_POOL, true)
	(_floors.multimesh.mesh as BoxMesh).size = Vector3(4.6, Tuning.FLOOR_HEIGHT, 7.4)
	_floors.material_override = _mat(Color.WHITE, 0.88)
	_floors.material_override.vertex_color_use_as_albedo = true
	_floors.name = "Floors"

	_barricades = _make_multimesh(BoxMesh.new(), BARRICADE_POOL, false)
	(_barricades.multimesh.mesh as BoxMesh).size = Vector3(0.85, 1.25, 0.45)
	# Every hazard in one colour family, so "this hurts" is read once and then
	# recognised at distance and in peripheral vision. Variety belongs in the
	# silhouette, never in the palette.
	_barricades.material_override = _mat(Color(0.80, 0.26, 0.13), 0.7)
	_barricades.name = "Barricades"

	_debris = _make_multimesh(BoxMesh.new(), DEBRIS_POOL, true)
	(_debris.multimesh.mesh as BoxMesh).size = Vector3(0.5, 0.5, 0.5)
	_debris.material_override = _mat(Color.WHITE, 0.95)
	_debris.material_override.vertex_color_use_as_albedo = true
	_debris.name = "Debris"

	_build_hud()


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)

	var tracks := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(2.4, 0.7, 4.2)
	tracks.mesh = tm
	tracks.material_override = _mat(Color(0.13, 0.13, 0.14), 0.85)
	tracks.position.y = 0.35
	_rig.add_child(tracks)

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.0, 1.1, 3.0)
	body.mesh = bm
	# Plant yellow, dulled and dusted. A saturated one reads as a toy, and the
	# whole art direction here is a machine that has been working all week.
	body.material_override = _mat(Color(0.62, 0.47, 0.11), 0.78)
	body.position = Vector3(0, 1.25, -0.3)
	_rig.add_child(body)

	var cab := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.3, 1.1, 1.3)
	cab.mesh = cm
	cab.material_override = _mat(Color(0.20, 0.21, 0.23), 0.45)
	cab.position = Vector3(0, 2.3, -0.9)
	_rig.add_child(cab)

	_boom = MeshInstance3D.new()
	var boom_mesh := BoxMesh.new()
	boom_mesh.size = Vector3(0.42, 0.42, 1.0)
	_boom.mesh = boom_mesh
	_boom.material_override = _mat(Color(0.58, 0.44, 0.12), 0.8)
	add_child(_boom)

	# The counterweight, out the back of the turret. It is not decoration: it
	# is the only thing on screen that says which way the TURRET is facing when
	# the boom is pointed away from the camera, and a player who cannot read
	# their own aim is guessing.
	_counterweight = MeshInstance3D.new()
	var cw := BoxMesh.new()
	cw.size = Vector3(1.7, 0.9, 1.2)
	_counterweight.mesh = cw
	_counterweight.material_override = _mat(Color(0.24, 0.23, 0.22), 0.8)
	add_child(_counterweight)

	_chain = MeshInstance3D.new()
	var chain_mesh := BoxMesh.new()
	chain_mesh.size = Vector3(0.14, 0.14, 1.0)
	_chain.mesh = chain_mesh
	_chain.material_override = _mat(Color(0.28, 0.27, 0.26), 0.55)
	add_child(_chain)

	_ball = MeshInstance3D.new()
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = Tuning.BALL_RADIUS
	ball_mesh.height = Tuning.BALL_RADIUS * 2.0
	ball_mesh.radial_segments = 20
	ball_mesh.rings = 12
	_ball.mesh = ball_mesh
	var ball_mat := _mat(Color(0.19, 0.18, 0.17), 0.34)
	ball_mat.metallic = 0.85
	_ball.material_override = ball_mat
	_ball.name = "Ball"
	add_child(_ball)


func _mat(c: Color, rough: float = 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = 0.0
	return m


## One MultiMesh per kind, rewritten every frame.
##
## `visible_instance_count` is the whole reason to use this rather than a pool
## of nodes: it is a number the tests can compare against the entity list. A
## render path that silently stops drawing and a subsystem that does not exist
## look identical from outside, and that has already cost a full tuning pass on
## another game here - the enemies were invisible while still charging, still
## costing crew and still being killed, and it read as a balance problem.
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


## The dial is 380 canvas units across on a 1080-wide base, so about a third of
## the screen width - roughly 3.5cm on this phone, which is a thumb. It sits
## clear of the bottom edge so the system gesture bar cannot eat the press.
const STICK_SIZE := 380.0
const STICK_BOTTOM := 190.0


## Drawn rather than assembled from Panels, because what it needs to show is a
## machine seen from above with its boom pointing somewhere - and that is three
## draw calls and no nodes.
##
## The boom on the dial is drawn from `sim.yaw` directly, never from the 3D
## boom's transform, so the control and the world read the same source. Screen
## rotation is clockwise-positive with y down, and world +yaw is to the
## player's right, so the two signs agree with no flip - which is only true
## because the street is drawn along -Z. See the note at the top of this file.
func _draw_stick() -> void:
	var r := STICK_SIZE * 0.5
	var c := Vector2(r, r)
	var lit: float = 0.55 if _stick_grab >= 0 else 0.32

	_stick.draw_circle(c, r, Color(0.05, 0.05, 0.06, 0.34))
	_stick.draw_arc(c, r - 4.0, 0.0, TAU, 64, Color(1.0, 0.86, 0.42, lit), 4.0)

	# The slew limits, so the player can see where the boom runs out of travel
	# instead of discovering it by pushing into a stop.
	for stop in [-Tuning.YAW_MAX, Tuning.YAW_MAX]:
		var d := Vector2(sin(stop), -cos(stop))
		_stick.draw_line(c + d * (r * 0.62), c + d * (r - 8.0),
			Color(1.0, 0.86, 0.42, 0.22), 3.0)

	var dir := Vector2(sin(sim.yaw), -cos(sim.yaw))
	var side := Vector2(dir.y, -dir.x)

	# The tracks: the machine's body, which does NOT turn with the boom.
	_stick.draw_line(c + Vector2(-26, 0), c + Vector2(-26, 0), Color.TRANSPARENT, 1.0)
	var body := PackedVector2Array([
		c + Vector2(-30, -34), c + Vector2(30, -34),
		c + Vector2(30, 34), c + Vector2(-30, 34)])
	_stick.draw_colored_polygon(body, Color(0.22, 0.21, 0.20, 0.9))

	# The turret and the boom, which do.
	_stick.draw_line(c - dir * 34.0, c + dir * (r * 0.80), Color(0.86, 0.68, 0.20, 0.95), 13.0)
	_stick.draw_circle(c - dir * 40.0, 15.0, Color(0.30, 0.29, 0.28, 0.95))
	_stick.draw_circle(c, 21.0, Color(0.42, 0.40, 0.36, 0.95))

	# And the ball, at its real bearing rather than the boom's - the gap
	# between the two IS the lag, and this is the one place it can be read
	# without taking your eyes off the street.
	var ball_dir := Vector2(sin(sim.bearing), -cos(sim.bearing))
	var reach: float = clampf(sim.radius / Tuning.RADIUS_MAX, 0.0, 1.0)
	_stick.draw_circle(c + ball_dir * (r * 0.46 + r * 0.42 * reach), 16.0,
		Color(0.92, 0.86, 0.72, 0.95))


## The dial owns its own touches, so the drawn circle and the region that
## responds are the same rectangle by construction.
##
## Absolute rather than relative: on a joystick the thumb's position IS the
## value, and a relative mapping would let the boom and the dial drift apart
## until they disagreed about where the crane was pointing.
func _on_stick_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_stick_grab = event.index if event is InputEventScreenTouch else 0
			_aim_from_stick(event.position)
		else:
			_stick_grab = -1
		_stick.accept_event()
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		if _stick_grab >= 0:
			_aim_from_stick(event.position)
			_stick.accept_event()


func _aim_from_stick(local: Vector2) -> void:
	var r := STICK_SIZE * 0.5
	var off := (local - Vector2(r, r)) / (r * 0.82)
	# Only the horizontal component steers the boom - the crane slews, it does
	# not luff - but the thumb is allowed to travel anywhere inside the dial so
	# a diagonal drag still reads as intended.
	sim.aim_to(clampf(off.x, -1.0, 1.0) * Tuning.YAW_MAX)


## THE LAYOUT RULE, learned by shipping it wrong.
##
## `window/stretch/aspect = "expand"` keeps the base WIDTH and extends the
## HEIGHT to the device's aspect. The project's base is 1080x1920; an S26 Ultra
## is about 19.5:9, so the canvas it actually renders into is roughly 1080x2340.
## Laying anything out against the number 1920 therefore puts it hundreds of
## pixels off the bottom of the screen, and Gideon's report - "the icons are
## about half an inch too high" - was exactly that.
##
## It shipped with a second bug of the same origin: the hit test scaled touches
## into a 1080x1920 space of its own, so the drawn control and its touch target
## were in two different coordinate systems and disagreed with each other as
## well as with the screen.
##
## So: NOTHING here is positioned against a literal screen size. One Control
## fills the viewport, everything anchors to that, and every interactive
## control handles its OWN input through `_gui_input`. Position and hit box are
## then the same object and cannot drift apart - which is the only fix that
## stays fixed.
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
	_readout.position = Vector2(46, 60)
	_readout.add_theme_font_size_override("font_size", 62)
	_readout.add_theme_color_override("font_color", Color(1, 0.96, 0.88))
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_readout.add_theme_constant_override("outline_size", 12)
	_ui.add_child(_readout)

	# The power meter sits directly under the rubble count, because rubble is
	# what fills it. A gauge placed away from the thing it measures is a gauge
	# the player has to be told about.
	_meter_back = ColorRect.new()
	_meter_back.position = Vector2(46, 150)
	_meter_back.size = Vector2(360, 18)
	_meter_back.color = Color(0, 0, 0, 0.45)
	_ui.add_child(_meter_back)

	_meter_fill = ColorRect.new()
	_meter_fill.position = Vector2(48, 152)
	_meter_fill.size = Vector2(0, 14)
	_meter_fill.color = Color(1.0, 0.72, 0.20)
	_ui.add_child(_meter_fill)

	# Centred and large, because it is the only moment the game speaks to the
	# player. It never blocks: it runs on its own timer and the next street
	# starts without a tap.
	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.anchor_top = 0.34
	_banner.anchor_bottom = 0.34
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.offset_left = 0
	_banner.offset_right = 0
	_banner.offset_top = 0
	_banner.offset_bottom = 130
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 84)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 16)
	_banner.visible = false
	_ui.add_child(_banner)

	# The crane dial. Anchored to the bottom CENTRE of whatever the viewport
	# actually is, and it draws the machine seen from above - so the control
	# and the thing it controls are the same picture, and your aim is readable
	# without looking up at the boom.
	_stick = Control.new()
	_stick.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stick.custom_minimum_size = Vector2(STICK_SIZE, STICK_SIZE)
	_stick.size = Vector2(STICK_SIZE, STICK_SIZE)
	_stick.offset_left = -STICK_SIZE * 0.5
	_stick.offset_right = STICK_SIZE * 0.5
	_stick.offset_top = -STICK_SIZE - STICK_BOTTOM
	_stick.offset_bottom = -STICK_BOTTOM
	_stick.mouse_filter = Control.MOUSE_FILTER_STOP
	_stick.name = "Stick"
	_stick.gui_input.connect(_on_stick_input)
	_stick.draw.connect(_draw_stick)
	_ui.add_child(_stick)

	_hud = Label.new()
	_hud.position = Vector2(46, 186)
	_hud.add_theme_font_size_override("font_size", 34)
	_hud.add_theme_color_override("font_color", Color(0.94, 0.92, 0.88))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("outline_size", 9)
	_ui.add_child(_hud)


# --- loop -----------------------------------------------------------------

func _process(delta: float) -> void:
	if frozen:
		return
	_tick(delta)


func _tick(dt: float) -> void:
	# Hit stop. Freezing the simulation for a few dozen milliseconds on an
	# impact is the highest value per line of code in the whole toolbox - the
	# same animation reads as a different game. Scaled to how big the hit was.
	if _hitstop > 0.0:
		_hitstop -= dt
	else:
		sim.advance(dt)
	_advance_interlude(dt)
	_advance_fx(dt)
	_sync()


## The headless seam.
##
## `_process` computes a delta and calls `_tick`; this steps `_tick` at a fixed
## delta instead. A whole street compresses into one call, deterministically and
## far faster than real time, with no window open.
##
## Freeze first. Real frames run between the scene loading and a harness taking
## over, and how many depends on how fast the machine starts - which quietly
## makes every recorded number a function of the test runner's speed.
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
	_shake = 0.0
	_hitstop = 0.0
	_interlude = 0.0
	_sync()


# --- feedback -------------------------------------------------------------

## Three channels on every action - something you see, something that moves the
## frame, and (when there is audio) something you hear. Any one alone reads as
## cheap.
func _on_floors_down(x: float, z: float, floors: int, flattened: bool) -> void:
	_burst(x, z, 9 + floors * 7, 0.9 if flattened else 0.65)
	_shake = maxf(_shake, 0.22 + 0.09 * float(floors))
	_hitstop = maxf(_hitstop, 0.035 + 0.012 * float(floors))


func _on_barricade_smashed(x: float, z: float) -> void:
	_burst(x, z, 14, 0.55)
	_shake = maxf(_shake, 0.2)
	_hitstop = maxf(_hitstop, 0.035)


func _on_rig_hit(x: float, z: float) -> void:
	_burst(x, z, 10, 0.5)
	_shake = maxf(_shake, 0.5)
	_hitstop = maxf(_hitstop, 0.08)


## The end of a street, and the end of a run, are the only two ways the world
## stops - so this is the only place that can start it again.
##
## The first build recorded the best haul here and did nothing else. `over` was
## already true, so `advance()` returned early from that moment on and the game
## sat frozen with a live HUD, which is indistinguishable from a crash to the
## person holding the phone.
##
## Worth being precise about why no test caught it: every test in the suite
## plays a street and reads the state at the end - which is exactly the instant
## the bug begins. Nothing anywhere asked what happens NEXT.
func _on_level_finished(won: bool) -> void:
	best_rubble = maxi(best_rubble, sim.rubble)
	best_street = maxi(best_street, sim.level)
	_save()
	_interlude = INTERLUDE_SECONDS
	_interlude_won = won


## Counts down whether or not the simulation is running, because the simulation
## is precisely what is not running while it does.
func _advance_interlude(dt: float) -> void:
	if _interlude <= 0.0:
		return
	_interlude -= dt
	if _interlude > 0.0:
		return
	if _interlude_won:
		sim.next_street()
	else:
		sim.restart(1)
	_chunks.clear()


## Debris comes off a SEEDED stream, not randf().
##
## It is cosmetic and it still must not be random: the smoke test asserts the
## count that is drawn against the count that exists, and a chunk whose
## lifetime came from randf() makes that assertion flake. The wider rule from a
## sibling game is that anything deciding *when* something happens is
## simulation however decorative it looks - and a particle's lifetime is
## exactly that.
func _burst(x: float, z: float, n: int, force: float) -> void:
	for i in n:
		if _chunks.size() >= DEBRIS_POOL:
			return
		var span := _fx_rng.range_f(0.55, 1.5)
		_chunks.append({
			"pos": Vector3(x, _fx_rng.range_f(0.6, 4.2), wz(z)),
			"vel": Vector3(
				_fx_rng.range_f(-4.0, 4.0) * force,
				_fx_rng.range_f(2.0, 8.0) * force,
				_fx_rng.range_f(-3.0, 3.0) * force),
			"ang": Vector3(_fx_rng.range_f(0.0, TAU), _fx_rng.range_f(0.0, TAU), 0.0),
			"spin": _fx_rng.range_f(-7.0, 7.0),
			"life": span,
			"span": span,
			"size": _fx_rng.range_f(0.35, 1.15),
		})


func _advance_fx(dt: float) -> void:
	_shake = maxf(0.0, _shake - dt * 2.4)
	var keep: Array[Dictionary] = []
	for c in _chunks:
		c.life -= dt
		if c.life <= 0.0:
			continue
		c.vel.y -= 22.0 * dt
		c.pos += c.vel * dt
		if c.pos.y < 0.25:
			c.pos.y = 0.25
			c.vel.y = absf(c.vel.y) * 0.32
			c.vel.x *= 0.7
			c.vel.z *= 0.7
		c.ang.x += c.spin * dt
		c.ang.y += c.spin * 0.6 * dt
		keep.append(c)
	_chunks = keep


# --- drawing --------------------------------------------------------------

func _sync() -> void:
	var z := sim.distance
	_rig.position = Vector3(sim.x, 0.0, wz(z))
	# Lean the whole rig into the turn. Read off lateral velocity, which is the
	# axis the machine is not pointing along - that is what "drifting" means.
	_rig.rotation = Vector3(0.0, 0.0, -sim.vx * 0.035)

	# The boom points where the turret is slewed; the chain hangs from its tip;
	# the ball is wherever the simulation says it is, which is NOT under the
	# tip - the gap between the two is the lag, drawn.
	#
	# All three are placed in world space rather than parented to the rig. The
	# rig leans into a lane change, and a boom that leaned with it would no
	# longer meet its own chain. Two things that must touch have to be placed
	# in one frame of reference.
	var turret := Vector3(sim.x, 2.5, wz(z))
	var tip := Vector3(sim.boom_tip_x(), Tuning.PIVOT_Y, wz(sim.boom_tip_z()))
	var ball := Vector3(sim.ball_x(), sim.ball_y(), wz(sim.ball_z()))
	_span(_boom, turret, tip)
	_span(_chain, tip, ball)
	_ball.position = ball

	# Opposite the boom, in plan. Reads the yaw straight out of the simulation
	# rather than from the boom's drawn transform, so the two cannot disagree.
	_counterweight.position = Vector3(
		sim.x - 1.9 * sin(sim.yaw), 2.6, wz(z - 1.9 * cos(sim.yaw)))
	_counterweight.rotation = Vector3(0.0, -sim.yaw, 0.0)

	_road.position = Vector3(0, -0.2, wz(z))
	for side in [-1, 1]:
		var kerb := get_node_or_null("Kerb%d" % side)
		if kerb:
			kerb.position.z = wz(z)

	if _stick != null:
		_stick.queue_redraw()

	_write_camera(z)
	_write_floors()
	_write_barricades()
	_write_debris()
	_write_hud()


## Stretch a unit-length box between two points.
##
## `Transform3D.looking_at`, never `Node3D.look_at`. The node method requires
## the node to be inside the tree and errors when it is not - which is exactly
## the headless case, because add_child() during SceneTree._initialize() does
## not put anything in the tree until the first processed frame. This is pure
## maths and works anywhere.
func _span(node: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.001:
		node.visible = false
		return
	node.visible = true
	var up := Vector3.UP if absf(delta.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var t := Transform3D(Basis.IDENTITY, (from + to) * 0.5).looking_at(to, up)
	node.transform = t
	node.scale = Vector3(1.0, 1.0, length)


func _write_camera(z: float) -> void:
	# Behind and above, travelling the same way the rig does, so the camera is
	# never turned around and screen right stays world +X. The pitch is a pure
	# rotation about X for the same reason.
	# Back and up, and now following the BALL rather than the rig.
	#
	# The subject of the shot changed when the crane did. The ball sweeps an
	# arc across the whole street instead of tracking along one line in front
	# of the cab, so a camera locked to the rig loses it at exactly the moment
	# it matters. Following a point between the two keeps the ball, the rig and
	# the kerb it is heading for in one frame - and the drift itself reads as
	# the crane swinging, which is feedback for free.
	# Pulled back hard when the crane replaced the pendulum. The boom is a
	# third of the length the old fixed one was - it has to be, because "at
	# rest the ball falls just short of the kerb" is the number the whole
	# design rests on - so the entire machine now sits much closer together,
	# and the framing that suited the long one put a two-metre ball across a
	# quarter of a portrait screen.
	var sway := (sim.x * 0.32 + sim.ball_x() * 0.22)
	var eye := Vector3(sway, 11.4, wz(z) + 21.5)
	if _shake > 0.0:
		# Cosmetic, and the one place randf() is legitimate: this moves the
		# lens, not the game. Nothing reads it back.
		eye += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake * 0.34
	_cam.transform = Transform3D(Basis(Vector3.RIGHT, -0.30), eye)


func _write_floors() -> void:
	var n := 0
	var mm := _floors.multimesh
	for b in sim.buildings:
		for f in b.left:
			if n >= FLOOR_POOL:
				break
			var y := Tuning.FLOOR_HEIGHT * (float(f) + 0.5)
			var pos := Vector3(
				float(b.side) * (Tuning.KERB_X + 1.5),
				y,
				wz(b.z))
			mm.set_instance_transform(n, Transform3D(Basis.IDENTITY, pos))
			# Per-instance colour over a white base is what makes one layer
			# look like many objects. Keyed on the building's place, so a
			# street looks the same every time it is played.
			# Darker than the road they stand beside, which is the opposite
			# of the first two passes and is what finally made the street read.
			# The play space wants to be the LIGHT thing and the scenery the
			# dark mass around it - separated by lightness, never by hue.
			#
			# The albedo was not the reason they came out white. A 2.1-energy
			# sun on a 0.22 albedo is a blown-out lit face whatever the colour
			# says, and the fix was the light rather than the paint. Measured
			# by reading the instance colour back out of a real renderer -
			# which is also how it emerged that a HEADLESS run allocates no
			# MultiMesh buffer at all, so colours there read as black and
			# prove nothing.
			var tint := SimUtil.hash2(int(b.z), b.side * 31)
			var shade := 0.15 + tint * 0.21
			# A hint of warmth or cold per building, so a row of them is a row
			# of separate buildings rather than one long wall.
			var warm := SimUtil.hash2(int(b.z) + 7, b.side * 53) - 0.5
			mm.set_instance_color(n, Color(
				shade * (1.0 + warm * 0.22),
				shade * 0.96,
				shade * (0.90 - warm * 0.20)))
			n += 1
	mm.visible_instance_count = n


func _write_barricades() -> void:
	var n := 0
	var mm := _barricades.multimesh
	for w in sim.barricades:
		if w.taken or n + 3 > BARRICADE_POOL:
			continue
		var lo: float = -Tuning.LANE_HALF_WIDTH if w.side < 0 else Tuning.BARRICADE_INNER_X
		var hi: float = -Tuning.BARRICADE_INNER_X if w.side < 0 else Tuning.LANE_HALF_WIDTH
		# Three posts across the blocked span, derived from the span itself.
		# Deriving the drawing from the collision - rather than placing it
		# alongside - is what stops a fair obstacle quietly becoming an unfair
		# one when one of the two numbers is edited.
		for i in 3:
			var t := float(i) / 2.0
			var pos := Vector3(lerpf(lo, hi, t), 0.62, wz(w.z))
			mm.set_instance_transform(n, Transform3D(Basis.IDENTITY, pos))
			n += 1
	mm.visible_instance_count = n


func _write_debris() -> void:
	var n := 0
	var mm := _debris.multimesh
	for c in _chunks:
		if n >= DEBRIS_POOL:
			break
		var fade: float = clampf(c.life / c.span, 0.0, 1.0)
		# Typed explicitly: a value read out of a Dictionary is a Variant, and
		# `var b := Basis.from_euler(c.ang)` cannot infer a type from one. The
		# parser rejects it outright rather than failing at runtime, which is
		# the good outcome - but the message names the variable, not the
		# dictionary lookup that caused it.
		var ang: Vector3 = c.ang
		var pos: Vector3 = c.pos
		var grow: float = float(c.size) * (0.4 + fade * 0.6)
		var b := Basis.from_euler(ang).scaled(Vector3.ONE * grow)
		mm.set_instance_transform(n, Transform3D(b, pos))
		mm.set_instance_color(n, Color(0.58, 0.56, 0.52, fade))
		n += 1
	mm.visible_instance_count = n


func _write_hud() -> void:
	_readout.text = SimUtil.fmt(sim.rubble)

	var target := sim.meter_target()
	var frac: float = 0.0 if target <= 0 else clampf(float(sim.meter) / float(target), 0.0, 1.0)
	_meter_fill.size.x = 356.0 * (1.0 if target <= 0 else frac)
	_meter_fill.color = Color(0.45, 0.85, 0.45) if target <= 0 else Color(1.0, 0.72, 0.20)

	if _interlude > 0.0:
		_banner.text = ("STREET %d CLEARED" % sim.level) if _interlude_won else "RUN OVER"
		_banner.visible = true
	else:
		_banner.visible = false

	_hud.text = "STREET %d    LIVES %d    x%d POWER\nBEST %s on street %d\n%s" % [
		sim.level, sim.lives, sim.power,
		SimUtil.fmt(best_rubble), best_street, BuildStamp.line(),
	]


# --- save -----------------------------------------------------------------

## Small on purpose. There is no shop yet, so the only thing worth keeping
## between runs is the record - which is also the only reason to start another
## one. A persistent currency with nothing to spend it on would be a number on
## the HUD that never does anything.
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
		best_street = int(data.get("best_street", 1))


func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"best_rubble": best_rubble,
		"best_street": best_street,
	}))
	f.close()


# --- input ----------------------------------------------------------------

## Two controls, split by where a touch begins.
##
## The dial takes its own presses through `_gui_input` and calls
## `accept_event()`, so anything that reaches here started somewhere else - and
## anything that starts somewhere else is a swipe that moves the machine. That
## includes the whole area below the dial, which is where Gideon asked for it,
## and everywhere else besides, because a control with an invisible boundary is
## a control that gets fumbled in a panic.
##
## One lane per swipe, and the swipe has to be released before another counts.
## Without that, holding a drag walks the rig across the street.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_swipe_id = event.index if event is InputEventScreenTouch else 0
			_swipe_from = event.position.x
			_swipe_used = false
		else:
			_swipe_id = -1
		return

	if event is InputEventScreenDrag or (event is InputEventMouseMotion and _swipe_id >= 0):
		if _swipe_id < 0 or _swipe_used:
			return
		var travelled: float = event.position.x - _swipe_from
		var threshold := float(get_viewport().get_visible_rect().size.x) * SWIPE_FRACTION
		if absf(travelled) < threshold:
			return
		_swipe_used = true
		# No sign flip: swiping right moves the rig right, because the street
		# is drawn along -Z and the camera is therefore never turned around.
		sim.nudge(1 if travelled > 0.0 else -1)
		# Feedback for a control with no button to light up. A lane change is
		# the rig lurching, so the lens lurches with it.
		_shake = maxf(_shake, 0.12)


## A swipe has to cross this fraction of the screen to count as one. Big enough
## that a wobble while reaching for the dial is not a lane change, small enough
## to be a flick rather than a drag.
const SWIPE_FRACTION := 0.12
