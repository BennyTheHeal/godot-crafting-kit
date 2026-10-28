extends "res://tests/crafting_kit/ck_test_case.gd"
## 1.1 features: tag ingredients, shaped recipes and the crafting grid, chance / bonus /
## quality with a seed, auto-craft, profession XP and levels, saves.


## oak_log, pine_log (tag log), oak_planks, pine_planks (tag planks), stick, iron, pick (stack 1), gem, ash.
func make_tag_db() -> IKItemDatabase:
	var db := IKItemDatabase.new()
	for entry in [[&"oak_log", [&"log"]], [&"pine_log", [&"log"]], [&"oak_planks", [&"planks"]],
			[&"pine_planks", [&"planks"]], [&"stick", []], [&"iron", []], [&"gem", []], [&"ash", []]]:
		var item := make_item(entry[0])
		item.tags.assign(entry[1])
		db.add_item(item)
	db.add_item(make_item(&"pick", 1))
	return db


## planks (hand, 1 #log -> 2 oak planks), sticks (hand, 2 #planks -> 4 sticks), pick (shaped
## "III"/" S "/" S ", hand), axe (shaped mirrored "II"/"IS"/" S", gives a pick, level 2 smithing),
## box (shapeless 4 #planks).
func make_tag_crafting(db: IKItemDatabase) -> CKCrafting:
	var book := CKRecipeBook.new()
	book.add_recipe(CKRecipe.make(&"planks", {&"#log": 1}, {&"oak_planks": 2}))
	book.add_recipe(CKRecipe.make(&"sticks", {&"#planks": 2}, {&"stick": 4}))
	book.add_recipe(CKRecipe.make_shaped(&"pick", ["III", " S ", " S "], {"I": &"iron", "S": &"stick"}, {&"pick": 1}))
	var axe := CKRecipe.make_shaped(&"axe", ["II", "IS", " S"], {"I": &"iron", "S": &"stick"}, {&"pick": 1}, &"", 0.0, true)
	axe.profession = &"smithing"
	axe.required_level = 2
	book.add_recipe(axe)
	book.add_recipe(CKRecipe.make(&"box", {&"#planks": 4}, {&"gem": 1}))
	var crafting := CKCrafting.new()
	crafting.book = book
	crafting.database = db
	crafting.rng_seed = 7
	add_to_tree(crafting)
	return crafting


func _place(db: IKItemDatabase, cells: Array, width: int = 3, amount: int = 1) -> IKContainer:
	var grid := IKContainer.new(&"grid", width * width, db)
	fill(grid, cells, amount)
	return grid


## Puts [param amount] of cells[i] in slot i of [param grid].
func fill(grid: IKContainer, cells: Array, amount: int = 1) -> void:
	for slot in cells.size():
		if StringName(cells[slot]).is_empty():
			continue
		var hand := IKContainer.new(&"hand", 1, grid.database)
		hand.add(cells[slot], amount)
		assert_ok(hand.move_to(0, grid, slot), "placing the grid")


func test_tag_ingredients_take_any_matching_item() -> void:
	var db := make_tag_db()
	var crafting := make_tag_crafting(db)
	var bag := make_bag(db, {&"oak_planks": 1, &"pine_planks": 3})
	assert_eq(CKIngredients.count(bag, &"#planks"), 4)
	assert_eq(crafting.get_max_crafts(crafting.book.get_recipe(&"sticks"), bag), 2)
	var result := crafting.craft(&"sticks", 2, bag)
	assert_true(result.ok, str(result))
	assert_eq(bag.count(&"oak_planks") + bag.count(&"pine_planks"), 0, "mixed planks used")
	assert_eq(bag.count(&"stick"), 8)
	var missing := crafting.craft(&"sticks", 1, bag)
	assert_craft(missing, CKResult.Code.MISSING_INGREDIENTS)
	assert_eq(missing.missing, {&"#planks": 2})
	assert_eq(CKText.ingredient_name(&"#planks", db), "Any planks")


func test_shaped_recipe_matches_anywhere_in_the_grid() -> void:
	var db := make_tag_db()
	var crafting := make_tag_crafting(db)
	var pick := ["iron", "iron", "iron", "", "stick", "", "", "stick", ""]
	assert_eq(crafting.match_grid(_place(db, pick), 3).id, &"pick")
	var wrong := ["iron", "iron", "iron", "stick", "", "", "", "stick", ""]
	assert_eq(crafting.match_grid(_place(db, wrong), 3), null, "shape matters")
	# A 2x3 shape slides left or right in a 3x3 grid.
	var axe_right := ["", "iron", "iron", "", "iron", "stick", "", "", "stick"]
	assert_eq(crafting.match_grid(_place(db, axe_right), 3).id, &"axe")
	var axe_mirrored := ["iron", "iron", "", "stick", "iron", "", "stick", "", ""]
	assert_eq(crafting.match_grid(_place(db, axe_mirrored), 3).id, &"axe", "mirrored allowed")
	crafting.book.get_recipe(&"axe").mirrored = false
	assert_eq(crafting.match_grid(_place(db, axe_mirrored), 3), null, "mirror refused")
	assert_eq(crafting.match_grid(_place(db, ["iron", "iron", "stick", "stick"], 2), 2), null, "3x3 shape in a 2x2 grid")
	# Shaped recipes are also made from the bag, with ingredients counted from the pattern.
	assert_eq(crafting.book.get_recipe(&"pick").get_ingredients(), {&"iron": 3, &"stick": 2})
	var bag := make_bag(db, {&"iron": 3, &"stick": 2})
	assert_true(crafting.craft(&"pick", 1, bag).ok)


func test_grid_craft_takes_one_item_per_cell() -> void:
	var db := make_tag_db()
	var crafting := make_tag_crafting(db)
	var grid := _place(db, ["oak_planks", "pine_planks", "", "oak_planks", "pine_planks", "", "", "", ""], 3, 3)
	assert_eq(crafting.match_grid(grid, 3).id, &"box", "shapeless: 4 planks of any kind")
	assert_eq(crafting.get_grid_max_crafts(grid), 3)
	var bag := make_bag(db)
	var result := crafting.craft_grid(grid, 3, bag, 2)
	assert_true(result.ok, str(result))
	assert_eq(bag.count(&"gem"), 2)
	assert_eq(grid.count(&"oak_planks"), 2, "one per cell per craft")
	assert_craft(crafting.craft_grid(_place(db, ["gem"]), 3, bag), CKResult.Code.NO_MATCH)


func test_grid_teaches_unknown_recipes() -> void:
	var db := make_tag_db()
	var crafting := make_tag_crafting(db)
	crafting.book.get_recipe(&"box").known_from_start = false
	crafting.load_data({"known": []})
	assert_false(crafting.is_known(&"box"))
	var bag := make_bag(db)
	crafting.learn_from_grid = false
	var cells := ["oak_planks", "oak_planks", "", "oak_planks", "oak_planks"]
	assert_craft(crafting.craft_grid(_place(db, cells), 3, bag), CKResult.Code.NOT_KNOWN)
	crafting.learn_from_grid = true
	assert_true(crafting.craft_grid(_place(db, cells), 3, bag).ok)
	assert_true(crafting.is_known(&"box"))


func test_chance_bonus_and_quality_replay_with_a_seed() -> void:
	var db := make_tag_db()
	var outcomes := []
	for run in 2:
		var crafting := make_tag_crafting(db)
		var recipe := crafting.book.get_recipe(&"box")
		recipe.success_chance = 0.5
		recipe.failure_results.assign({&"ash": 1})
		recipe.quality_weights = PackedFloat32Array([50, 50])
		recipe.bonus_results.append(CKBonusResult.make(&"stick", 1, 0.5))
		var bag := make_bag(db, {&"oak_planks": 40}, 12)
		var result := crafting.craft(&"box", 10, bag)
		assert_true(result.ok, str(result))
		assert_eq(result.failures, bag.count(&"ash"), "one ash per failed craft")
		assert_eq(bag.count(&"gem"), 10 - result.failures)
		outcomes.append([result.failures, bag.count(&"stick"), result.produced])
		var fine := 0
		for slot in bag.size():
			var stack := bag.get_stack(slot)
			if stack != null and stack.item_id == &"gem" and stack.data.get(CKRecipe.QUALITY_KEY, 0) == 1:
				fine += stack.amount
		assert_true(fine > 0 and fine < 10 - result.failures, "two qualities rolled (%d fine)" % fine)
	assert_eq(outcomes[0], outcomes[1], "same seed, same outcomes")
	assert_true(outcomes[0][0] > 0 and outcomes[0][0] < 10, "some crafts failed")


func test_refused_craft_keeps_the_luck() -> void:
	var db := make_tag_db()
	var crafting := make_tag_crafting(db)
	crafting.book.get_recipe(&"box").success_chance = 0.5
	var state := crafting.rng.state
	var full := make_bag(db, {&"oak_planks": 4, &"iron": 20, &"stick": 20}, 3)
	assert_craft(crafting.craft(&"box", 1, full, make_bag(db, {&"pick": 1}, 1)), CKResult.Code.NO_ROOM)
	assert_eq(crafting.rng.state, state, "rng restored after a refused craft")


func test_station_rolls_once_per_craft_and_gives_xp() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	crafting.rng_seed = 3
	var ingot := crafting.book.get_recipe(&"ingot")
	ingot.bonus_results.append(CKBonusResult.make(&"coal", 1, 1.0))
	ingot.xp = 30
	ingot.required_level = 0
	crafting.level_thresholds = PackedInt32Array([50, 100])
	var levels := []
	crafting.level_up.connect(func(profession: StringName, level: int) -> void: levels.append([profession, level]))
	var forge := make_forge(crafting, 1)
	var bag := make_bag(db, {&"ore": 4, &"coal": 2})
	assert_true(forge.enqueue(&"ingot", 2, bag).ok)
	forge.advance(2.0)
	assert_true(forge.is_blocked(), "ingot + bonus coal need two slots")
	assert_eq(forge.output.count(&"ingot"), 0)
	forge.output.resize(3)
	forge.advance(0.0)
	assert_eq([forge.output.count(&"ingot"), forge.output.count(&"coal")], [1, 1], "the waiting roll is delivered")
	forge.advance(2.0)
	assert_eq(forge.output.count(&"coal"), 2)
	assert_eq(crafting.get_xp(&"forge"), 60, "profession = station id by default")
	assert_eq(crafting.get_level(&"forge"), 2)
	assert_eq(levels, [[&"forge", 2]])
	disconnect_all([crafting])


func test_level_gates_recipes() -> void:
	var db := make_tag_db()
	var crafting := make_tag_crafting(db)
	var bag := make_bag(db, {&"iron": 3, &"stick": 2})
	assert_craft(crafting.craft(&"axe", 1, bag), CKResult.Code.LEVEL_TOO_LOW)
	var axe_cells := ["iron", "iron", "", "iron", "stick", "", "", "stick", ""]
	assert_craft(crafting.craft_grid(_place(db, axe_cells), 3, bag), CKResult.Code.LEVEL_TOO_LOW)
	assert_eq(crafting.add_xp(&"smithing", 100), 2)
	assert_eq(crafting.get_recipes_unlocked_at(&"smithing", 2).size(), 1)
	assert_true(crafting.craft(&"axe", 1, bag).ok)
	var progress := crafting.get_level_progress(&"smithing")
	assert_eq([progress.level, progress.current, progress.next], [2, 100, 250])
	assert_eq(CKText.result_message(CKResult.failure(CKResult.Code.LEVEL_TOO_LOW)), "Your skill is too low for this recipe.")


func test_auto_craft_makes_missing_components() -> void:
	var db := make_tag_db()
	var crafting := make_tag_crafting(db)
	var bag := make_bag(db, {&"pine_log": 1, &"iron": 3})
	assert_craft(crafting.craft(&"pick", 1, bag), CKResult.Code.MISSING_INGREDIENTS, "off by default")
	crafting.auto_craft = true
	assert_eq(crafting.get_craftable_count(crafting.book.get_recipe(&"pick"), bag), 1)
	var result := crafting.craft(&"pick", 1, bag)
	assert_true(result.ok, str(result))
	assert_eq(result.components, [[&"planks", 1], [&"sticks", 1]], "log -> planks -> sticks")
	assert_eq(bag.count(&"pick"), 1)
	assert_eq(bag.count(&"stick"), 2, "4 sticks made, 2 used")
	assert_eq(bag.count(&"pine_log"), 0)
	var poor := make_bag(db, {&"iron": 3})
	assert_craft(crafting.craft(&"pick", 1, poor), CKResult.Code.MISSING_INGREDIENTS)
	assert_eq(poor.count(&"iron"), 3, "nothing taken")


func test_auto_craft_at_a_station_and_tag_refund() -> void:
	var db := make_tag_db()
	var crafting := make_tag_crafting(db)
	crafting.auto_craft = true
	var forge := CKStation.new()
	forge.station_id = &"bench"
	forge.crafting = crafting
	forge.auto_process = false
	add_to_tree(forge)
	crafting.book.add_recipe(CKRecipe.make(&"crate", {&"#planks": 3, &"stick": 1}, {&"gem": 1}, &"bench", 1.0))
	crafting.learn(&"crate")
	var bag := make_bag(db, {&"oak_planks": 1, &"pine_planks": 4, &"oak_log": 1})
	var result := forge.enqueue(&"crate", 1, bag)
	assert_true(result.ok, str(result))
	assert_eq(result.components, [[&"sticks", 1]])
	assert_eq(bag.count(&"stick"), 3, "leftover sticks to the bag")
	assert_true(forge.cancel(0, bag).ok)
	assert_eq(CKIngredients.count(bag, &"#planks"), 3, "the planks taken for the crate come back")
	var data: Dictionary = JSON.parse_string(JSON.stringify(forge.to_data()))
	assert_eq(int(data.version), 2)


func test_saves_keep_xp_and_luck_and_read_version_1() -> void:
	var db := make_tag_db()
	var crafting := make_tag_crafting(db)
	crafting.add_xp(&"smithing", 120)
	crafting.rng.randf()
	var data: Dictionary = JSON.parse_string(JSON.stringify(crafting.to_data()))
	var next := crafting.rng.randf()
	var other := make_tag_crafting(db)
	assert_true(other.load_data(data))
	assert_eq(other.get_level(&"smithing"), 2)
	assert_eq(other.rng.randf(), next, "random state restored")
	assert_true(other.load_data({"version": 1, "known": ["pick"]}), "1.0 save")
	assert_eq(other.get_xp(&"smithing"), 0)
	# A 1.0 station save (no "used") still refunds on cancel.
	var forge := make_forge(make_crafting(make_db()))
	assert_true(forge.load_data({"version": 1, "jobs": [{"recipe": "ingot", "count": 2, "done": 1, "progress": 0.5}]}))
	var bag := make_bag(forge.crafting.database)
	assert_true(forge.cancel(0, bag).ok)
	assert_eq(bag.count(&"ore"), 2)


func test_validation_of_tags_and_patterns() -> void:
	var db := make_tag_db()
	var crafting := make_tag_crafting(db)
	assert_eq(crafting.book.validate(db), PackedStringArray())
	crafting.book.add_recipe(CKRecipe.make(&"bad_tag", {&"#nothing": 1}, {&"gem": 1}))
	crafting.book.add_recipe(CKRecipe.make_shaped(&"bad_key", ["XS"], {"S": &"stick"}, {&"gem": 1}))
	var problems := crafting.book.validate(db)
	assert_eq(problems.size(), 2, str(problems))


func test_grid_panel() -> void:
	var db := make_tag_db()
	var crafting := make_tag_crafting(db)
	var bag := make_bag(db)
	var ui := IKInventoryUI.new()
	add_to_tree(ui)
	var panel := CKCraftGridPanel.new()
	panel.crafting = crafting
	panel.bag = bag
	ui.add_child(panel)
	panel.grid_width = 2
	panel.grid_height = 2
	assert_eq(panel.grid.size(), 4)
	assert_eq(panel.view.get_slot_views().size(), 4)
	await wait_frames(1)
	fill(panel.grid, ["oak_planks", "pine_planks", "oak_planks", "oak_planks"], 2)
	await wait_frames(1)
	assert_eq(panel.get_match().id, &"box")
	assert_false(panel._craft.disabled)
	assert_true(panel.craft(9999).ok)
	assert_eq(bag.count(&"gem"), 2)
	assert_eq(panel.grid.get_totals(), {}, "grid used up")
	panel.grid.add(&"iron", 1)
	panel.clear()
	assert_eq(bag.count(&"iron"), 1, "Clear returns items to the bag")
	disconnect_all([crafting])


func test_window_shows_tags_levels_and_odds() -> void:
	var db := make_tag_db()
	var crafting := make_tag_crafting(db)
	crafting.book.get_recipe(&"box").success_chance = 0.8
	var window := CKCraftingWindow.new()
	window.crafting = crafting
	window.bag = make_bag(db, {&"oak_planks": 2})
	add_to_tree(window)
	await wait_frames(2)
	window._select(&"box")
	assert_true(window._detail_text.text.contains("Any planks"), window._detail_text.text)
	assert_true(window._detail_text.text.contains("80%"))
	window._select(&"axe")
	assert_true(window._detail_text.text.contains("Needs Smithing level 2"), window._detail_text.text)
	assert_true(window._action.disabled)


func test_demo_fits_the_screen_and_grid_works() -> void:
	var demo: Node = add_to_tree(load("res://demo/craft/craft_demo.tscn").instantiate())
	await wait_frames(3)
	var margin: Control = demo.get_children().filter(func(n: Node) -> bool: return n is MarginContainer)[0]
	var needed := margin.get_combined_minimum_size()
	assert_true(needed.x <= 1280 and needed.y <= 720, "demo layout needs %s" % needed)
	var bag: IKContainer = demo.bag.container
	bag.add(&"iron_ingot", 1)
	var grid: IKContainer = demo.grid_panel.grid
	IKTransaction.new().move(bag, bag.find_slots(&"iron_ingot")[0], grid, 1).commit()
	assert_true(demo.crafting.craft(&"oak_planks", 1, bag).ok)
	IKTransaction.new().move(bag, bag.find_slots(&"oak_planks")[0], grid, 4, 1).commit()
	assert_eq(demo.grid_panel.get_match().id, &"dagger")
	assert_true(demo.grid_panel.craft().ok)
	assert_eq(bag.count(&"dagger"), 1)
	assert_eq(demo.crafting.get_xp(&"smithing"), 4)
