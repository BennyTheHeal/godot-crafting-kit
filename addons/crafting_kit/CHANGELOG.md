# Changelog

All notable changes to Crafting Kit are documented here. Versions follow [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-10-28

### Added
- Shaped recipes: `CKRecipe.pattern`, `pattern_keys`, `mirrored`, `CKRecipe.make_shaped()`; ingredients counted from the pattern (`get_ingredients()`).
- Crafting grid of any size: `CKCrafting.match_grid()`, `craft_grid()`, `get_grid_max_crafts()`, `CKRecipeBook.find_in_grid()`; shapeless recipes match the grid too; `learn_from_grid`; `CKCraftGridPanel` UI.
- Substitute ingredients with item tags (`&"#planks"`), `CKIngredients`, "Any planks" texts (`CKText.tag_names`).
- Chance: `success_chance`, `failure_results`, `bonus_results` (`CKBonusResult`), `quality_weights` (quality in the stack data), seeded `CKCrafting.rng` / `rng_seed`, saved random state; `CKResult.produced`, `failures`, `quality`; signals `craft_failed`.
- Auto-craft of hand-made components (`auto_craft`, `plan_craft()`, `get_craftable_count()`, `CKResult.components`), at hand and at stations.
- Professions: `profession`, `xp`, `required_level` on recipes; `add_xp()`, `get_level()`, `get_level_progress()`, `is_unlocked()`, `get_recipes_unlocked_at()`, `level_thresholds`; signals `xp_gained`, `level_up`; `CKStation.profession`; result code `LEVEL_TOO_LOW`; `NO_MATCH` for grids.
- Crafting window: tag ingredients, locked recipes, chance, bonus, quality odds, XP gained, components auto-craft will make, profession level bar.
- Demo: crafting grid tab with shaped weapons, pine and birch planks for "any planks" recipes, potions that fail or come out finer, bonus nuggets, profession levels, auto-craft toggle. 15 new tests (40 in all).

### Changed
- Save data version 2 for `CKCrafting` (XP, random state) and `CKStation` (items taken per job, pending roll). Version 1 saves still load.

## [1.0.0] - 2026-10-26

### Added
- `CKRecipe`, `CKRecipeBook`: recipes as resources (ingredients, results, station, duration, category, learning, hint) with validation.
- `CKCrafting`: known recipes, learning, discovery when every ingredient is held, missing-ingredient checks, crafting by hand in one Inventory Kit transaction, save / load.
- `CKStation`: timed queue per station, speed, output tray that pauses the station when full, cancel with refund, collect, save / load.
- `CKCraftingWindow`: tabs per place, recipe grid with filters, ingredients you have and lack, queue with progress bars, tray, mouse, keyboard and gamepad, Inventory Kit skins.
- Workshop demo with 23 recipes in the four Inventory Kit art styles; 25 automated tests; translation template.
