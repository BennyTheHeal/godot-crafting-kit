@tool
class_name CKRecipe
extends Resource
## One way to make something: ingredients in, results out, at a station or by hand.
##
## Ingredient keys are item ids or tags ([code]&"#planks"[/code]: any item tagged "planks",
## see [CKIngredients]). A recipe can also have a [member pattern] (shaped, like a 3x3
## crafting grid), a [member success_chance], [member bonus_results], quality levels, and
## give profession XP.

## Key of the result stacks' data holding the quality level (1 and above; quality 0 = no data).
const QUALITY_KEY := "quality"
## Characters of [member pattern] that mean "empty cell".
const EMPTY_CELLS := " ."

## Stable id, stored in save files. Pick it once and never change it.
@export var id: StringName
## Name shown to players. Empty = the name of the first result item.
@export var display_name: String = ""
## Consumed items, {item_id or #tag: amount}. Shaped recipes may leave it empty: it is
## then counted from the [member pattern] (see [method get_ingredients]).
@export var ingredients: Dictionary[StringName, int] = {}
## Produced items, {item_id: amount}.
@export var results: Dictionary[StringName, int] = {}
## Station id ([member CKStation.station_id]). Empty = crafted by hand, instantly.
@export var station: StringName
## Seconds per craft at a station (multiplied by the station's speed).
@export_range(0.0, 3600.0, 0.1) var duration: float = 0.0
## Free grouping for filters: "weapons", "potions"...
@export var category: StringName

@export_group("Learning")
## Known from the start. Otherwise learned with [method CKCrafting.learn] or by discovery.
@export var known_from_start: bool = true
## Learned automatically the first time the player holds every ingredient.
@export var discover_when_held: bool = true
## Shown in place of the recipe while it is unknown ("Smelt some ore...").
@export var hint: String = ""

@export_group("Shape")
## Rows of a crafting grid, one character per cell, e.g. [code]["  I", " P ", "P  "][/code].
## Spaces and dots are empty cells. Empty = shapeless recipe. The shape may sit anywhere
## in a larger grid ([method CKCrafting.match_grid]).
@export var pattern: PackedStringArray = []
## What each character of [member pattern] stands for: {"P": &"#planks", "I": &"iron_ingot"}.
@export var pattern_keys: Dictionary[String, StringName] = {}
## The left-right mirror of the pattern works too.
@export var mirrored: bool = false

@export_group("Outcome")
## Chance that a craft succeeds. A failed craft uses its ingredients and gives
## [member failure_results] instead of [member results].
@export_range(0.0, 1.0, 0.01) var success_chance: float = 1.0
## Given when a craft fails ("ash", "burnt bread"). Often empty.
@export var failure_results: Dictionary[StringName, int] = {}
## Extra items with their own chance, on successful crafts.
@export var bonus_results: Array[CKBonusResult] = []
## Weights of quality levels 0, 1, 2... for the results, e.g. [code][70, 25, 5][/code].
## Empty = no quality. Quality 1+ is stored in the result stacks' data
## ([code]{"quality": 2}[/code]); quality 0 items are plain items and stack with any.
@export var quality_weights: PackedFloat32Array = []

@export_group("Profession")
## Profession that earns [member xp] and gates [member required_level]. Empty = the station id.
@export var profession: StringName
## Profession XP per craft (failed crafts included).
@export_range(0, 100000) var xp: int = 0
## Profession level needed to make it ([method CKCrafting.get_level]). 0 or 1 = none.
@export_range(0, 100) var required_level: int = 0


static func make(p_id: StringName, p_ingredients: Dictionary, p_results: Dictionary,
		p_station: StringName = &"", p_duration: float = 0.0) -> CKRecipe:
	var recipe := CKRecipe.new()
	recipe.id = p_id
	recipe.ingredients.assign(p_ingredients)
	recipe.results.assign(p_results)
	recipe.station = p_station
	recipe.duration = p_duration
	return recipe


## A shaped recipe: [param p_pattern] rows, [param p_keys] {character: item id or #tag}.
static func make_shaped(p_id: StringName, p_pattern: Array, p_keys: Dictionary, p_results: Dictionary,
		p_station: StringName = &"", p_duration: float = 0.0, p_mirrored: bool = false) -> CKRecipe:
	var recipe := make(p_id, {}, p_results, p_station, p_duration)
	recipe.pattern = PackedStringArray(p_pattern)
	recipe.pattern_keys.assign(p_keys)
	recipe.mirrored = p_mirrored
	return recipe


## The first result: the item the recipe is named and drawn after.
func main_result() -> StringName:
	return results.keys()[0] if not results.is_empty() else &""


func is_shaped() -> bool:
	return not pattern.is_empty()


## Ingredients of one craft, {item_id or #tag: amount}: [member ingredients], or for a
## shaped recipe that leaves them empty, the cells of its [member pattern].
func get_ingredients() -> Dictionary:
	if not ingredients.is_empty() or not is_shaped():
		return ingredients
	var counted := {}
	for row: Array in get_pattern_rows():
		for key: StringName in row:
			if not key.is_empty():
				counted[key] = int(counted.get(key, 0)) + 1
	return counted


## Ingredients (or results) for [param count] crafts.
func scaled(items: Dictionary, count: int) -> Dictionary:
	var scaled_items := {}
	for item_id in items:
		scaled_items[item_id] = items[item_id] * count
	return scaled_items


func get_display_name(database: IKItemDatabase) -> String:
	if not display_name.is_empty():
		return CKText.t(display_name)
	var definition := database.get_item(main_result()) if database != null else null
	return IKText.item_name(definition) if definition != null else String(id)


## Profession earning XP for this recipe: [member profession], or the station id.
func get_profession() -> StringName:
	return profession if not profession.is_empty() else station


# --- Shape -------------------------------------------------------------------------

## The pattern as rows of requirement keys (&"" = empty cell), trimmed to its bounding box.
func get_pattern_rows() -> Array:
	var rows := []
	for line in pattern:
		var row := []
		for character in line:
			row.append(&"" if EMPTY_CELLS.contains(character) else pattern_keys.get(character, StringName("?" + character)))
		rows.append(row)
	return trim_rows(rows)


## Whether the items of a crafting grid make this recipe. [param cells] holds one item id
## per cell (&"" = empty), row by row, [param width] cells per row. Shaped recipes compare
## the shape (anywhere in the grid, mirrored if allowed); shapeless ones need exactly one
## item per filled cell for their ingredients.
func matches_grid(cells: Array, width: int, database: IKItemDatabase) -> bool:
	if width <= 0:
		return false
	if not is_shaped():
		var totals := {}
		var filled := 0
		for cell: StringName in cells:
			if not cell.is_empty():
				totals[cell] = int(totals.get(cell, 0)) + 1
				filled += 1
		var needed := 0
		for key in ingredients:
			needed += int(ingredients[key])
		return filled > 0 and filled == needed and CKIngredients.resolve(ingredients, totals, database).missing.is_empty()
	var grid_rows := []
	for start in range(0, cells.size(), width):
		grid_rows.append(cells.slice(start, mini(start + width, cells.size())))
	var grid := trim_rows(grid_rows)
	var shape := get_pattern_rows()
	if _same_shape(shape, grid, database):
		return true
	if mirrored:
		var flipped := []
		for row: Array in shape:
			var copy := row.duplicate()
			copy.reverse()
			flipped.append(copy)
		return _same_shape(flipped, grid, database)
	return false


## Rows (arrays of keys or item ids, &"" = empty) cut to the smallest box holding every
## filled cell, padded to the same width. No filled cell = [].
static func trim_rows(rows: Array) -> Array:
	var top := -1
	var bottom := -1
	var left := 1 << 30
	var right := -1
	for r in rows.size():
		var row: Array = rows[r]
		for c in row.size():
			if not StringName(row[c]).is_empty():
				top = r if top < 0 else top
				bottom = r
				left = mini(left, c)
				right = maxi(right, c)
	if top < 0:
		return []
	var trimmed := []
	for r in range(top, bottom + 1):
		var row: Array = rows[r]
		var cut := []
		for c in range(left, right + 1):
			cut.append(StringName(row[c]) if c < row.size() else &"")
		trimmed.append(cut)
	return trimmed


func _same_shape(shape: Array, grid: Array, database: IKItemDatabase) -> bool:
	if shape.is_empty() or shape.size() != grid.size():
		return false
	for r in shape.size():
		var want: Array = shape[r]
		var have: Array = grid[r]
		if want.size() != have.size():
			return false
		for c in want.size():
			var key: StringName = want[c]
			var item_id: StringName = have[c]
			if key.is_empty() != item_id.is_empty():
				return false
			if not key.is_empty() and not CKIngredients.matches(key, item_id, database):
				return false
	return true


# --- Outcome -------------------------------------------------------------------------

## True when crafting it involves chance (success, bonus or quality).
func is_random() -> bool:
	return success_chance < 1.0 or not bonus_results.is_empty() or not quality_weights.is_empty()


## Rolls one craft: [code]{"success": bool, "quality": int (-1 = none), "items": [[item_id, amount, data]]}[/code].
## Pass the crafting node's [member CKCrafting.rng] so a seed replays the same outcomes.
func roll(rng: RandomNumberGenerator) -> Dictionary:
	var items := []
	var outcome := {"success": true, "quality": -1, "items": items}
	if success_chance < 1.0 and rng.randf() >= success_chance:
		outcome.success = false
		for item_id in failure_results:
			items.append([item_id, failure_results[item_id], {}])
		return outcome
	var quality := roll_quality(rng)
	outcome.quality = quality
	for item_id in results:
		items.append([item_id, results[item_id], {QUALITY_KEY: quality} if quality > 0 else {}])
	for bonus in bonus_results:
		if bonus != null and not bonus.item_id.is_empty() and rng.randf() < bonus.chance:
			items.append([bonus.item_id, bonus.amount, {}])
	return outcome


## A quality level picked from [member quality_weights]; -1 without quality.
func roll_quality(rng: RandomNumberGenerator) -> int:
	if quality_weights.is_empty():
		return -1
	var total := 0.0
	for weight in quality_weights:
		total += maxf(0.0, weight)
	if total <= 0.0:
		return 0
	var pick := rng.randf() * total
	for level in quality_weights.size():
		pick -= maxf(0.0, quality_weights[level])
		if pick < 0.0:
			return level
	return quality_weights.size() - 1
