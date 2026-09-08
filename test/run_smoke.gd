extends SceneTree

## Smoke test: boots the real scene and plays it.
##
##   godot --headless --script res://test/run_smoke.gd
##
## The pure tests cannot see a wiring bug - a scene that fails to build, a node
## that is never added, a render path that stopped being flushed, a HUD reading
## a field that no longer exists. Those only show up when something actually
## instantiates the game.
##
## Three assertions here carry most of the weight, and all three are for bugs
## that have actually shipped on this project:
##
## 1. **What exists is drawn.** A subsystem that renders nothing and one that
##    does not exist look identical from outside. That cost a full tuning pass
##    on a sibling game - the enemies were invisible while still killing.
## 2. **World +X is on the right of the screen.** A chase camera turned around
##    mirrors X, and a sibling game shipped inverted steering for its whole
##    life because every test drove the seam in world coordinates.
## 3. **The level can be left.** Reaching the end set `over`, `advance()`
##    returned early from then on, and the game froze with a live HUD. Every
##    other test read the state at the end of a level, which is the exact
##    instant that freeze began.

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
	# harness taking over, and `_ready` has not fired yet either, because
	# add_child() during SceneTree._initialize() defers it to the first
	# processed frame. freeze() boots the scene explicitly.
	main.freeze()

	_t.begin("smoke > the scene builds its world")
	_t.ok(main.sim != null, "Sim was never created")
	_t.ok(main.get_node_or_null("Ground") != null, "the site is missing from the scene")
	_t.ok(main.get_node_or_null("Rig") != null, "the crane is missing from the scene")
	_t.ok(main.get_node_or_null("Ball") != null, "the wrecking ball is missing from the scene")
	_t.ok(main.get_node_or_null("Floors") != null, "the building is missing from the scene")
	_t.ok(main.get_node_or_null("Columns") != null, "the columns are missing from the scene")
	_t.ok(main.get_node_or_null("Hud") != null, "the HUD layer is missing")
	_t.ok(main.get_node_or_null("Neighbour-1") != null,
		"the neighbouring block is missing - the thing the whole game is about not hitting")

	_check_the_building_is_drawn(main)
	_check_the_controls_are_anchored(main)
	_check_screen_right(main)

	# Play it properly rather than passively, or the drawing paths that only
	# fire on an impact are never reached and this proves the game boots rather
	# than that it works.
	main.freeze()
	var peak_debris := 0
	var mem := {}
	var guard := 0
	while not main.sim.over and guard < 6000:
		Policies.steer(Policies.DEMOLISHER, main.sim, mem)
		main.advance(1.0 / 60.0, 1.0 / 60.0)
		peak_debris = maxi(peak_debris, main._debris.multimesh.visible_instance_count)
		guard += 1

	_t.begin("smoke > a whole demolition happened")
	_t.eq(main.sim.over, true, "the demolition never finished")
	_t.eq(main.sim.won, true, "the balanced policy failed the first building")
	_t.gt(float(main.sim.floors_down), 0.0, "nothing came down")
	_t.gt(float(main.sim.rubble), 0.0, "nothing was earned")

	_t.begin("smoke > impacts produced debris")
	_t.gt(float(peak_debris), 0.0, "a building came down and nothing was thrown into the air")
	_t.lt(float(peak_debris), float(main.DEBRIS_POOL) + 0.5, "more debris was drawn than the pool holds")

	_t.begin("smoke > nothing is drawn once the building is gone")
	_t.eq(main._floors.multimesh.visible_instance_count, 0,
		"floors are still being drawn after every bay came down")
	_t.eq(main._columns.multimesh.visible_instance_count, 0,
		"columns are still being drawn after every bay came down")

	_t.begin("smoke > the HUD reflects the demolition")
	_t.ok(main._hud.text.contains("SITE"), "the HUD is not being written")
	_t.ok(main._hud.text.contains(str(main.sim.swings_left)),
		"the HUD swing count disagrees with the demolition")
	_t.ok(main._readout.text == SimUtil.fmt(main.sim.rubble),
		"the rubble readout disagrees with the demolition")

	_check_the_site_can_be_left(main)

	_finish()


## What the model says is standing must be what is drawn, cell for cell.
func _check_the_building_is_drawn(main) -> void:
	_t.begin("smoke > the building on screen is the building in the model")
	main.freeze()
	var expected := 0
	for b in main.sim.bays:
		expected += int(b.floors)
	_t.eq(main._floors.multimesh.visible_instance_count, mini(expected, main.FLOOR_POOL),
		"the floors drawn do not match the floors standing")
	_t.eq(main._columns.multimesh.visible_instance_count, main.sim.bays_standing(),
		"the columns drawn do not match the bays standing")

	# And after one bay goes, exactly that bay's worth must stop being drawn.
	var floors: int = main.sim.bays[1].floors
	var before: int = main._floors.multimesh.visible_instance_count
	var guard := 0
	while main.sim.bays[1].standing and guard < 3000:
		Policies.work_bay(main.sim, 1)
		main.advance(1.0 / 60.0, 1.0 / 60.0)
		guard += 1
	_t.eq(main._floors.multimesh.visible_instance_count, before - floors,
		"a bay came down and the floors drawn did not change by exactly its height")


## The controls must be ANCHORED to the viewport, never placed at a literal
## coordinate.
##
## A structural assertion, because the bug it guards against is invisible at
## the size the tests run: the project stretches with `aspect = "expand"`, so
## on a 19.5:9 phone the canvas is about 1080x2340 while the base is 1080x1920.
## Two thumb pads laid out against the literal 1920 drew hundreds of pixels
## high, and the report was "the icons are about half an inch too high". A
## headless run uses the base size, where the wrong layout and the right one
## are identical - so no screenshot or coordinate check taken here could ever
## have caught it. What CAN be checked is the property that makes it impossible.
func _check_the_controls_are_anchored(main) -> void:
	_t.begin("smoke > the controls are anchored, not placed")
	var stick: Control = main._stick
	_t.eq(stick.anchor_bottom, 1.0,
		"the crane dial is not anchored to the bottom of the viewport - it will drift on a tall screen")
	_t.eq(stick.anchor_top, 1.0,
		"the crane dial is anchored to the TOP, so its distance from the bottom depends on the aspect")
	_t.lt(stick.offset_bottom, 0.0,
		"the crane dial is offset downward from its anchor and will sit off the bottom of the screen")
	_t.ok(stick.gui_input.get_connections().size() > 0,
		"the dial does not handle its own input, so its hit box is a second source of truth")
	_t.eq(stick.mouse_filter, Control.MOUSE_FILTER_STOP,
		"the dial does not consume its own touches, so a slew will also register as a swipe")


## The one test that catches inverted controls.
##
## Everything else drives the input seam in world coordinates, and `aim(0.5)`
## putting `yaw` at 0.5 passes just as happily when the camera mirrors the
## axis. This asks the camera where a point to the crane's right actually lands.
func _check_screen_right(main) -> void:
	_t.begin("smoke > world +x is on the right of the screen")
	var cam: Camera3D = main._cam
	var here := Vector3(0.0, 1.0, main.wz(Tuning.FACE_Z))
	var to_the_right := here + Vector3(2.0, 0.0, 0.0)

	# `transform`, NOT `global_transform`. A node added during
	# SceneTree._initialize() is not in the tree yet, and global_transform does
	# not error for that - it returns IDENTITY, a plausible-looking wrong
	# answer. Node3D.look_at at least has the decency to fail.
	var inv := cam.transform.affine_inverse()
	var a := inv * here
	var b := inv * to_the_right
	_t.lt(a.z, 0.0, "the building is behind the camera - the camera is facing the wrong way")
	_t.gt(b.x - a.x, 0.0,
		"world +x projects to the LEFT of the screen: dragging right will slew the boom the wrong way")

	# And the other half, now that the drag aims: a POSITIVE yaw must put the
	# ball at greater x. Asserting the camera alone would pass on a crane whose
	# sign was inverted, and the crane alone would pass on a mirrored camera.
	# The bug lives in whichever of the two the test does not look at.
	main.freeze()
	main.sim.aim_to(Tuning.YAW_MAX)
	main.advance(0.8, 1.0 / 60.0)
	_t.gt(main.sim.ball_x() - main.sim.x, 0.0,
		"aiming to a positive yaw swung the ball to the player's LEFT")
	_t.gt(main._ball.position.x - main._rig.position.x, 0.0,
		"the ball is DRAWN on the opposite side from where the simulation put it")
	main.freeze()


## The assertion the first build did not have, and the one that would have
## caught the only bug Gideon hit. Driven through the REAL scene, because the
## missing code was in the renderer's handler and not in Sim.
func _check_the_site_can_be_left(main) -> void:
	_t.begin("smoke > a finished site starts the next one")
	_t.eq(main.sim.over, true, "the demolition is not over, so there is nothing to leave")
	var site: int = main.sim.level
	var banked: int = main.sim.rubble

	main.advance(main.INTERLUDE_SECONDS * 0.4, 1.0 / 60.0)
	_t.ok(main._banner.visible, "nothing on screen says what happened to the building")
	_t.eq(main.sim.level, site, "the next site started before the banner was readable")

	main.advance(main.INTERLUDE_SECONDS, 1.0 / 60.0)
	_t.eq(main.sim.over, false,
		"the game is still frozen after the interlude - this is the bug that shipped")
	_t.eq(main.sim.level, site + 1, "the next site never started")
	_t.eq(main.sim.rubble, banked, "the haul was lost moving between sites")
	_t.ok(not main._banner.visible, "the banner never went away")
	_t.gt(float(main._floors.multimesh.visible_instance_count), 0.0,
		"the next site arrived with nothing standing on it")


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
