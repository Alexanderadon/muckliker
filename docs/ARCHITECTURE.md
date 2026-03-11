# 3D Survival Roguelike Architecture (Godot 4 + GDScript)

## 1. Архитектура проекта

Цель: модульная component-based архитектура для параллельной разработки несколькими программистами без конфликтов.

- Паттерн: `Entity + Components + Systems`.
- Entity содержит только набор компонентов и визуальную сцену.
- Системы изолированы по папкам и общаются только через `EventBus` + контракты payload.
- Прямые вызовы между системами запрещены, кроме `core/interfaces`.
- Любая gameplay-логика размещается в компонентах и системах, не в placeholder-модели.

### Слой Core
- `core/events`:
  - `event_bus.gd` как глобальный autoload для событий.
- `core/game_config.gd`:
  - единый источник runtime-констант (autoload).
- `core/debug_profiler.gd`:
  - опциональный системный профилировщик (autoload).
- `core/components`:
  - общие компоненты (`Health`, `Damage`, `Movement`, `Inventory`).
- `core/data`:
  - загрузка json-данных (`JsonDataLoader`) для data-driven модулей.
- `core/pooling`:
  - общие пулы объектов для повторного использования Node.
- `core/systems`:
  - утилиты интервального апдейта (`UpdateIntervalGate`).
- `core/entities`:
  - базовые правила для entity-сборки.
- `core/interfaces`:
  - интерфейсные контракты для безопасного взаимодействия модулей.

### Независимые системы
1. `world` - чанки, процедурная генерация, lazy spawning.
2. `player` - управление, состояние игрока, сборка player entity.
3. `inventory` - контейнеры, перенос и стекование.
4. `resource` - ресурсы мира (tree/rock/crystal), harvest.
5. `crafting` - рецепты и крафт операций.
6. `combat` - урон, атаки, резисты, hit resolution.
7. `enemies` - AI, спавн, поведение врагов и боссов.
8. `abilities` - способности и cooldown.
9. `loot` - генерация и выдача лута.
10. `progression` - дни, волны, скейлинг сложности.
11. `ui` - HUD, инвентарь, крафт-окна, подсказки.
12. `network` - валидация клиентских действий, authoritative server layer.

## 2. Структура папок

```text
res://
  core/
    events/
    interfaces/
    entities/
    components/
      common/
      gameplay/
    systems/

  world/
    scenes/
    scripts/
    components/

  player/
    scenes/
    scripts/
    components/

  inventory/
    scenes/
    scripts/
    components/

  resource/
    scenes/
    scripts/
    components/

  crafting/
    scenes/
    scripts/
    components/

  combat/
    scenes/
    scripts/
    components/

  enemies/
    scenes/
    scripts/
    components/

  abilities/
    scenes/
    scripts/
    components/

  loot/
    scenes/
    scripts/
    components/

  progression/
    scenes/
    scripts/
    components/

  ui/
    scenes/
    scripts/
    components/

  network/
    scenes/
    scripts/
    components/

  shared/
    items/
    stats/
    inventory/

  data/
    enemies/
    recipes/
    resources/

  assets/placeholders/
    scenes/
    materials/
```

## 3. Пример компонентов (единые для Player/Enemy/Boss)

Компоненты:
- `HealthComponent`
- `DamageComponent`
- `InventoryComponent`
- `MovementComponent`

Пример entity:

```text
Entity (CharacterBody3D)
  Visual
  Health
  Damage
  Movement
  Inventory
```

Подход к замене placeholder на реальные модели:
- Меняется только child `Visual`/`MeshInstance3D`.
- Компоненты и системы не меняются.

## 4. Пример Player System

Реализация:
- `player/scenes/player.tscn`.
- `player/scripts/player_controller.gd`.
- Компоненты movement/health/damage подключены как children.

Поток:
1. InputMap (`WASD`) -> `player_controller.gd`.
2. Контроллер вызывает `MovementComponent.move_character(...)`.
3. Combat/Ability/Progression получают события через `EventBus`.

## 5. Пример World System (процедурка)

Реализация:
- `world/scripts/world_generator.gd`.
- `world/scenes/game_main.tscn`.

Что делает система:
- Chunk loading/unloading вокруг игрока.
- Lazy spawning объектов в чанке.
- Object pooling для врагов.
- Простой LOD через вариативность плотности/масштаба.

Контент чанка (placeholder):
- Tree (cylinder + sphere)
- Rock (sphere)
- Crystal resource (box)
- Enemy (capsule)

## 6. Placeholder-модели и визуальные различия

Используются только примитивы:
- Player: голубая капсула.
- Enemy: красная капсула.
- Tree: коричневый цилиндр + зеленая сфера.
- Rock: серая сфера.
- Crystal: светящийся циан box.
- Loot: желтый светящийся box.
- Ground: зеленый plane + collision.

Все цвета задаются материалами `StandardMaterial3D` в самих `.tscn`.

## Разделение по разработчикам

- Dev 1: `player`, `combat`, `abilities`.
- Dev 2: `world`, `resource`, `loot`.
- Dev 3: `enemies`, `progression`, `bosses`.
- Shared: `inventory`, `shared/items`, `shared/stats`, `core`.

## Правила зависимостей

Разрешено:
- `EventBus.emit_game_event(...)`
- Подписка на `EventBus.event_emitted`
- Контракты через `core/interfaces`

Запрещено:
- Прямой вызов внутренних методов другой системы.

## Оптимизация

- Chunk loading/unloading.
- Lazy spawning в момент загрузки чанка.
- Enemy object pooling.
- LOD-политика (дистанционная плотность/детализация).

## Безопасность и античит

- Валидировать входные payload в EventBus.
- Сетевые действия обрабатывать через whitelist.
- Не доверять клиентским значениям урона/лута.
- Сервер должен быть источником истины (authoritative).

## Ограничение размера

- Каждая система держится в пределах `<= 400` строк на модуль/файл.
- Сложная логика разбивается на компоненты и helper-модули.
