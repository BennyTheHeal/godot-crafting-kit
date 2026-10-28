class_name CKCraftGridPanel
extends PanelContainer
## A crafting grid (2x2, 3x3...) that players fill with items, like Minecraft: the recipe
## the placed items make shows next to it, with Craft, Craft all and Clear.
##
## Place it inside an [IKInventoryUI] next to the bag's [IKContainerView], so items can be
## dragged in and out. Set [member crafting] and [member bag] (where results go).
## Shaped recipes ([member CKRecipe.pattern]) match by shape, shapeless ones by their items.
## [codeblock]
## var panel := CKCraftGridPanel.new()
## panel.crafting = crafting
## panel.bag = bag.container
## panel.grid_width = 2
## panel.grid_height = 2
## inventory_ui.add_child(panel)
## [/codeblock]

signal crafted(result: CKResult)
signal refused(result: CKResult, text: String)

@export var crafting: CKCrafting:
	set(value):
		if crafting != null and crafting.changed.is_connected(_queue_refresh):
			crafting.changed.disconnect(_queue_refresh)
		crafting = value
		if crafting != null:
			crafting.changed.connect(_queue_refresh)
		_queue_refresh()
## Results go there; Clear returns the grid's items there.
var bag: IKContainer:
	set(value):
		bag = value
		_queue_refresh()
@export_range(1, 6) var grid_width: int = 3:
	set(value):
		grid_width = value
		_resize_grid()
@export_range(1, 6) var grid_height: int = 3:
	set(value):
		grid_height = value
		_resize_grid()
## Recipes of this station can be made in the grid ("" = hand recipes).
@export var station: StringName
@export var title: String = "Crafting grid"

## The cells, [member grid_width] per row. Save it with your inventory to keep what was left in it.
var grid: IKContainer
## The grid's slots, interactive inside an [IKInventoryUI].
var view := IKContainerView.new()

var _title := Label.new()
var _result_icon := TextureRect.new()
var _result_name := Label.new()
var _result_text := RichTextLabel.new()
var _craft := Button.new()
var _craft_all := Button.new()
var _clear := Button.new()
var _status := Label.new()
var _refresh_queued := false


func _init() -> void:
	grid = IKContainer.new(&"craft_grid", grid_width * grid_height)
	grid.changed.connect(_queue_refresh)
	_build()
	view.bind(grid)


func _ready() -> void:
	refresh()


## The recipe the grid makes now, or null.
func get_match() -> CKRecipe:
	_sync_database()
	return crafting.match_grid(grid, grid_width, station) if crafting != null else null


## Crafts [param count] times (fewer if the grid runs out).
func craft(count: int = 1) -> CKResult:
	if crafting == null or bag == null:
		return CKResult.failure(CKResult.Code.INVALID_ARGUMENT, "no crafting node or bag")
	_sync_database()
	var result := crafting.craft_grid(grid, grid_width, bag, count, station)
	if result.ok:
		var recipe := crafting.book.get_recipe(result.recipe_id)
		var text := "%s %d × %s." % [CKText.t("Crafted"), result.amount, recipe.get_display_name(_database())]
		if result.failures > 0:
			text += " " + CKText.t("%d failed.") % result.failures
		if result.quality > 0:
			text += " " + CKText.t("Best quality: %s.") % CKText.quality_name(result.quality)
		_set_status(text, false)
		crafted.emit(result)
	else:
		var text := CKText.result_message(result)
		_set_status(text, true)
		refused.emit(result, text)
	refresh()
	return result


## Moves the grid's items back to [member bag], as much as fits.
func clear() -> void:
	if bag == null:
		return
	for slot in grid.size():
		if not grid.is_slot_empty(slot):
			grid.transfer_to(slot, bag)
	refresh()


func refresh() -> void:
	_refresh_queued = false
	_sync_database()
	_title.text = CKText.t(title)
	var recipe := get_match()
	_craft.disabled = true
	_craft_all.disabled = true
	_clear.disabled = grid.get_totals().is_empty()
	_result_text.text = ""
	if recipe == null:
		_result_icon.texture = null
		_result_name.text = CKText.t("Place items in the grid.") if grid.get_totals().is_empty() else CKText.t("These items make nothing.")
		return
	var definition := _definition(recipe.main_result())
	_result_icon.texture = definition.icon if definition != null else null
	var known := crafting.is_known(recipe.id)
	_result_icon.modulate = Color.WHITE if known else Color(0, 0, 0, 0.85)
	var lines := PackedStringArray()
	if known:
		_result_name.text = "%d × %s" % [recipe.results.get(recipe.main_result(), 1), recipe.get_display_name(_database())]
	else:
		_result_name.text = "???"
		lines.append("[i]%s[/i]" % (CKText.t("Something new... craft it to learn it.") if crafting.learn_from_grid else CKText.t("You don't know this recipe yet.")))
	var unlocked := crafting.is_unlocked(recipe)
	if not unlocked:
		lines.append("[color=#ff7a6b]%s[/color]" % (CKText.t("Needs %s level %d") % [CKText.profession_name(recipe.get_profession()), recipe.required_level]))
	if known and recipe.success_chance < 1.0:
		lines.append("%s %d%%" % [CKText.t("Success chance:"), roundi(recipe.success_chance * 100.0)])
	if known and not recipe.quality_weights.is_empty():
		lines.append(CKText.t("Quality varies."))
	_result_text.text = "\n".join(lines)
	var can := unlocked and (known or crafting.learn_from_grid) and bag != null
	_craft.disabled = not can
	_craft_all.disabled = not can or crafting.get_grid_max_crafts(grid) <= 1


func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	margin.add_child(column)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	column.add_child(row)
	view.name = "GridView"
	view.columns = grid_width
	row.add_child(view)
	var arrow := Label.new()
	arrow.text = "→"
	arrow.add_theme_font_size_override(&"font_size", 26)
	arrow.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(arrow)
	var result_box := VBoxContainer.new()
	result_box.size_flags_horizontal = SIZE_EXPAND_FILL
	result_box.custom_minimum_size = Vector2(150, 0)
	row.add_child(result_box)
	_result_icon.custom_minimum_size = Vector2(52, 52)
	_result_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_result_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_result_icon.size_flags_horizontal = SIZE_SHRINK_BEGIN
	result_box.add_child(_result_icon)
	_result_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_box.add_child(_result_name)
	_result_text.bbcode_enabled = true
	_result_text.fit_content = true
	_result_text.scroll_active = false
	result_box.add_child(_result_text)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 6)
	column.add_child(buttons)
	for entry in [[_craft, "Craft", func() -> void: craft(1)],
			[_craft_all, "Craft all", func() -> void: craft(9999)],
			[_clear, "Clear", clear]]:
		var button: Button = entry[0]
		button.text = CKText.t(entry[1])
		button.focus_mode = FOCUS_NONE
		button.pressed.connect(entry[2])
		buttons.add_child(button)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)


func _resize_grid() -> void:
	if grid == null:
		return
	var wanted := grid_width * grid_height
	if grid.size() != wanted:
		if not grid.get_totals().is_empty() and bag != null:
			clear()
		grid.resize(wanted)
	view.columns = grid_width
	view.bind(grid)
	_queue_refresh()


func _sync_database() -> void:
	var database := _database()
	if database != null and grid.database != database:
		grid.database = database
		view.refresh_all()


func _set_status(text: String, warning: bool) -> void:
	_status.text = text
	_status.modulate = Color(1, 0.62, 0.52) if warning else Color(0.6, 1, 0.65)


func _database() -> IKItemDatabase:
	if crafting != null and crafting.database != null:
		return crafting.database
	return bag.database if bag != null else null


func _definition(item_id: StringName) -> IKItemDefinition:
	var database := _database()
	return database.get_item(item_id) if database != null else null


func _queue_refresh() -> void:
	if _refresh_queued or not is_inside_tree():
		return
	_refresh_queued = true
	refresh.call_deferred()
