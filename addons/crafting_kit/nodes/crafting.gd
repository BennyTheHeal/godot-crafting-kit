class_name CKCrafting
extends Node
## What the player knows how to make, profession levels, and crafting by hand or in a grid.
##
## Every craft is one [IKTransaction]: ingredients are taken and results given together,
## or nothing changes. Recipes made at a station go through [CKStation] instead.
## [codeblock]
## crafting.watch(bag.container)   # learn recipes when their ingredients are picked up
## var result := crafting.craft(&"oak_planks", 2, bag.container)
## if not result.ok:
##     status.text = CKText.result_message(result)
## [/codeblock]

signal recipe_learned(recipe: CKRecipe)
## Emitted after every successful hand or grid craft (components made by auto-craft too).
signal crafted(recipe: CKRecipe, count: int)
signal changed
## [param count] crafts failed their [member CKRecipe.success_chance] (ingredients used).
signal craft_failed(recipe: CKRecipe, count: int)
signal xp_gained(profession: StringName, amount: int, total: int)
## Emitted once per level gained. New recipes may be unlocked: see [method get_recipes_unlocked_at].
signal level_up(profession: StringName, level: int)

const DATA_VERSION := 2
## How deep auto-craft looks for components of components.
const MAX_COMPONENT_DEPTH := 6

## Rolls successes, bonuses and qualities. Seed it ([member rng_seed]) to replay the same outcomes.
var rng := RandomNumberGenerator.new()

@export var book: CKRecipeBook
## Item definitions, for names in the UI. Defaults to the first watched container's database.
@export var database: IKItemDatabase
## False: every recipe is known (no learning in your game).
@export var use_learning: bool = true
## Craft the missing components first, from known hand recipes without chance
## (a sword asks for planks: the logs in the bag are turned into planks in the same transaction).
@export var auto_craft: bool = false
## Crafting an unknown recipe from a grid teaches it (players experiment). False: refused.
@export var learn_from_grid: bool = true

@export_group("Professions")
## Total profession XP needed for levels 2, 3, 4... (level 1 needs none).
@export var level_thresholds: PackedInt32Array = [100, 250, 450, 700, 1000, 1400, 1900, 2500, 3200]

@export_group("Randomness")
## Seed of [member rng]: the same seed gives the same successes, bonuses and qualities. 0 = random.
@export var rng_seed: int = 0:
	set(value):
		rng_seed = value
		if value != 0:
			rng.seed = value

var _known: Dictionary = {}  # recipe id -> true
var _xp: Dictionary = {}  # profession -> total XP
var _watched: Array[IKContainer] = []


func _ready() -> void:
	if book == null:
		book = CKRecipeBook.new()
	for recipe in book.recipes:
		if recipe != null and recipe.known_from_start:
			_known[recipe.id] = true
	if rng_seed == 0:
		rng.randomize()


func _exit_tree() -> void:
	for container in _watched:
		if container.item_added.is_connected(_on_item_added):
			container.item_added.disconnect(_on_item_added)
	_watched.clear()


# --- Knowledge -----------------------------------------------------------------

func is_known(recipe_id: StringName) -> bool:
	return not use_learning or _known.has(recipe_id)


func get_known_recipes() -> Array[CKRecipe]:
	var known: Array[CKRecipe] = []
	for recipe in book.recipes:
		if recipe != null and is_known(recipe.id):
			known.append(recipe)
	return known


## Teaches a recipe (a book read, a quest reward, a trainer...). False if unknown or already known.
func learn(recipe_id: StringName) -> bool:
	var recipe := book.get_recipe(recipe_id)
	if recipe == null or _known.has(recipe_id):
		return false
	_known[recipe_id] = true
	recipe_learned.emit(recipe)
	changed.emit()
	return true


## Learns every unknown recipe marked [member CKRecipe.discover_when_held] whose ingredients
## are all held in [param container] (at least one of each). Returns what was learned.
func discover(container: IKContainer) -> Array[CKRecipe]:
	var learned: Array[CKRecipe] = []
	if not use_learning or container == null:
		return learned
	for recipe in book.recipes:
		if recipe == null or _known.has(recipe.id) or not recipe.discover_when_held:
			continue
		var needs := recipe.get_ingredients()
		if needs.is_empty():
			continue
		var holds_all := true
		for key: StringName in needs:
			if CKIngredients.count(container, key) <= 0:
				holds_all = false
				break
		if holds_all:
			_known[recipe.id] = true
			learned.append(recipe)
			recipe_learned.emit(recipe)
	if not learned.is_empty():
		changed.emit()
	return learned


## Calls [method discover] on [param container] now and whenever it gains items.
func watch(container: IKContainer) -> void:
	if container == null or _watched.has(container):
		return
	_watched.append(container)
	if database == null:
		database = container.database
	container.item_added.connect(_on_item_added.bind(container))
	discover(container)


# --- Professions -----------------------------------------------------------------

func get_xp(profession: StringName) -> int:
	return int(_xp.get(profession, 0))


## Level 1 with no XP, then one more per [member level_thresholds] reached.
func get_level(profession: StringName) -> int:
	var total := get_xp(profession)
	var level := 1
	for threshold in level_thresholds:
		if total < threshold:
			break
		level += 1
	return level


## For a progress bar: {level, xp, current (XP where this level starts), next (XP of the
## next level, -1 at the top)}.
func get_level_progress(profession: StringName) -> Dictionary:
	var level := get_level(profession)
	return {"level": level, "xp": get_xp(profession),
		"current": level_thresholds[level - 2] if level >= 2 else 0,
		"next": level_thresholds[level - 1] if level - 1 < level_thresholds.size() else -1}


## Gives profession XP (quests, trainers...). Crafts give it on their own. Returns the new level.
func add_xp(profession: StringName, amount: int) -> int:
	var before := get_level(profession)
	if profession.is_empty() or amount <= 0:
		return before
	_xp[profession] = get_xp(profession) + amount
	xp_gained.emit(profession, amount, get_xp(profession))
	var after := get_level(profession)
	for level in range(before + 1, after + 1):
		level_up.emit(profession, level)
	changed.emit()
	return after


## Whether the profession level allows [param recipe] ([member CKRecipe.required_level]).
func is_unlocked(recipe: CKRecipe) -> bool:
	return recipe != null and (recipe.required_level <= 1 or get_level(recipe.get_profession()) >= recipe.required_level)


## Recipes that [param level] of [param profession] unlocks: for a "level up!" message.
func get_recipes_unlocked_at(profession: StringName, level: int) -> Array[CKRecipe]:
	var found: Array[CKRecipe] = []
	for recipe in book.recipes:
		if recipe != null and recipe.get_profession() == profession and recipe.required_level == level:
			found.append(recipe)
	return found


# --- Checks ----------------------------------------------------------------------

## Ingredients still needed for [param count] crafts, {item_id or #tag: amount}. Empty = all there.
func get_missing(recipe: CKRecipe, container: IKContainer, count: int = 1) -> Dictionary:
	var needs := recipe.scaled(recipe.get_ingredients(), count)
	if container == null:
		return needs
	return CKIngredients.resolve(needs, container.get_totals(), _db(container)).missing


## How many times the recipe can be made from [param container]'s ingredients (no auto-craft).
func get_max_crafts(recipe: CKRecipe, container: IKContainer) -> int:
	if recipe == null or container == null:
		return 0
	var needs := recipe.get_ingredients()
	var totals := container.get_totals()
	var db := _db(container)
	var most := 9999
	var tagged := false
	for key: StringName in needs:
		tagged = tagged or CKIngredients.is_tag(key)
		most = mini(most, CKIngredients.count_in(totals, key, db) / maxi(1, needs[key]))
	if not tagged or most <= 0:
		return most
	# Two tags may share the same items: find the largest batch that resolves as a whole.
	var low := 0
	var high := most
	while low < high:
		var middle := (low + high + 1) / 2
		if CKIngredients.resolve(recipe.scaled(needs, middle), totals, db).missing.is_empty():
			low = middle
		else:
			high = middle - 1
	return low


## Like [method get_max_crafts], counting components [member auto_craft] would make.
func get_craftable_count(recipe: CKRecipe, container: IKContainer, limit: int = 999) -> int:
	var plain := get_max_crafts(recipe, container)
	if plain > 0 or not auto_craft or recipe == null or container == null:
		return plain
	if not plan_craft(recipe, 1, container).ok:
		return 0
	var low := 1
	var high := 2
	while high <= limit and plan_craft(recipe, high, container).ok:
		low = high
		high *= 2
	high = mini(high, limit + 1)
	while high - low > 1:
		var middle := (low + high) / 2
		if plan_craft(recipe, middle, container).ok:
			low = middle
		else:
			high = middle
	return low


## What [param count] crafts take from [param container]:
## [code]{"ok", "use": {item_id: n} taken, "give": {item_id: n} components left over,
## "ingredients": {item_id: n} the recipe's own ingredients, "components": [[recipe_id, count]],
## "missing": {key: n}}[/code]. With [member auto_craft], missing components are planned
## from known hand recipes without chance.
func plan_craft(recipe: CKRecipe, count: int, container: IKContainer) -> Dictionary:
	var totals := container.get_totals() if container != null else {}
	var db := _db(container)
	var direct := CKIngredients.resolve(recipe.scaled(recipe.get_ingredients(), count), totals, db)
	var plan := {"ok": direct.missing.is_empty(), "use": direct.use, "give": {}, "ingredients": direct.use,
		"components": [], "missing": direct.missing}
	if plan.ok or not auto_craft or container == null:
		return plan
	var state := {"totals": totals.duplicate(), "steps": [], "visiting": {}, "db": db}
	var used: Variant = _run(recipe, count, state, 0, false)
	if used == null:
		return plan
	var use := {}
	var give := {}
	for item_id: StringName in state.totals:
		var delta := int(state.totals[item_id]) - int(totals.get(item_id, 0))
		if delta < 0:
			use[item_id] = -delta
		elif delta > 0:
			give[item_id] = delta
	return {"ok": true, "use": use, "give": give, "ingredients": used, "components": state.steps, "missing": {}}


## Whether [param count] crafts are possible right now (known, level, ingredients).
func check(recipe_id: StringName, count: int, container: IKContainer) -> CKResult:
	return _prepare(recipe_id, count, container)[0]


# --- Crafting by hand -----------------------------------------------------------

## Makes a hand recipe [param count] times: ingredients from [param from], results into
## [param to] (the same container by default). All crafts or none. Each craft rolls its
## own success, bonuses and quality; see [member CKResult.produced] and [member CKResult.failures].
func craft(recipe_id: StringName, count: int, from: IKContainer, to: IKContainer = null) -> CKResult:
	var prepared := _prepare(recipe_id, count, from)
	var result: CKResult = prepared[0]
	if not result.ok:
		return result
	var recipe := book.get_recipe(recipe_id)
	if not recipe.station.is_empty():
		return CKResult.failure(CKResult.Code.WRONG_STATION, "%s is made at the %s" % [recipe_id, recipe.station])
	to = to if to != null else from
	var plan: Dictionary = prepared[1]
	var rng_before := rng.state
	var outcome := roll_crafts(recipe, count)
	var transaction := IKTransaction.new()
	if not plan.use.is_empty():
		transaction.consume(from, plan.use)
	for item_id in plan.give:
		transaction.add(from, item_id, plan.give[item_id])
	for entry: Array in outcome.items:
		transaction.add(to, entry[0], entry[1], false, entry[2])
	var committed := transaction.commit()
	if not committed.ok:
		rng.state = rng_before  # a refused craft does not use up the luck
		return CKResult.from_inventory(committed)
	return _finish(recipe, count, outcome, plan.components)


## Rolls [param count] crafts of [param recipe] with [member rng]:
## [code]{"items": [[item_id, amount, data]], "produced": {item_id: amount}, "failures", "quality"}[/code].
func roll_crafts(recipe: CKRecipe, count: int) -> Dictionary:
	var merged := {}
	var produced := {}
	var failures := 0
	var best := -1
	for i in count:
		var outcome := recipe.roll(rng)
		if not outcome.success:
			failures += 1
		best = maxi(best, outcome.quality)
		for entry: Array in outcome.items:
			var key := "%s|%s" % [entry[0], entry[2]]
			if merged.has(key):
				merged[key][1] += entry[1]
			else:
				merged[key] = [entry[0], entry[1], entry[2]]
			produced[entry[0]] = int(produced.get(entry[0], 0)) + entry[1]
	return {"items": merged.values(), "produced": produced, "failures": failures, "quality": best}


# --- Crafting grid -------------------------------------------------------------

## One item id per slot of [param grid] ([code]&""[/code] = empty).
static func grid_cells(grid: IKContainer) -> Array:
	var cells := []
	for slot in grid.size():
		cells.append(&"" if grid.is_slot_empty(slot) else grid.get_stack(slot).item_id)
	return cells


## The recipe the items placed in [param grid] make ([param width] slots per row), or null.
## Unknown recipes match too (see [member learn_from_grid]).
func match_grid(grid: IKContainer, width: int, station: StringName = &"") -> CKRecipe:
	if grid == null:
		return null
	return book.find_in_grid(grid_cells(grid), width, _db(grid), station)


## Crafts possible from the grid: the smallest stack placed in it.
func get_grid_max_crafts(grid: IKContainer) -> int:
	var most := -1
	for slot in grid.size():
		if not grid.is_slot_empty(slot):
			var amount := grid.get_stack(slot).amount
			most = amount if most < 0 else mini(most, amount)
	return maxi(0, most)


## Crafts the recipe the grid makes, [param count] times at most: each craft takes one item
## from every filled cell, results go to [param to]. One transaction.
func craft_grid(grid: IKContainer, width: int, to: IKContainer, count: int = 1, station: StringName = &"") -> CKResult:
	if grid == null or to == null or width <= 0 or count <= 0:
		return CKResult.failure(CKResult.Code.INVALID_ARGUMENT, "craft_grid: bad grid, width, container or count")
	var recipe := match_grid(grid, width, station)
	if recipe == null:
		return CKResult.failure(CKResult.Code.NO_MATCH, "the grid makes no recipe")
	var learning := not is_known(recipe.id)
	if learning and not learn_from_grid:
		return CKResult.failure(CKResult.Code.NOT_KNOWN, "%s is not learned" % recipe.id)
	if not is_unlocked(recipe):
		return _level_refusal(recipe)
	count = mini(count, get_grid_max_crafts(grid))
	var rng_before := rng.state
	var outcome := roll_crafts(recipe, count)
	var transaction := IKTransaction.new()
	for slot in grid.size():
		if not grid.is_slot_empty(slot):
			transaction.remove_at(grid, slot, count)
	for entry: Array in outcome.items:
		transaction.add(to, entry[0], entry[1], false, entry[2])
	var committed := transaction.commit()
	if not committed.ok:
		rng.state = rng_before
		return CKResult.from_inventory(committed)
	if learning:
		learn(recipe.id)
	return _finish(recipe, count, outcome, [])


# --- Saving ----------------------------------------------------------------------

func to_data() -> Dictionary:
	var known := []
	for recipe_id in _known:
		known.append(String(recipe_id))
	known.sort()
	var xp := {}
	for profession in _xp:
		xp[String(profession)] = _xp[profession]
	return {"version": DATA_VERSION, "known": known, "xp": xp, "rng_state": str(rng.state)}


## Restores [method to_data] (version 1 saves too). Recipes removed from the book are
## ignored; recipes added since the save that are [member CKRecipe.known_from_start] stay known.
func load_data(data: Dictionary) -> bool:
	if typeof(data.get("known")) != TYPE_ARRAY:
		return false
	_known.clear()
	for recipe in book.recipes:
		if recipe != null and recipe.known_from_start:
			_known[recipe.id] = true
	for raw: Variant in data.known:
		var recipe_id := StringName(str(raw))
		if book.has_recipe(recipe_id):
			_known[recipe_id] = true
	_xp.clear()
	if typeof(data.get("xp")) == TYPE_DICTIONARY:
		for profession: Variant in data.xp:
			var amount := int(data.xp[profession])
			if amount > 0:
				_xp[StringName(str(profession))] = amount
	if data.has("rng_state"):
		rng.state = str(data.rng_state).to_int()
	changed.emit()
	return true


# --- Internals -------------------------------------------------------------------

## [result: CKResult, plan: Dictionary].
func _prepare(recipe_id: StringName, count: int, container: IKContainer) -> Array:
	var recipe := book.get_recipe(recipe_id)
	if recipe == null:
		return [CKResult.failure(CKResult.Code.UNKNOWN_RECIPE, "no recipe '%s'" % recipe_id), {}]
	if count <= 0 or container == null:
		return [CKResult.failure(CKResult.Code.INVALID_ARGUMENT, "check(%s, %d): bad count or container" % [recipe_id, count]), {}]
	if not is_known(recipe_id):
		return [CKResult.failure(CKResult.Code.NOT_KNOWN, "%s is not learned" % recipe_id), {}]
	if not is_unlocked(recipe):
		return [_level_refusal(recipe), {}]
	var plan := plan_craft(recipe, count, container)
	if not plan.ok:
		var result := CKResult.failure(CKResult.Code.MISSING_INGREDIENTS, "missing %s" % plan.missing)
		result.missing = plan.missing
		return [result, plan]
	var success := CKResult.success(recipe_id, count)
	success.components = plan.components
	return [success, plan]


func _level_refusal(recipe: CKRecipe) -> CKResult:
	return CKResult.failure(CKResult.Code.LEVEL_TOO_LOW, "%s needs %s level %d" % [recipe.id, recipe.get_profession(), recipe.required_level])


## XP and signals after a hand or grid craft.
func _finish(recipe: CKRecipe, count: int, outcome: Dictionary, components: Array) -> CKResult:
	for step: Array in components:
		var component := book.get_recipe(step[0])
		crafted.emit(component, step[1])
		add_xp(component.get_profession(), component.xp * int(step[1]))
	if outcome.failures > 0:
		craft_failed.emit(recipe, outcome.failures)
	crafted.emit(recipe, count)
	add_xp(recipe.get_profession(), recipe.xp * count)
	var result := CKResult.success(recipe.id, count)
	result.produced = outcome.produced
	result.failures = outcome.failures
	result.quality = outcome.quality
	result.components = components
	return result


## Takes [param recipe]'s ingredients for [param crafts] from state.totals, planning the
## missing components first; adds its results when [param add_results]. Null if impossible.
func _run(recipe: CKRecipe, crafts: int, state: Dictionary, depth: int, add_results: bool) -> Variant:
	var snapshot: Dictionary = state.totals.duplicate()
	var steps_before: int = state.steps.size()
	var needs := recipe.scaled(recipe.get_ingredients(), crafts)
	state.visiting[recipe.id] = true
	var ok := true
	for key: StringName in needs:
		if not _ensure(key, needs[key], state, depth):
			ok = false
			break
	state.visiting.erase(recipe.id)
	var resolved := CKIngredients.resolve(needs, state.totals, state.db) if ok else {}
	if not ok or not resolved.missing.is_empty():
		state.totals = snapshot
		state.steps.resize(steps_before)
		return null
	for item_id: StringName in resolved.use:
		state.totals[item_id] = int(state.totals[item_id]) - int(resolved.use[item_id])
	if add_results:
		for item_id: StringName in recipe.results:
			state.totals[item_id] = int(state.totals.get(item_id, 0)) + recipe.results[item_id] * crafts
		state.steps.append([recipe.id, crafts])
	return resolved.use


## Makes state.totals hold [param amount] items matching [param key], crafting them if needed.
func _ensure(key: StringName, amount: int, state: Dictionary, depth: int) -> bool:
	var have := CKIngredients.count_in(state.totals, key, state.db)
	if have >= amount:
		return true
	if depth >= MAX_COMPONENT_DEPTH:
		return false
	for recipe in book.producing(key, state.db):
		if not recipe.station.is_empty() or recipe.is_random() or state.visiting.has(recipe.id) \
				or not is_known(recipe.id) or not is_unlocked(recipe):
			continue
		var per_craft := 0
		for item_id: StringName in recipe.results:
			if CKIngredients.matches(key, item_id, state.db):
				per_craft += recipe.results[item_id]
		var crafts := ceili(float(amount - have) / maxi(1, per_craft))
		if _run(recipe, crafts, state, depth + 1, true) != null:
			return true
	return false


func _db(container: IKContainer) -> IKItemDatabase:
	if container != null and container.database != null:
		return container.database
	return database


func _on_item_added(_item_id: StringName, _amount: int, container: IKContainer) -> void:
	discover(container)
