# muckliker

A 3D survival roguelike prototype built with Godot 4 and GDScript.

## Status

Prototype. Placeholder visuals (primitive meshes), several systems are stubs (`progression`, `network`), no tests or CI.

## Features

Implemented, based on the scripts in this repository:

- **Procedural chunked world** — `world/systems/world_system.gd` streams terrain chunks around the player (chunk size 64, view distance 4 chunks) with per-frame load/unload budgets, chunk data caching and LOD culling. Heightmaps come from `world/generation/terrain_generator.gd` (layered `FastNoiseLite`: base terrain, mountains, rivers, lakes, island falloff, water level). Resources and ground pickups are spawned lazily per chunk.
- **Component-based entities** — `core/components/` provides reusable `HealthComponent`, `DamageComponent`, `MovementComponent`, `InventoryComponent` and `player_economy.gd`; entities are assembled from components under `core/entities/`.
- **Global event bus** — `core/events/event_bus.gd` (autoload `EventBus`) with a whitelist of event names and required payload fields (`player_damaged`, `entity_died`, `resource_harvested`, `loot_spawn_requested`, `chunk_loaded`, `enemy_killed`, `gold_changed`, `totem_activated`, `ability_collected`, ...).
- **Player** — third-person character controller (`player/systems/player_system.gd`): WASD movement, jump, attack, interact, 8-slot hotbar with mouse-wheel selection, item drop, camera mode toggle; runtime-registered input actions.
- **Resources and harvesting** — tree / rock resource nodes (`resource/`), harvest events, resource types defined in `data/resources/resource_types.json`.
- **Inventory and hotbar UI** — inventory model and system (`inventory/`), slot-based inventory window, hotbar and minimap (`ui/`), floating damage numbers and world-space health bars in 3D.
- **Crafting** — data-driven recipes from `data/recipes/default_recipes.json` (e.g. axe, pickaxe) via `crafting/crafting_system.gd`.
- **Enemies** — `enemies/ai/enemy_ai.gd` with detect / chase / lose-target radii and attack timing loaded from `data/enemies/default_enemy.json`; enemy pooling in `enemies/systems/enemy_system.gd`.
- **Loot** — pooled loot drops with pickup distance, physics freeze and auto-despawn (`loot/loot_system.gd`); item definitions in `shared/items/item_db.json`.
- **Totems and abilities** — totem encounters that spawn wolves and reward gold / ability capsules (`totem/`), ability collection and cooldown handling (`abilities/`).
- **Debug tooling** — `DebugProfiler` autoload, performance overlay (`ui/debug_performance_overlay.gd`) and an X-ray overlay for resources (`debug/xray_debug_system.gd`, F2).

## Stack

- Godot 4.6 (`config/features` in `project.godot`)
- GDScript only
- Autoloads: `EventBus`, `GameConfig`, `GameState`, `ResourceStore`, `DebugProfiler`
- Main scene: `world/scenes/game_main.tscn`, default window 1920x1080

## Architecture

The project follows an Entity + Components + Systems layout. Each gameplay system lives in its own top-level folder and communicates with other systems through `EventBus` payloads rather than direct calls. The design notes (in Russian) are in `docs/ARCHITECTURE.md`.

```text
core/         autoloads, event bus, components, entities, JSON loader, object pool
world/        chunk streaming, terrain generation, world scene
player/       player scene, controller and player system
inventory/    inventory model and system
resource/     harvestable resource nodes
crafting/     recipe-based crafting
combat/       damage / hit resolution
enemies/      enemy AI and spawning
abilities/    ability capsules and ability system
loot/         loot spawning and pickup
totem/        totem encounters
progression/  waves (stub)
network/      client action validation (stub)
ui/           HUD, inventory, hotbar, minimap, damage popups
debug/        X-ray debug overlay
data/         enemy stats, recipes, resource types (JSON)
shared/       item database (JSON)
assets/       audio, FBX models, placeholder scenes
```

## Controls

Input actions are registered at runtime by the player and UI scripts (`player/systems/player_system.gd`, `ui/inventory_ui.gd`, `ui/minimap_ui.gd`):

| Action | Key |
| --- | --- |
| Move | W / A / S / D |
| Jump | Space |
| Attack | Left mouse button |
| Interact | E |
| Hotbar slot | 1–8, mouse wheel |
| Drop one item | Q |
| Inventory | Tab |
| Crafting | I |
| Map | M |
| Camera mode | F3 |
| X-ray debug overlay | F2 |

## How to open

1. Install Godot 4.6.
2. Open Godot, choose **Import**, and select `project.godot` from this repository.
3. Press **Run** (F5); the main scene is `world/scenes/game_main.tscn`.

## License

MIT — see [LICENSE](LICENSE).
