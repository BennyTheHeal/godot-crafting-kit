class_name CKIngredients
extends RefCounted
## Turns recipe requirements into the exact items to take.
##
## A requirement key is an item id ([code]&"oak_planks"[/code]) or a tag of items prefixed
## with [code]#[/code] ([code]&"#planks"[/code]: any item whose [member IKItemDefinition.tags]
## contain "planks"). Tags work in [member CKRecipe.ingredients] and in shaped patterns.

const TAG_PREFIX := "#"


static func is_tag(key: StringName) -> bool:
	return String(key).begins_with(TAG_PREFIX)


## [code]&"#planks"[/code] -> [code]&"planks"[/code].
static func tag_of(key: StringName) -> StringName:
	return StringName(String(key).substr(1)) if is_tag(key) else key


## [code]&"planks"[/code] -> [code]&"#planks"[/code], the requirement key for "any planks".
static func tag(tag_name: StringName) -> StringName:
	return StringName(TAG_PREFIX + String(tag_name))


## Whether [param item_id] satisfies the requirement [param key].
static func matches(key: StringName, item_id: StringName, database: IKItemDatabase) -> bool:
	if item_id.is_empty():
		return false
	if not is_tag(key):
		return key == item_id
	var definition := database.get_item(item_id) if database != null else null
	return definition != null and definition.has_tag(tag_of(key))


## How many items of [param totals] ({item_id: amount}) satisfy [param key].
static func count_in(totals: Dictionary, key: StringName, database: IKItemDatabase) -> int:
	if not is_tag(key):
		return int(totals.get(key, 0))
	var total := 0
	for item_id: StringName in totals:
		if matches(key, item_id, database):
			total += int(totals[item_id])
	return total


## How many items of [param container] satisfy [param key] (an item id or a tag).
static func count(container: IKContainer, key: StringName) -> int:
	if container == null:
		return 0
	if not is_tag(key):
		return container.count(key)
	return count_in(container.get_totals(), key, container.database)


## Chooses the items to take for [param requirements] ({key: amount}) out of
## [param totals] ({item_id: amount}). Exact items are taken first, then tags (the tag
## with the fewest candidates first); within a tag, items in the order they are held.
## Returns [code]{"use": {item_id: amount}, "missing": {key: amount}}[/code].
static func resolve(requirements: Dictionary, totals: Dictionary, database: IKItemDatabase) -> Dictionary:
	var left := totals.duplicate()
	var use := {}
	var missing := {}
	var tags: Array[StringName] = []
	for key: StringName in requirements:
		var need := int(requirements[key])
		if need <= 0:
			continue
		if is_tag(key):
			tags.append(key)
			continue
		var taken := mini(int(left.get(key, 0)), need)
		if taken > 0:
			use[key] = int(use.get(key, 0)) + taken
			left[key] = int(left[key]) - taken
		if taken < need:
			missing[key] = need - taken
	var candidates := {}
	for key in tags:
		candidates[key] = count_in(left, key, database)
	tags.sort_custom(func(a: StringName, b: StringName) -> bool:
		return candidates[a] < candidates[b] or (candidates[a] == candidates[b] and String(a) < String(b)))
	for key in tags:
		var need := int(requirements[key])
		for item_id: StringName in left:
			if need <= 0:
				break
			if int(left[item_id]) <= 0 or not matches(key, item_id, database):
				continue
			var taken := mini(int(left[item_id]), need)
			use[item_id] = int(use.get(item_id, 0)) + taken
			left[item_id] = int(left[item_id]) - taken
			need -= taken
		if need > 0:
			missing[key] = need
	return {"use": use, "missing": missing}


## [param a] minus [param b], keeping positive amounts only.
static func subtract(a: Dictionary, b: Dictionary) -> Dictionary:
	var left := {}
	for item_id in a:
		var amount := int(a[item_id]) - int(b.get(item_id, 0))
		if amount > 0:
			left[item_id] = amount
	return left
