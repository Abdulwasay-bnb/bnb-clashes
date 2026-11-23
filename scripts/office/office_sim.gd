class_name OfficeSim
extends MafiaSim
## MafiaSim's walls and walking graph for the virtual office, which has four levels side by side:
## a point only ever bumps into the walls of its own level, so each level's walls are looked up on
## their own (the office's map is four times the size of BNB Mafia's).

var by_level := {}


## Call after the walls are all in.
func index_walls() -> void:
	by_level.clear()
	for w in walls:
		var l := OfficeFloors.level_of(w.get_center().x)
		if not by_level.has(l): by_level[l] = []
		by_level[l].append(w)


func blocked(p: Vector2, r: float) -> bool:
	for w in by_level.get(OfficeFloors.level_of(p.x), walls):
		if p.x > w.position.x - r and p.x < w.end.x + r and p.y > w.position.y - r and p.y < w.end.y + r: return true
	return false
