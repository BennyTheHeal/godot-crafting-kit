class_name CKRecipeButton
extends Button
## One recipe in the crafting window: result icon and amount, styled with the
## Inventory Kit skin. Unknown recipes show as a dark silhouette. Focusable (gamepad).

var recipe_id: StringName
var _amount_label := Label.new()
var _skin: IKSkin


func _init() -> void:
	focus_mode = FOCUS_ALL
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clip_contents = true
	_amount_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_amount_label)
	_amount_label.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	_amount_label.grow_horizontal = GROW_DIRECTION_BEGIN
	_amount_label.grow_vertical = GROW_DIRECTION_BEGIN


func setup(recipe: CKRecipe, definition: IKItemDefinition, known: bool, craftable: bool, skin: IKSkin, size_px: Vector2) -> void:
	recipe_id = recipe.id
	icon = definition.icon if definition != null else null
	custom_minimum_size = size_px
	_skin = skin
	var amount: int = recipe.results.get(recipe.main_result(), 1)
	_amount_label.text = str(amount) if amount > 1 and known else ""
	# Unknown: a black silhouette. Known but not craftable now: dimmed.
	self_modulate = Color.WHITE
	add_theme_color_override(&"icon_normal_color", Color(0, 0, 0, 0.85) if not known else (Color.WHITE if craftable else Color(1, 1, 1, 0.4)))
	add_theme_color_override(&"icon_hover_color", Color(0, 0, 0, 0.85) if not known else Color.WHITE)
	add_theme_color_override(&"icon_focus_color", Color(0, 0, 0, 0.85) if not known else Color.WHITE)
	add_theme_color_override(&"icon_pressed_color", Color(0, 0, 0, 0.85) if not known else Color.WHITE)
	if skin != null:
		skin.apply_amount_label(_amount_label)
		add_theme_stylebox_override(&"normal", skin.get_slot_style(IKSlotView.State.NORMAL))
		add_theme_stylebox_override(&"hover", skin.get_slot_style(IKSlotView.State.HOVER))
		add_theme_stylebox_override(&"pressed", skin.get_slot_style(IKSlotView.State.MARKED))
		add_theme_stylebox_override(&"focus", skin.get_slot_style(IKSlotView.State.FOCUS))
		add_theme_constant_override(&"icon_max_width", int(size_px.x - skin.icon_margin * 2))
	_amount_label.offset_right = -4
	_amount_label.offset_bottom = -1


func set_selected(selected: bool) -> void:
	if _skin != null:
		add_theme_stylebox_override(&"normal", _skin.get_slot_style(IKSlotView.State.MARKED if selected else IKSlotView.State.NORMAL))
