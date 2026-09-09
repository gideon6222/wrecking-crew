class_name Changelog
extends RefCounted

## What changed, in the player's terms.
##
## The build stamp answers "did my update land". It cannot answer "what is
## actually different", which after a few sessions of work is the question that
## matters more - and a commit log is the wrong shape for it, being written for
## whoever maintains the code.
##
## Rules for entries: describe what the player can now do or see, not what was
## refactored; one line each; newest first. Add this from day one. On an
## earlier game it arrived far too late to be as useful as it should have been.

const VERSION := "0.4.0"

const RELEASES := [
	{
		"version": "0.4.0",
		"date": "2026-09-08",
		"title": "Down in the basement",
		"notes": [
			"You are inside a parking level now, driving a wrecking machine around a room full of columns.",
			"Left thumb drives, right thumb swings the boom. The ball is on a chain and nothing aims it - you move it by moving the machine.",
			"Damage is SPEED. Nudging a column does nothing; whipping the ball round at ten metres a second takes a chunk out.",
			"Break the columns and the infill walls. The support gauge at the top is how much is still holding the slab up.",
			"Take out enough and the whole thing lets go - and then you have seconds to reach the ramp before it comes down on you.",
			"Concrete, dust and a real captured environment lighting the room.",
		],
	},
	{
		"version": "0.3.0",
		"date": "2026-09-08",
		"title": "Bring it down on purpose",
		"notes": [
			"No more driving. Each site is one condemned building and you have a fixed number of swings.",
			"Break the columns at the base. Every bay you drop shifts the load, and the gauge at the top shows which way it is going.",
			"Take one side first and it goes over onto the block next door - that is a failed demolition however much came down.",
			"Drop it straight and you get the clean bonus, which is worth more than the whole building.",
			"Columns are not all the same. The bright ones are one swing from going.",
			"Wide buildings cannot be reached from one spot - swipe to move the crane along the site.",
		],
	},
	{
		"version": "0.2.1",
		"date": "2026-09-08",
		"title": "A dial you can actually hit",
		"notes": [
			"Fixed: the controls were drawn well above where they responded. Both are now in the same place.",
			"The lane buttons are gone. There is a crane dial at the bottom instead - drag it to slew the boom.",
			"The dial draws the machine from above, with the boom where you have pointed it and the ball where it actually is.",
			"Swipe anywhere else, including below the dial, to move the rig a lane.",
		],
	},
	{
		"version": "0.2.0",
		"date": "2026-09-08",
		"title": "You swing the crane now",
		"notes": [
			"Drag anywhere to slew the crane. The boom points where you drag; the ball trails it and swings past.",
			"Two pads at the bottom move the rig between three lanes.",
			"Pointing at a building is not enough - the ball only reaches a kerb once it is really travelling.",
			"Fewer barricades. They are something to watch for now, not the job.",
			"The camera follows the ball as well as the rig, so you can see where the swing is going.",
		],
	},
	{
		"version": "0.1.1",
		"date": "2026-09-08",
		"title": "The street ends properly",
		"notes": [
			"Fixed: reaching the end of a street froze the game.",
			"Clearing a street now rolls straight into the next one, keeping your haul, your power and your lives.",
			"Running out of lives starts a fresh run from street one.",
		],
	},
	{
		"version": "0.1.0",
		"date": "2026-09-08",
		"title": "First street",
		"notes": [
			"Drive the rig down a condemned street and take the buildings down.",
			"The ball swings on the boom about a second behind you - drag AWAY from the kerb you want, then back into it.",
			"A hit throws the ball the other way, so a street can be chained left to right to left.",
			"Barricades block half the road: swing through them, or take the gap and give up the aim.",
			"Rubble fills the meter; a full meter is another floor per swing for the rest of the run.",
			"Your best haul is kept between runs.",
		],
	},
]
