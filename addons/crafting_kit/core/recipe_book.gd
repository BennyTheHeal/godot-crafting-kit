@tool
class_name CKRecipeBook
extends Resource
## Every recipe of the game. Save it as a .tres and share it between nodes.

@export var recipes: Array[CKRecipe] = []

var _index: Dictionary = {}
var _indexed_count := -1


func get_recipe(recipe_id: StringName) -> CKRecipe:
	_refresh()
	return _index.get(recipe_id)


func has_recipe(recipe_id: StringName) -> bool:
	return get_recipe(recipe_id) != null


func add_recipe(recipe: CKRecipe) -> void:
	recipes.append(recipe)
	_indexed_count = -1


## Recipes made at [param station] ("" = by hand).
func for_station(station: StringName) -> Array[CKRecipe]:
	var found: Array[CKRecipe] = []
	for recipe in recipes:
		if recipe != null and recipe.station == station:
			found.append(recipe)
	return found


## The recipe the items of a crafting grid make, or null. [param cells]: one item id per
## cell, row by row ([code]&""[/code] = empty), [param width] cells per row. Shaped recipes
## are tried first, then shapeless ones. Only recipes made at [param station] ("" = by hand).
func find_in_grid(cells: Array, width: int, database: IKItemDatabase, station: StringName = &"") -> CKRecipe:
	for shaped in [true, false]:
		for recipe in recipes:
			if recipe != null and recipe.station == station and recipe.is_shaped() == shaped \
					and recipe.matches_grid(cells, width, database):
				return recipe
	return null


## Recipes with a result matching [param key] (an item id or a #tag).
func producing(key: StringName, database: IKItemDatabase) -> Array[CKRecipe]:
	var found: Array[CKRecipe] = []
	for recipe in recipes:
		if recipe == null:
			continue
		for item_id: StringName in recipe.results:
			if CKIngredients.matches(key, item_id, database):
				found.append(recipe)
				break
	return found


## Problems a developer should fix: duplicate ids, unknown items or tags, empty recipes,
## pattern characters without a key.
func validate(database: IKItemDatabase) -> PackedStringArray:
	var problems := PackedStringArray()
	var seen := {}
	for recipe in recipes:
		if recipe == null:
			problems.append("empty slot in the recipe list")
			continue
		if recipe.id.is_empty() or seen.has(recipe.id):
			problems.append("recipe id missing or duplicated: '%s'" % recipe.id)
		seen[recipe.id] = true
		if recipe.results.is_empty():
			problems.append("%s has no result" % recipe.id)
		if recipe.is_shaped() and recipe.get_pattern_rows().is_empty():
			problems.append("%s: the pattern has no filled cell" % recipe.id)
		for items: Dictionary in [recipe.get_ingredients(), recipe.results, recipe.failure_results]:
			for item_id: StringName in items:
				if String(item_id).begins_with("?"):
					problems.append("%s: pattern character '%s' has no key" % [recipe.id, String(item_id).substr(1)])
				elif CKIngredients.is_tag(item_id):
					if database != null and not _tag_used(database, CKIngredients.tag_of(item_id)):
						problems.append("%s: no item has the tag %s" % [recipe.id, item_id])
				elif database != null and not database.has_item(item_id):
					problems.append("%s uses unknown item %s" % [recipe.id, item_id])
				if int(items[item_id]) <= 0:
					problems.append("%s: amount of %s must be positive" % [recipe.id, item_id])
		for bonus in recipe.bonus_results:
			if bonus == null or bonus.item_id.is_empty() or (database != null and not database.has_item(bonus.item_id)):
				problems.append("%s: bonus result with a missing or unknown item" % recipe.id)
	return problems


func _refresh() -> void:
	if _indexed_count == recipes.size():
		return
	_index.clear()
	for recipe in recipes:
		if recipe != null and not recipe.id.is_empty():
			_index[recipe.id] = recipe
	_indexed_count = recipes.size()


static func _tag_used(database: IKItemDatabase, tag: StringName) -> bool:
	for item_id in database.get_ids():
		var definition := database.get_item(item_id)
		if definition != null and definition.has_tag(tag):
			return true
	return false
