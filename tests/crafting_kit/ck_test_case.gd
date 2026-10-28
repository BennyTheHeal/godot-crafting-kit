extends RefCounted
## Base class for Crafting Kit tests: assertions and shared fixtures.

var _failures := PackedStringArray()
var _nodes: Array[Node] = []


func get_failures() -> PackedStringArray:
	return _failures


func get_tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Adds [param node] to the scene root; it is freed after the test.
func add_to_tree(node: Node) -> Node:
	get_tree().root.add_child(node)
	_nodes.append(node)
	return node


func wait_frames(count: int = 1) -> void:
	for i in count:
		await get_tree().process_frame


## Called by the runner after each test.
func cleanup() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	await get_tree().process_frame


func fail(message: String) -> void:
	_failures.append(message)


func assert_true(condition: bool, message: String = "expected true") -> void:
	if not condition:
		fail(message)


func assert_false(condition: bool, message: String = "expected false") -> void:
	if condition:
		fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("%sexpected <%s> but got <%s>" % [message + ": " if message else "", expected, actual])


func assert_ok(result: IKResult, message: String = "") -> void:
	if result == null or not result.ok:
		fail("%sexpected OK, got %s" % [message + ": " if message else "", result])


func assert_code(result: IKResult, code: IKResult.Code, message: String = "") -> void:
	if result == null or result.code != code:
		fail("%sexpected %s, got %s" % [message + ": " if message else "", IKResult.Code.keys()[code], result])


## Disconnects every signal of [param objects]. Call at the end of tests whose
## lambdas capture the emitter, otherwise the reference cycle leaks.
func disconnect_all(objects: Array) -> void:
	for object: Object in objects:
		for info in object.get_signal_list():
			for connection in object.get_signal_connection_list(info.name):
				object.disconnect(info.name, connection.callable)




# --- Fixtures ----------------------------------------------------------------

func assert_craft(result: CKResult, code: CKResult.Code, message: String = "") -> void:
	if result == null or result.code != code:
		fail("%sexpected %s, got %s" % [message + ": " if message else "", CKResult.Code.keys()[code], result])


func make_item(id: StringName, max_stack: int = 20) -> IKItemDefinition:
	var item := IKItemDefinition.new()
	item.id = id
	item.display_name = String(id).capitalize()
	item.max_stack = max_stack
	return item


## log, plank, ore, coal, ingot, sword (stack 1), herb, potion.
func make_db() -> IKItemDatabase:
	var db := IKItemDatabase.new()
	for id: StringName in [&"log", &"plank", &"ore", &"coal", &"ingot", &"herb", &"potion"]:
		db.add_item(make_item(id))
	db.add_item(make_item(&"sword", 1))
	return db


## planks (hand, 1 log -> 4 planks), ingot (forge, 2 ore + 1 coal, 2 s), sword (forge, 3 ingots, 5 s,
## learned by discovery), potion (alchemy, 2 herbs, not discoverable, unknown).
func make_book() -> CKRecipeBook:
	var book := CKRecipeBook.new()
	book.add_recipe(CKRecipe.make(&"planks", {&"log": 1}, {&"plank": 4}))
	book.add_recipe(CKRecipe.make(&"ingot", {&"ore": 2, &"coal": 1}, {&"ingot": 1}, &"forge", 2.0))
	var sword := CKRecipe.make(&"sword", {&"ingot": 3}, {&"sword": 1}, &"forge", 5.0)
	sword.known_from_start = false
	book.add_recipe(sword)
	var potion := CKRecipe.make(&"potion", {&"herb": 2}, {&"potion": 1}, &"alchemy", 1.0)
	potion.known_from_start = false
	potion.discover_when_held = false
	book.add_recipe(potion)
	return book


func make_crafting(db: IKItemDatabase) -> CKCrafting:
	var crafting := CKCrafting.new()
	crafting.book = make_book()
	crafting.database = db
	add_to_tree(crafting)
	return crafting


func make_forge(crafting: CKCrafting, output_slots: int = 6) -> CKStation:
	var forge := CKStation.new()
	forge.station_id = &"forge"
	forge.crafting = crafting
	forge.output_size = output_slots
	forge.auto_process = false
	add_to_tree(forge)
	return forge


func make_bag(db: IKItemDatabase, items: Dictionary = {}, slots: int = 8) -> IKContainer:
	var bag := IKContainer.new(&"bag", slots, db)
	for item_id: StringName in items:
		bag.add(item_id, items[item_id])
	return bag
