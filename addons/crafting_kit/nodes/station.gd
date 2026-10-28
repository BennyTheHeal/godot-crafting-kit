class_name CKStation
extends Node
## A workbench, forge or alchemy table: queued crafts that take time.
##
## Ingredients are taken when a job is queued (one transaction), results land in the
## station's own [member output] tray as each craft finishes, and the player collects
## them. If the tray is full, the station waits: nothing is ever lost. Cancelling a job
## gives back the ingredients of the crafts not started yet.
## [codeblock]
## var result := forge.enqueue(&"iron_ingot", 5, bag.container)
## forge.job_finished.connect(func(recipe, count): print("ready"))
## forge.collect(bag.container)
## [/codeblock]

signal job_queued(recipe: CKRecipe, count: int)
## One craft of a job finished and its results are in the tray.
signal craft_finished(recipe: CKRecipe)
## One craft of a job failed its [member CKRecipe.success_chance] (emitted before craft_finished).
signal craft_failed(recipe: CKRecipe)
## Every craft of a job finished.
signal job_finished(recipe: CKRecipe, count: int)
## Queue, progress or tray changed: refresh the UI.
signal changed

const DATA_VERSION := 2

## Matches [member CKRecipe.station] of the recipes made here.
@export var station_id: StringName = &"workbench"
@export var display_name: String = ""
## Profession shown for this station in the crafting window. Empty = [member station_id].
## The XP itself goes to each recipe's [method CKRecipe.get_profession].
@export var profession: StringName
@export var book: CKRecipeBook
## Optional: only recipes the player knows can be queued. Also gives profession XP,
## auto-craft, and the seeded [member CKCrafting.rng].
@export var crafting: CKCrafting
## Item definitions of the output tray. Defaults to the crafting node's, then to the
## first container ingredients come from.
@export var database: IKItemDatabase:
	set(value):
		database = value
		if output != null:
			output.database = value
@export_range(1, 64) var queue_size: int = 5
## Slots of the output tray.
@export_range(1, 64) var output_size: int = 6
## 2.0 = twice as fast (upgrades, skills).
@export var speed: float = 1.0
## Advance jobs in _process. Turn it off to call [method advance] yourself (turn-based games, tests).
@export var auto_process: bool = true

## Where finished items wait. Save it with your inventory, or use [method to_data].
var output: IKContainer
## Used for chance when no [member crafting] node is set.
var rng := RandomNumberGenerator.new()

# {recipe: CKRecipe, count, done, progress (seconds into the current craft),
#  used: {item_id: n} ingredients taken for the crafts not done, roll: outcome waiting for room}
var _jobs: Array[Dictionary] = []
var _blocked := false


func _init() -> void:
	output = IKContainer.new(&"station_output", 6)


func _ready() -> void:
	if book == null and crafting != null:
		book = crafting.book
	if book == null:
		book = CKRecipeBook.new()
	if database == null and crafting != null:
		database = crafting.database
	if database != null:
		output.database = database
	output.container_id = StringName("%s_output" % station_id)
	if output.size() != output_size:
		output.resize(output_size)
	set_process(auto_process)


func _process(delta: float) -> void:
	if not _jobs.is_empty():
		advance(delta)


# --- Reading -------------------------------------------------------------------

func get_display_name() -> String:
	return CKText.t(display_name) if not display_name.is_empty() else String(station_id).capitalize()


func get_profession() -> StringName:
	return profession if not profession.is_empty() else station_id


## Recipes made here, known ones only when [member crafting] is set.
func get_recipes() -> Array[CKRecipe]:
	var found: Array[CKRecipe] = []
	for recipe in book.for_station(station_id):
		if crafting == null or crafting.is_known(recipe.id):
			found.append(recipe)
	return found


## Read-only view of the queue: [{recipe, count, done, progress (0..1 of the current craft), seconds_left}].
func get_jobs() -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	for job in _jobs:
		var total := _craft_time(job.recipe)
		var remaining_crafts: int = job.count - job.done
		jobs.append({"recipe": job.recipe, "count": job.count, "done": job.done,
			"progress": clampf(job.progress / total, 0.0, 1.0) if total > 0.0 else 1.0,
			"seconds_left": maxf(0.0, total * remaining_crafts - job.progress)})
	return jobs


func is_busy() -> bool:
	return not _jobs.is_empty()


## True while the tray is too full for the next result: collect to resume.
func is_blocked() -> bool:
	return _blocked


# --- Jobs ------------------------------------------------------------------------

## Queues [param count] crafts: the ingredients for all of them are taken now from [param from].
## With [member CKCrafting.auto_craft], missing hand-made components are crafted first in the
## same transaction (their leftovers go to [param from]).
func enqueue(recipe_id: StringName, count: int, from: IKContainer) -> CKResult:
	var recipe := book.get_recipe(recipe_id)
	if recipe == null:
		return CKResult.failure(CKResult.Code.UNKNOWN_RECIPE, "no recipe '%s'" % recipe_id)
	if count <= 0 or from == null:
		return CKResult.failure(CKResult.Code.INVALID_ARGUMENT, "enqueue(%s, %d): bad count or container" % [recipe_id, count])
	if recipe.station != station_id:
		return CKResult.failure(CKResult.Code.WRONG_STATION, "%s is made at '%s', not '%s'" % [recipe_id, recipe.station, station_id])
	if crafting != null and not crafting.is_known(recipe_id):
		return CKResult.failure(CKResult.Code.NOT_KNOWN, "%s is not learned" % recipe_id)
	if crafting != null and not crafting.is_unlocked(recipe):
		return CKResult.failure(CKResult.Code.LEVEL_TOO_LOW, "%s needs %s level %d" % [recipe_id, recipe.get_profession(), recipe.required_level])
	if _jobs.size() >= queue_size:
		return CKResult.failure(CKResult.Code.QUEUE_FULL, "%d jobs queued" % _jobs.size())
	if output.database == null:
		database = from.database
	var plan: Dictionary
	if crafting != null:
		plan = crafting.plan_craft(recipe, count, from)
	else:
		var direct := CKIngredients.resolve(recipe.scaled(recipe.get_ingredients(), count), from.get_totals(), from.database)
		plan = {"ok": direct.missing.is_empty(), "use": direct.use, "give": {}, "ingredients": direct.use,
			"components": [], "missing": direct.missing}
	if not plan.ok:
		var refused := CKResult.failure(CKResult.Code.MISSING_INGREDIENTS, "missing %s" % plan.missing)
		refused.missing = plan.missing
		return refused
	if not plan.use.is_empty() or not plan.give.is_empty():
		var transaction := IKTransaction.new()
		if not plan.use.is_empty():
			transaction.consume(from, plan.use)
		for item_id in plan.give:
			transaction.add(from, item_id, plan.give[item_id])
		var taken := transaction.commit()
		if not taken.ok:
			return CKResult.from_inventory(taken)
	for step: Array in plan.components:
		var component := book.get_recipe(step[0])
		if component != null and crafting != null:
			crafting.crafted.emit(component, step[1])
			crafting.add_xp(component.get_profession(), component.xp * int(step[1]))
	_jobs.append({"recipe": recipe, "count": count, "done": 0, "progress": 0.0, "used": plan.ingredients.duplicate()})
	job_queued.emit(recipe, count)
	changed.emit()
	var result := CKResult.success(recipe_id, count)
	result.components = plan.components
	return result


## Cancels job [param index]: the ingredients of the crafts not finished yet go back to
## [param to] (all or nothing: refused if they do not fit). Finished results stay in the tray.
func cancel(index: int, to: IKContainer) -> CKResult:
	if index < 0 or index >= _jobs.size() or to == null:
		return CKResult.failure(CKResult.Code.INVALID_ARGUMENT, "cancel(%d): bad index or container" % index)
	var job := _jobs[index]
	var left: int = job.count - job.done
	var refund: Dictionary = job.get("used", job.recipe.scaled(job.recipe.get_ingredients(), left))
	if not refund.is_empty():
		var transaction := IKTransaction.new()
		for item_id in refund:
			transaction.add(to, item_id, refund[item_id])
		var given := transaction.commit()
		if not given.ok:
			return CKResult.from_inventory(given)
	_jobs.remove_at(index)
	_blocked = false
	changed.emit()
	return CKResult.success(job.recipe.id, left)


## Moves everything from the tray to [param to], as much as fits. [member CKResult.amount]
## is the number of items moved; NO_ROOM if some had to stay.
func collect(to: IKContainer) -> CKResult:
	if to == null:
		return CKResult.failure(CKResult.Code.INVALID_ARGUMENT, "collect: no container")
	var moved := 0
	var left_behind := false
	for slot in output.size():
		if output.is_slot_empty(slot):
			continue
		var amount := output.get_stack(slot).amount
		var result := output.transfer_to(slot, to)
		if not result.ok:
			left_behind = true
			continue
		moved += amount - result.remainder
		left_behind = left_behind or result.remainder > 0
	if moved > 0:
		_blocked = false
		changed.emit()
	if left_behind:
		var partial := CKResult.failure(CKResult.Code.NO_ROOM, "%d items moved, the rest did not fit" % moved)
		partial.amount = moved
		return partial
	return CKResult.success(&"", moved)


## Runs the station for [param seconds] (called by _process when [member auto_process] is on).
func advance(seconds: float) -> void:
	var budget := maxf(0.0, seconds)
	var touched := false
	# Runs even with no time left: a craft waiting for room in the tray is retried.
	while not _jobs.is_empty():
		var job := _jobs[0]
		var recipe: CKRecipe = job.recipe
		var total := _craft_time(recipe)
		var step := clampf(total - job.progress, 0.0, budget)
		job.progress += step
		budget -= step
		touched = touched or step > 0.0
		if job.progress < total - 0.00001:
			break
		if not job.has("roll"):
			job.roll = recipe.roll(_rng())  # rolled once: retries after a full tray keep it
		if not _deliver(job.roll.items):
			_blocked = true  # tray full: wait without losing time already spent
			job.progress = total
			break
		var outcome: Dictionary = job.roll
		job.erase("roll")
		_blocked = false
		touched = true
		job.done += 1
		job.progress = 0.0
		if job.has("used"):
			var one := CKIngredients.resolve(recipe.get_ingredients(), job.used, output.database if output.database != null else database)
			job.used = CKIngredients.subtract(job.used, one.use)
		if crafting != null:
			crafting.add_xp(recipe.get_profession(), recipe.xp)
		if not outcome.success:
			craft_failed.emit(recipe)
			if crafting != null:
				crafting.craft_failed.emit(recipe, 1)
		craft_finished.emit(recipe)
		if job.done >= job.count:
			_jobs.pop_front()
			job_finished.emit(recipe, job.count)
	if touched:
		changed.emit()


# --- Saving ----------------------------------------------------------------------

## Queue and tray as JSON-friendly data.
func to_data() -> Dictionary:
	var jobs := []
	for job in _jobs:
		var saved := {"recipe": String(job.recipe.id), "count": job.count, "done": job.done, "progress": job.progress}
		if job.has("used"):
			var used := {}
			for item_id in job.used:
				used[String(item_id)] = job.used[item_id]
			saved.used = used
		if job.has("roll"):
			saved.roll = job.roll
		jobs.append(saved)
	return {"version": DATA_VERSION, "station": String(station_id), "jobs": jobs, "output": IKSerializer.to_dict([output])}


## Restores [method to_data] (version 1 saves too). Jobs of recipes removed from the book are dropped.
func load_data(data: Dictionary) -> bool:
	if typeof(data.get("jobs")) != TYPE_ARRAY:
		return false
	var jobs: Array[Dictionary] = []
	for raw: Variant in data.jobs:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var recipe := book.get_recipe(StringName(str(raw.get("recipe", ""))))
		var count := int(raw.get("count", 0))
		var done := clampi(int(raw.get("done", 0)), 0, count)
		if recipe == null or count <= 0 or done >= count:
			continue
		var job := {"recipe": recipe, "count": count, "done": done, "progress": maxf(0.0, float(raw.get("progress", 0.0)))}
		var used := {}
		if typeof(raw.get("used")) == TYPE_DICTIONARY:
			for item_id: Variant in raw.used:
				if int(raw.used[item_id]) > 0:
					used[StringName(str(item_id))] = int(raw.used[item_id])
		else:
			used = recipe.scaled(recipe.get_ingredients(), count - done)  # version 1: no tags
		job.used = used
		if typeof(raw.get("roll")) == TYPE_DICTIONARY:
			job.roll = _load_roll(raw.roll)
		jobs.append(job)
	if typeof(data.get("output")) == TYPE_DICTIONARY:
		var report := IKSerializer.load_into(data.output, [output])
		if not report.ok:
			return false
	_jobs = jobs
	_blocked = false
	changed.emit()
	return true


func _craft_time(recipe: CKRecipe) -> float:
	return recipe.duration / maxf(0.01, speed)


func _rng() -> RandomNumberGenerator:
	return crafting.rng if crafting != null else rng


func _deliver(items: Array) -> bool:
	if items.is_empty():
		return true
	var transaction := IKTransaction.new()
	for entry: Array in items:
		transaction.add(output, StringName(entry[0]), int(entry[1]), false, entry[2])
	return transaction.commit().ok


static func _load_roll(raw: Dictionary) -> Dictionary:
	var items := []
	if typeof(raw.get("items")) == TYPE_ARRAY:
		for entry: Variant in raw.items:
			if typeof(entry) == TYPE_ARRAY and entry.size() >= 2:
				var data: Dictionary = entry[2] if entry.size() > 2 and typeof(entry[2]) == TYPE_DICTIONARY else {}
				if data.has(CKRecipe.QUALITY_KEY):
					data = {CKRecipe.QUALITY_KEY: int(data[CKRecipe.QUALITY_KEY])}  # JSON turns ints into floats
				items.append([StringName(str(entry[0])), int(entry[1]), data])
	return {"success": bool(raw.get("success", true)), "quality": int(raw.get("quality", -1)), "items": items}
