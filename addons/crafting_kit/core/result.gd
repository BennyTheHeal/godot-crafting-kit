class_name CKResult
extends RefCounted
## Outcome of a craft, a queued job, a cancel or a collect.
##
## Expected refusals (missing ingredients, full bag...) never push engine errors:
## check [member ok] and [member code], show [method CKText.result_message] to players.
## A craft that [i]happened[/i] but failed its [member CKRecipe.success_chance] is still
## [member ok]: see [member failures].

enum Code {
	OK,
	## Bad recipe, amount or container: a bug in the calling code.
	INVALID_ARGUMENT,
	## The recipe id is not in the recipe book.
	UNKNOWN_RECIPE,
	## The player has not learned this recipe yet.
	NOT_KNOWN,
	## Ingredients are missing: see [member missing].
	MISSING_INGREDIENTS,
	## The results (or refunded ingredients) do not fit.
	NO_ROOM,
	## This recipe is made at another station (or needs one).
	WRONG_STATION,
	## The station's queue is full.
	QUEUE_FULL,
	## The inventory refused for another reason: see [member inventory_result].
	INVENTORY_ERROR,
	## The profession level is too low: see [member CKRecipe.required_level].
	LEVEL_TOO_LOW,
	## The items in a crafting grid make no recipe.
	NO_MATCH,
}

var code: Code = Code.OK
## Technical detail for developers and logs (English, not translated).
var message: String = ""
var inventory_result: IKResult
var recipe_id: StringName
## Crafts done, queued, cancelled or items collected.
var amount: int = 0
## Missing ingredients for MISSING_INGREDIENTS: {item_id or #tag: amount}.
var missing: Dictionary = {}
## Items given by a hand or grid craft, {item_id: amount} (results, bonuses, failure results).
var produced: Dictionary = {}
## Crafts that failed their success chance (their ingredients are used).
var failures: int = 0
## Best quality level rolled; -1 when the recipe has no quality.
var quality: int = -1
## Components crafted first by auto-craft: [[recipe_id, count], ...].
var components: Array = []

var ok: bool:
	get:
		return code == Code.OK


static func success(p_recipe_id: StringName = &"", p_amount: int = 0) -> CKResult:
	var result := CKResult.new()
	result.recipe_id = p_recipe_id
	result.amount = p_amount
	return result


static func failure(error_code: Code, error_message: String = "", inventory: IKResult = null) -> CKResult:
	var result := CKResult.new()
	result.code = error_code
	result.message = error_message
	result.inventory_result = inventory
	return result


static func from_inventory(result: IKResult) -> CKResult:
	match result.code:
		IKResult.Code.CONTAINER_FULL, IKResult.Code.RULE_REJECTED, IKResult.Code.SLOT_FULL:
			return failure(Code.NO_ROOM, result.message, result)
		IKResult.Code.NOT_ENOUGH_ITEMS:
			return failure(Code.MISSING_INGREDIENTS, result.message, result)
	return failure(Code.INVENTORY_ERROR, result.message, result)


func code_name() -> String:
	return Code.keys()[code]


func _to_string() -> String:
	if ok:
		return "CKResult(OK, %s x%d)" % [recipe_id, amount]
	return "CKResult(%s: %s)" % [code_name(), message]
