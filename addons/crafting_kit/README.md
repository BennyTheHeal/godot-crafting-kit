# Crafting Kit for Godot 4

Crafting for your RPG or survival game: **recipes, stations with timed queues, recipes to discover**, ingredient checks, saves, and a **ready-to-use crafting window** that works with the mouse, the keyboard and a gamepad.

**Pay what you want, from $0.** Code under MIT. A tip on itch.io keeps new kits coming. Official page, downloads and playable web demo: https://banc-essai.site-testeurs.workers.dev/crafting-kit/
More kits, and our game prototypes waiting for testers: https://banc-essai.site-testeurs.workers.dev/

- Built on **Inventory Kit** (included in the download): every craft is one atomic transaction. Ingredients are taken and results given together, or nothing changes: no ingredient lost when the bag is full, nothing duplicated.
- **Recipes** as resources: ingredients, one or several results, station, duration, category, hint.
- **By hand** (instant) or at **stations** (workbench, forge, alchemy table...): a queue per station, a duration per craft, a speed multiplier, results waiting in the station's **output tray**. A full tray pauses the station, nothing is lost. **Cancel** gives back the ingredients of the crafts not finished.
- **Learning**: recipes known from the start, taught (`learn()`: books, trainers, quests) or **discovered** when the player first holds every ingredient. Unknown recipes show as silhouettes with a hint.
- Checks for your own UI: missing ingredients, how many crafts are possible.
- Save / load what the player knows and each station's queue and tray (`to_data()` / `load_data()`).
- `CKCraftingWindow`: one tab per place (by hand, each station), recipe grid, category filter, "craftable now", ingredients you have and lack, amount, Craft / Queue, the queue with progress bars, Cancel, Collect all. Styled by Inventory Kit skins in 4 art styles.
- **Shaped recipes and a crafting grid** (2x2, 3x3 or any size, like Minecraft): patterns, optional mirror, the recipe found from the items placed, `CKCraftGridPanel` ready to drop in. Shapeless recipes work in the grid too.
- **Substitute ingredients**: `&"#planks"` takes any item tagged "planks" (oak, pine...), using Inventory Kit's item tags.
- **Chance**: success chance (failed crafts use their ingredients), bonus results with their own chance, quality levels (Common, Fine...) stored in the item stack. A seed replays the same outcomes, and the random state is saved.
- **Auto-craft** (optional): missing components are made from known hand recipes in the same transaction (logs -> planks -> sticks -> pickaxe).
- **Professions**: XP per craft, levels that unlock recipes (`required_level`), signals for level ups.
- Every player text is translatable (`translations/crafting_kit.csv`). 40 automated tests.

## Install

1. Copy `addons/inventory_kit/` and `addons/crafting_kit/` into your project's `addons/` folder (skip Inventory Kit if you already have it).
2. Open `demo/craft/craft_demo.tscn`: a workshop with a workbench, a forge and an alchemy table, and a crafting grid in the second tab (drag iron and planks into it to make a dagger).

## Five-minute setup

```gdscript
# Recipes live in a CKRecipeBook resource (.tres), shared by every node.
var book := CKRecipeBook.new()
book.add_recipe(CKRecipe.make(&"oak_planks", {&"oak_log": 1}, {&"oak_planks": 2}))                 # by hand
book.add_recipe(CKRecipe.make(&"iron_ingot", {&"iron_ore": 2, &"coal": 1}, {&"iron_ingot": 1}, &"forge", 2.0))

var crafting := CKCrafting.new()      # what the player knows, and crafting by hand
crafting.book = book
add_child(crafting)
crafting.watch(bag.container)         # discover recipes when their ingredients are picked up

var result := crafting.craft(&"oak_planks", 3, bag.container)
if not result.ok:
	status.text = CKText.result_message(result)   # "Missing ingredients.", "Not enough room in your bag."…
	print(result.missing)                         # {&"oak_log": 2}

var forge := CKStation.new()          # a station with a timed queue
forge.station_id = &"forge"
forge.crafting = crafting
add_child(forge)
forge.enqueue(&"iron_ingot", 5, bag.container)   # ingredients taken now
forge.job_finished.connect(func(recipe, count): print("%d ingots ready" % count))
forge.collect(bag.container)                     # from the output tray to the bag
```

Ready-made UI:

```gdscript
var window := CKCraftingWindow.new()
window.crafting = crafting
window.bag = bag.container
window.stations = [workbench, forge]
window.skin = preload("res://addons/inventory_kit/art/painted/painted_skin.tres")
window.theme = preload("res://addons/inventory_kit/art/painted/painted_theme.tres")
add_child(window)
window.close_requested.connect(window.hide)
```

Turn-based game or tests? Set `forge.auto_process = false` and call `forge.advance(seconds)` yourself.

Saving next to your inventory:

```gdscript
var data := {"crafting": crafting.to_data(), "forge": forge.to_data()}
FileAccess.open("user://crafting.json", FileAccess.WRITE).store_string(JSON.stringify(data))
```

## Shaped recipes and the crafting grid

```gdscript
# Rows of the grid, one character per cell; spaces (or dots) are empty cells.
var pick := CKRecipe.make_shaped(&"pickaxe", ["III", " S ", " S "],
		{"I": &"iron_ingot", "S": &"stick"}, {&"pickaxe": 1})
var axe := CKRecipe.make_shaped(&"axe", ["II", "IS", " S"],
		{"I": &"iron_ingot", "S": &"stick"}, {&"axe": 1}, &"", 0.0, true)   # true = mirrored works too
book.add_recipe(pick)
book.add_recipe(axe)

# Any IKContainer can be a grid: 9 slots, 3 per row.
var grid := IKContainer.new(&"craft_grid", 9, database)
var recipe := crafting.match_grid(grid, 3)          # null when the items make nothing
var result := crafting.craft_grid(grid, 3, bag.container, 1)   # takes one item per filled cell
```

The shape can sit anywhere in a bigger grid; a 3x3 shape never fits a 2x2 grid. Shapeless recipes match the grid when there is exactly one item per filled cell for their ingredients. Shaped recipes stay craftable from the recipe window too: their ingredients are counted from the pattern (`get_ingredients()`).

Unknown recipes placed in the grid are learned when crafted (`learn_from_grid`, on by default): players can experiment. Set it to false to refuse them.

Ready-made panel, to place inside your `IKInventoryUI` next to the bag (drag and drop come from Inventory Kit):

```gdscript
var panel := CKCraftGridPanel.new()
panel.crafting = crafting
panel.bag = bag.container      # where results go, and where Clear puts items back
panel.grid_width = 2           # a 2x2 pocket grid; 3x3 by default
panel.grid_height = 2
inventory_ui.add_child(panel)
```

## Substitute ingredients (tags)

An ingredient key starting with `#` is an item tag: `&"#planks"` is any item whose `tags` contain `planks`. Works in `ingredients` and in pattern keys.

```gdscript
book.add_recipe(CKRecipe.make(&"bow", {&"#planks": 3, &"linen_thread": 2}, {&"bow": 1}, &"workbench", 3.0))
```

Exact items are taken first, then tags; for a tag, items in the order the bag holds them. Missing tags show as `{&"#planks": 2}` in `result.missing`, and `CKText.ingredient_name()` gives "Any planks" (rename it with `CKText.tag_names[&"planks"] = "Any wooden planks"`).

## Chance, bonus results and quality

```gdscript
var potion := CKRecipe.make(&"health_potion", {&"herb": 3}, {&"health_potion": 1}, &"alchemy", 3.0)
potion.success_chance = 0.85                          # a failed craft uses the herbs
potion.failure_results.assign({&"ash": 1})            # optional consolation item
potion.bonus_results.append(CKBonusResult.make(&"herb", 1, 0.2))   # 20%: one herb back
potion.quality_weights = PackedFloat32Array([60, 30, 10])           # Common, Fine, Superior

crafting.rng_seed = 1234      # same seed, same outcomes (0 = random each run)
var result := crafting.craft(&"health_potion", 5, bag.container)
print(result.failures, result.produced, CKText.quality_name(result.quality))
```

- Each craft rolls on its own. At a station, the roll happens when the craft finishes, once: a full tray does not re-roll it.
- Quality 1 and up is stored in the result stack's data, `{"quality": 2}` (`CKRecipe.QUALITY_KEY`), so read it like any Inventory Kit stack data. Quality 0 is a plain item that stacks with the others.
- A refused craft (no room) does not use up the random state. `to_data()` saves it.
- Signals: `CKCrafting.craft_failed(recipe, count)`, `CKStation.craft_failed(recipe)`.

## Auto-craft components

```gdscript
crafting.auto_craft = true
crafting.craft(&"pickaxe", 1, bag.container)   # bag holds logs and iron: planks, then sticks, then the pickaxe
```

Components come from known, unlocked hand recipes without chance (no success roll, bonus or quality), up to 6 levels deep. Everything happens in one transaction; leftovers (the 2 extra sticks) go to the bag. `plan_craft()` tells you beforehand what will be taken, made and left over, `result.components` what was made. At a station, the components are made when the job is queued; cancelling refunds the job's own ingredients.

## Professions and levels

```gdscript
recipe.profession = &"smithing"     # empty = the station id
recipe.xp = 10                      # per craft, failed ones included
recipe.required_level = 3           # locked below Smithing 3: LEVEL_TOO_LOW

crafting.level_thresholds = PackedInt32Array([100, 250, 450])   # total XP for levels 2, 3, 4
crafting.level_up.connect(func(profession, level):
	for recipe in crafting.get_recipes_unlocked_at(profession, level):
		print("Unlocked: ", recipe.get_display_name(database)))
crafting.add_xp(&"smithing", 50)    # quests, trainers...
```

`get_level()`, `get_xp()`, `get_level_progress()` (for a bar), `is_unlocked(recipe)`. The crafting window shows the level of the current place and the requirement of locked recipes. XP is saved by `to_data()`.

## Saves from 1.0

`CKCrafting` and `CKStation` save as version 2 (XP, random state, the exact items a job took). Version 1 saves load as before.

## Classes

| Class | Role |
|---|---|
| `CKRecipe` | Ingredients (items or `#tags`), results, station, duration, category, learning, pattern (shaped, mirrored), chance, bonus results, quality, profession, XP, required level |
| `CKRecipeBook` | All recipes: `get_recipe()`, `for_station()`, `find_in_grid()`, `producing()`, `validate()` |
| `CKCrafting` | What the player knows (`learn()`, `discover()`, `watch()`), checks (`get_missing()`, `get_max_crafts()`, `plan_craft()`), crafting by hand (`craft()`) or in a grid (`match_grid()`, `craft_grid()`), auto-craft, professions (`add_xp()`, `get_level()`), seeded `rng`, save |
| `CKIngredients`, `CKBonusResult` | Tag matching and ingredient choice; a bonus result with its chance |
| `CKStation` | Timed queue: `enqueue()`, `cancel()`, `collect()`, `advance()`, output tray, speed, save; signals `job_queued`, `craft_finished`, `job_finished`, `changed` |
| `CKResult`, `CKText` | Outcome codes (`MISSING_INGREDIENTS` with `missing`, `NO_ROOM`, `NOT_KNOWN`, `WRONG_STATION`, `QUEUE_FULL`, `LEVEL_TOO_LOW`, `NO_MATCH`), `produced`, `failures`, `quality`, `components`; player texts, quality and profession names |
| `CKCraftingWindow`, `CKRecipeButton` | The crafting screen |
| `CKCraftGridPanel` | The crafting grid with its result, Craft, Craft all, Clear |

Controls of the crafting window: click or Enter / A to pick a recipe, the arrows / d-pad move between recipes, Q / E or LB / RB switch tabs, Escape / B emits `close_requested`. Add actions named `ck_previous_tab` / `ck_next_tab` in your Input Map to rebind the tabs.

## Running the tests

```bash
godot --headless --path <project> --import
godot --headless --path <project> -s res://tests/crafting_kit/run_tests.gd
```

## Licenses

- Source code: MIT (`LICENSE.txt`).
- The item art in `addons/inventory_kit/art/` is covered by Inventory Kit's `LICENSE_ART.txt`: free to use in your games, please do not re-upload it; link to the official page instead.
- Found a bug or want a feature? Tell us: https://banc-essai.site-testeurs.workers.dev/
