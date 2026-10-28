class_name CKCraftingWindow
extends PanelContainer
## A ready-to-use crafting screen: one tab per place (by hand, then each station),
## recipe grid with filters, ingredients you have and lack, amount, Craft / Queue,
## the station's queue with progress bars, and its output tray.
##
## Works with the mouse, the keyboard and a gamepad (focus navigation; Q / E or LB / RB
## switch tabs). Set [member crafting], [member bag] and [member stations], optionally
## [member skin] (an Inventory Kit [IKSkin]) so it matches the inventory.

signal crafted(result: CKResult)
signal refused(result: CKResult, text: String)
## The player pressed Cancel (Escape / B) in the window.
signal close_requested

const TAB_PREVIOUS := &"ck_previous_tab"
const TAB_NEXT := &"ck_next_tab"

@export var crafting: CKCrafting:
	set(value):
		_disconnect()
		crafting = value
		_connect()
		_queue_refresh()
## Where ingredients come from and results go.
var bag: IKContainer:
	set(value):
		_disconnect()
		bag = value
		_connect()
		_queue_refresh()
## Stations shown as tabs after "By hand".
var stations: Array[CKStation] = []:
	set(value):
		_disconnect()
		stations = value
		_connect()
		_queue_refresh()
## Show a "By hand" tab for station-less recipes.
@export var include_hand: bool = true
## Show unknown recipes as silhouettes with their hint (false = hide them).
@export var show_unknown: bool = true
@export var skin: IKSkin:
	set(value):
		skin = value
		_queue_refresh()
@export var columns: int = 6
@export var item_size := Vector2(60, 60)

## Index in [method get_places]: 0 = by hand when [member include_hand].
var current_tab: int = 0
var _title := Label.new()
var _tab_row := HBoxContainer.new()
var _tabs: Array[Button] = []
var _category := OptionButton.new()
var _only_craftable := CheckBox.new()
var _grid := GridContainer.new()
var _empty := Label.new()
var _detail_icon := TextureRect.new()
var _detail_name := Label.new()
var _detail_text := RichTextLabel.new()
var _amount := SpinBox.new()
var _action := Button.new()
var _status := Label.new()
var _queue_box := VBoxContainer.new()
var _queue_rows := VBoxContainer.new()
var _tray := HBoxContainer.new()
var _collect := Button.new()
var _xp_row := HBoxContainer.new()
var _xp_label := Label.new()
var _xp_bar := ProgressBar.new()
var _selected: StringName
var _categories: Array[StringName] = []
var _connected: Array[Object] = []
var _queue_signature := ""
var _fallback_skin: IKSkin
var _refresh_queued := false


func _init() -> void:
	_build()


func _ready() -> void:
	_ensure_actions()
	refresh()


func _exit_tree() -> void:
	_disconnect()


## [null] for "by hand" (when [member include_hand]), then the stations.
func get_places() -> Array:
	var places: Array = [null] if include_hand else []
	places.append_array(stations)
	return places


func get_current_station() -> CKStation:
	var places := get_places()
	return places[current_tab] if current_tab >= 0 and current_tab < places.size() else null


func show_tab(index: int) -> void:
	var count := get_places().size()
	if count == 0:
		return
	current_tab = posmod(index, count)
	_selected = &""
	refresh()
	_focus_selected.call_deferred()


## Rebuilds everything from the crafting node, the bag and the stations.
func refresh() -> void:
	_refresh_queued = false
	_rebuild_tabs()
	var station := get_current_station()
	_title.text = station.get_display_name() if station != null else CKText.t("Crafting")
	_refresh_xp()
	_rebuild_categories()
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var had_focus := focused != null and _grid.is_ancestor_of(focused)
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_grid.columns = columns
	var recipes := _visible_recipes()
	for recipe in recipes:
		var known := crafting == null or crafting.is_known(recipe.id)
		var button := CKRecipeButton.new()
		button.setup(recipe, _definition(recipe.main_result()), known, known and crafting.is_unlocked(recipe) and _max_crafts(recipe) > 0, _skin(), item_size)
		button.tooltip_text = recipe.get_display_name(_database()) if known else (CKText.t(recipe.hint) if not recipe.hint.is_empty() else "???")
		var recipe_id := recipe.id
		button.pressed.connect(func() -> void: _select(recipe_id))
		button.focus_entered.connect(func() -> void: _select(recipe_id, false))
		button.set_selected(recipe_id == _selected)
		_grid.add_child(button)
	_empty.visible = recipes.is_empty()
	if not recipes.any(func(r: CKRecipe) -> bool: return r.id == _selected):
		_selected = recipes[0].id if not recipes.is_empty() else &""
	_refresh_details()
	_refresh_queue(true)
	if had_focus:
		_focus_selected.call_deferred()


# --- Building ----------------------------------------------------------------

func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	_title.add_theme_font_size_override(&"font_size", 21)
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(_title)
	var hint := Label.new()
	hint.text = CKText.t("Q / E · LB / RB")
	hint.modulate = Color(1, 1, 1, 0.55)
	header.add_child(hint)
	column.add_child(_tab_row)
	_xp_row.add_theme_constant_override(&"separation", 8)
	column.add_child(_xp_row)
	_xp_label.custom_minimum_size = Vector2(170, 0)
	_xp_row.add_child(_xp_label)
	_xp_bar.max_value = 1.0
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(160, 12)
	_xp_bar.size_flags_horizontal = SIZE_EXPAND_FILL
	_xp_bar.size_flags_vertical = SIZE_SHRINK_CENTER
	_xp_row.add_child(_xp_bar)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override(&"separation", 10)
	column.add_child(filters)
	_category.focus_mode = FOCUS_NONE
	_category.item_selected.connect(func(_i: int) -> void: refresh())
	filters.add_child(_category)
	_only_craftable.text = CKText.t("Craftable now")
	_only_craftable.focus_mode = FOCUS_NONE
	_only_craftable.toggled.connect(func(_on: bool) -> void: refresh())
	filters.add_child(_only_craftable)

	var body := HBoxContainer.new()
	body.add_theme_constant_override(&"separation", 14)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(body)
	# Left: recipes, then the station's queue and tray under them.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.add_theme_constant_override(&"separation", 8)
	body.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 130)
	left.add_child(scroll)
	left.add_child(_queue_box)
	var grid_box := VBoxContainer.new()
	grid_box.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(grid_box)
	_grid.add_theme_constant_override(&"h_separation", 6)
	_grid.add_theme_constant_override(&"v_separation", 6)
	grid_box.add_child(_grid)
	_empty.text = CKText.t("No recipe here yet.")
	_empty.modulate = Color(1, 1, 1, 0.6)
	grid_box.add_child(_empty)

	var details := VBoxContainer.new()
	details.custom_minimum_size = Vector2(280, 0)
	details.add_theme_constant_override(&"separation", 6)
	body.add_child(details)
	var name_row := HBoxContainer.new()
	details.add_child(name_row)
	_detail_icon.custom_minimum_size = Vector2(52, 52)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	name_row.add_child(_detail_icon)
	_detail_name.add_theme_font_size_override(&"font_size", 19)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_name.size_flags_horizontal = SIZE_EXPAND_FILL
	name_row.add_child(_detail_name)
	_detail_text.bbcode_enabled = true
	_detail_text.fit_content = true
	_detail_text.scroll_active = false
	_detail_text.size_flags_vertical = SIZE_EXPAND_FILL
	details.add_child(_detail_text)
	var amount_row := HBoxContainer.new()
	details.add_child(amount_row)
	var amount_label := Label.new()
	amount_label.text = CKText.t("Amount")
	amount_row.add_child(amount_label)
	_amount.min_value = 1
	_amount.max_value = 1
	_amount.value_changed.connect(func(_v: float) -> void: _refresh_details(false))
	amount_row.add_child(_amount)
	_action.custom_minimum_size = Vector2(0, 42)
	_action.pressed.connect(_on_action)
	details.add_child(_action)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_status)

	_queue_box.add_theme_constant_override(&"separation", 4)
	_queue_box.add_child(_queue_rows)
	var tray_row := HBoxContainer.new()
	tray_row.add_theme_constant_override(&"separation", 8)
	_queue_box.add_child(tray_row)
	var tray_label := Label.new()
	tray_label.text = CKText.t("Ready:")
	tray_row.add_child(tray_label)
	_tray.add_theme_constant_override(&"separation", 4)
	_tray.size_flags_horizontal = SIZE_EXPAND_FILL
	tray_row.add_child(_tray)
	_collect.text = CKText.t("Collect all")
	_collect.pressed.connect(_on_collect)
	tray_row.add_child(_collect)


func _rebuild_tabs() -> void:
	var places := get_places()
	if _tabs.size() != places.size():
		for tab in _tabs:
			tab.queue_free()
		_tabs.clear()
		var group := ButtonGroup.new()
		for i in places.size():
			var tab := Button.new()
			tab.toggle_mode = true
			tab.button_group = group
			tab.focus_mode = FOCUS_NONE
			var index := i
			tab.pressed.connect(func() -> void: show_tab(index))
			_tab_row.add_child(tab)
			_tabs.append(tab)
	current_tab = clampi(current_tab, 0, maxi(0, places.size() - 1))
	for i in places.size():
		_tabs[i].text = places[i].get_display_name() if places[i] != null else CKText.t("By hand")
		_tabs[i].button_pressed = i == current_tab
		_tabs[i].modulate = Color.WHITE if i == current_tab else Color(1, 1, 1, 0.55)


func _rebuild_categories() -> void:
	var wanted: Array[StringName] = []
	for recipe in _place_recipes():
		if not recipe.category.is_empty() and not wanted.has(recipe.category):
			wanted.append(recipe.category)
	if wanted == _categories and _category.item_count > 0:
		return
	var previous := _categories[_category.selected - 1] if _category.selected > 0 and _category.selected - 1 < _categories.size() else &""
	_categories = wanted
	_category.clear()
	_category.add_item(CKText.t("All"))
	for category in _categories:
		_category.add_item(CKText.t(String(category).capitalize()))
	_category.select(_categories.find(previous) + 1 if previous != &"" else 0)
	_category.visible = not _categories.is_empty()


# --- Content -----------------------------------------------------------------

func _place_recipes() -> Array[CKRecipe]:
	var found: Array[CKRecipe] = []
	if crafting == null or crafting.book == null:
		return found
	var station := get_current_station()
	for recipe in crafting.book.for_station(station.station_id if station != null else &""):
		if show_unknown or crafting.is_known(recipe.id):
			found.append(recipe)
	return found


func _visible_recipes() -> Array[CKRecipe]:
	var category: StringName = _categories[_category.selected - 1] if _category.selected > 0 and _category.selected - 1 < _categories.size() else &""
	var found: Array[CKRecipe] = []
	for recipe in _place_recipes():
		if category != &"" and recipe.category != category:
			continue
		if _only_craftable.button_pressed and (not crafting.is_known(recipe.id) or not crafting.is_unlocked(recipe) or _max_crafts(recipe) <= 0):
			continue
		found.append(recipe)
	return found


func _select(recipe_id: StringName, grab: bool = true) -> void:
	_selected = recipe_id
	for child in _grid.get_children():
		if child is CKRecipeButton:
			child.set_selected(child.recipe_id == recipe_id)
			if grab and child.recipe_id == recipe_id and not child.has_focus():
				child.grab_focus()
	_refresh_details()


func _refresh_details(reset_amount: bool = true) -> void:
	var recipe := crafting.book.get_recipe(_selected) if crafting != null and crafting.book != null and _selected != &"" else null
	var known := recipe != null and crafting.is_known(recipe.id)
	var station := get_current_station()
	_action.text = CKText.t("Queue") if station != null else CKText.t("Craft")
	if recipe == null:
		_detail_icon.texture = null
		_detail_name.text = ""
		_detail_text.text = ""
		_action.disabled = true
		return
	var definition := _definition(recipe.main_result())
	_detail_icon.texture = definition.icon if definition != null else null
	_detail_icon.modulate = Color.WHITE if known else Color(0, 0, 0, 0.85)
	if not known:
		_detail_name.text = "???"
		_detail_text.text = "[i]%s[/i]" % (CKText.t(recipe.hint) if not recipe.hint.is_empty() else CKText.t("You don't know this recipe yet."))
		_action.disabled = true
		return
	_detail_name.text = recipe.get_display_name(_database())
	var most := _max_crafts(recipe)
	_amount.max_value = maxi(1, most)
	if reset_amount:
		_amount.value = 1
	var count := int(_amount.value)
	var lines := PackedStringArray()
	var description := IKText.item_description(definition)
	if not description.is_empty():
		lines.append("[i]%s[/i]" % description)
	var unlocked := crafting.is_unlocked(recipe)
	if not unlocked:
		lines.append("[color=#ff7a6b]%s[/color]" % (CKText.t("Needs %s level %d") % [CKText.profession_name(recipe.get_profession()), recipe.required_level]))
	if recipe.is_shaped():
		lines.append("[i]%s[/i]" % CKText.t("Shaped: can also be made in a crafting grid."))
	lines.append(CKText.t("Needs:"))
	var needs := recipe.get_ingredients()
	for key: StringName in needs:
		var need: int = needs[key] * count
		var have := CKIngredients.count(bag, key)
		lines.append("  [color=%s]%d / %d[/color]  %s" % ["#7ee08a" if have >= need else "#ff7a6b", have, need, CKText.ingredient_name(key, _database())])
	if unlocked and crafting.auto_craft and bag != null and crafting.get_max_crafts(recipe, bag) < count:
		var plan := crafting.plan_craft(recipe, count, bag)
		if plan.ok and not plan.components.is_empty():
			var parts := PackedStringArray()
			for step: Array in plan.components:
				var component := crafting.book.get_recipe(step[0])
				parts.append("%d × %s" % [step[1], component.get_display_name(_database())])
			lines.append("[color=#ffd27a]%s %s[/color]" % [CKText.t("Crafts first:"), ", ".join(parts)])
	var made := PackedStringArray()
	for item_id in recipe.results:
		made.append("%d × %s" % [recipe.results[item_id] * count, IKText.item_name(_definition(item_id))])
	lines.append("%s %s" % [CKText.t("Makes:"), ", ".join(made)])
	if recipe.success_chance < 1.0:
		lines.append("%s %d%%" % [CKText.t("Success chance:"), roundi(recipe.success_chance * 100.0)])
	for bonus in recipe.bonus_results:
		if bonus != null:
			lines.append("  %s %d × %s (%d%%)" % [CKText.t("Bonus:"), bonus.amount, IKText.item_name(_definition(bonus.item_id)), roundi(bonus.chance * 100.0)])
	if not recipe.quality_weights.is_empty():
		lines.append("%s %s" % [CKText.t("Quality:"), _quality_odds(recipe)])
	if recipe.xp > 0 and not recipe.get_profession().is_empty():
		lines.append("+%d %s XP" % [recipe.xp * count, CKText.profession_name(recipe.get_profession())])
	if recipe.duration > 0.0 and station != null:
		lines.append("%s %s" % [CKText.t("Time:"), CKText.duration_text(recipe.duration / maxf(0.01, station.speed) * count)])
	_detail_text.text = "\n".join(lines)
	_action.disabled = most <= 0 or not unlocked


func _refresh_queue(force: bool = false) -> void:
	var station := get_current_station()
	_queue_box.visible = station != null
	if station == null:
		return
	var jobs := station.get_jobs()
	var signature := ",".join(jobs.map(func(j: Dictionary) -> String: return "%s:%d:%d" % [j.recipe.id, j.count, j.done]))
	signature += "|%s" % station.output.get_revision()
	if force or signature != _queue_signature:
		_queue_signature = signature
		for child in _queue_rows.get_children():
			_queue_rows.remove_child(child)
			child.queue_free()
		for i in jobs.size():
			var row := HBoxContainer.new()
			row.add_theme_constant_override(&"separation", 8)
			var icon := TextureRect.new()
			var definition := _definition(jobs[i].recipe.main_result())
			icon.texture = definition.icon if definition != null else null
			icon.custom_minimum_size = Vector2(28, 28)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			row.add_child(icon)
			var label := Label.new()
			label.custom_minimum_size = Vector2(150, 0)
			row.add_child(label)
			var bar := ProgressBar.new()
			bar.max_value = 1.0
			bar.show_percentage = false
			bar.custom_minimum_size = Vector2(120, 14)
			bar.size_flags_horizontal = SIZE_EXPAND_FILL
			bar.size_flags_vertical = SIZE_SHRINK_CENTER
			row.add_child(bar)
			var cancel := Button.new()
			cancel.text = CKText.t("Cancel")
			var index := i
			cancel.pressed.connect(func() -> void: _on_cancel(index))
			row.add_child(cancel)
			_queue_rows.add_child(row)
		for child in _tray.get_children():
			_tray.remove_child(child)
			child.queue_free()
		for slot in station.output.size():
			var stack := station.output.get_stack(slot)
			if stack == null:
				continue
			var item := TextureRect.new()
			var definition := _definition(stack.item_id)
			item.texture = definition.icon if definition != null else null
			item.tooltip_text = "%d × %s" % [stack.amount, IKText.item_name(definition)]
			item.custom_minimum_size = Vector2(32, 32)
			item.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			item.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_tray.add_child(item)
		_collect.disabled = _tray.get_child_count() == 0
	var rows := _queue_rows.get_children()
	for i in mini(rows.size(), jobs.size()):
		var row: HBoxContainer = rows[i]
		var label: Label = row.get_child(1)
		var bar: ProgressBar = row.get_child(2)
		label.text = "%s  %d/%d" % [jobs[i].recipe.get_display_name(_database()), jobs[i].done, jobs[i].count]
		bar.value = jobs[i].progress
		bar.tooltip_text = CKText.duration_text(jobs[i].seconds_left)
	if station.is_blocked():
		_set_status(CKText.t("The output tray is full: collect to keep crafting."), true)


# --- Actions -----------------------------------------------------------------

func _on_action() -> void:
	if crafting == null or bag == null or _selected == &"":
		return
	var station := get_current_station()
	var count := int(_amount.value)
	var result := station.enqueue(_selected, count, bag) if station != null else crafting.craft(_selected, count, bag)
	if result.ok:
		var recipe := crafting.book.get_recipe(_selected)
		var text := "%s %d × %s." % [CKText.t("Queued") if station != null else CKText.t("Crafted"), count, recipe.get_display_name(_database())]
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
	_queue_refresh()


func _on_cancel(index: int) -> void:
	var station := get_current_station()
	if station == null or bag == null:
		return
	var result := station.cancel(index, bag)
	_set_status(CKText.t("Cancelled: ingredients returned.") if result.ok else CKText.result_message(result), not result.ok)


func _on_collect() -> void:
	var station := get_current_station()
	if station == null or bag == null:
		return
	var result := station.collect(bag)
	_set_status(CKText.t("Collected.") if result.ok else CKText.result_message(result), not result.ok)


func _set_status(text: String, warning: bool) -> void:
	_status.text = text
	_status.modulate = Color(1, 0.62, 0.52) if warning else Color(0.6, 1, 0.65)


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed(TAB_PREVIOUS):
		show_tab(current_tab - 1)
		accept_event()
	elif event.is_action_pressed(TAB_NEXT):
		show_tab(current_tab + 1)
		accept_event()
	elif event.is_action_pressed(&"ui_cancel"):
		close_requested.emit()
		accept_event()


func _focus_selected() -> void:
	if not is_inside_tree():
		return
	for child in _grid.get_children():
		if child is CKRecipeButton and not child.is_queued_for_deletion() and (child.recipe_id == _selected or _selected == &""):
			child.grab_focus()
			return


func _ensure_actions() -> void:
	var defaults := {
		TAB_PREVIOUS: [_key(KEY_Q), _joy(JOY_BUTTON_LEFT_SHOULDER)],
		TAB_NEXT: [_key(KEY_E), _joy(JOY_BUTTON_RIGHT_SHOULDER)],
	}
	for action: StringName in defaults:
		if InputMap.has_action(action):
			continue  # the game's own bindings win
		InputMap.add_action(action)
		for event: InputEvent in defaults[action]:
			InputMap.action_add_event(action, event)


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


# --- Internals -----------------------------------------------------------------

func _max_crafts(recipe: CKRecipe) -> int:
	return crafting.get_craftable_count(recipe, bag) if crafting != null else 0


## "Common 70% · Fine 25% · Superior 5%".
func _quality_odds(recipe: CKRecipe) -> String:
	var total := 0.0
	for weight in recipe.quality_weights:
		total += maxf(0.0, weight)
	var parts := PackedStringArray()
	for level in recipe.quality_weights.size():
		if total > 0.0 and recipe.quality_weights[level] > 0.0:
			parts.append("%s %d%%" % [CKText.quality_name(level), roundi(recipe.quality_weights[level] / total * 100.0)])
	return " · ".join(parts)


## The profession of the current place, its level and XP bar. Hidden when no recipe there gives XP.
func _refresh_xp() -> void:
	var profession := _place_profession()
	_xp_row.visible = crafting != null and not profession.is_empty()
	if not _xp_row.visible:
		return
	var progress := crafting.get_level_progress(profession)
	_xp_label.text = CKText.t("%s · level %d") % [CKText.profession_name(profession), progress.level]
	if progress.next < 0:
		_xp_bar.value = 1.0
		_xp_bar.tooltip_text = "%d XP" % progress.xp
	else:
		_xp_bar.value = float(progress.xp - progress.current) / maxf(1.0, progress.next - progress.current)
		_xp_bar.tooltip_text = "%d / %d XP" % [progress.xp, progress.next]


func _place_profession() -> StringName:
	if crafting == null or crafting.book == null:
		return &""
	var station := get_current_station()
	var place := station.station_id if station != null else &""
	for recipe in crafting.book.for_station(place):
		if recipe.xp > 0 or recipe.required_level > 1:
			return station.profession if station != null and not station.profession.is_empty() else recipe.get_profession()
	return &""


func _database() -> IKItemDatabase:
	if crafting != null and crafting.database != null:
		return crafting.database
	return bag.database if bag != null else null


func _definition(item_id: StringName) -> IKItemDefinition:
	var database := _database()
	return database.get_item(item_id) if database != null else null


func _skin() -> IKSkin:
	if skin != null:
		return skin
	if _fallback_skin == null:
		_fallback_skin = IKSkin.create_default()
	return _fallback_skin


## Several signals fire for one change: rebuild once, next frame.
func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	refresh.call_deferred()


func _on_station_changed() -> void:
	_refresh_queue()


func _connect() -> void:
	for object: Object in [crafting, bag]:
		if object != null and not _connected.has(object):
			object.changed.connect(_queue_refresh)
			_connected.append(object)
	for station in stations:
		if station != null and not _connected.has(station):
			station.changed.connect(_on_station_changed)
			_connected.append(station)


func _disconnect() -> void:
	for object in _connected:
		if not is_instance_valid(object):
			continue
		for callable: Callable in [_queue_refresh, _on_station_changed]:
			if object.is_connected(&"changed", callable):
				object.disconnect(&"changed", callable)
	_connected.clear()
