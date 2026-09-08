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

	_finish()


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
		"world +x projects to the LEFT of the screen: a rightward drag will move the rig the wrong way")


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
