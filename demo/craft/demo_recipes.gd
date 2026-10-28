extends RefCounted
## The demo's recipe book, built in code so every recipe is visible in one place.
## In a game you would save it as a .tres (CKRecipeBook) and assign it in the inspector.
##
## "#planks" is any item tagged "planks" (oak, pine or birch planks).

## Profession of each place, and the XP its recipes give per second of crafting.
const PROFESSIONS := {&"workbench": &"woodworking", &"forge": &"smithing", &"alchemy": &"alchemy"}
## Total XP for levels 2, 3, 4, 5: low, so a few crafts show a level up.
const LEVELS: PackedInt32Array = [20, 50, 90, 140]


static func book() -> CKRecipeBook:
	var book := CKRecipeBook.new()
	# By hand, instant.
	for wood in [&"oak", &"pine", &"birch"]:
		var planks := _add(book, StringName("%s_planks" % wood), {StringName("%s_log" % wood): 1}, {StringName("%s_planks" % wood): 2}, &"", 0.0, &"materials")
		planks.profession = &"woodworking"
		planks.xp = 1
	_add(book, &"linen_thread", {&"plant_fiber": 3}, {&"linen_thread": 1}, &"", 0.0, &"materials")
	_add(book, &"cloth", {&"linen_thread": 2}, {&"cloth": 1}, &"", 0.0, &"materials")
	_add(book, &"torch", {&"#planks": 1, &"resin": 1}, {&"torch": 2}, &"", 0.0, &"tools")
	_unknown(_add(book, &"arrows", {&"#planks": 1, &"feather": 2, &"iron_nugget": 1}, {&"arrows": 10}, &"", 0.0, &"weapons"),
		"Feathers, wood and a bit of metal... for something that flies.")
	# By hand, shaped: also made in the crafting grid (the grid finds them by their shape).
	_shaped(book, &"dagger", ["I", "P"], 0, 4)
	_shaped(book, &"spear", ["  I", " P ", "P  "], 2, 6, true)  # mirrored: leaning left works too
	# Not discovered by holding its items: found by trying the shape in the grid.
	_unknown(_shaped(book, &"mace", ["III", " P ", " P "], 3, 8), "Heavy iron on a wooden handle... try shapes in the grid.") \
		.discover_when_held = false
	# Workbench.
	_add(book, &"leather", {&"rawhide": 2}, {&"leather": 1}, &"workbench", 2.0, &"materials")
	_add(book, &"bow", {&"#planks": 3, &"linen_thread": 2}, {&"bow": 1}, &"workbench", 3.0, &"weapons")
	_add(book, &"shield", {&"#planks": 4, &"iron_ingot": 1}, {&"shield": 1}, &"workbench", 4.0, &"armor")
	_add(book, &"cloth_helmet", {&"cloth": 2, &"leather": 1}, {&"cloth_helmet": 1}, &"workbench", 3.0, &"armor")
	_unknown(_add(book, &"staff", {&"#planks": 2, &"crystal": 1}, {&"staff": 1}, &"workbench", 4.0, &"weapons"),
		"A crystal could focus magic through a length of wood.")
	# Forge.
	var iron := _add(book, &"iron_ingot", {&"iron_ore": 2, &"coal": 1}, {&"iron_ingot": 1}, &"forge", 2.0, &"metals")
	iron.bonus_results.append(CKBonusResult.make(&"iron_nugget", 2, 0.25))
	_add(book, &"copper_ingot", {&"copper_ore": 2, &"coal": 1}, {&"copper_ingot": 1}, &"forge", 2.0, &"metals")
	_add(book, &"tin_ingot", {&"tin_ore": 2, &"coal": 1}, {&"tin_ingot": 1}, &"forge", 2.0, &"metals")
	_unknown(_add(book, &"bronze_ingot", {&"copper_ingot": 3, &"tin_ingot": 1}, {&"bronze_ingot": 2}, &"forge", 3.0, &"metals"),
		"Copper alone is soft. Something to mix it with?")
	var steel := _unknown(_add(book, &"steel_ingot", {&"iron_ingot": 2, &"coal": 2}, {&"steel_ingot": 1}, &"forge", 5.0, &"metals"),
		"Iron, fired again with plenty of coal.")
	steel.required_level = 2
	_add(book, &"iron_nugget", {&"iron_ingot": 1}, {&"iron_nugget": 5}, &"forge", 1.0, &"metals")
	var sword := _add(book, &"sword", {&"iron_ingot": 3, &"leather": 1}, {&"sword": 1}, &"forge", 5.0, &"weapons")
	sword.quality_weights = PackedFloat32Array([55, 30, 12, 3])
	_add(book, &"axe", {&"iron_ingot": 2, &"#planks": 2}, {&"axe": 1}, &"forge", 4.0, &"weapons")
	_add(book, &"iron_helmet", {&"iron_ingot": 4}, {&"iron_helmet": 1}, &"forge", 6.0, &"armor").required_level = 3
	# Alchemy table: potions can fail, and come out in several qualities.
	var health := _add(book, &"health_potion", {&"herb": 3}, {&"health_potion": 1}, &"alchemy", 3.0, &"potions")
	health.success_chance = 0.85
	health.quality_weights = PackedFloat32Array([60, 30, 10])
	_add(book, &"stamina_potion", {&"herb": 2, &"apple": 1}, {&"stamina_potion": 1}, &"alchemy", 3.0, &"potions") \
		.quality_weights = PackedFloat32Array([70, 25, 5])
	var mana := _unknown(_add(book, &"mana_potion", {&"herb": 2, &"magic_essence": 1}, {&"mana_potion": 1}, &"alchemy", 4.0, &"potions"),
		"Herbs steeped in pure magic.")
	mana.success_chance = 0.75
	mana.required_level = 2
	var antidote := _unknown(_add(book, &"antidote", {&"herb": 1, &"bone": 1}, {&"antidote": 1}, &"alchemy", 3.0, &"potions"),
		"Written in an old book somewhere...")
	antidote.discover_when_held = false  # only taught (the demo's "Read the old book" button)
	# Station recipes give XP to the station's profession.
	for recipe in book.recipes:
		if PROFESSIONS.has(recipe.station):
			recipe.profession = PROFESSIONS[recipe.station]
			recipe.xp = maxi(1, roundi(recipe.duration * 2.0))
	return book


static func _add(book: CKRecipeBook, id: StringName, ingredients: Dictionary, results: Dictionary,
		station: StringName, duration: float, category: StringName) -> CKRecipe:
	var recipe := CKRecipe.make(id, ingredients, results, station, duration)
	recipe.category = category
	book.add_recipe(recipe)
	return recipe


## A hand-made iron weapon: I = iron ingot, P = any planks. Smithing XP, level gate.
static func _shaped(book: CKRecipeBook, id: StringName, pattern: Array, level: int, xp: int, mirrored: bool = false) -> CKRecipe:
	var recipe := CKRecipe.make_shaped(id, pattern, {"I": &"iron_ingot", "P": &"#planks"}, {id: 1}, &"", 0.0, mirrored)
	recipe.category = &"weapons"
	recipe.profession = &"smithing"
	recipe.required_level = level
	recipe.xp = xp
	book.add_recipe(recipe)
	return recipe


static func _unknown(recipe: CKRecipe, hint: String) -> CKRecipe:
	recipe.known_from_start = false
	recipe.hint = hint
	return recipe
