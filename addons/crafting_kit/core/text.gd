class_name CKText
extends RefCounted
## Every text Crafting Kit shows to players goes through here, so it can be translated
## or reworded with Godot's translation system (template:
## [code]addons/crafting_kit/translations/crafting_kit.csv[/code]), like Inventory Kit's IKText.

## Player text for each refusal. Replace entries to reword them in code, e.g.
## [code]CKText.result_texts[CKResult.Code.MISSING_INGREDIENTS] = "You lack materials."[/code]
static var result_texts := {
	CKResult.Code.INVALID_ARGUMENT: "That did not work.",
	CKResult.Code.UNKNOWN_RECIPE: "Unknown recipe.",
	CKResult.Code.NOT_KNOWN: "You don't know this recipe yet.",
	CKResult.Code.MISSING_INGREDIENTS: "Missing ingredients.",
	CKResult.Code.NO_ROOM: "Not enough room in your bag.",
	CKResult.Code.WRONG_STATION: "This is made at another station.",
	CKResult.Code.QUEUE_FULL: "The station is busy: its queue is full.",
	CKResult.Code.INVENTORY_ERROR: "That did not work.",
	CKResult.Code.LEVEL_TOO_LOW: "Your skill is too low for this recipe.",
	CKResult.Code.NO_MATCH: "These items make nothing.",
}

## Names of quality levels 0, 1, 2... Replace or extend them for your game.
static var quality_names: PackedStringArray = ["Common", "Fine", "Superior", "Masterwork", "Legendary"]
## Player names of professions, {profession id: name}. Missing ids are capitalized.
static var profession_names := {}
## Player names of item tags for "#tag" ingredients, {tag: name}. Missing: "Any <tag>".
static var tag_names := {}


static func t(text: String) -> String:
	if text.is_empty():
		return text
	return String(TranslationServer.translate(text))


## What to tell the player about a refused craft.
static func result_message(result: CKResult) -> String:
	if result == null or result.ok:
		return ""
	if result.inventory_result != null and not result.inventory_result.player_text.is_empty():
		return IKText.result_message(result.inventory_result)  # "Too heavy." from a weight rule
	if result.code == CKResult.Code.INVENTORY_ERROR and result.inventory_result != null:
		return IKText.result_message(result.inventory_result)
	return t(result_texts.get(result.code, "That did not work."))


## "0:12" or "4 s": a short duration for the UI.
static func duration_text(seconds: float) -> String:
	if seconds < 60.0:
		return "%s s" % (str(snappedf(seconds, 0.1)) if seconds < 10.0 else str(roundi(seconds)))
	var total := roundi(seconds)
	return "%d:%02d" % [total / 60, total % 60]


## "Fine", "Masterwork"...; "" for -1 (no quality).
static func quality_name(level: int) -> String:
	if level < 0:
		return ""
	return t(quality_names[level]) if level < quality_names.size() else "%s %d" % [t("Quality"), level]


static func profession_name(profession: StringName) -> String:
	return t(profession_names.get(profession, String(profession).capitalize()))


## Name of an ingredient key: the item's name, or "Any planks" for &"#planks".
static func ingredient_name(key: StringName, database: IKItemDatabase) -> String:
	if CKIngredients.is_tag(key):
		var tag := CKIngredients.tag_of(key)
		if tag_names.has(tag):
			return t(tag_names[tag])
		return t("Any %s") % t(String(tag).capitalize().to_lower())
	return IKText.item_name(database.get_item(key) if database != null else null) if database != null and database.has_item(key) else String(key)
