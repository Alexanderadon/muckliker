# Checklist: Game Analytics Implementation

Date: 2026-03-11
Project: Godot survival

## 1) Scope and ownership

- [ ] Define sprint goal for analytics (example: D1 retention, craft conversion, loot balance).
- [ ] Define 3-5 KPIs (example: `session_length`, `craft_success_rate`, `death_rate`, `loot_pickup_rate`).
- [ ] Approve event naming convention (`snake_case`, verb+noun).
- [ ] Assign analytics owner (event schema and dashboards).

## 2) Analytics technical base

- [ ] Add `AnalyticsService` (autoload Node) to collect and forward events.
- [ ] Add shared fields to every event: `event_time`, `session_id`, `player_id`, `build_version`, `platform`.
- [ ] Add `event_id` (UUID) for deduplication.
- [ ] Add local disk queue for offline/crash safety.
- [ ] Add batched sending and retry with backoff.
- [ ] Add analytics disable switch for dev builds.

## 3) Already available in project (EventBus)

- [x] `player_damaged`
- [x] `entity_died`
- [x] `resource_harvested`
- [x] `loot_spawn_requested`
- [x] `loot_picked`
- [x] `chunk_loaded`
- [x] `chunk_unloaded`
- [ ] Subscribe `AnalyticsService` to `EventBus.game_event` and forward whitelisted events.

## 4) Events to add for product analytics

- [ ] `session_started`
- [ ] `session_ended`
- [ ] `game_paused`
- [ ] `game_resumed`
- [ ] `player_died`
- [ ] `respawned` (if respawn exists)
- [ ] `inventory_opened`
- [ ] `inventory_closed`
- [ ] `craft_attempted`
- [ ] `craft_succeeded`
- [ ] `craft_failed` (`not_enough_resources` or `no_space`)
- [ ] `item_dropped`
- [ ] `enemy_killed` (killer and enemy type)

## 5) Required payload fields

- [ ] For all events: `event_time`, `session_id`, `player_id`, `build_version`, `platform`, `map_seed`.
- [ ] Combat events: `target_type`, `damage`, `weapon_type`, `player_hp_before`, `player_hp_after`.
- [ ] Loot events: `item_id`, `amount`, `source` (`world`, `enemy`, `drop`), `position`.
- [ ] Craft events: `recipe_id`, `result`, `fail_reason`, `inventory_free_slots`.
- [ ] Economy events: `item_balance_before`, `item_balance_after` for tracked resources.

## 6) Data quality checks

- [ ] Verify each event is sent once (no duplicates).
- [ ] Verify `loot_picked` is not sent when inventory is full.
- [ ] Verify `craft_failed` always has a valid reason.
- [ ] Verify all required fields exist.
- [ ] Verify field types are stable across sessions (int/string/bool).
- [ ] Verify queued events are delivered after restart.

## 7) Dashboards and funnels

- [ ] Dashboard 1: event health (volume, errors, drops).
- [ ] Dashboard 2: core loop (harvest -> craft -> combat -> loot).
- [ ] Funnel: `session_started -> resource_harvested -> craft_attempted -> craft_succeeded`.
- [ ] Funnel: `session_started -> player_damaged -> player_died`.
- [ ] Segments: build version, session length, new vs returning players.

## 8) Pack to send to analytics/product

- [ ] This checklist.
- [ ] Event table (name, trigger point, payload schema, sample payload).
- [ ] Controlled vocabularies for `item_id`, `recipe_id`, `enemy_type`.
- [ ] Current KPI values and sprint targets.
- [ ] Dashboard links and event-schema freeze date.
