extends RefCounted

## THE HANDEDNESS GATE. Push the stick right, go right - asserted, not assumed.
##
## This studio has shipped inverted controls in six things now: Captain Run for
## its whole life, Coreward twice, Stillwater, Wildform, the project template,
## and THIS GAME. Gideon's report on the build that had it was *"the driving
## controls almost feel backward but not sure if that is the main issue"* - a
## nagging doubt rather than a complaint, because a fixed camera over
## vehicle-relative controls is correct half the time. The rule has been written
## down in `CRAFT.md` and `POLISH.md` the entire time and has never once
## prevented it, because it was written as advice about a convention rather than
## as a test that fails.
##
## **Why nothing else here catches it.** `test_golden.gd` plays three whole
## demolitions, `test_sim.gd` asserts the machine drives and turns, and
## `run_smoke.gd` boots the real scene and checks the camera is behind the
## machine. Every one of them drives the game through `Sim.drive_dir()` or
## `Sim.drive()`. `drive_dir` takes a bearing in the WORLD and drives the
## machine there correctly, on a mirrored game exactly as on a correct one - the
## bug lives in the two steps either side of it:
##
##   1. `_read_stick()` turning a thumb's position into that bearing, and
##   2. the camera turning a world +X into a screen left or a screen right.
##
## A suite made entirely of policies has no coverage of either, and a contact
## sheet of a machine sliding left while nobody is watching a thumb looks
## exactly like a machine sliding left on purpose. **The one thing no bot in
## this studio does is hold a thumb.** This file holds one.
##
## **It drives `_on_stick_input` and `_on_slew_input` themselves** - the exact
## functions the `gui_input` signal calls - and not `_read_stick`, `_read_slew`,
## `aim_to` or `drive_dir` underneath them. Anything below those handlers takes
## a value already in the game's own coordinates and applies it correctly on a
## mirrored game exactly as on a correct one.
##
## **And it never adds the scene to a tree**, so it never calls
## `get_viewport()`, never processes a frame and never asks whether a node added
## during `SceneTree._initialize()` is inside the tree - a question two files in
## the knowledge base currently answer differently, and a gate that turns red on
## an unsettled engine fact is a gate nobody will trust. The one thing those
## handlers do that looks like it needs a viewport is `accept_event()`, and it
## does not: `Control::accept_event()` is wrapped in `if (is_inside_tree())` in
## every Godot 4 branch (checked against 4.3, 4.4, 4.5 and master), so outside
## the tree it is a silent no-op - not an error, not a warning, nothing in the
## log. That is what lets the real handler run here unchanged. Everything below
## is arithmetic on objects that exist without a tree.


const STEP := 1.0 / 60.0

## How long a thumb is held over. The machine PIVOTS before it drives - that is
## the whole point of the alignment cone - so a flick that only lasts a few
## frames measures the pivot and never reaches the part where the machine goes
## anywhere. Two seconds is comfortably past the pivot and still far short of
## the deck's side wall, which is 17.5 m from the spawn.
const HOLD := 2.0

## How far over the stick is pushed, as a fraction of its radius. Well past the
## dead zone on purpose: a failure here should mean the DIRECTION is wrong, not
## that the push was too gentle to register.
const PUSH := 0.76

## The floor under "it actually went somewhere". Without it, a stick that does
## nothing at all passes both the right-hand and the left-hand assertion, since
## "did not travel left" and "did not travel right" are both true of a machine
## standing still.
const TRAVELLED := 0.5


## A booted game.
##
## `freeze()` boots the world explicitly and restarts the site. `_ready` has not
## fired - nothing is in a tree - so without it `sim` is still null and every
## read below is a non-fatal runtime error that silently deletes the rest of the
## check.
func _game():
	var scene: PackedScene = load("res://src/game/main.tscn")
	var main = scene.instantiate()
	main.freeze(1)
	return main


## Hold a thumb on the drive stick, off to one side, for `HOLD` seconds.
##
## Re-sent every frame, because that is what a held thumb is. `drive_dir` sets a
## throttle and a steer that persist until the next event, so a single drag
## followed by two seconds of silence would leave the machine spinning at full
## lock long after the bearing was reached - which is a fair description of a
## bug, but not of a player.
func _hold_stick(main, side: float) -> void:
	var r: float = main.PAD * 0.5
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = Vector2(r, r)
	main._on_stick_input(down)
	for i in int(round(HOLD / STEP)):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = Vector2(r + side * r * PUSH, r)
		drag.relative = Vector2(side * r * PUSH, 0.0)
		main._on_stick_input(drag)
		main.advance(STEP, STEP)


## Where a world point sits ON SCREEN, as a signed number: positive is right of
## the centre line, negative is left of it.
##
## `transform.affine_inverse() * p` puts the point in the camera's own space,
## where +X is screen right by definition. That is the whole of the projection
## that matters for handedness, it needs no viewport and no frame, and it is the
## quantity a world-coordinate assertion cannot see.
##
## `transform`, never `global_transform`: outside the tree the global one does
## not error, it returns IDENTITY - a plausible wrong answer.
func _screen_x(main, p: Vector3) -> float:
	return (main._cam.transform.affine_inverse() * p).x


## How far the machine travelled ALONG THE SCREEN'S RIGHT, in metres.
##
## The camera here follows the machine, so the machine itself never leaves the
## middle of the frame and its own screen x says nothing. What the player sees
## instead is the room sliding the other way, and what they mean by "it went
## right" is that the travel pointed at screen right. That is this number.
func _travel_right(main, from: Vector3) -> float:
	return main._cam.transform.basis.x.normalized().dot(main._rig.position - from)


func test_the_scene_is_the_game_this_file_thinks_it_is(t: TestHarness) -> void:
	# Every other check here holds a booted Main. If main.tscn stops loading its
	# script, or the two input seams are renamed, those checks bail on their
	# first line and this harness reports a smaller number nobody reads.
	var scene: PackedScene = load("res://src/game/main.tscn")
	t.ok(scene != null, "res://src/game/main.tscn failed to load - this whole gate is inert")
	if scene == null:
		return
	var main = scene.instantiate()
	t.ok(main.has_method("freeze"), "main.tscn did not load its script - read the parse error ABOVE this line")
	t.ok(main.has_method("_on_stick_input"),
		"Main._on_stick_input is gone, so nothing below drives the real stick handler")
	t.ok(main.has_method("_on_slew_input"),
		"Main._on_slew_input is gone, so nothing below drives the real slew handler")
	main.free()


func test_a_thumb_to_the_right_of_the_stick_drives_the_machine_right_on_screen(t: TestHarness) -> void:
	var main = _game()
	var from: Vector3 = main._rig.position
	var room_before := _screen_x(main, Vector3.ZERO)
	_hold_stick(main, 1.0)

	var went := _travel_right(main, from)
	t.gt(absf(went), TRAVELLED,
		"the machine barely moved (%.2f m) in %.1f s on a stick held hard over - the assertions below would be reading noise"
			% [absf(went), HOLD])
	t.gt(went, 0.0,
		"a thumb on the RIGHT of the stick carried the machine %.2f m toward SCREEN LEFT - the driving controls are inverted. A world-coordinate assertion passes in this state, which is why this one is in camera space."
			% went)
	# And the same fact the other way round, which is the one the player
	# actually sees under a camera that follows: drive right and the room goes
	# left past the lens.
	t.lt(_screen_x(main, Vector3.ZERO), room_before,
		"the machine drove right and the middle of the deck did not slide LEFT across the screen (%.2f -> %.2f)"
			% [room_before, _screen_x(main, Vector3.ZERO)])
	main.free()


func test_a_thumb_to_the_left_mirrors_it(t: TestHarness) -> void:
	# The pair that proves the control exists differs in exactly one thing: the
	# sign of the push. A single-direction test passes on a control that is
	# stuck to one side, and on one that always drives toward the ramp.
	var main = _game()
	var from: Vector3 = main._rig.position
	var room_before := _screen_x(main, Vector3.ZERO)
	_hold_stick(main, -1.0)

	var went := _travel_right(main, from)
	t.gt(absf(went), TRAVELLED,
		"the machine barely moved (%.2f m) on a stick held hard over to the left" % absf(went))
	t.lt(went, 0.0,
		"a thumb on the LEFT of the stick carried the machine %.2f m toward SCREEN RIGHT - the driving controls are INVERTED"
			% went)
	t.gt(_screen_x(main, Vector3.ZERO), room_before,
		"the machine drove left and the middle of the deck did not slide RIGHT across the screen (%.2f -> %.2f)"
			% [room_before, _screen_x(main, Vector3.ZERO)])
	main.free()


## THE NDC TEST, as arithmetic.
##
## A Godot camera looks down its own -Z, so a chase camera following a deck laid
## out toward +Z would have its right-hand basis vector pointing at world -X:
## screen right would BE world -X, and every drag would then move the machine
## the wrong way while every world-coordinate assertion in the suite went on
## passing. `CLAUDE.md` states this game draws the room along -Z for exactly
## that reason. This is that sentence, as a number - no GPU, no tree, no frame,
## the camera's own basis is the entire claim.
func test_screen_right_is_world_plus_x(t: TestHarness) -> void:
	var main = _game()
	var right: Vector3 = main._cam.transform.basis.x
	# Normalised first, because a basis carries the node's scale and a dot
	# product against an unnormalised axis reads low for a perfectly correct
	# camera - which is how this same assertion has once been "fixed" by
	# loosening it.
	t.approx(right.length(), 1.0, 0.001,
		"the camera basis is scaled (%.3f), so the assertion below is measuring scale as well as direction"
			% right.length())
	t.gt(right.normalized().x, 0.5,
		"the camera's right-hand vector points at world %s, so screen right is world -X and every control in the game is backwards"
			% str(right.normalized()))
	main.free()


## The slew slider is the other handed control, and it is ABSOLUTE: where the
## thumb sits along the track IS where the boom is asked to point. Right of the
## centre mark must therefore put the boom right of the machine ON SCREEN.
##
## Compared against the MACHINE rather than against the world, because the boom
## is mounted on a thing the camera follows: "the boom is on the right of the
## picture" is the claim, not "the turret angle has a positive sign".
func test_the_slew_slider_swings_the_boom_the_way_the_thumb_went(t: TestHarness) -> void:
	var main = _game()
	var w: float = main.SLEW_W
	var mid: float = main.SLEW_H * 0.5

	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = Vector2(w * 0.5, mid)
	main._on_slew_input(down)

	_slew_to(main, w * 0.86, mid)
	# Long enough for the boom to actually get there: the slew is rate-limited to
	# about a radian a second and the track asks for most of its range.
	main.advance(2.5, STEP)
	var swung := _screen_x(main, _boom_tip_world(main)) - _screen_x(main, main._rig.position)
	t.gt(swung, 0.0,
		"a thumb on the RIGHT of the slew track swung the boom to SCREEN LEFT of the machine (%.2f)"
			% swung)

	# Mirrored on the same booted game, so a boom stuck to one side cannot pass.
	_slew_to(main, w * 0.14, mid)
	main.advance(5.0, STEP)
	swung = _screen_x(main, _boom_tip_world(main)) - _screen_x(main, main._rig.position)
	t.lt(swung, 0.0,
		"a thumb on the LEFT of the slew track left the boom on SCREEN RIGHT of the machine (%.2f)"
			% swung)
	main.free()


## A real drag along the slew track, held where it lands.
func _slew_to(main, x: float, mid: float) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(x, mid)
	drag.relative = Vector2(0.0, 0.0)
	main._on_slew_input(drag)


## Where the boom tip is in the world, through the same conversion the scene
## draws it with.
func _boom_tip_world(main) -> Vector3:
	return main.to_world(main.sim.boom_tip(), 0.0)


## The positive control. A construct that cannot fail is untested, not safe -
## and the way the assertions above go vacuous is for the stick to move nothing
## at all, in which case "did not go left" and "did not go right" are both true
## of a game that has stopped reading the screen.
func test_a_thumb_that_does_not_move_moves_nothing(t: TestHarness) -> void:
	var main = _game()
	var from: Vector3 = main._rig.position

	# Dead centre of the pad, held. This stick is absolute, so the centre is the
	# only place a thumb can rest without asking for anything.
	var r: float = main.PAD * 0.5
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = Vector2(r, r)
	main._on_stick_input(down)
	for i in int(round(HOLD / STEP)):
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = Vector2(r, r)
		drag.relative = Vector2.ZERO
		main._on_stick_input(drag)
		main.advance(STEP, STEP)

	t.approx(main._rig.position.distance_to(from), 0.0, 0.01,
		"a thumb resting on the centre of the stick drove the machine %.3f m, so the assertions above may be reading drift rather than input"
			% main._rig.position.distance_to(from))

	# And the handler must ignore what is not a gesture at all. A key event that
	# steered would mean the type checks above it had stopped discriminating.
	var key := InputEventKey.new()
	key.keycode = KEY_A
	key.pressed = true
	main._on_stick_input(key)
	main._on_slew_input(key)
	var turret_before: float = main.sim.turret_target
	main.advance(0.5, STEP)
	t.approx(main._rig.position.distance_to(from), 0.0, 0.01,
		"a key press through the stick handler moved the machine %.3f m - the type checks in it have stopped discriminating"
			% main._rig.position.distance_to(from))
	t.approx(main.sim.turret_target, turret_before, 0.0001,
		"a key press through the slew handler re-aimed the boom")
	main.free()
