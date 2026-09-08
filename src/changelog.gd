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

const VERSION := "0.1.0"

const RELEASES := [
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
