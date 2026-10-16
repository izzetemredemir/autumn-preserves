extends RefCounted
## GD-GARDEN · The garden's hand-placed map: 30x17 tiles of 16 px, one 480x270 screen (the last row sits
## 2 px under the bottom edge). Pure data and lookups, no autoloads. Cells are [col, row]; things that span
## several cells list them all. Ground ids are WildGen.T_* so WildMapView's forest_tiles atlas draws them.
##
##   rows 0-1   hedge, the cottage (cols 10-17, rows 0-5) with its door at the bottom (left of centre: the To-Do note)
##   left       apple and quince trees, the beds in a 2-column grid, the compost bin
##   middle     path from the door down to the garden gate in the bottom fence
##   right      road to town (rows 9-10) leaving through the right fence, the walnut tree
## The painted ground (garden_ground.png) follows PATH_COLS / ROAD_ROWS; move them and the painting together.

const W := 30
const H := 17
const TILE := 16
const VIEW_H := 270  ## camera bounds height: one screen
## How far the ground is painted past the map, for wider or taller windows (stretch aspect "expand").
const MARGIN := Vector2i(6, 3)

const T_GRASS := 0
const T_LEAVES := 1
const T_PATH := 4

const HEDGE_ROWS := 2
const HOUSE := Rect2i(10, 0, 8, 6)
const DOOR := [Vector2i(13, 5), Vector2i(14, 5)]
const MAILBOX := Vector2i(11, 6)
const COMPOST := Vector2i(12, 11)
## Tree trunks by type (rules.garden.trees); TREE_SLOTS for types this table doesn't know.
const TREES := {"apple": Vector2i(3, 7), "quince": Vector2i(3, 13), "walnut": Vector2i(24, 15)}
const TREE_SLOTS := [Vector2i(3, 7), Vector2i(3, 13), Vector2i(24, 15)]
## Left cell of each 2x1 bed, in state.garden.beds order (P0 has 4, the P1 upgrade 6).
const BEDS := [Vector2i(7, 8), Vector2i(10, 8), Vector2i(7, 11), Vector2i(10, 11), Vector2i(7, 14), Vector2i(10, 14)]
const PATH_COLS := [13, 14]
const ROAD_ROWS := [9, 10]
const GATE := [Vector2i(13, 16), Vector2i(14, 16)]
const GATE_SIGN := Vector2i(19, 15)
const ROAD_EXIT := [Vector2i(29, 9), Vector2i(29, 10)]
const TOWN_SIGN := Vector2i(27, 11)
## Where Granny appears, by where she comes back from: [cell, facing].
const SPAWN := {
	"door": [Vector2i(13, 6), Vector2i.DOWN],
	"wild": [Vector2i(13, 15), Vector2i.UP],
	"town": [Vector2i(28, 9), Vector2i.LEFT],
}
## Hand-placed decor on the lawn: [cell, frame of garden_decor.png]. Flowers and leaf piles are walked over;
## pumpkins stand (is_open says no) so Granny never steps into one.
const D_PUMPKIN := 0
const D_FLOWERS_RED := 1
const D_FLOWERS_GOLD := 2
const D_LEAVES := 3
const DECOR := [
	[Vector2i(6, 3), D_FLOWERS_RED], [Vector2i(8, 4), D_PUMPKIN], [Vector2i(5, 2), D_LEAVES],
	[Vector2i(20, 3), D_FLOWERS_GOLD], [Vector2i(24, 5), D_FLOWERS_RED], [Vector2i(27, 3), D_PUMPKIN],
	[Vector2i(21, 7), D_LEAVES], [Vector2i(26, 7), D_FLOWERS_GOLD], [Vector2i(19, 12), D_FLOWERS_RED],
	[Vector2i(16, 12), D_PUMPKIN], [Vector2i(17, 12), D_FLOWERS_GOLD], [Vector2i(6, 10), D_FLOWERS_GOLD],
	[Vector2i(1, 15), D_FLOWERS_RED], [Vector2i(21, 12), D_LEAVES], [Vector2i(27, 14), D_PUMPKIN],
	[Vector2i(8, 6), D_FLOWERS_GOLD], [Vector2i(16, 7), D_FLOWERS_RED], [Vector2i(6, 15), D_LEAVES],
]


static func size() -> Vector2i:
	return Vector2i(W, H)


static func spawn(from: String) -> Array:
	return SPAWN.get(from, SPAWN.door)


static func tree_cell(type: String, index: int) -> Vector2i:
	if TREES.has(type):
		return TREES[type]
	return TREE_SLOTS[clampi(index, 0, TREE_SLOTS.size() - 1)]


static func bed_cells(index: int) -> Array:
	var c: Vector2i = BEDS[index]
	return [c, c + Vector2i.RIGHT]


static func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


## Terrain walkability: hedge, cottage, fences and pumpkins block; the gate and the road gap are open.
## Things standing in the garden (trees, beds, signs) are added by the scene.
static func is_open(c: Vector2i) -> bool:
	if not in_map(c) or c.y < HEDGE_ROWS or HOUSE.has_point(c) or is_pumpkin(c):
		return false
	if c in GATE or c in ROAD_EXIT:
		return true
	return c.x > 0 and c.x < W - 1 and c.y < H - 1


static func is_pumpkin(c: Vector2i) -> bool:
	for d in DECOR:
		if d[0] == c and d[1] == D_PUMPKIN:
			return true
	return false


static func is_gate(c: Vector2i) -> bool:
	return c in GATE


static func is_road_exit(c: Vector2i) -> bool:
	return c in ROAD_EXIT


## Ground id for any cell, also outside the map: footstep sounds, and the tiles in the margin around the painted
## ground (wider windows), which keep the path and road going. The lawn is a carpet of fallen leaves.
static func ground(c: Vector2i) -> int:
	if c.x in PATH_COLS and c.y >= HOUSE.end.y:
		return T_PATH
	if c.y in ROAD_ROWS and c.x > PATH_COLS[1]:
		return T_PATH
	if c.y < HEDGE_ROWS or HOUSE.has_point(c):
		return T_GRASS
	return T_LEAVES
