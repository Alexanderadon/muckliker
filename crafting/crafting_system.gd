extends Node
class_name CraftingSystem

var _inventory_system: Node = null

const RECIPES_DATA_PATH: String = "res://data/recipes/default_recipes.json"
const DEFAULT_RECIPES: Dictionary = {
	"axe": {
		"requires": {
			"stone": 3,
			"wood": 2
		},
		"output": {
			"item_id": "axe",
			"amount": 1
		}
	},
	"pickaxe": {
		"requires": {
			"stone": 3,
			"wood": 2
		},
		"output": {
			"item_id": "pickaxe",
			"amount": 1
		}
	}
}

var _recipes: Dictionary = {}

func _ready() -> void:
	_load_recipes()

func set_inventory_system(inventory_system: Node) -> void:
	_inventory_system = inventory_system

func craft_item(recipe_id: String, inventory_source: Node = null) -> bool:
	if _recipes.is_empty():
		_load_recipes()
	var inventory_ref: Node = inventory_source
	if inventory_ref == null:
		if _inventory_system == null:
			_inventory_system = _resolve_inventory_system()
		inventory_ref = _inventory_system
	if inventory_ref == null:
		return false
	var recipe: Dictionary = get_recipe_data(recipe_id)
	if recipe.is_empty():
		return false
	if not inventory_ref.has_method("can_craft"):
		return false
	if not inventory_ref.has_method("craft"):
		return false
	var can_craft_variant: Variant = inventory_ref.call("can_craft", recipe)
	if not bool(can_craft_variant):
		return false
	var craft_variant: Variant = inventory_ref.call("craft", recipe)
	return bool(craft_variant)

func craft(recipe_id: String, inventory_source: Node = null) -> bool:
	return craft_item(recipe_id, inventory_source)

func get_recipe_ids() -> Array[String]:
	if _recipes.is_empty():
		_load_recipes()
	var result: Array[String] = []
	for key_variant in _recipes.keys():
		result.append(String(key_variant))
	return result

func get_recipe_data(recipe_id: String) -> Dictionary:
	if _recipes.is_empty():
		_load_recipes()
	var recipe_variant: Variant = _recipes.get(recipe_id.to_lower(), {})
	if recipe_variant is Dictionary:
		return Dictionary(recipe_variant).duplicate(true)
	return {}

func _load_recipes() -> void:
	_recipes = DEFAULT_RECIPES.duplicate(true)
	var root: Dictionary = JsonDataLoader.load_dictionary(RECIPES_DATA_PATH)
	var recipes_variant: Variant = root.get("recipes", {})
	if not (recipes_variant is Dictionary):
		return
	var recipes: Dictionary = Dictionary(recipes_variant)
	if recipes.is_empty():
		return
	_recipes = {}
	for key_variant in recipes.keys():
		var recipe_id: String = String(key_variant).to_lower()
		var recipe_variant: Variant = recipes[key_variant]
		if recipe_id.is_empty() or not (recipe_variant is Dictionary):
			continue
		_recipes[recipe_id] = Dictionary(recipe_variant).duplicate(true)

func _resolve_inventory_system() -> Node:
	var tree_ref: SceneTree = get_tree()
	if tree_ref == null:
		return null
	if tree_ref.current_scene != null:
		var from_scene: Node = tree_ref.current_scene.find_child("InventorySystem", true, false)
		if from_scene != null:
			return from_scene
	var root_node: Node = tree_ref.root
	if root_node != null:
		return root_node.find_child("InventorySystem", true, false)
	return null
