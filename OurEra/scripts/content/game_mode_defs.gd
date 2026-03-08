class_name GameModeDefs
extends RefCounted

const CREATIVE := &"creative"
const SURVIVAL := &"survival"

const SETTING_BLOCK_DROPS := &"block_drops_enabled"
const SETTING_PLACEMENT_CONSUMES_INVENTORY := &"placement_consumes_inventory"
const SETTING_PLACEMENT_REQUIRES_INVENTORY := &"placement_requires_inventory"
const SETTING_DROP_PICKUP_ENABLED := &"drop_pickup_enabled"
const SETTING_INSTANT_BREAK_ENABLED := &"instant_break_enabled"
const SETTING_HEALTH_ENABLED := &"health_enabled"
const SETTING_HUNGER_ENABLED := &"hunger_enabled"
const SETTING_DAMAGE_ENABLED := &"damage_enabled"

const DEFAULT_MODE := SURVIVAL

const _ORDERED_GAME_MODES := [
	CREATIVE,
	SURVIVAL,
]

static var _GAME_MODES: Dictionary = _build_game_modes()

static func has_mode(mode_id: StringName) -> bool:
	return _GAME_MODES.has(mode_id)

static func get_mode_ids() -> Array[StringName]:
	var mode_ids: Array[StringName] = []
	for mode_id in _ORDERED_GAME_MODES:
		mode_ids.append(mode_id)
	return mode_ids

static func get_default_mode_id() -> StringName:
	return DEFAULT_MODE

static func normalize_mode_id(mode_id: StringName) -> StringName:
	if has_mode(mode_id):
		return mode_id
	return DEFAULT_MODE

static func get_mode_def(mode_id: StringName) -> Dictionary:
	return _resolve_mode(mode_id).duplicate(true)

static func get_display_data(mode_id: StringName) -> Dictionary:
	return Dictionary(_resolve_mode(mode_id).get("display", {})).duplicate(true)

static func get_mode_meta(mode_id: StringName) -> Dictionary:
	return Dictionary(_resolve_mode(mode_id).get("meta", {})).duplicate(true)

static func get_setting(mode_id: StringName, setting_key: StringName, default_value: Variant = null) -> Variant:
	var settings: Dictionary = _resolve_mode(mode_id).get("settings", {})
	return settings.get(setting_key, default_value)

static func are_block_drops_enabled(mode_id: StringName) -> bool:
	return bool(get_setting(mode_id, SETTING_BLOCK_DROPS, true))

static func does_placement_consume_inventory(mode_id: StringName) -> bool:
	return bool(get_setting(mode_id, SETTING_PLACEMENT_CONSUMES_INVENTORY, false))

static func does_placement_require_inventory(mode_id: StringName) -> bool:
	return bool(get_setting(mode_id, SETTING_PLACEMENT_REQUIRES_INVENTORY, false))

static func is_drop_pickup_enabled(mode_id: StringName) -> bool:
	return bool(get_setting(mode_id, SETTING_DROP_PICKUP_ENABLED, true))

static func is_instant_break_enabled(mode_id: StringName) -> bool:
	return bool(get_setting(mode_id, SETTING_INSTANT_BREAK_ENABLED, false))

static func is_health_enabled(mode_id: StringName) -> bool:
	return bool(get_setting(mode_id, SETTING_HEALTH_ENABLED, false))

static func is_hunger_enabled(mode_id: StringName) -> bool:
	return bool(get_setting(mode_id, SETTING_HUNGER_ENABLED, false))

static func is_damage_enabled(mode_id: StringName) -> bool:
	return bool(get_setting(mode_id, SETTING_DAMAGE_ENABLED, false))

static func _resolve_mode(mode_id: StringName) -> Dictionary:
	var normalized_mode := normalize_mode_id(mode_id)
	return _GAME_MODES.get(normalized_mode, _GAME_MODES[DEFAULT_MODE])

static func _build_game_modes() -> Dictionary:
	return {
		CREATIVE: {
			"id": CREATIVE,
			"display": {
				"name": "Creative",
				"short_name": "Creative",
			},
			"meta": {
				"debug_name": "CREATIVE",
				"tags": PackedStringArray(["sandbox", "building"]),
			},
			"settings": {
				SETTING_BLOCK_DROPS: false,
				SETTING_PLACEMENT_CONSUMES_INVENTORY: false,
				SETTING_PLACEMENT_REQUIRES_INVENTORY: false,
				SETTING_DROP_PICKUP_ENABLED: false,
				SETTING_INSTANT_BREAK_ENABLED: true,
				SETTING_HEALTH_ENABLED: false,
				SETTING_HUNGER_ENABLED: false,
				SETTING_DAMAGE_ENABLED: false,
			},
		},
		SURVIVAL: {
			"id": SURVIVAL,
			"display": {
				"name": "Survival",
				"short_name": "Survival",
			},
			"meta": {
				"debug_name": "SURVIVAL",
				"tags": PackedStringArray(["progression", "resource_management"]),
			},
			"settings": {
				SETTING_BLOCK_DROPS: true,
				SETTING_PLACEMENT_CONSUMES_INVENTORY: true,
				SETTING_PLACEMENT_REQUIRES_INVENTORY: true,
				SETTING_DROP_PICKUP_ENABLED: true,
				SETTING_INSTANT_BREAK_ENABLED: false,
				SETTING_HEALTH_ENABLED: true,
				SETTING_HUNGER_ENABLED: true,
				SETTING_DAMAGE_ENABLED: true,
			},
		},
	}
