extends IKInventoryUI
## Crafting Kit demo: a small workshop. Craft by hand, queue jobs at the workbench,
## the forge and the alchemy table, discover recipes by gathering their ingredients,
## learn one from a book, collect results, save / load, and switch art directions.
## New in 1.1: a 3x3 crafting grid (shaped recipes, drag items from the bag), "any planks"
## ingredients, potions that can fail or come out finer, bonus nuggets at the forge,
## profession levels that unlock recipes, and optional auto-craft of components.

const ART := "res://addons/inventory_kit/art/"
const DIRECTIONS := {"painted": "Hand-painted", "realistic": "Realistic", "cartoon": "Cartoon", "flat": "Flat"}
const RECIPES := preload("res://demo/craft/demo_recipes.gd")
const SAVE_DIR := "user://craft_demo/"
const SITE := "https://banc-essai.site-testeurs.workers.dev/?src=craft-demo"
const GATHERED: Array[StringName] = [&"oak_log", &"pine_log", &"birch_log", &"plant_fiber", &"iron_ore", &"coal", &"copper_ore", &"tin_ore",
	&"rawhide", &"herb", &"feather", &"resin", &"crystal", &"magic_essence", &"apple", &"bone"]

var bag: IKInventory
var crafting: CKCrafting
var stations: Array[CKStation] = []
var window: CKCraftingWindow
var grid_panel: CKCraftGridPanel
## Recipes / Crafting grid tabs.
var grid_tabs: TabContainer
var art_direction := ""
var _picker: OptionButton
var _status: Label
var _rng := RandomNumberGenerator.new()
var _save := IKSaveFile.new(SAVE_DIR + "inventory.json")


static func available_directions() -> Array[String]:
	var result: Array[String] = []
	for da in DIRECTIONS:
		if ResourceLoader.exists(ART + "%s/%s_items.tres" % [da, da]):
			result.append(da)
	return result


func _ready() -> void:
	_rng.seed = 12
	var directions := available_directions()
	var database: IKItemDatabase = load(ART + "%s/%s_items.tres" % [directions[0], directions[0]])
	bag = IKInventory.new()
	bag.name = "Bag"
	bag.container_id = &"bag"
	bag.size = 18
	bag.database = database
	bag.initial_items.assign({&"oak_log": 10, &"pine_log": 4, &"plant_fiber": 9, &"resin": 3, &"feather": 6, &"iron_ore": 8,
		&"coal": 8, &"copper_ore": 6, &"tin_ore": 2, &"rawhide": 4, &"herb": 10, &"apple": 3, &"bone": 2})
	add_child(bag)
	crafting = CKCrafting.new()
	crafting.name = "Crafting"
	crafting.book = RECIPES.book()
	crafting.database = database
	crafting.level_thresholds = RECIPES.LEVELS
	crafting.rng_seed = 12  # same outcomes on every run: handy for tests and bug reports
	add_child(crafting)
	for place in [[&"workbench", "Workbench"], [&"forge", "Forge"], [&"alchemy", "Alchemy table"]]:
		var station := CKStation.new()
		station.name = String(place[0]).capitalize()
		station.station_id = place[0]
		station.display_name = place[1]
		station.profession = RECIPES.PROFESSIONS[place[0]]
		station.crafting = crafting
		station.database = database
		add_child(station)
		stations.append(station)
	_build_layout(directions)
	super._ready()
	crafting.watch(bag.container)
	window.crafting = crafting
	window.bag = bag.container
	window.stations = stations
	grid_panel.crafting = crafting
	grid_panel.bag = bag.container
	grid_panel.crafted.connect(func(result: CKResult) -> void:
		_set_status("Made in the grid: %d × %s." % [result.amount, crafting.book.get_recipe(result.recipe_id).get_display_name(crafting.database)]))
	crafting.level_up.connect(_on_level_up)
	crafting.craft_failed.connect(func(recipe: CKRecipe, count: int) -> void:
		_set_status("%d × %s failed: the ingredients are lost." % [count, recipe.get_display_name(crafting.database)], true))
	crafting.recipe_learned.connect(func(recipe: CKRecipe) -> void:
		_set_status("New recipe: %s!" % recipe.get_display_name(crafting.database)))
	for station in stations:
		station.job_finished.connect(func(recipe: CKRecipe, count: int) -> void:
			_set_status("%s: %d × %s ready to collect." % [station.get_display_name(), count, recipe.get_display_name(crafting.database)]))
	interaction_failed.connect(func(result: IKResult) -> void: _set_status(IKText.result_message(result), true))
	apply_art_direction(directions[0])


## Icons, slot skin and window theme change; recipes, queues and items do not.
func apply_art_direction(da: String) -> void:
	art_direction = da
	var database: IKItemDatabase = load(ART + "%s/%s_items.tres" % [da, da])
	bag.container.database = database
	cursor.container.database = database
	crafting.database = database
	for station in stations:
		station.database = database
	theme = load(ART + "%s/%s_theme.tres" % [da, da])
	skin = load(ART + "%s/%s_skin.tres" % [da, da])
	window.skin = skin
	grid_panel.refresh()
	var index := available_directions().find(da)
	if _picker != null and index >= 0 and _picker.selected != index:
		_picker.select(index)


## Adds a handful of random raw materials, as if the player went out gathering.
func gather() -> void:
	var transaction := IKTransaction.new()
	var found := PackedStringArray()
	for i in 3:
		var item_id: StringName = GATHERED[_rng.randi_range(0, GATHERED.size() - 1)]
		var amount := _rng.randi_range(1, 3)
		transaction.add(bag.container, item_id, amount, true)
		found.append("%d %s" % [amount, IKText.item_name(bag.container.database.get_item(item_id))])
	var result := transaction.commit()
	_set_status("Gathered " + ", ".join(found) + "." if result.ok else IKText.result_message(result), not result.ok)


func fast_forward() -> void:
	for station in stations:
		station.advance(10.0)
	_set_status("Ten seconds later...")


func _build_layout(directions: Array[String]) -> void:
	var background := ColorRect.new()
	background.color = Color(0.07, 0.08, 0.10)
	background.mouse_filter = MOUSE_FILTER_IGNORE
	background.set_anchors_preset(PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	column.add_child(header)
	var title := Label.new()
	title.text = "Crafting Kit — demo"
	title.add_theme_font_size_override(&"font_size", 22)
	header.add_child(title)
	_picker = OptionButton.new()
	for da in directions:
		_picker.add_item(DIRECTIONS[da])
	_picker.item_selected.connect(func(index: int) -> void: apply_art_direction(directions[index]))
	_picker.focus_mode = FOCUS_NONE
	header.add_child(_picker)
	_button(header, "Save", _on_save)
	_button(header, "Load", _on_load)
	var site := LinkButton.new()
	site.text = "More kits & our games »"
	site.uri = SITE
	site.size_flags_vertical = SIZE_SHRINK_CENTER
	header.add_child(site)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 14)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 8)
	body.add_child(left)
	var bag_frame := PanelContainer.new()
	left.add_child(bag_frame)
	var bag_box := VBoxContainer.new()
	bag_frame.add_child(bag_box)
	var bag_label := Label.new()
	bag_label.text = "Your bag"
	bag_box.add_child(bag_label)
	var view := IKContainerView.new()
	view.name = "BagView"
	view.columns = 6
	view.inventory = bag
	bag_box.add_child(view)
	var actions := HBoxContainer.new()
	left.add_child(actions)
	_button(actions, "Gather materials", gather)
	_button(actions, "Read the old book", func() -> void:
		_set_status("You learn the antidote recipe." if crafting.learn(&"antidote") else "Nothing new in this book."))
	var options := HBoxContainer.new()
	left.add_child(options)
	_button(options, "Wait 10 seconds", fast_forward)
	var auto := CheckBox.new()
	auto.text = "Auto-craft components"
	auto.tooltip_text = "Missing planks, thread or cloth are made from what you hold, in the same craft."
	auto.focus_mode = FOCUS_NONE
	auto.toggled.connect(func(on: bool) -> void:
		crafting.auto_craft = on
		window.refresh())
	options.add_child(auto)
	_status = Label.new()
	_status.text = "Pick up the right ingredients to discover new recipes."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(360, 0)
	_status.clip_text = false
	_status.size_flags_vertical = SIZE_EXPAND_FILL
	left.add_child(_status)

	window = CKCraftingWindow.new()
	window.name = "CraftingWindow"
	window.size_flags_horizontal = SIZE_EXPAND_FILL
	window.size_flags_vertical = SIZE_EXPAND_FILL
	window.columns = 5
	window.item_size = Vector2(58, 58)
	window.close_requested.connect(func() -> void: _set_status("Cancel in the window: a game would close it here."))
	# Right side: the recipe window, and the crafting grid in a second tab.
	var places := TabContainer.new()
	places.size_flags_horizontal = SIZE_EXPAND_FILL
	places.size_flags_vertical = SIZE_EXPAND_FILL
	places.tab_focus_mode = FOCUS_NONE
	body.add_child(places)
	window.name = "Recipes"
	places.add_child(window)
	grid_panel = CKCraftGridPanel.new()
	grid_panel.name = "Crafting grid"
	grid_panel.title = "Drag items from your bag into the grid: shapes make weapons."
	places.add_child(grid_panel)
	grid_tabs = places


func _button(parent: Control, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)


func _on_save() -> void:
	return_held()
	grid_panel.clear()  # like closing a crafting table: what was in the grid goes back to the bag
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var error := _save.save([bag.container])
	var data := {"crafting": crafting.to_data()}
	for station in stations:
		data[String(station.station_id)] = station.to_data()
	var file := FileAccess.open(SAVE_DIR + "crafting.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "\t"))
	_set_status("Saved: bag, known recipes, queues and trays." if error == OK and file != null else "Save failed.", error != OK or file == null)


func _on_load() -> void:
	return_held()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_DIR + "crafting.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		_set_status("Nothing to load yet: press Save first.", true)
		return
	var report := _save.load_into([bag.container])
	if not report.ok:
		_set_status(report.error, true)
		return
	if typeof(parsed.get("crafting")) == TYPE_DICTIONARY:
		crafting.load_data(parsed.crafting)
	for station in stations:
		var saved: Variant = parsed.get(String(station.station_id))
		if typeof(saved) == TYPE_DICTIONARY:
			station.load_data(saved)
	_set_status("Loaded.")


func _on_level_up(profession: StringName, level: int) -> void:
	var names := PackedStringArray()
	for recipe in crafting.get_recipes_unlocked_at(profession, level):
		names.append(recipe.get_display_name(crafting.database))
	_set_status("%s level %d!%s" % [CKText.profession_name(profession), level,
		" Unlocked: %s." % ", ".join(names) if not names.is_empty() else ""])


func _set_status(text: String, warning: bool = false) -> void:
	_status.text = text
	_status.modulate = Color(1, 0.6, 0.5) if warning else Color(0.7, 1, 0.7)
