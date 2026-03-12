extends Area3D
class_name AbilityCapsule

signal collected(ability_id: StringName, collector: Node)
const DEFAULT_PICKUP_SOUND_PATH: String = "res://assets/audio/ui/ability_capsule_pickup.wav"

@export var ability_pool: Array[StringName] = [&"max_hp_plus_5", &"move_speed_bonus", &"jump_bonus_5_percent"]
@export var pickup_sound: AudioStream = null
@export var pickup_sound_bus: StringName = &"Master"
@export var pickup_sound_volume_db: float = -4.0
@export var float_amplitude: float = 0.22
@export var float_frequency: float = 1.9
@export var rotation_speed_radians: float = 0.9
@export var glow_energy: float = 1.4
@export var hover_base_height: float = 0.75
@export var pickup_height_offset: float = 0.0

var _base_y: float = 0.0
var _time_accumulator: float = 0.0
var _picked: bool = false
var _has_spawn_world_position: bool = false
var _spawn_world_position: Vector3 = Vector3.ZERO
var _pickup_audio_player: AudioStreamPlayer = null

func _ready() -> void:
	add_to_group("ability_capsule")
	_ensure_visuals()
	_ensure_audio_player()
	_try_assign_default_pickup_sound()
	if _has_spawn_world_position:
		global_position = _spawn_world_position
	_base_y = global_position.y + hover_base_height
	var start_position: Vector3 = global_position
	start_position.y = _base_y + pickup_height_offset
	global_position = start_position
	if not body_entered.is_connected(Callable(self, "_on_body_entered")):
		body_entered.connect(Callable(self, "_on_body_entered"))

func _process(delta: float) -> void:
	if _picked:
		return
	_time_accumulator += delta
	var floating_offset: float = sin(_time_accumulator * float_frequency) * float_amplitude
	var current_position: Vector3 = global_position
	current_position.y = _base_y + floating_offset + pickup_height_offset
	global_position = current_position
	rotation.y += rotation_speed_radians * delta

func _on_body_entered(body: Node) -> void:
	if _picked:
		return
	if body == null or not is_instance_valid(body):
		return
	if not body.is_in_group("player"):
		return
	var ability_manager: Node = _resolve_ability_manager(body)
	if ability_manager == null:
		return
	if not ability_manager.has_method("collect_random_from_pool"):
		return
	var collected_variant: Variant = ability_manager.call("collect_random_from_pool", ability_pool)
	var collected_id: StringName = StringName(String(collected_variant))
	if collected_id == StringName(""):
		return
	_picked = true
	collected.emit(collected_id, body)
	_finalize_collection()

func set_spawn_world_position(world_position: Vector3) -> void:
	_has_spawn_world_position = true
	_spawn_world_position = world_position
	if is_inside_tree():
		global_position = world_position
		_base_y = global_position.y + hover_base_height

func _resolve_ability_manager(player: Node) -> Node:
	if player == null:
		return null
	if player.has_method("get_ability_manager"):
		var manager_variant: Variant = player.call("get_ability_manager")
		if manager_variant is Node:
			return manager_variant as Node
	var by_name: Node = player.get_node_or_null("AbilityManager")
	if by_name != null:
		return by_name
	return player.find_child("AbilityManager", true, false)

func _ensure_visuals() -> void:
	if get_node_or_null("CollisionShape3D") == null:
		var collision_shape: CollisionShape3D = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		var sphere_shape: SphereShape3D = SphereShape3D.new()
		sphere_shape.radius = 0.62
		collision_shape.shape = sphere_shape
		collision_shape.position = Vector3(0.0, 0.25, 0.0)
		add_child(collision_shape)
	if get_node_or_null("Visual") == null:
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.name = "Visual"
		var capsule: CapsuleMesh = CapsuleMesh.new()
		capsule.radius = 0.28
		capsule.height = 0.9
		visual.mesh = capsule
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.56, 0.24, 0.93, 1.0)
		material.emission_enabled = true
		material.emission = Color(0.65, 0.33, 0.98, 1.0)
		material.emission_energy_multiplier = glow_energy
		material.roughness = 0.25
		visual.material_override = material
		add_child(visual)
	if get_node_or_null("GlowLight") == null:
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "GlowLight"
		light.light_color = Color(0.65, 0.33, 0.98, 1.0)
		light.light_energy = 0.85
		light.omni_range = 5.0
		light.position = Vector3(0.0, 0.55, 0.0)
		add_child(light)

func _ensure_audio_player() -> void:
	if _pickup_audio_player != null and is_instance_valid(_pickup_audio_player):
		return
	for child_variant in get_children():
		var child_player: AudioStreamPlayer = child_variant as AudioStreamPlayer
		if child_player != null:
			_pickup_audio_player = child_player
			break
	if _pickup_audio_player == null:
		_pickup_audio_player = AudioStreamPlayer.new()
		_pickup_audio_player.name = "PickupAudioPlayer"
		add_child(_pickup_audio_player)

func _finalize_collection() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_process(false)
	set_physics_process(false)
	for child_variant in get_children():
		if child_variant is MeshInstance3D or child_variant is OmniLight3D:
			var child_node: Node3D = child_variant as Node3D
			if child_node != null:
				child_node.visible = false
		elif child_variant is CollisionShape3D:
			var collision_shape: CollisionShape3D = child_variant as CollisionShape3D
			if collision_shape != null:
				collision_shape.set_deferred("disabled", true)
	if pickup_sound == null:
		queue_free()
		return
	_ensure_audio_player()
	if _pickup_audio_player == null:
		queue_free()
		return
	_pickup_audio_player.stream = pickup_sound
	_pickup_audio_player.bus = String(pickup_sound_bus)
	_pickup_audio_player.volume_db = pickup_sound_volume_db
	var finished_callback: Callable = Callable(self, "_on_pickup_sound_finished")
	if _pickup_audio_player.finished.is_connected(finished_callback):
		_pickup_audio_player.finished.disconnect(finished_callback)
	_pickup_audio_player.finished.connect(finished_callback, CONNECT_ONE_SHOT)
	_pickup_audio_player.play()

func _on_pickup_sound_finished() -> void:
	queue_free()

func _try_assign_default_pickup_sound() -> void:
	if pickup_sound != null:
		return
	var import_meta_path: String = "%s.import" % DEFAULT_PICKUP_SOUND_PATH
	if FileAccess.file_exists(import_meta_path):
		var import_config: ConfigFile = ConfigFile.new()
		if import_config.load(import_meta_path) == OK:
			var remapped_path: String = String(import_config.get_value("remap", "path", ""))
			if remapped_path != "" and not FileAccess.file_exists(remapped_path):
				return
	if not ResourceLoader.exists(DEFAULT_PICKUP_SOUND_PATH):
		return
	var loaded_stream: AudioStream = load(DEFAULT_PICKUP_SOUND_PATH) as AudioStream
	if loaded_stream != null:
		pickup_sound = loaded_stream
