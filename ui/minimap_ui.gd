extends Control
class_name MinimapUI

const MAP_TOGGLE_ACTION: StringName = &"map_toggle"
const MAP_RESOLUTION: int = 512
const MINIMAP_SIZE: Vector2 = Vector2(228.0, 228.0)
const MINIMAP_WORLD_RADIUS: float = 180.0
const FULL_MAP_TEXTURE_SIZE: Vector2 = Vector2(780.0, 780.0)
const FULL_MAP_ZOOM_MIN: float = 1.0
const FULL_MAP_ZOOM_MAX: float = 6.0
const FULL_MAP_ZOOM_STEP: float = 1.2

const FOG_UNEXPLORED_ALPHA: float = 0.82
const FOG_REVEAL_RADIUS_WORLD: float = 44.0

const BOUNDARY_RING_WIDTH_WORLD: float = 8.0
const COAST_BAND_HEIGHT: float = 1.2
const MOUNTAIN_HEIGHT_OFFSET: float = 11.0

const COLOR_WATER_DEEP: Color = Color(0.02, 0.14, 0.34, 1.0)
const COLOR_WATER_SHALLOW: Color = Color(0.1, 0.31, 0.58, 1.0)
const COLOR_COAST: Color = Color(0.78, 0.75, 0.55, 1.0)
const COLOR_LAND_LOW: Color = Color(0.2, 0.52, 0.24, 1.0)
const COLOR_LAND_HIGH: Color = Color(0.34, 0.63, 0.29, 1.0)
const COLOR_MOUNTAIN_LOW: Color = Color(0.45, 0.45, 0.45, 1.0)
const COLOR_MOUNTAIN_HIGH: Color = Color(0.79, 0.79, 0.79, 1.0)
const COLOR_WORLD_BOUNDARY: Color = Color(0.9, 0.22, 0.22, 1.0)

var _bound_player: Node3D = null
var _world_system: Node = null
var _terrain_generator: TerrainGenerator = null

var _map_world_radius: float = 500.0
var _map_extent_world: float = 680.0
var _water_level: float = 0.0
var _terrain_height_scale: float = 10.0

var _map_texture: ImageTexture = null
var _fog_image: Image = null
var _fog_texture: ImageTexture = null
var _minimap_map_atlas: AtlasTexture = null
var _minimap_fog_atlas: AtlasTexture = null
var _full_map_map_atlas: AtlasTexture = null
var _full_map_fog_atlas: AtlasTexture = null

var _generated_seed: int = -2147483648
var _generated_radius: float = -1.0
var _generated_extent: float = -1.0
var _generated_water_level: float = 99999.0
var _generated_height_scale: float = -1.0

var _last_reveal_pixel: Vector2 = Vector2(-99999.0, -99999.0)

var _minimap_panel: PanelContainer = null
var _minimap_map_rect: TextureRect = null
var _minimap_fog_rect: TextureRect = null
var _minimap_marker: ColorRect = null

var _full_map_panel: PanelContainer = null
var _full_map_map_rect: TextureRect = null
var _full_map_fog_rect: TextureRect = null
var _full_map_marker: ColorRect = null

var _full_map_zoom: float = 1.0
var _full_map_center_uv: Vector2 = Vector2(0.5, 0.5)
var _is_dragging_full_map: bool = false
var _full_map_initialized: bool = false
var _heavy_update_gate: UpdateIntervalGate = UpdateIntervalGate.new()

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heavy_update_gate.set_interval(GameConfig.MINIMAP_UPDATE_INTERVAL)
	_ensure_input_action()
	_build_layout()
	_set_full_map_visible(false)

func _process(delta: float) -> void:
	DebugProfiler.start_sample("minimap.process")
	if _bound_player == null or not is_instance_valid(_bound_player):
		DebugProfiler.end_sample("minimap.process")
		return
	_update_minimap_marker()
	if _heavy_update_gate.should_run(delta):
		_reveal_fog_around_player(false)
		_update_minimap_region()
	if _full_map_panel != null and _full_map_panel.visible:
		_update_full_map_marker()
	DebugProfiler.end_sample("minimap.process")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.pressed and not key_event.echo and key_event.is_action_pressed(MAP_TOGGLE_ACTION):
			_toggle_full_map()
			get_viewport().set_input_as_handled()
			return

func bind(player: Node, world_system: Node) -> void:
	_bound_player = player as Node3D
	_world_system = world_system
	_sync_world_settings()
	_generate_map_resources_if_needed(true)
	_update_minimap_region()
	_reveal_fog_around_player(true)
	_update_minimap_marker()
	if not _full_map_initialized:
		_full_map_center_uv = _get_player_uv()
		_full_map_initialized = true
	_apply_full_map_region()
	_update_full_map_marker()

func _ensure_input_action() -> void:
	if not InputMap.has_action(MAP_TOGGLE_ACTION):
		InputMap.add_action(MAP_TOGGLE_ACTION)
	for event in InputMap.action_get_events(MAP_TOGGLE_ACTION):
		if event is InputEventKey and event.physical_keycode == KEY_M:
			return
	var key_event: InputEventKey = InputEventKey.new()
	key_event.physical_keycode = KEY_M
	InputMap.action_add_event(MAP_TOGGLE_ACTION, key_event)

func _build_layout() -> void:
	for child in get_children():
		child.queue_free()

	_build_minimap_layout()
	_build_full_map_layout()

func _build_minimap_layout() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(column)

	var top_row: HBoxContainer = HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(top_row)

	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	_minimap_panel = PanelContainer.new()
	_minimap_panel.custom_minimum_size = Vector2(MINIMAP_SIZE.x + 10.0, MINIMAP_SIZE.y + 10.0)
	top_row.add_child(_minimap_panel)

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.18)
	panel_style.border_color = Color(0.75, 0.75, 0.8, 0.75)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 120
	panel_style.corner_radius_top_right = 120
	panel_style.corner_radius_bottom_left = 120
	panel_style.corner_radius_bottom_right = 120
	_minimap_panel.add_theme_stylebox_override("panel", panel_style)

	var stack: Control = Control.new()
	stack.custom_minimum_size = MINIMAP_SIZE
	_minimap_panel.add_child(stack)

	_minimap_map_rect = TextureRect.new()
	_minimap_map_rect.anchor_right = 1.0
	_minimap_map_rect.anchor_bottom = 1.0
	_minimap_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_minimap_map_rect.modulate = Color(1.0, 1.0, 1.0, 0.8)
	_minimap_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_map_rect.material = _create_circle_mask_material()
	stack.add_child(_minimap_map_rect)

	_minimap_fog_rect = TextureRect.new()
	_minimap_fog_rect.anchor_right = 1.0
	_minimap_fog_rect.anchor_bottom = 1.0
	_minimap_fog_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_minimap_fog_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_minimap_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_fog_rect.material = _create_circle_mask_material()
	stack.add_child(_minimap_fog_rect)

	_minimap_marker = ColorRect.new()
	_minimap_marker.custom_minimum_size = Vector2(10.0, 10.0)
	_minimap_marker.size = Vector2(10.0, 10.0)
	_minimap_marker.color = Color(1.0, 0.92, 0.2, 1.0)
	_minimap_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap_map_rect.add_child(_minimap_marker)

func _build_full_map_layout() -> void:
	var center: CenterContainer = CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	_full_map_panel = PanelContainer.new()
	_full_map_panel.custom_minimum_size = Vector2(FULL_MAP_TEXTURE_SIZE.x + 34.0, FULL_MAP_TEXTURE_SIZE.y + 80.0)
	_full_map_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_full_map_panel.gui_input.connect(Callable(self, "_on_full_map_gui_input"))
	center.add_child(_full_map_panel)

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	panel_style.border_color = Color(0.25, 0.25, 0.3, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	_full_map_panel.add_theme_stylebox_override("panel", panel_style)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_full_map_panel.add_child(margin)

	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var title: Label = Label.new()
	title.text = "World Map (M)"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var map_stack: Control = Control.new()
	map_stack.custom_minimum_size = FULL_MAP_TEXTURE_SIZE
	column.add_child(map_stack)

	_full_map_map_rect = TextureRect.new()
	_full_map_map_rect.anchor_right = 1.0
	_full_map_map_rect.anchor_bottom = 1.0
	_full_map_map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_full_map_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_full_map_map_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_stack.add_child(_full_map_map_rect)

	_full_map_fog_rect = TextureRect.new()
	_full_map_fog_rect.anchor_right = 1.0
	_full_map_fog_rect.anchor_bottom = 1.0
	_full_map_fog_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_full_map_fog_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_full_map_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_stack.add_child(_full_map_fog_rect)

	_full_map_marker = ColorRect.new()
	_full_map_marker.custom_minimum_size = Vector2(12.0, 12.0)
	_full_map_marker.size = Vector2(12.0, 12.0)
	_full_map_marker.color = Color(1.0, 0.92, 0.2, 1.0)
	_full_map_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full_map_map_rect.add_child(_full_map_marker)

func _set_full_map_visible(value: bool) -> void:
	if _full_map_panel == null:
		return
	_full_map_panel.visible = value
	if value:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		_is_dragging_full_map = false
		if not _is_inventory_open():
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _toggle_full_map() -> void:
	if _full_map_panel == null:
		return
	var next_visible: bool = not _full_map_panel.visible
	_set_full_map_visible(next_visible)
	if not next_visible:
		return
	_sync_world_settings()
	_generate_map_resources_if_needed(false)
	if not _full_map_initialized:
		_full_map_center_uv = _get_player_uv()
		_full_map_initialized = true
	_apply_full_map_region()
	_update_full_map_marker()

func _on_full_map_gui_input(event: InputEvent) -> void:
	if _full_map_panel == null or not _full_map_panel.visible:
		return
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	if event is InputEventMouseButton:
		var mouse_button_event: InputEventMouseButton = event
		if mouse_button_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button_event.pressed and _is_point_in_full_map(mouse_position):
				_is_dragging_full_map = true
				get_viewport().set_input_as_handled()
				return
			if not mouse_button_event.pressed and _is_dragging_full_map:
				_is_dragging_full_map = false
				get_viewport().set_input_as_handled()
				return
		if mouse_button_event.pressed and _is_point_in_full_map(mouse_position):
			if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_zoom_full_map(FULL_MAP_ZOOM_STEP, mouse_position)
				get_viewport().set_input_as_handled()
				return
			if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_full_map(1.0 / FULL_MAP_ZOOM_STEP, mouse_position)
				get_viewport().set_input_as_handled()
				return
	if event is InputEventMouseMotion and _is_dragging_full_map:
		var motion_event: InputEventMouseMotion = event
		_drag_full_map(motion_event.relative)
		get_viewport().set_input_as_handled()

func _sync_world_settings() -> void:
	if _world_system == null:
		return
	var seed_value: int = _get_seed_from_world()
	_map_world_radius = _get_world_radius_from_world()
	_water_level = _get_water_level_from_world()
	_terrain_height_scale = _get_height_scale_from_world()
	_map_extent_world = _map_world_radius + maxf(MINIMAP_WORLD_RADIUS * 1.25, 180.0)
	if _terrain_generator == null or seed_value != _generated_seed or not is_equal_approx(_terrain_height_scale, _generated_height_scale):
		_terrain_generator = TerrainGenerator.new()
		_terrain_generator.configure(seed_value, _terrain_height_scale)

func _generate_map_resources_if_needed(force_rebuild: bool) -> void:
	if _terrain_generator == null:
		return
	var seed_value: int = _get_seed_from_world()
	var has_textures: bool = _map_texture != null and _fog_texture != null and _fog_image != null
	var same_seed: bool = seed_value == _generated_seed
	var same_radius: bool = is_equal_approx(_map_world_radius, _generated_radius)
	var same_extent: bool = is_equal_approx(_map_extent_world, _generated_extent)
	var same_water_level: bool = is_equal_approx(_water_level, _generated_water_level)
	var same_height_scale: bool = is_equal_approx(_terrain_height_scale, _generated_height_scale)
	var unchanged: bool = has_textures and same_seed and same_radius and same_extent and same_water_level and same_height_scale
	if unchanged and not force_rebuild:
		_assign_map_textures()
		return

	var map_image: Image = Image.create(MAP_RESOLUTION, MAP_RESOLUTION, false, Image.FORMAT_RGBA8)
	var max_index: float = float(MAP_RESOLUTION - 1)
	for y in range(MAP_RESOLUTION):
		var v: float = float(y) / max_index
		var world_z: float = lerpf(-_map_extent_world, _map_extent_world, v)
		for x in range(MAP_RESOLUTION):
			var u: float = float(x) / max_index
			var world_x: float = lerpf(-_map_extent_world, _map_extent_world, u)
			var distance_from_center: float = Vector2(world_x, world_z).length()
			var height: float = _terrain_generator.terrain_height(world_x, world_z)
			map_image.set_pixel(x, y, _sample_map_color(height, distance_from_center))

	if _map_texture == null:
		_map_texture = ImageTexture.create_from_image(map_image)
	else:
		_map_texture.update(map_image)

	_fog_image = Image.create(MAP_RESOLUTION, MAP_RESOLUTION, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color(0.0, 0.0, 0.0, FOG_UNEXPLORED_ALPHA))
	if _fog_texture == null:
		_fog_texture = ImageTexture.create_from_image(_fog_image)
	else:
		_fog_texture.update(_fog_image)
	_last_reveal_pixel = Vector2(-99999.0, -99999.0)

	_generated_seed = seed_value
	_generated_radius = _map_world_radius
	_generated_extent = _map_extent_world
	_generated_water_level = _water_level
	_generated_height_scale = _terrain_height_scale

	_assign_map_textures()
	_apply_full_map_region()
	_update_minimap_region()

func _assign_map_textures() -> void:
	_ensure_atlas_wrappers()
	if _map_texture != null:
		_minimap_map_atlas.atlas = _map_texture
		_full_map_map_atlas.atlas = _map_texture
	if _fog_texture != null:
		_minimap_fog_atlas.atlas = _fog_texture
		_full_map_fog_atlas.atlas = _fog_texture
	if _minimap_map_rect != null:
		_minimap_map_rect.texture = _minimap_map_atlas
	if _full_map_map_rect != null:
		_full_map_map_rect.texture = _full_map_map_atlas
	if _minimap_fog_rect != null:
		_minimap_fog_rect.texture = _minimap_fog_atlas
	if _full_map_fog_rect != null:
		_full_map_fog_rect.texture = _full_map_fog_atlas

func _sample_map_color(height: float, distance_from_center: float) -> Color:
	if distance_from_center > _map_world_radius:
		return COLOR_WATER_DEEP
	if absf(distance_from_center - _map_world_radius) <= BOUNDARY_RING_WIDTH_WORLD:
		return COLOR_WORLD_BOUNDARY
	if height <= _water_level:
		var depth_t: float = clampf((_water_level - height) / 12.0, 0.0, 1.0)
		return COLOR_WATER_SHALLOW.lerp(COLOR_WATER_DEEP, depth_t)

	var elevation: float = height - _water_level
	if elevation <= COAST_BAND_HEIGHT:
		return COLOR_COAST
	if elevation >= MOUNTAIN_HEIGHT_OFFSET:
		var mountain_t: float = clampf((elevation - MOUNTAIN_HEIGHT_OFFSET) / 24.0, 0.0, 1.0)
		return COLOR_MOUNTAIN_LOW.lerp(COLOR_MOUNTAIN_HIGH, mountain_t)
	var land_t: float = clampf(elevation / MOUNTAIN_HEIGHT_OFFSET, 0.0, 1.0)
	return COLOR_LAND_LOW.lerp(COLOR_LAND_HIGH, land_t)

func _reveal_fog_around_player(force: bool) -> void:
	if _bound_player == null or _fog_image == null or _fog_texture == null:
		return
	var player_uv: Vector2 = _get_player_uv()
	var center_pixel: Vector2 = player_uv * float(MAP_RESOLUTION - 1)
	if not force and center_pixel.distance_squared_to(_last_reveal_pixel) < 1.0:
		return
	_last_reveal_pixel = center_pixel

	var pixels_per_world: float = _world_to_pixel_scale()
	var reveal_radius_px: int = maxi(int(round(FOG_REVEAL_RADIUS_WORLD * pixels_per_world)), 2)
	var center_x: int = int(round(center_pixel.x))
	var center_y: int = int(round(center_pixel.y))
	var min_x: int = maxi(center_x - reveal_radius_px, 0)
	var max_x: int = mini(center_x + reveal_radius_px, MAP_RESOLUTION - 1)
	var min_y: int = maxi(center_y - reveal_radius_px, 0)
	var max_y: int = mini(center_y + reveal_radius_px, MAP_RESOLUTION - 1)

	var changed: bool = false
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var offset_x: float = float(x - center_x)
			var offset_y: float = float(y - center_y)
			var distance: float = sqrt(offset_x * offset_x + offset_y * offset_y)
			if distance > float(reveal_radius_px):
				continue
			var ratio: float = clampf(distance / maxf(float(reveal_radius_px), 1.0), 0.0, 1.0)
			var target_alpha: float = ratio * FOG_UNEXPLORED_ALPHA
			var fog_color: Color = _fog_image.get_pixel(x, y)
			if target_alpha < fog_color.a:
				fog_color.a = target_alpha
				_fog_image.set_pixel(x, y, fog_color)
				changed = true
	if changed:
		_fog_texture.update(_fog_image)

func _update_minimap_region() -> void:
	if _minimap_map_rect == null or _minimap_fog_rect == null:
		return
	if _bound_player == null:
		return
	var center_uv: Vector2 = _get_player_uv()
	var center_px: Vector2 = center_uv * float(MAP_RESOLUTION - 1)
	var half_region_px: float = maxf(MINIMAP_WORLD_RADIUS * _world_to_pixel_scale(), 8.0)
	var region_size: Vector2 = Vector2(half_region_px * 2.0, half_region_px * 2.0)
	var region_position: Vector2 = center_px - Vector2(half_region_px, half_region_px)
	var region: Rect2 = _clamp_region_to_texture(Rect2(region_position, region_size))
	_set_minimap_region_pixels(region)

func _update_minimap_marker() -> void:
	if _minimap_marker == null or _minimap_map_rect == null:
		return
	_minimap_marker.visible = _bound_player != null and is_instance_valid(_bound_player)
	if not _minimap_marker.visible:
		return
	var map_size: Vector2 = _minimap_map_rect.size
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		map_size = _minimap_map_rect.get_combined_minimum_size()
	var marker_size: Vector2 = _minimap_marker.size
	_minimap_marker.position = Vector2(
		(map_size.x - marker_size.x) * 0.5,
		(map_size.y - marker_size.y) * 0.5
	)

func _apply_full_map_region() -> void:
	if _full_map_map_rect == null or _full_map_fog_rect == null:
		return
	var region_size_norm: float = 1.0 / maxf(_full_map_zoom, FULL_MAP_ZOOM_MIN)
	var half_norm: float = region_size_norm * 0.5
	_full_map_center_uv.x = clampf(_full_map_center_uv.x, half_norm, 1.0 - half_norm)
	_full_map_center_uv.y = clampf(_full_map_center_uv.y, half_norm, 1.0 - half_norm)
	var region_origin_norm: Vector2 = _full_map_center_uv - Vector2(half_norm, half_norm)
	var source_size: Vector2 = Vector2(float(MAP_RESOLUTION), float(MAP_RESOLUTION))
	var region: Rect2 = _clamp_region_to_texture(Rect2(region_origin_norm * source_size, Vector2(region_size_norm, region_size_norm) * source_size))
	_set_full_map_region_pixels(region)

func _update_full_map_marker() -> void:
	if _full_map_marker == null or _full_map_map_rect == null:
		return
	if _bound_player == null or not is_instance_valid(_bound_player):
		_full_map_marker.visible = false
		return
	var player_uv: Vector2 = _get_player_uv()
	var source_size: Vector2 = Vector2(float(MAP_RESOLUTION), float(MAP_RESOLUTION))
	var region: Rect2 = _get_full_map_region_pixels()
	var region_origin_norm: Vector2 = Vector2(region.position.x / source_size.x, region.position.y / source_size.y)
	var region_size_norm: Vector2 = Vector2(region.size.x / source_size.x, region.size.y / source_size.y)
	if region_size_norm.x <= 0.0 or region_size_norm.y <= 0.0:
		_full_map_marker.visible = false
		return
	var local_norm_x: float = (player_uv.x - region_origin_norm.x) / region_size_norm.x
	var local_norm_y: float = (player_uv.y - region_origin_norm.y) / region_size_norm.y
	var marker_visible: bool = local_norm_x >= 0.0 and local_norm_x <= 1.0 and local_norm_y >= 0.0 and local_norm_y <= 1.0
	_full_map_marker.visible = marker_visible
	if not marker_visible:
		return
	var map_size: Vector2 = _full_map_map_rect.size
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		map_size = _full_map_map_rect.get_combined_minimum_size()
	var marker_size: Vector2 = _full_map_marker.size
	_full_map_marker.position = Vector2(
		local_norm_x * map_size.x - marker_size.x * 0.5,
		local_norm_y * map_size.y - marker_size.y * 0.5
	)

func _zoom_full_map(zoom_factor: float, mouse_position: Vector2) -> void:
	var old_zoom: float = _full_map_zoom
	var new_zoom: float = clampf(_full_map_zoom * zoom_factor, FULL_MAP_ZOOM_MIN, FULL_MAP_ZOOM_MAX)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var map_size: Vector2 = _full_map_map_rect.size
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		map_size = _full_map_map_rect.get_combined_minimum_size()
	var map_rect: Rect2 = _full_map_map_rect.get_global_rect()
	var cursor_norm: Vector2 = Vector2(0.5, 0.5)
	if map_rect.has_point(mouse_position) and map_size.x > 0.0 and map_size.y > 0.0:
		cursor_norm = Vector2(
			clampf((mouse_position.x - map_rect.position.x) / map_size.x, 0.0, 1.0),
			clampf((mouse_position.y - map_rect.position.y) / map_size.y, 0.0, 1.0)
		)
	var old_size_norm: float = 1.0 / old_zoom
	var old_half_norm: float = old_size_norm * 0.5
	var old_origin_norm: Vector2 = _full_map_center_uv - Vector2(old_half_norm, old_half_norm)
	var cursor_world_uv: Vector2 = old_origin_norm + cursor_norm * old_size_norm
	_full_map_zoom = new_zoom
	var new_size_norm: float = 1.0 / _full_map_zoom
	var new_origin_norm: Vector2 = cursor_world_uv - cursor_norm * new_size_norm
	_full_map_center_uv = new_origin_norm + Vector2(new_size_norm, new_size_norm) * 0.5
	_apply_full_map_region()
	_update_full_map_marker()

func _drag_full_map(relative_motion: Vector2) -> void:
	if _full_map_map_rect == null:
		return
	var map_size: Vector2 = _full_map_map_rect.size
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		map_size = _full_map_map_rect.get_combined_minimum_size()
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		return
	var delta_uv: Vector2 = Vector2(
		relative_motion.x / map_size.x,
		relative_motion.y / map_size.y
	) * (1.0 / maxf(_full_map_zoom, FULL_MAP_ZOOM_MIN))
	_full_map_center_uv -= delta_uv
	_apply_full_map_region()
	_update_full_map_marker()

func _is_point_in_full_map(screen_position: Vector2) -> bool:
	if _full_map_map_rect == null:
		return false
	return _full_map_map_rect.get_global_rect().has_point(screen_position)

func _ensure_atlas_wrappers() -> void:
	var full_region: Rect2 = Rect2(Vector2.ZERO, Vector2(float(MAP_RESOLUTION), float(MAP_RESOLUTION)))
	if _minimap_map_atlas == null:
		_minimap_map_atlas = AtlasTexture.new()
		_minimap_map_atlas.region = full_region
	if _minimap_fog_atlas == null:
		_minimap_fog_atlas = AtlasTexture.new()
		_minimap_fog_atlas.region = full_region
	if _full_map_map_atlas == null:
		_full_map_map_atlas = AtlasTexture.new()
		_full_map_map_atlas.region = full_region
	if _full_map_fog_atlas == null:
		_full_map_fog_atlas = AtlasTexture.new()
		_full_map_fog_atlas.region = full_region

func _set_minimap_region_pixels(region: Rect2) -> void:
	_ensure_atlas_wrappers()
	_minimap_map_atlas.region = region
	_minimap_fog_atlas.region = region

func _set_full_map_region_pixels(region: Rect2) -> void:
	_ensure_atlas_wrappers()
	_full_map_map_atlas.region = region
	_full_map_fog_atlas.region = region

func _get_full_map_region_pixels() -> Rect2:
	if _full_map_map_atlas != null and _full_map_map_atlas.region.size.length_squared() > 0.0:
		return _full_map_map_atlas.region
	return Rect2(Vector2.ZERO, Vector2(float(MAP_RESOLUTION), float(MAP_RESOLUTION)))

func _clamp_region_to_texture(region: Rect2) -> Rect2:
	var texture_size: Vector2 = Vector2(float(MAP_RESOLUTION), float(MAP_RESOLUTION))
	var clamped_size: Vector2 = Vector2(
		clampf(region.size.x, 1.0, texture_size.x),
		clampf(region.size.y, 1.0, texture_size.y)
	)
	var max_position: Vector2 = Vector2(
		maxf(texture_size.x - clamped_size.x, 0.0),
		maxf(texture_size.y - clamped_size.y, 0.0)
	)
	var clamped_position: Vector2 = Vector2(
		clampf(region.position.x, 0.0, max_position.x),
		clampf(region.position.y, 0.0, max_position.y)
	)
	return Rect2(clamped_position, clamped_size)

func _get_player_uv() -> Vector2:
	if _bound_player == null:
		return Vector2(0.5, 0.5)
	var player_position: Vector3 = _bound_player.global_position
	return _world_to_uv(Vector2(player_position.x, player_position.z))

func _world_to_uv(world_xz: Vector2) -> Vector2:
	var extent: float = maxf(_map_extent_world, 1.0)
	var normalized_x: float = clampf((world_xz.x + extent) / (extent * 2.0), 0.0, 1.0)
	var normalized_y: float = clampf((world_xz.y + extent) / (extent * 2.0), 0.0, 1.0)
	return Vector2(normalized_x, normalized_y)

func _world_to_pixel_scale() -> float:
	return float(MAP_RESOLUTION) / maxf(_map_extent_world * 2.0, 1.0)

func _get_seed_from_world() -> int:
	if _world_system == null:
		return 0
	if _world_system.has_method("get_world_seed"):
		var seed_variant: Variant = _world_system.call("get_world_seed")
		return _variant_to_int(seed_variant, 0)
	return 0

func _get_world_radius_from_world() -> float:
	if _world_system == null:
		return 500.0
	if _world_system.has_method("get_world_radius"):
		var radius_variant: Variant = _world_system.call("get_world_radius")
		return maxf(_variant_to_float(radius_variant, 500.0), 1.0)
	return 500.0

func _get_water_level_from_world() -> float:
	if _world_system == null:
		return 0.0
	if _world_system.has_method("get_water_level"):
		var water_variant: Variant = _world_system.call("get_water_level")
		return _variant_to_float(water_variant, 0.0)
	return 0.0

func _get_height_scale_from_world() -> float:
	if _world_system == null:
		return 10.0
	var scale_variant: Variant = _world_system.get("terrain_height_scale")
	return _variant_to_float(scale_variant, 10.0)

func _is_inventory_open() -> bool:
	var inventory_nodes: Array = get_tree().get_nodes_in_group("inventory_ui")
	for inventory_node_variant in inventory_nodes:
		var inventory_ui: Control = inventory_node_variant as Control
		if inventory_ui == null:
			continue
		if not inventory_ui.has_method("is_inventory_panel_open"):
			continue
		var open_variant: Variant = inventory_ui.call("is_inventory_panel_open")
		if bool(open_variant):
			return true
	return false

func _create_circle_mask_material() -> ShaderMaterial:
	var shader: Shader = Shader.new()
	shader.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec2 centered_uv = UV * 2.0 - 1.0;\n\tfloat inside_mask = step(length(centered_uv), 1.0);\n\tvec4 sampled = texture(TEXTURE, UV) * COLOR;\n\tCOLOR = vec4(sampled.rgb, sampled.a * inside_mask);\n}"
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = shader
	return shader_material

func _variant_to_float(value: Variant, fallback: float) -> float:
	var value_type: int = typeof(value)
	if value_type == TYPE_FLOAT or value_type == TYPE_INT:
		return float(value)
	return fallback

func _variant_to_int(value: Variant, fallback: int) -> int:
	var value_type: int = typeof(value)
	if value_type == TYPE_INT:
		return int(value)
	if value_type == TYPE_FLOAT:
		return int(round(float(value)))
	return fallback
