extends "res://tests/crafting_kit/ck_test_case.gd"
## The crafting window and the demo scene: tabs, crafting and queueing through the UI,
## unknown recipes, cancel / collect, save / load.


func _window() -> Dictionary:
	var db := make_db()
	var crafting := make_crafting(db)
	var forge := make_forge(crafting)
	var bag := make_bag(db, {&"log": 2, &"ore": 4, &"coal": 2})
	var window := CKCraftingWindow.new()
	window.crafting = crafting
	window.bag = bag
	window.stations = [forge]
	add_to_tree(window)
	return {"window": window, "crafting": crafting, "forge": forge, "bag": bag}


func test_tabs_and_recipes() -> void:
	var w := _window()
	await wait_frames(2)
	var window: CKCraftingWindow = w.window
	assert_eq(window.get_places().size(), 2, "by hand + forge")
	assert_eq(window._grid.get_child_count(), 1, "planks by hand")
	window.show_tab(1)
	await wait_frames(1)
	assert_eq(window._grid.get_child_count(), 2, "ingot + unknown sword (silhouette)")
	window.show_unknown = false
	window.refresh()
	assert_eq(window._grid.get_child_count(), 1)


func test_craft_by_hand_through_the_window() -> void:
	var w := _window()
	await wait_frames(2)
	var window: CKCraftingWindow = w.window
	window._select(&"planks")
	window._amount.value = 2
	window._on_action()
	await wait_frames(2)
	assert_eq(w.bag.count(&"plank"), 8)


func test_queue_cancel_and_collect_through_the_window() -> void:
	var w := _window()
	await wait_frames(2)
	var window: CKCraftingWindow = w.window
	var forge: CKStation = w.forge
	window.show_tab(1)
	await wait_frames(1)
	window._select(&"ingot")
	window._amount.value = 2
	window._on_action()
	await wait_frames(1)
	assert_true(forge.is_busy())
	assert_eq(window._queue_rows.get_child_count(), 1)
	forge.advance(2.0)
	window._on_cancel(0)
	assert_eq(w.bag.count(&"ore"), 2, "one craft refunded")
	window._on_collect()
	assert_eq(w.bag.count(&"ingot"), 1)


func test_refusal_is_reported() -> void:
	var w := _window()
	await wait_frames(2)
	var window: CKCraftingWindow = w.window
	var texts := []
	window.refused.connect(func(_r: CKResult, text: String) -> void: texts.append(text))
	window.show_tab(1)
	await wait_frames(1)
	window._select(&"ingot")
	w.bag.remove(&"coal", 2)
	window._on_action()
	assert_eq(texts, ["Missing ingredients."])


func test_tab_shortcuts() -> void:
	var w := _window()
	await wait_frames(2)
	var window: CKCraftingWindow = w.window
	var event := InputEventAction.new()
	event.action = CKCraftingWindow.TAB_NEXT
	event.pressed = true
	window._unhandled_input(event)
	assert_eq(window.current_tab, 1)
	window._unhandled_input(event)
	assert_eq(window.current_tab, 0, "wraps around")


func test_demo_runs_in_every_art_direction() -> void:
	var demo: Node = add_to_tree(load("res://demo/craft/craft_demo.tscn").instantiate())
	await wait_frames(3)
	for da in demo.available_directions():
		demo.apply_art_direction(da)
		for tab in demo.window.get_places().size():
			demo.window.show_tab(tab)
			await wait_frames(1)
			assert_true(demo.window._grid.get_child_count() > 0, "%s tab %d has recipes" % [da, tab])
	var bag: IKContainer = demo.bag.container
	assert_true(demo.crafting.craft(&"oak_planks", 2, bag).ok)
	assert_true(demo.stations[1].enqueue(&"iron_ingot", 2, bag).ok)
	demo.fast_forward()
	assert_eq(demo.stations[1].output.count(&"iron_ingot"), 2)
	assert_true(demo.crafting.is_known(&"steel_ingot") == false)
	demo.stations[1].collect(bag)
	assert_true(demo.crafting.is_known(&"steel_ingot"), "discovered when iron ingots arrived in the bag")
	demo._on_save()
	demo.crafting.learn(&"antidote")
	demo._on_load()
	assert_false(demo.crafting.is_known(&"antidote"), "Load restores the known recipes")
