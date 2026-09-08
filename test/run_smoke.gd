extends SceneTree

## Smoke test: boots the real scene and plays it.
##
##   godot --headless --script res://test/run_smoke.gd
##
## The pure tests in run_tests.gd cannot see a wiring bug - a scene that fails
## to build, a node that is never added, a render path that stopped being
## flushed, a HUD reading a field that no longer exists. Those only show up
## when something actually instantiates the game.
##
## Two assertions here carry most of the weight:
##
## 1. **The number of instances drawn must match the number that exist.** A
##    subsystem that renders nothing and a subsystem that does not exist look
##    identical from outside. That exact bug cost a full tuning pass on a
##    sibling game - the enemies were invisible while still charging, still
##    costing crew and still being killed, and it read as a balance problem.
##
## 2. **World +X must project to the RIGHT of the screen.** A chase camera
##    placed behind an object moving toward +Z has to be turned around to see
##    it, which mirrors X - and a sibling game shipped with inverted steering
##    for its entire life because every test drove the seam in world
##    coordinates, which is the layer underneath the bug. The only thing that
##    catches it is asking where a point lands in the frame.

var _t := TestHarness.new()


func _initialize() -> void:
	var scene: PackedScene = load("res://src/game/main.tscn")
	_t.begin("smoke > the scene loads")
	_t.ok(scene != null, "main.tscn failed to load")
	if scene == null:
		_finish()
		return

	var main = scene.instantiate()
	root.add_child(main)

	# Freeze first, then step. Real frames run between a scene loading and a
	# harness taking over, so without this every number would move with the
	# speed of the machine - and `_ready` has not fired yet either, because
	# add_child() during SceneTree._initialize() defers it to the first
	# processed frame. freeze() boots the scene explicitly, which is why the
	# assertions come after it.
	main.freeze()

	_t.begin("smoke > the scene builds its world")
	_t.ok(main.sim != null, "Sim was never created")
	_t.ok(main.get_node_or_null("Road") != null, "the road is missing from the scene")
	_t.ok(main.get_node_or_null("Rig") != null, "the rig is missing from the scene")
	_t.ok(main.get_node_or_null("Ball") != null, "the wrecking ball is missing from the scene")
	_t.ok(main.get_node_or_null("Floors") != null, "the building floors layer is missing")
	_t.ok(main.get_node_or_null("Hud") != null, "the HUD layer is missing")

	_check_screen_right(main)

	# Play it properly rather than passively, or the drawing paths that only
	# fire on an impact are never reached and the smoke test proves the game
	# boots rather than that it works.
	# Debris is watched DURING the run, not after it. A chunk lives about a
	# second, and asserting on the count at the end of eighteen seconds only
	# tests whether the last impact happened to be recent - which is a test of
	# the level layout wearing a render test's clothes.
	var peak_debris := 0
	var mem := {}
	for i in 1080:  # eighteen seconds at sixty steps
		Policies.steer(Policies.WRECKER, main.sim, mem)
		main.advance(1.0 / 60.0, 1.0 / 60.0)
		peak_debris = maxi(peak_debris, main._debris.multimesh.visible_instance_count)

	var s: Dictionary = main.sim.state()

	_t.begin("smoke > eighteen seconds of play happened")
	_t.gt(s["distance"], 120.0, "the rig barely moved in eighteen seconds")
	_t.gt(float(s["buildings"]), 0.0, "nothing was built on the street")
	_t.gt(float(s["floors_felled"]), 0.0,
		"a full run of the aiming policy knocked nothing down - the ball is not connecting")

	_t.begin("smoke > everything that exists is actually drawn")
	var drawn_floors: int = main._floors.multimesh.visible_instance_count
	var live_floors := 0
	for b in main.sim.buildings:
		live_floors += int(b.left)
	_t.gt(float(drawn_floors), 0.0,
		"buildings exist in the model but no floors are drawn - visible_instance_count is not being set")
	_t.eq(drawn_floors, mini(live_floors, main.FLOOR_POOL),
		"drawn floors do not match the floors still standing")

	var drawn_walls: int = main._barricades.multimesh.visible_instance_count
	var live_walls := 0
	for w in main.sim.barricades:
		if not w.taken:
			live_walls += 1
	_t.eq(drawn_walls, mini(live_walls * 3, main.BARRICADE_POOL),
		"drawn barricade posts do not match the barricades standing")

	_t.begin("smoke > the ball is drawn where the simulation says it is")
	_t.approx(main._ball.position.x, main.sim.ball_x(), 0.001, "the ball is drawn at the wrong x")
	_t.approx(main._ball.position.y, main.sim.ball_y(), 0.001, "the ball is drawn at the wrong height")
	_t.approx(main._ball.position.z, main.wz(main.sim.ball_z()), 0.001,
		"the ball is drawn at the wrong z - the world axis mapping was bypassed")
	_t.ok(main._chain.visible, "the chain is not being drawn")

	_t.begin("smoke > impacts produced debris")
	_t.gt(float(peak_debris), 0.0,
		"floors came down and nothing was thrown into the air")
	_t.lt(float(peak_debris), float(main.DEBRIS_POOL) + 0.5,
		"more debris was drawn than the pool holds")

	_t.begin("smoke > the HUD reflects the run")
	_t.ok(main._hud.text.contains("STREET"), "the HUD is not being written")
	_t.ok(main._hud.text.contains(str(main.sim.lives)), "the HUD lives count disagrees with the run")
	_t.ok(main._readout.text == SimUtil.fmt(main.sim.rubble), "the rubble readout disagrees with the run")
	_t.gt(main._meter_fill.size.x, 0.0, "the power meter never filled despite rubble being earned")

	_check_the_controls_are_anchored(main)
	_check_the_street_can_be_left(main)

	_finish()


## The controls must be ANCHORED to the viewport, never placed at a literal
## coordinate.
##
## This is a structural assertion rather than a behavioural one, because the
## bug it guards against is invisible at the size the tests run. The project
## stretches with `aspect = "expand"`, which keeps the base WIDTH and extends
## the HEIGHT - so on a 19.5:9 phone the canvas is about 1080x2340 while the
## base is 1080x1920. Two thumb pads laid out against the literal 1920 drew
## hundreds of pixels above where they belonged, and the report was "the icons
## are about half an inch too high".
##
## A headless run uses the base size, where the wrong layout and the right one
## are identical - so no screenshot and no coordinate check taken here could
## ever have caught it. What CAN be checked is the property that makes it
## impossible: the control resolves its position from the viewport's edge.
func _check_the_controls_are_anchored(main) -> void:
	_t.begin("smoke > the controls are anchored, not placed")
	var stick: Control = main._stick
	_t.eq(stick.anchor_bottom, 1.0,
		"the crane dial is not anchored to the bottom of the viewport - it will drift on a tall screen")
	_t.eq(stick.anchor_top, 1.0,
		"the crane dial is anchored to the TOP, so its distance from the bottom depends on the aspect ratio")
	_t.lt(stick.offset_bottom, 0.0,
		"the crane dial is offset downward from its anchor and will sit off the bottom of the screen")

	# And it must own its own touches. The same shipped bug had a second half:
	# a hand-rolled hit test scaled touches into a coordinate space of its own,
	# so the drawn control and the region that responded disagreed with each
	# other as well as with the screen.
	_t.ok(stick.gui_input.get_connections().size() > 0,
		"the dial does not handle its own input, so its hit box is a second source of truth")
	_t.eq(stick.mouse_filter, Control.MOUSE_FILTER_STOP,
		"the dial does not consume its own touches, so a slew will also register as a swipe")


## The assertion the first build did not have, and the one that would have
## caught the only bug Gideon hit.
##
## Reaching the end of a street sets `over`, and from that moment `advance()`
## returns early. If nothing clears it the game sits frozen with a live HUD -
## which on a phone is indistinguishable from a crash. Every other check here
## plays a street and reads the state at the end, which is precisely the
## instant the freeze starts, so the whole suite was blind to it.
##
## This drives the REAL scene rather than the simulation, because the thing
## that was missing lived in the renderer's handler, not in Sim.
func _check_the_street_can_be_left(main) -> void:
	_t.begin("smoke > a finished street starts the next one")
	main.freeze()
	var mem := {}
	var guard := 0
	while not main.sim.over and guard < 6000:
		Policies.steer(Policies.WRECKER, main.sim, mem)
		main.advance(1.0 / 60.0, 1.0 / 60.0)
		guard += 1
	_t.eq(main.sim.over, true, "the street never ended")
	_t.eq(main.sim.won, true, "the aiming policy did not finish street one")

	# Annotated, not inferred. `main` is an untyped instantiated scene, so
	# everything reached through it is a Variant and `:=` cannot infer from
	# one - the same trap as reading a value out of a Dictionary.
	var street: int = main.sim.level
	var rubble: int = main.sim.rubble

	# Halfway through the interlude the world is still held and the banner is
	# up; the player is reading it.
	main.advance(main.INTERLUDE_SECONDS * 0.5, 1.0 / 60.0)
	_t.ok(main._banner.visible, "nothing on screen says the street was cleared")
	_t.eq(main.sim.level, street, "the next street started before the banner was readable")

	main.advance(main.INTERLUDE_SECONDS, 1.0 / 60.0)
	_t.eq(main.sim.over, false,
		"the game is still frozen after the interlude - this is the bug that shipped")
	_t.eq(main.sim.level, street + 1, "the next street never started")
	_t.eq(main.sim.rubble, rubble, "the haul was lost moving between streets")
	_t.ok(not main._banner.visible, "the banner never went away")

	main.advance(4.0, 1.0 / 60.0)
	_t.gt(main.sim.distance, 30.0, "the next street does not move when the frame loop runs")


## The one test that catches inverted steering.
##
## Everything else in the suite drives the steering seam in world coordinates,
## and `steer(1.5)` putting `x` at 1.5 passes just as happily when the camera
## is mirroring the axis. This asks the camera where a point to the rig's right
## actually lands in the frame.
func _check_screen_right(main) -> void:
	_t.begin("smoke > world +x is on the right of the screen")
	var cam: Camera3D = main._cam
	var here := Vector3(0.0, 1.0, main.wz(main.sim.distance))
	var to_the_right := here + Vector3(2.0, 0.0, 0.0)

	# Projected by hand rather than through unproject_position, which needs a
	# viewport with a size - the headless renderer has one, but relying on it
	# would make this test about the harness instead of about the camera.
	#
	# `transform`, NOT `global_transform`. A node added during
	# SceneTree._initialize() is not in the tree yet, and global_transform
	# does not error for that - it prints a condition failure and returns
	# IDENTITY, which is a plausible-looking wrong answer rather than a
	# refusal. The camera then appears to sit at the origin facing -Z and the
	# assertion fails for a reason that has nothing to do with what it tests.
	# Node3D.look_at at least has the decency to error. The camera is a direct
	# child of a root that never moves, so the local transform is the global
	# one here.
	var inv := cam.transform.affine_inverse()
	var a := inv * here
	var b := inv * to_the_right

	_t.lt(a.z, 0.0, "the reference point is behind the camera - the camera is facing the wrong way")
	_t.gt(b.x - a.x, 0.0,
		"world +x projects to the LEFT of the screen: a rightward drag will aim the crane the wrong way")

	# And the other half of the same question, now that the drag aims rather
	# than steers: a POSITIVE yaw has to put the ball at greater x. Asserting
	# the camera alone would pass happily on a crane whose sign was inverted,
	# and asserting the crane alone would pass happily on a mirrored camera.
	# The bug lives in whichever of the two the test does not look at.
	main.freeze()
	main.sim.aim_to(Tuning.YAW_MAX)
	main.advance(0.8, 1.0 / 60.0)
	_t.gt(main.sim.ball_x() - main.sim.x, 0.0,
		"aiming to a positive yaw swung the ball to the player's LEFT")
	_t.gt(main._ball.position.x - main._rig.position.x, 0.0,
		"the ball is DRAWN on the opposite side from where the simulation put it")
	main.freeze()


func _finish() -> void:
	print("")
	if _t.failures.is_empty():
		print("  smoke: %d assertions, all passing" % _t.checks)
		quit(0)
		return
	for f in _t.failures:
		print("  FAIL  %s" % f)
	print("")
	print("  smoke: %d assertions, %d FAILED" % [_t.checks, _t.failures.size()])
	quit(1)
