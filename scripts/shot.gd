extends SceneTree

## Take a screenshot of the real game at a chosen moment.
##
##   godot --path . --resolution 540x960 --script res://scripts/shot.gd -- 14.0
##
## NOT headless: this needs a real rendering context, which is the whole point.
## Every other check in this repo runs without a GPU and can therefore tell you
## that the numbers are right and nothing about whether the picture is.
##
## The scene is frozen and advanced through the same seam the tests use, so the
## moment captured is deterministic - the same second of the same street, every
## time. That makes two screenshots taken a week apart comparable, which a
## screenshot of live play never is.

var _main
var _frames := 0
var _seconds := 12.0
var _tag := ""


## The documented form is `-- 45 <state>`, and the old parser was
##   for a in OS.get_cmdline_user_args(): _seconds = float(a)
## which assigned EVERY user argument to `_seconds`. `float("<state>")` is 0.0,
## so the two-argument form photographed the TITLE FRAME and still exited 0 with
## a plausible-looking PNG. First numeric argument is the seconds, first
## non-numeric one is the state/tag - the same split stillwater's shot.gd makes.
func _initialize() -> void:
	var got_seconds := false
	for a in OS.get_cmdline_user_args():
		if a.is_valid_float():
			if not got_seconds:
				_seconds = float(a)
				got_seconds = true
		elif _tag == "":
			_tag = String(a)

	var scene: PackedScene = load("res://src/game/main.tscn")
	_main = scene.instantiate()
	root.add_child(_main)
	# Freeze before advancing, or how far the run has got depends on how long
	# the window took to open.
	_main.freeze()

	# Played rather than watched. A passive run is a building nobody touched,
	# which is a picture of the game not being played.
	var mem := {}
	var step := 1.0 / 60.0
	for i in int(round(_seconds / step)):
		Policies.steer(Policies.WRECKER, _main.sim, mem)
		_main.advance(step, step)


func _process(_delta: float) -> bool:
	# A few frames so the sky, the shadow map and the MultiMesh buffers have
	# actually been drawn once. Capturing on frame one gives a grey rectangle.
	_frames += 1
	if _frames < 5:
		return false
	var img := root.get_texture().get_image()
	var out := "shot" if _tag == "" else "shot_" + _tag
	img.save_png("user://%s.png" % out)
	print("wrote %s/%s.png at t=%.1fs  rubble=%d  cols=%d"
		% [OS.get_user_data_dir(), out, _seconds, _main.sim.rubble, _main.sim.columns_down])
	quit(0)
	return true
