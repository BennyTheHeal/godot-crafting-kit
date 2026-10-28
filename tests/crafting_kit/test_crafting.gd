extends "res://tests/crafting_kit/ck_test_case.gd"
## Hand crafting, checks, learning and discovery, saving the known recipes.


func test_hand_craft_is_atomic() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	var bag := make_bag(db, {&"log": 3})
	var crafted := []
	crafting.crafted.connect(func(recipe: CKRecipe, count: int) -> void: crafted.append([recipe.id, count]))
	assert_true(crafting.craft(&"planks", 2, bag).ok)
	assert_eq(bag.count(&"log"), 1)
	assert_eq(bag.count(&"plank"), 8)
	assert_eq(crafted, [[&"planks", 2]])


func test_missing_ingredients_are_listed() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	var bag := make_bag(db, {&"log": 1})
	var result := crafting.craft(&"planks", 3, bag)
	assert_craft(result, CKResult.Code.MISSING_INGREDIENTS)
	assert_eq(result.missing, {&"log": 2})
	assert_eq(bag.count(&"log"), 1, "nothing taken")
	assert_eq(crafting.get_max_crafts(crafting.book.get_recipe(&"planks"), bag), 1)


func test_no_room_takes_nothing() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	var bag := make_bag(db, {&"log": 1, &"ore": 20, &"coal": 20, &"herb": 20}, 4)  # every slot used
	var result := crafting.craft(&"planks", 1, bag)
	# The log slot empties, so the planks fit: paying can free the slot it needs.
	assert_true(result.ok, str(result))
	bag.add(&"log", 1)
	var full := make_bag(db, {&"log": 2, &"ore": 20, &"coal": 20, &"herb": 20, &"plank": 20}, 5)
	full.remove(&"plank", 18)  # 2 planks: room for 18 more, 4 x 5 = 20 needed
	assert_craft(crafting.craft(&"planks", 5, full), CKResult.Code.MISSING_INGREDIENTS, "only 2 logs")
	var tight := make_bag(db, {&"log": 2, &"ore": 20, &"coal": 20, &"herb": 20, &"plank": 18}, 5)
	assert_craft(crafting.craft(&"planks", 1, tight), CKResult.Code.NO_ROOM, "4 planks, room for 2")
	assert_eq(tight.count(&"log"), 2, "the log is still there")


func test_separate_result_container() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	var bag := make_bag(db, {&"log": 1})
	var chest := make_bag(db, {}, 2)
	assert_true(crafting.craft(&"planks", 1, bag, chest).ok)
	assert_eq(chest.count(&"plank"), 4)
	assert_eq(bag.count(&"plank"), 0)


func test_station_recipes_refuse_hand_crafting() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	var bag := make_bag(db, {&"ore": 2, &"coal": 1})
	assert_craft(crafting.craft(&"ingot", 1, bag), CKResult.Code.WRONG_STATION)
	assert_craft(crafting.craft(&"nope", 1, bag), CKResult.Code.UNKNOWN_RECIPE)


func test_learning_and_discovery() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	var learned := []
	crafting.recipe_learned.connect(func(recipe: CKRecipe) -> void: learned.append(recipe.id))
	assert_false(crafting.is_known(&"sword"))
	var bag := make_bag(db)
	crafting.watch(bag)
	bag.add(&"herb", 2)
	assert_false(crafting.is_known(&"potion"), "not discoverable: must be taught")
	bag.add(&"ingot", 1)
	assert_true(crafting.is_known(&"sword"), "picked up its only ingredient")
	assert_eq(learned, [&"sword"])
	assert_true(crafting.learn(&"potion"))
	assert_false(crafting.learn(&"potion"), "already known")
	assert_eq(crafting.get_known_recipes().size(), 4)


func test_unknown_recipe_is_refused() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	var bag := make_bag(db, {&"herb": 2})
	assert_craft(crafting.check(&"potion", 1, bag), CKResult.Code.NOT_KNOWN)


func test_learning_can_be_turned_off() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	crafting.use_learning = false
	assert_true(crafting.is_known(&"potion"))


func test_save_and_load_known_recipes() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	crafting.learn(&"potion")
	var data: Dictionary = JSON.parse_string(JSON.stringify(crafting.to_data()))
	var other := make_crafting(db)
	assert_false(other.is_known(&"potion"))
	assert_true(other.load_data(data))
	assert_true(other.is_known(&"potion"))
	assert_false(other.is_known(&"sword"))
	assert_false(other.load_data({"bad": 1}))


func test_book_validation() -> void:
	var db := make_db()
	var book := make_book()
	assert_eq(book.validate(db), PackedStringArray())
	book.add_recipe(CKRecipe.make(&"planks", {&"gold": 1}, {}))
	var problems := book.validate(db)
	assert_eq(problems.size(), 3, str(problems))
