extends Resource
class_name ChatInterfaces

const DEFAULT_PROFILE_TEMPLATE := {
	"display_name": "",
	"npc_color": Color(1, 0.878, 0.502),
	"player_color": Color(0.533, 0.8, 1),
	"accent_color": Color(1, 1, 1),
	"prompt_verb": "Hablar con",
	"prompt_action": "interact",
	"placeholder": "Escribí algo y presioná",
	"player_label": "Vos"
}

static var DEFAULT_PROFILE := DEFAULT_PROFILE_TEMPLATE.duplicate(true)
static var PROFILES := {}

static func _profile(overrides: Dictionary) -> Dictionary:
	var profile := DEFAULT_PROFILE_TEMPLATE.duplicate(true)
	for key in overrides.keys():
		profile[key] = overrides[key]
	return profile

static func profile_for(npc_id: String) -> Dictionary:
	if PROFILES.is_empty():
		_init_profiles()
	var profile: Dictionary = PROFILES.get(npc_id, PROFILES["_default"]).duplicate(true)
	profile["npc_id"] = npc_id
	return profile


static func _init_profiles() -> void:
	if not PROFILES.is_empty():
		return
	PROFILES["_default"] = DEFAULT_PROFILE.duplicate(true)
	PROFILES["Criada"] = _profile({
		"display_name": "Criada",
		"npc_color": Color(1, 0.819, 0.957),
		"player_color": Color(0.533, 0.8, 1),
		"accent_color": Color(0.957, 0.561, 0.694),
	})
	PROFILES["Esteban"] = _profile({
		"display_name": "Esteban",
		"npc_color": Color(0.875, 0.949, 0.761),
		"accent_color": Color(0.412, 0.702, 0.435),
	})
	PROFILES["Juan"] = _profile({
		"display_name": "Juan",
		"npc_color": Color(0.804, 0.898, 1),
		"accent_color": Color(0.309, 0.514, 0.8),
	})
	PROFILES["Pablo"] = _profile({
		"display_name": "Pablo",
		"npc_color": Color(0.914, 0.902, 1),
		"accent_color": Color(0.486, 0.424, 1),
	})
	PROFILES["Forense"] = _profile({
		"display_name": "Forense",
		"npc_color": Color(0.886, 0.957, 1),
		"accent_color": Color(0.506, 0.631, 0.756),
	})
