extends Node

# World generation and chunk streaming
const CHUNK_SIZE: int = 64
const TERRAIN_HEIGHT_SCALE: float = 10.0
const VIEW_DISTANCE_CHUNKS: int = 4
const MAX_ACTIVE_CHUNKS: int = 81
const LOD_CULL_DISTANCE_CHUNKS: int = 6
const TERRAIN_RESOLUTION: int = 32
const RESOURCE_SPAWNS_PER_CHUNK: int = 8
const GROUND_PICKUPS_PER_CHUNK: int = 6
const MAX_SPAWN_OPERATIONS_PER_FRAME: int = 6
const WORLD_BOUNDARY_MARGIN: float = 2.0
const WATER_LEVEL: float = -3.5
const DEEP_WATER_TERRAIN_THRESHOLD: float = -4.0

# Rendering and environment
const CAMERA_FAR_CLIP: float = 1000.0
const FOG_DEPTH_BEGIN: float = 260.0
const FOG_DEPTH_END: float = 980.0
const FOG_DENSITY: float = 0.0025

# Enemy and loot runtime
const ENEMY_POOL_SIZE: int = 50
const MAX_ENEMIES_PER_CHUNK: int = 5
const ENEMY_SPAWN_MIN_DISTANCE: float = 15.0
const ENEMY_DESPAWN_DISTANCE: float = 80.0
const LOOT_POOL_SIZE: int = 220
const LOOT_PICKUP_DISTANCE: float = 2.0
const LOOT_PICKUP_DELAY_SECONDS: float = 0.35

# Interval update targets
# Keep defaults at 0.0 for behavior parity; can be increased for perf profiles.
const AI_UPDATE_INTERVAL: float = 0.0
const MINIMAP_UPDATE_INTERVAL: float = 0.0

# Tooling
const ENABLE_DEBUG_PROFILER: bool = false
