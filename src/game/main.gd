extends Node3D

## The shell. Reads `Sim` and draws it; never decides anything.
##
## Everything visible is built here in code rather than laid out in the editor,
## for two reasons: a procedural game's world is built at runtime anyway, so an
## editor layout would be a second source of truth; and it keeps the whole
## project reviewable as text, where a scene tree assembled by clicking is
## invisible in a diff.
##
## THE AXIS DECISION, and it is load bearing.
##
## The simulation measures depth INTO the site as positive z. The world draws
## it as -Z, so the building is at negative z and the camera sits behind the
## crane at positive z looking along its own default forward.
##
## That is not a preference. A camera placed behind an object and turned around
## to look at it is rotated 180 degrees about Y, which mirrors the X axis:
## world +X then projects to screen LEFT, so dragging right would slew the boom
## the wrong way. A sibling game shipped exactly that for its entire life,
## because every test drove the input seam in world coordinates - the layer the
## bug lives underneath. Going the other way makes screen right world +X by
## construction, and `run_smoke.gd` asserts it in camera space anyway.

const FLOOR_POOL := 128
const COLUMN_POOL := 16
const DEBRIS_POOL := 200
const SAVE_PATH := "user://wrecking-crew.save"

var sim: Sim

var _cam: Camera3D
var _ground: MeshInstance3D
var _rig: Node3D
var _boom: MeshInstance3D
var _chain: MeshInstance3D
var _ball: MeshInstance3D
var _counterweight: MeshInstance3D
var _floors: MultiMeshInstance3D
var _columns: MultiMeshInstance3D
var _debris: MultiMeshInstance3D

var _ui: Control
var _stick: Control
var _readout: Label
var _hud: Label
var _banner: Label
var _lean_back: ColorRect
var _lean_fill: ColorRect
var _lean_mark: ColorRect

var _stick_grab := -1
var _swipe_from := 0.0
var _swipe_id := -1
var _swipe_used := false

var _shake := 0.0
var _hitstop := 0.0

## Long enough to read what happened, short enough that it never feels like a
## menu. The game is playable again on the other side without a tap.
const INTERLUDE_SECONDS := 2.6
var _interlude := 0.0
var _interlude_won := false
var _interlude_text := ""

## Cosmetic only. Drawn and never read back: nothing in `Sim` can see a chunk
## and no decision depends on one. That is what allows them to exist at all - a
## debris chunk that could nudge a score would put the outcome of a demolition
## inside a particle system.
var _chunks: Array[Dictionary] = []
var _fx_rng := SimRng.new(20260908)

var best_rubble := 0
var best_site := 1

## Set by the headless harness. When true the frame loop does not step the sim,
## so `advance()` is the only thing moving time.
var frozen := false
var _booted := false


func _ready() -> void:
	_ensure_booted()


## Building the world is idempotent and callable before the first frame.
##
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
	sim.column_struck.connect(_on_column_struck)
	sim.bay_fell.connect(_on_bay_fell)
	sim.building_down.connect(_on_building_down)
	sim.toppled.connect(_on_toppled)
	sim.out_of_swings.connect(_on_out_of_swings)
	sim.level_finished.connect(_on_level_finished)
	_sync()


## The simulation's depth counts up; the world's counts down. One function,
## called everywhere, so the two can never be mixed by accident.
static func wz(sim_z: float) -> float:
	return -sim_z


# --- world ----------------------------------------------------------------

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()

	# A real sky rather than a flat colour, and it is not decoration: a metal
	# has no diffuse term of its own, so its colour comes entirely from what it
	# reflects. With nothing to reflect the ball renders as specular hotspots
	# on black, and the instinct is to reduce metalness, which is the wrong fix.
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
	e.ambient_light_energy = 0.46

	# Cool dust against warm concrete. A warm sun on warm material under a warm
	# sky has nothing to separate against however far apart the values are -
	# three passes of darker concrete on the street version kept rendering as
	# pale boxes until the atmosphere went cold.
	e.fog_enabled = true
	e.fog_light_color = Color(0.44, 0.46, 0.49)
	e.fog_density = 0.0055
	e.fog_sky_affect = 0.15
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.15
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 132, 0)
	sun.light_energy = 1.45
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 58
	_cam.far = 240
	add_child(_cam)

	_ground = MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(90.0, 0.4, 90.0)
	_ground.mesh = gm
	_ground.material_override = _mat(Color(0.34, 0.33, 0.31), 0.95)
	_ground.position = Vector3(0, -0.2, wz(6.0))
	_ground.name = "Ground"
	add_child(_ground)

	_build_neighbours()
	_build_rig()

	# The building, one FLOOR CELL at a time. That is what makes the health bar
	# and the silhouette the same object: a bay coming down is not an animation,
	# it is that column's cells no longer being drawn. There is nothing to keep
	# in sync because there is only one thing.
	_floors = _make_multimesh(BoxMesh.new(), FLOOR_POOL, true)
	(_floors.multimesh.mesh as BoxMesh).size = Vector3(
		Tuning.BAY_WIDTH - 0.12, Tuning.FLOOR_HEIGHT - 0.12, Tuning.BUILDING_DEPTH)
	_floors.material_override = _mat(Color.WHITE, 0.88)
	_floors.material_override.vertex_color_use_as_albedo = true
	_floors.name = "Floors"

	# The columns are drawn separately and in the hazard colour, because they
	# are the only thing on the building the player can actually act on. Every
	# other surface is scenery. One colour family for "this is the target", the
	# way a hazard gets one on a runner.
	_columns = _make_multimesh(BoxMesh.new(), COLUMN_POOL, true)
	(_columns.multimesh.mesh as BoxMesh).size = Vector3(
		Tuning.COLUMN_HALF_WIDTH * 2.0, Tuning.FLOOR_HEIGHT * 1.25, 1.4)
	_columns.material_override = _mat(Color.WHITE, 0.45)
	_columns.material_override.vertex_color_use_as_albedo = true
	_columns.name = "Columns"

	_debris = _make_multimesh(BoxMesh.new(), DEBRIS_POOL, true)
	(_debris.multimesh.mesh as BoxMesh).size = Vector3(0.55, 0.55, 0.55)
	_debris.material_override = _mat(Color.WHITE, 0.95)
	_debris.material_override.vertex_color_use_as_albedo = true
	_debris.name = "Debris"

	_build_hud()


## The blocks either side of the site. They are the stake: the whole game is
## not putting the building on them, so they have to be visibly THERE and
## visibly close, or the lean gauge is a number about nothing.
func _build_neighbours() -> void:
	for side in [-1.0, 1.0]:
		var n := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(8.0, 17.0, 12.0)
		n.mesh = m
		# Lighter than the condemned building, so the thing you must NOT hit
		# reads as a different object from the thing you must. Separated by
		# lightness rather than hue - the rule that finally made the street
		# version legible - and close enough to be in frame, because a stake
		# you cannot see is not a stake.
		n.material_override = _mat(Color(0.46, 0.45, 0.46), 0.9)
		n.position = Vector3(side * 13.5, 8.5, wz(Tuning.FACE_Z + 3.0))
		n.name = "Neighbour%d" % int(side)
		add_child(n)


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)

	var tracks := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(2.6, 0.7, 4.4)
	tracks.mesh = tm
	tracks.material_override = _mat(Color(0.13, 0.13, 0.14), 0.85)
	tracks.position.y = 0.35
	_rig.add_child(tracks)

	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.1, 1.2, 3.0)
	body.mesh = bm
	# Plant yellow, dulled and dusted. A saturated one reads as a toy.
	body.material_override = _mat(Color(0.62, 0.47, 0.11), 0.78)
	body.position = Vector3(0, 1.3, -0.2)
	_rig.add_child(body)

	_boom = MeshInstance3D.new()
	var boom_mesh := BoxMesh.new()
	boom_mesh.size = Vector3(0.42, 0.42, 1.0)
	_boom.mesh = boom_mesh
	_boom.material_override = _mat(Color(0.58, 0.44, 0.12), 0.8)
	add_child(_boom)

	# Opposite the boom. Not decoration: it is the only thing on screen that
	# says which way the TURRET is facing when the boom is pointed away from
	# the camera, and a player who cannot read their own aim is guessing.
	_counterweight = MeshInstance3D.new()
	var cw := BoxMesh.new()
	cw.size = Vector3(1.8, 1.0, 1.3)
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


## `visible_instance_count` is the whole reason to use a MultiMesh rather than
## a pool of nodes: it is a number the tests can compare against the model. A
## render path that silently stops drawing and a subsystem that does not exist
## look identical from outside, and that has cost a full tuning pass on another
## game here.
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
## HEIGHT to the device's aspect. The base is 1080x1920; an S26 Ultra is about
## 19.5:9, so the canvas is roughly 1080x2340. Laying anything out against the
## number 1920 puts it hundreds of pixels off, and the report was "the icons
## are about half an inch too high".
##
## So: NOTHING here is positioned against a literal screen size. One Control
## fills the viewport, everything anchors to that, and every interactive
## control handles its OWN input. Position and hit box are then the same object.
const STICK_SIZE := 380.0
const STICK_BOTTOM := 190.0
const SWIPE_FRACTION := 0.12


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
	_readout.position = Vector2(46, 56)
	_readout.add_theme_font_size_override("font_size", 62)
	_readout.add_theme_color_override("font_color", Color(1, 0.96, 0.88))
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_readout.add_theme_constant_override("outline_size", 12)
	_ui.add_child(_readout)

	# The lean gauge. Centred, because what it measures is whether the building
	# is centred - a bar that fills from one end would be saying the wrong
	# thing about a quantity that has two directions.
	_lean_back = ColorRect.new()
	_lean_back.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lean_back.anchor_left = 0.5
	_lean_back.anchor_right = 0.5
	_lean_back.offset_left = -300
	_lean_back.offset_right = 300
	_lean_back.offset_top = 150
	_lean_back.offset_bottom = 176
	_lean_back.color = Color(0, 0, 0, 0.45)
	_ui.add_child(_lean_back)

	_lean_fill = ColorRect.new()
	_lean_fill.color = Color(0.45, 0.85, 0.45)
	_lean_back.add_child(_lean_fill)

	# The centre line, so "upright" is a place on the gauge rather than a
	# number the player has to remember.
	_lean_mark = ColorRect.new()
	_lean_mark.color = Color(1, 1, 1, 0.5)
	_lean_mark.position = Vector2(298, -6)
	_lean_mark.size = Vector2(4, 38)
	_lean_back.add_child(_lean_mark)

	_hud = Label.new()
	_hud.position = Vector2(46, 186)
	_hud.add_theme_font_size_override("font_size", 34)
	_hud.add_theme_color_override("font_color", Color(0.94, 0.92, 0.88))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hud.add_theme_constant_override("outline_size", 9)
	_ui.add_child(_hud)

	_banner = Label.new()
	_banner.anchor_left = 0.0
	_banner.anchor_right = 1.0
	_banner.anchor_top = 0.36
	_banner.anchor_bottom = 0.36
	_banner.offset_bottom = 130
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 78)
	_banner.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 16)
	_banner.visible = false
	_ui.add_child(_banner)

	# The crane dial: anchored to the bottom CENTRE of whatever the viewport
	# actually is, drawing the machine seen from above, so the control and the
	# thing it controls are the same picture.
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


## Drawn rather than assembled from Panels, because what it needs to show is a
## machine seen from above with a boom pointing somewhere - three draw calls
## and no nodes.
##
## The boom is drawn from `sim.yaw` directly, never from the 3D boom's
## transform, so the control and the world read one source.
func _draw_stick() -> void:
	var r := STICK_SIZE * 0.5
	var c := Vector2(r, r)
	var lit: float = 0.55 if _stick_grab >= 0 else 0.32

	_stick.draw_circle(c, r, Color(0.05, 0.05, 0.06, 0.34))
	_stick.draw_arc(c, r - 4.0, 0.0, TAU, 64, Color(1.0, 0.86, 0.42, lit), 4.0)

	for stop in [-Tuning.YAW_MAX, Tuning.YAW_MAX]:
		var d := Vector2(sin(stop), -cos(stop))
		_stick.draw_line(c + d * (r * 0.62), c + d * (r - 8.0),
			Color(1.0, 0.86, 0.42, 0.22), 3.0)

	var dir := Vector2(sin(sim.yaw), -cos(sim.yaw))
	var body := PackedVector2Array([
		c + Vector2(-30, -34), c + Vector2(30, -34),
		c + Vector2(30, 34), c + Vector2(-30, 34)])
	_stick.draw_colored_polygon(body, Color(0.22, 0.21, 0.20, 0.9))
	_stick.draw_line(c - dir * 34.0, c + dir * (r * 0.80), Color(0.86, 0.68, 0.20, 0.95), 13.0)
	_stick.draw_circle(c - dir * 40.0, 15.0, Color(0.30, 0.29, 0.28, 0.95))
	_stick.draw_circle(c, 21.0, Color(0.42, 0.40, 0.36, 0.95))

	# And the ball, at its real bearing rather than the boom's - the gap
	# between the two IS the lag, and this is the one place it can be read
	# without taking your eyes off the building.
	var ball_dir := Vector2(sin(sim.bearing), -cos(sim.bearing))
	var reach: float = clampf(sim.radius / Tuning.RADIUS_MAX, 0.0, 1.0)
	_stick.draw_circle(c + ball_dir * (r * 0.46 + r * 0.42 * reach), 16.0,
		Color(0.92, 0.86, 0.72, 0.95))


## Absolute rather than relative: on a dial the thumb's position IS the value,
## and a relative mapping would let the boom and the drawing drift apart.
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
	sim.aim_to(clampf(off.x, -1.0, 1.0) * Tuning.YAW_MAX)


# --- loop -----------------------------------------------------------------

func _process(delta: float) -> void:
	if frozen:
		return
	_tick(delta)


func _tick(dt: float) -> void:
	# Hit stop. Freezing the simulation for a few dozen milliseconds on an
	# impact makes the same animation read as a different game.
	if _hitstop > 0.0:
		_hitstop -= dt
	else:
		sim.advance(dt)
	_advance_interlude(dt)
	_advance_fx(dt)
	_sync()


## The headless seam. `_process` computes a delta and calls `_tick`; this steps
## it at a fixed delta instead, so a whole demolition compresses into one call,
## deterministically and far faster than real time, with no window open.
##
## Freeze first, or every recorded number is a function of how fast the machine
## boots.
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

func _on_column_struck(bay: int, hp_left: int) -> void:
	_burst(Tuning.bay_x(sim.level, bay), Tuning.FACE_Z, 2.0, 12, 0.7)
	_shake = maxf(_shake, 0.22)
	_hitstop = maxf(_hitstop, 0.045)


func _on_bay_fell(bay: int, floors: int) -> void:
	# The whole stack comes down, so the debris comes off the whole height.
	for f in floors:
		_burst(Tuning.bay_x(sim.level, bay), Tuning.FACE_Z,
			Tuning.FLOOR_HEIGHT * (float(f) + 0.5), 7, 0.9)
	_shake = maxf(_shake, 0.55)
	_hitstop = maxf(_hitstop, 0.09)


func _on_building_down(clean: bool) -> void:
	_interlude_text = "CLEAN DROP" if clean else "DOWN"


func _on_toppled(direction: float) -> void:
	_interlude_text = "IT WENT OVER"
	_shake = maxf(_shake, 1.1)


func _on_out_of_swings() -> void:
	_interlude_text = "OUT OF SWINGS"


func _on_level_finished(won: bool) -> void:
	best_rubble = maxi(best_rubble, sim.rubble)
	best_site = maxi(best_site, sim.level)
	_save()
	_interlude = INTERLUDE_SECONDS
	_interlude_won = won


## The only place the world can be started again. The first build of this game
## recorded the best score here and did nothing else, so `over` stayed true,
## `advance()` returned early forever, and the game sat frozen with a live HUD.
## Every test in that suite read the state at the end of a level - which is the
## exact instant the freeze began.
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


## Debris comes off a SEEDED stream, not randf().
##
## It is cosmetic and it still must not be random: the smoke test asserts the
## count drawn against the count that exists, and a chunk whose lifetime came
## from randf() makes that assertion flake. The wider rule is that anything
## deciding *when* something happens is simulation however decorative it looks.
func _burst(x: float, z: float, y: float, n: int, force: float) -> void:
	for i in n:
		if _chunks.size() >= DEBRIS_POOL:
			return
		var span := _fx_rng.range_f(0.7, 1.9)
		_chunks.append({
			"pos": Vector3(x + _fx_rng.range_f(-1.2, 1.2), y, wz(z) - _fx_rng.range_f(0.0, 2.0)),
			"vel": Vector3(
				_fx_rng.range_f(-4.0, 4.0) * force,
				_fx_rng.range_f(1.0, 7.0) * force,
				_fx_rng.range_f(1.0, 6.0) * force),
			"ang": Vector3(_fx_rng.range_f(0.0, TAU), _fx_rng.range_f(0.0, TAU), 0.0),
			"spin": _fx_rng.range_f(-7.0, 7.0),
			"life": span,
			"span": span,
			"size": _fx_rng.range_f(0.35, 1.25),
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
		if c.pos.y < 0.28:
			c.pos.y = 0.28
			c.vel.y = absf(c.vel.y) * 0.32
			c.vel.x *= 0.7
			c.vel.z *= 0.7
		c.ang.x += c.spin * dt
		c.ang.y += c.spin * 0.6 * dt
		keep.append(c)
	_chunks = keep


# --- drawing --------------------------------------------------------------

func _sync() -> void:
	_rig.position = Vector3(sim.x, 0.0, 0.0)
	_rig.rotation = Vector3(0.0, 0.0, -sim.vx * 0.03)

	var turret := Vector3(sim.x, 2.6, 0.0)
	var tip := Vector3(sim.boom_tip_x(), Tuning.PIVOT_Y, wz(sim.boom_tip_z()))
	var ball := Vector3(sim.ball_x(), sim.ball_y(), wz(sim.ball_z()))
	_span(_boom, turret, tip)
	_span(_chain, tip, ball)
	_ball.position = ball

	_counterweight.position = Vector3(
		sim.x - 2.0 * sin(sim.yaw), 2.7, wz(-2.0 * cos(sim.yaw)))
	_counterweight.rotation = Vector3(0.0, -sim.yaw, 0.0)

	if _stick != null:
		_stick.queue_redraw()

	_write_camera()
	_write_building()
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


func _write_camera() -> void:
	# Fixed on the site rather than chasing the crane. The subject is the
	# building - the player is judging a shape, not travelling anywhere - so
	# the frame holds still and the machine moves inside it. A camera that
	# followed would take the reference away from the thing being judged.
	# Back far enough to see the whole building at once, which is the thing
	# being judged. The first framing put the lens 15 metres out and the
	# building filled the frame edge to edge - you could see the bay you were
	# hitting and nothing about the shape you were making, which is the only
	# question the game asks.
	var sway := sim.x * 0.18 + sim.ball_x() * 0.08
	var eye := Vector3(sway, 14.5, 30.0)
	if _shake > 0.0:
		# Cosmetic, and the one place randf() is legitimate: this moves the
		# lens, not the game. Nothing reads it back.
		eye += Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * _shake * 0.4
	_cam.transform = Transform3D(Basis(Vector3.RIGHT, -0.26), eye)


## The building, leaning.
##
## Every standing cell is rotated about the ground line at the centre of the
## site by an angle taken straight from `sim.lean`, so the picture and the
## gauge are the same number. A building that leaned by some separate
## animation value would be a second source of truth for the one thing the
## player is judging.
func _write_building() -> void:
	var tilt := sim.lean * 0.16
	var ca := cos(tilt)
	var sa := sin(tilt)
	var basis := Basis(Vector3.BACK, tilt)

	var n := 0
	var mm := _floors.multimesh
	var cn := 0
	var cmm := _columns.multimesh

	for i in sim.bays.size():
		var b := sim.bays[i]
		if not b.standing:
			continue
		var bx := Tuning.bay_x(sim.level, i)

		if cn < COLUMN_POOL:
			var cy := Tuning.FLOOR_HEIGHT * 0.62
			cmm.set_instance_transform(cn, Transform3D(basis, Vector3(
				bx * ca - cy * sa, bx * sa + cy * ca,
				wz(Tuning.FACE_Z - 0.5))))
			# Red hot when it is one hit from going, so the player can see what
			# their next swing will cost them before they take it.
			var hp: int = b.hp
			# One colour family for "this is what you hit", the way a hazard
			# gets one on a runner - and it brightens as the column weakens,
			# so what your next swing will cost is visible before you take it.
			cmm.set_instance_color(cn, Color(1.00, 0.42, 0.14) if hp <= 1
				else Color(0.86, 0.62, 0.16))
			cn += 1

		for f in int(b.floors):
			if n >= FLOOR_POOL:
				break
			# Floor 0 is the storey the column holds up, so it starts above it.
			var y := Tuning.FLOOR_HEIGHT * (float(f) + 1.7)
			mm.set_instance_transform(n, Transform3D(basis, Vector3(
				bx * ca - y * sa, bx * sa + y * ca,
				wz(Tuning.FACE_Z + Tuning.BUILDING_DEPTH * 0.5))))
			# Per-instance colour keyed on the place, so a given building looks
			# the same every time it is played.
			var tint := SimUtil.hash2(i * 7 + f, 31 + sim.level)
			var shade := 0.30 + tint * 0.22
			mm.set_instance_color(n, Color(shade * 1.06, shade * 0.98, shade * 0.9))
			n += 1

	mm.visible_instance_count = n
	cmm.visible_instance_count = cn


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
		var grow: float = float(c.size) * (0.4 + fade * 0.6)
		mm.set_instance_transform(n, Transform3D(
			Basis.from_euler(ang).scaled(Vector3.ONE * grow), pos))
		mm.set_instance_color(n, Color(0.52, 0.50, 0.47, fade))
		n += 1
	mm.visible_instance_count = n


func _write_hud() -> void:
	_readout.text = SimUtil.fmt(sim.rubble)

	# The gauge grows from the centre in whichever direction the building is
	# going, and changes colour at the same threshold the bonus is judged on -
	# so "you have lost the clean drop" is visible at the moment it happens
	# rather than on the results screen.
	var span: float = clampf(sim.lean / Tuning.TOPPLE_LIMIT, -1.0, 1.0)
	var half := 296.0
	_lean_fill.position = Vector2(300.0 + (0.0 if span > 0.0 else span * half), 3)
	_lean_fill.size = Vector2(absf(span) * half, 20)
	var danger: float = absf(sim.lean)
	if danger >= Tuning.LEAN_WARN:
		_lean_fill.color = Color(0.92, 0.32, 0.18)
	elif danger >= Tuning.LEAN_WARN * 0.6:
		_lean_fill.color = Color(0.95, 0.72, 0.22)
	else:
		_lean_fill.color = Color(0.45, 0.85, 0.45)

	if _interlude > 0.0:
		_banner.text = _interlude_text
		_banner.visible = true
	else:
		_banner.visible = false

	_hud.text = "SITE %d    SWINGS %d    %d/%d BAYS\nBEST %s at site %d\n%s" % [
		sim.level, sim.swings_left, sim.bays_standing(), sim.bays.size(),
		SimUtil.fmt(best_rubble), best_site, BuildStamp.line(),
	]


# --- save -----------------------------------------------------------------

## Small on purpose. There is no yard yet, so the only thing worth keeping
## between runs is the record - which is also the only reason to start another.
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


# --- input ----------------------------------------------------------------

## Two controls, split by where a touch begins.
##
## The dial takes its own presses through `_gui_input` and calls
## `accept_event()`, so anything reaching here started somewhere else - and
## anything that starts somewhere else is a swipe that moves the crane. That
## includes the area below the dial, where Gideon asked for it, and everywhere
## else besides, because a control with an invisible boundary gets fumbled.
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
		# No sign flip: swiping right moves the crane right, because the site
		# is drawn along -Z and the camera is therefore never turned around.
		sim.nudge(1 if travelled > 0.0 else -1)
		_shake = maxf(_shake, 0.1)
