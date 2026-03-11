extends Node
class_name NetworkSystem

# Сервер-авторитетный каркас. Реализация RPC добавляется позже.
func validate_client_action(action: Dictionary) -> bool:
	if not action.has("type"):
		return false
	var allowed: Dictionary = {"move": true, "attack": true, "use_ability": true}
	return allowed.has(action["type"])
