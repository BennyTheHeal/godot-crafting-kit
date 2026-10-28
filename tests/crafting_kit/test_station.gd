extends "res://tests/crafting_kit/ck_test_case.gd"
## Stations: timed queue, output tray, blocking when full, cancel with refund, saving.


func test_queue_takes_ingredients_and_delivers_over_time() -> void:
	var db := make_db()
	var forge := make_forge(make_crafting(db))
	var bag := make_bag(db, {&"ore": 6, &"coal": 3})
	var finished := []
	forge.job_finished.connect(func(recipe: CKRecipe, count: int) -> void: finished.append([recipe.id, count]))
	assert_true(forge.enqueue(&"ingot", 3, bag).ok)
	assert_eq(bag.count(&"ore"), 0, "ingredients taken when queued")
	forge.advance(1.0)
	assert_eq(forge.output.count(&"ingot"), 0)
	assert_eq(forge.get_jobs()[0].progress, 0.5)
	forge.advance(3.5)
	assert_eq(forge.output.count(&"ingot"), 2)
	forge.advance(10.0)
	assert_eq(forge.output.count(&"ingot"), 3)
	assert_false(forge.is_busy())
	assert_eq(finished, [[&"ingot", 3]])
	assert_true(forge.collect(bag).ok)
	assert_eq(bag.count(&"ingot"), 3)


func test_speed() -> void:
	var db := make_db()
	var forge := make_forge(make_crafting(db))
	forge.speed = 2.0
	var bag := make_bag(db, {&"ore": 2, &"coal": 1})
	forge.enqueue(&"ingot", 1, bag)
	forge.advance(1.0)
	assert_eq(forge.output.count(&"ingot"), 1)


func test_refusals() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	var forge := make_forge(crafting)
	forge.queue_size = 1
	var bag := make_bag(db, {&"ore": 4, &"coal": 2, &"log": 1})
	assert_craft(forge.enqueue(&"planks", 1, bag), CKResult.Code.WRONG_STATION)
	assert_craft(forge.enqueue(&"sword", 1, bag), CKResult.Code.NOT_KNOWN)
	var missing := forge.enqueue(&"ingot", 3, bag)
	assert_craft(missing, CKResult.Code.MISSING_INGREDIENTS)
	assert_eq(missing.missing, {&"ore": 2, &"coal": 1})
	assert_true(forge.enqueue(&"ingot", 1, bag).ok)
	assert_craft(forge.enqueue(&"ingot", 1, bag), CKResult.Code.QUEUE_FULL)


func test_full_tray_waits_without_loss() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	crafting.learn(&"sword")
	var forge := make_forge(crafting, 1)
	var bag := make_bag(db, {&"ingot": 6})
	assert_true(forge.enqueue(&"sword", 2, bag).ok)
	forge.advance(20.0)
	assert_eq(forge.output.count(&"sword"), 1, "one slot: one sword (stack 1)")
	assert_true(forge.is_blocked())
	assert_true(forge.is_busy())
	assert_true(forge.collect(bag).ok)
	assert_false(forge.is_blocked())
	forge.advance(0.0)
	assert_eq(forge.output.count(&"sword"), 1, "the waiting sword arrives as soon as there is room")
	assert_false(forge.is_busy())


func test_cancel_refunds_crafts_not_finished() -> void:
	var db := make_db()
	var forge := make_forge(make_crafting(db))
	var bag := make_bag(db, {&"ore": 6, &"coal": 3})
	forge.enqueue(&"ingot", 3, bag)
	forge.advance(3.0)  # one done, the second halfway
	var result := forge.cancel(0, bag)
	assert_true(result.ok)
	assert_eq(result.amount, 2)
	assert_eq(bag.count(&"ore"), 4)
	assert_eq(bag.count(&"coal"), 2)
	assert_eq(forge.output.count(&"ingot"), 1, "finished results stay")
	assert_false(forge.is_busy())


func test_cancel_refused_when_refund_does_not_fit() -> void:
	var db := make_db()
	var forge := make_forge(make_crafting(db))
	var bag := make_bag(db, {&"ore": 2, &"coal": 1})
	forge.enqueue(&"ingot", 1, bag)
	var tiny := IKContainer.new(&"tiny", 1, db)
	assert_craft(forge.cancel(0, tiny), CKResult.Code.NO_ROOM)
	assert_true(forge.is_busy(), "the job is kept")
	assert_eq(tiny.count(&"ore"), 0)


func test_collect_partial() -> void:
	var db := make_db()
	var forge := make_forge(make_crafting(db))
	var bag := make_bag(db, {&"ore": 4, &"coal": 2})
	forge.enqueue(&"ingot", 2, bag)
	forge.advance(10.0)
	var tiny := IKContainer.new(&"tiny", 1, db)
	tiny.add(&"ingot", 19)
	var result := forge.collect(tiny)
	assert_craft(result, CKResult.Code.NO_ROOM)
	assert_eq(result.amount, 1)
	assert_eq(forge.output.count(&"ingot"), 1)


func test_save_and_load() -> void:
	var db := make_db()
	var crafting := make_crafting(db)
	var forge := make_forge(crafting)
	var bag := make_bag(db, {&"ore": 6, &"coal": 3})
	forge.enqueue(&"ingot", 3, bag)
	forge.advance(3.0)
	var data: Dictionary = JSON.parse_string(JSON.stringify(forge.to_data()))
	var copy := make_forge(crafting)
	assert_true(copy.load_data(data))
	assert_eq(copy.output.count(&"ingot"), 1)
	assert_eq(copy.get_jobs()[0].done, 1)
	copy.advance(10.0)
	assert_eq(copy.output.count(&"ingot"), 3, "the job resumes where it was")
	assert_false(copy.load_data({"jobs": "nope"}))


func test_items_are_conserved() -> void:
	# Queue, advance, collect and cancel at random: ore and coal in = ingots out + refunds.
	var db := make_db()
	var forge := make_forge(make_crafting(db), 2)
	var bag := make_bag(db, {&"ore": 20, &"coal": 10}, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for step in 300:
		match rng.randi_range(0, 3):
			0:
				forge.enqueue(&"ingot", rng.randi_range(1, 3), bag)
			1:
				forge.advance(rng.randf_range(0.0, 5.0))
			2:
				forge.collect(bag)
			3:
				if forge.is_busy():
					forge.cancel(0, bag)
		var queued := 0
		for job in forge.get_jobs():
			queued += job.count - job.done
		var ingots := bag.count(&"ingot") + forge.output.count(&"ingot")
		assert_eq(bag.count(&"ore") + 2 * (queued + ingots), 20, "ore, step %d" % step)
		assert_eq(bag.count(&"coal") + queued + ingots, 10, "coal, step %d" % step)
