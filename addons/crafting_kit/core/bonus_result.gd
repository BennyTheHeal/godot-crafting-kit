@tool
class_name CKBonusResult
extends Resource
## An extra item a recipe may give on a successful craft ("10% chance of a gem").

@export var item_id: StringName
@export_range(1, 999) var amount: int = 1
## 0.25 = one craft in four.
@export_range(0.0, 1.0, 0.01) var chance: float = 0.1


static func make(p_item_id: StringName, p_amount: int = 1, p_chance: float = 0.1) -> CKBonusResult:
	var bonus := CKBonusResult.new()
	bonus.item_id = p_item_id
	bonus.amount = p_amount
	bonus.chance = p_chance
	return bonus
