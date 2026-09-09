extends SceneTree

## Smoke test: boots the real scene and plays it.
##
## The pure tests cannot see a wiring bug - a scene that fails to build, a node
## never added, a render path that stopped being flushed, a HUD reading a field
## that no longer exists. Those only show up when something instantiates the
## game.
##
## Three of these are for bugs that actually shipped on this project: what
## exists must be drawn; the controls must resolve from the viewport edge
## rather than a literal screen size; and a finished level must start the next.

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
	main.freeze()

	_t.begin("smoke > the scene builds the room")
	_t.ok(main.sim != null, "Sim was never created")
	for n in ["Deck", "Roof", "Rig", "Ball", "Columns", "Walls", "Dust", "Hud"]:
		_t.ok(main.get_node_or_null(n) != null, "%s is missing from the scene" % n)

	_check_the_room_is_drawn(main)
	_check_the_controls_are_anchored(main)
	_check_the_camera_is_behind_the_machine(main)

	# Played rather than watched, or the drawing paths that only fire on an
	# impact are never reached and this proves the game boots rather than that
	# it works.
	main.freeze(2)
	var peak_debris := 0
	var mem := {}
	var guard := 0
	while not main.sim.over and guard < 7000:
		Policies.steer(Policies.WRECKER, main.sim, mem)
		main.advance(1.0 / 60.0, 1.0 / 60.0)
		peak_debris = maxi(peak_debris, main._debris.multimesh.visible_instance_count)
		guard += 1

	_t.begin("smoke > a whole demolition happened")
	_t.eq(main.sim.over, true, "the demolition never finished")
	_t.gt(float(main.sim.columns_down), 0.0, "no columns came down")
	_t.gt(float(main.sim.rubble), 0.0, "nothing was earned")
	_t.eq(main.sim.collapsing, true, "the slab never let go")

	_t.begin("smoke > impacts produced debris")
	_t.gt(float(peak_debris), 0.0, "columns came down and nothing was thrown into the air")
	_t.lt(float(peak_debris), float(main.DEBRIS_POOL) + 0.5,
		"more debris was drawn than the pool holds")

	_t.begin("smoke > the HUD reflects the demolition")
	_t.ok(main._hud.text.contains("LEVEL"), "the HUD is not being written")
	_t.ok(main._readout.text == SimUtil.fmt(main.sim.rubble),
		"the rubble readout disagrees with the demolition")
	_t.lt(main._gauge_fill.size.x, 574.0, "the support gauge is still full after a demolition")

	_check_the_level_can_be_left(main)
	_finish()


## What the model says is standing must be what is drawn, one for one.
func _check_the_room_is_drawn(main) -> void:
	_t.begin("smoke > the room on screen is the room in the model")
	main.freeze()
	_t.eq(main._columns.multimesh.visible_instance_count, main.sim.columns.size(),
		"the columns drawn do not match the columns standing")
	_t.eq(main._walls.multimesh.visible_instance_count, main.sim.walls.size(),
		"the panels drawn do not match the panels standing")

	var before: int = main._columns.multimesh.visible_instance_count
	main.sim.columns[0].standing = false
	main.advance(1.0 / 60.0, 1.0 / 60.0)
	_t.eq(main._columns.multimesh.visible_instance_count, before - 1,
		"a column came down and the same number are still being drawn")
	main.freeze()


## Structural, because the bug it guards against is invisible at the size the
## tests run: the project stretches with `aspect = "expand"`, so on a 19.5:9
## phone the canvas is about 1080x2340 while the base is 1080x1920. Controls
## laid out against the literal 1920 drew hundreds of pixels high, and the
## report was "the icons are about half an inch too high". A headless run uses
## the base size, where the wrong layout and the right one are identical - so
## no screenshot taken here could catch it. The property CAN be checked.
func _check_the_controls_are_anchored(main) -> void:
	_t.begin("smoke > the controls are anchored, not placed")
	for pad in [main._stick, main._slew]:
		_t.eq(pad.anchor_bottom, 1.0,
			"%s is not anchored to the bottom - it will drift on a tall screen" % pad.name)
		_t.eq(pad.anchor_top, 1.0,
			"%s is anchored to the TOP, so its distance from the bottom follows the aspect" % pad.name)
		_t.lt(pad.offset_bottom, 0.0, "%s will sit off the bottom of the screen" % pad.name)
		_t.ok(pad.gui_input.get_connections().size() > 0,
			"%s does not handle its own input, so its hit box is a second source of truth" % pad.name)
		_t.eq(pad.mouse_filter, Control.MOUSE_FILTER_STOP,
			"%s does not consume its own touches" % pad.name)
	# And they must not overlap, or a thumb on one drives the other.
	_t.lt(main._stick.anchor_left, main._slew.anchor_left + 0.001,
		"the drive stick is not on the left of the slew slider")
	# The slew control is a SLIDER: wider than it is tall, because it controls
	# one dimension and the width is what makes it precise. It was a dial for
	# two builds - a two-dimensional control for a one-dimensional quantity.
	_t.gt(main._slew.size.x, main._slew.size.y,
		"the slew control is not wider than it is tall - it has gone back to being a dial")


## The camera has to be BEHIND the machine and looking at it. A chase camera
## that ends up in front mirrors the picture, and a sibling game shipped
## inverted steering for its whole life because every test drove the input seam
## in world coordinates - the layer that bug lives underneath.
func _check_the_camera_is_behind_the_machine(main) -> void:
	_t.begin("smoke > the camera is behind the machine, looking in")
	main.freeze()
	var cam: Camera3D = main._cam
	var rig: Node3D = main._rig
	# `transform`, NOT `global_transform`: a node added during
	# SceneTree._initialize() is not in the tree yet, and global_transform does
	# not error for that - it returns IDENTITY, a plausible wrong answer.
	var inv := cam.transform.affine_inverse()
	var machine: Vector3 = inv * rig.position
	_t.lt(machine.z, 0.0, "the machine is behind the camera")
	_t.lt(absf(machine.x), 6.0, "the machine is off the side of the frame")
	_t.gt(cam.transform.origin.y, rig.position.y, "the camera is below the machine")

	# Driving forward must carry the machine AWAY from where the camera was,
	# never toward it.
	var eye := cam.transform.origin
	var start: float = eye.distance_to(rig.position)
	for i in 60:
		main.sim.drive_dir(Vector2(0.0, 1.0), 1.0)
		main.advance(1.0 / 60.0, 1.0 / 60.0)
	_t.gt(eye.distance_to(main._rig.position), start,
		"driving forward moved the machine toward where the camera was - the axes are mirrored")
	main.freeze()


## The assertion an earlier build did not have, and the one that would have
## caught the only bug Gideon hit. Driven through the REAL scene, because the
## missing code was in the renderer's handler and not in Sim.
func _check_the_level_can_be_left(main) -> void:
	_t.begin("smoke > a finished level starts the next one")
	_t.eq(main.sim.over, true, "the demolition is not over, so there is nothing to leave")
	var level: int = main.sim.level
	var won: bool = main.sim.won

	main.advance(main.INTERLUDE_SECONDS * 0.4, 1.0 / 60.0)
	_t.eq(main.sim.level, level, "the next level started before the banner was readable")

	main.advance(main.INTERLUDE_SECONDS, 1.0 / 60.0)
	_t.eq(main.sim.over, false,
		"the game is still frozen after the interlude - this is the bug that shipped")
	if won:
		_t.eq(main.sim.level, level + 1, "the next level never started after getting out")
	else:
		_t.eq(main.sim.level, 1, "being crushed did not send the run back to the first level")
	_t.gt(float(main._columns.multimesh.visible_instance_count), 0.0,
		"the next level arrived with nothing standing in it")


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
