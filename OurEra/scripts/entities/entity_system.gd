class_name EntitySystem
extends Node3D

signal entity_registered(entity: EntityBase)
signal entity_unregistered(entity: EntityBase)
signal entity_despawned(entity_id: String, reason: String)

@export var world_path: NodePath

var _world: Node
var _entities_by_instance_id: Dictionary = {}
var _entities_by_id: Dictionary = {}
var _despawn_queue: Array = []
var _entity_scene_registry: Dictionary = {}
var _next_runtime_id := 1

func _ready() -> void:
	add_to_group("entity_system")
	_world = get_node_or_null(world_path)

func _physics_process(delta: float) -> void:
	_resolve_world()

	var entities: Array = _entities_by_instance_id.values()
	entities.sort_custom(func(a, b) -> bool:
		return a.get_simulation_priority() < b.get_simulation_priority()
	)

	for entity_any in entities:
		var entity: EntityBase = entity_any
		if not is_instance_valid(entity):
			continue
		entity.entity_physics_tick(delta)

	_flush_despawn_queue()

func get_world() -> Node:
	return _resolve_world()

func get_entity(entity_id: String) -> EntityBase:
	var entity_any: Variant = _entities_by_id.get(entity_id, null)
	if entity_any is EntityBase:
		return entity_any
	return null

func get_entities_in_category(category: String) -> Array:
	var entities: Array = []
	for entity_any in _entities_by_instance_id.values():
		var entity: EntityBase = entity_any
		if not is_instance_valid(entity):
			continue
		if entity.entity_category != category:
			continue
		entities.append(entity)

	entities.sort_custom(func(a, b) -> bool:
		if a.get_simulation_priority() == b.get_simulation_priority():
			return a.get_entity_id() < b.get_entity_id()
		return a.get_simulation_priority() < b.get_simulation_priority()
	)
	return entities

func get_primary_entity(category: String, preferred_id: String = "") -> EntityBase:
	var normalized_preferred_id := preferred_id.strip_edges()
	if not normalized_preferred_id.is_empty():
		var preferred := get_entity(normalized_preferred_id)
		if preferred != null and preferred.entity_category == category:
			return preferred

	var matches := get_entities_in_category(category)
	if matches.is_empty():
		return null
	return matches[0]

func register_entity(entity: EntityBase) -> void:
	if entity == null:
		return

	var instance_id: int = entity.get_instance_id()
	if _entities_by_instance_id.has(instance_id):
		return

	var requested_id: String = entity.get_entity_id()
	if requested_id.is_empty():
		requested_id = _allocate_runtime_entity_id(entity)
	elif _entities_by_id.has(requested_id) and _entities_by_id[requested_id] != entity:
		requested_id = _allocate_runtime_entity_id(entity, requested_id)

	entity.bind_entity_system(self)
	entity.bind_world(get_world())
	entity.set_entity_id(requested_id)

	_entities_by_instance_id[instance_id] = entity
	_entities_by_id[requested_id] = entity

	entity.on_registered()
	entity_registered.emit(entity)

func unregister_entity(entity: EntityBase) -> void:
	if entity == null:
		return

	var instance_id: int = entity.get_instance_id()
	if not _entities_by_instance_id.has(instance_id):
		return

	_entities_by_instance_id.erase(instance_id)

	var current_id: String = entity.get_entity_id()
	if _entities_by_id.get(current_id, null) == entity:
		_entities_by_id.erase(current_id)

	entity.on_unregistered()
	entity_unregistered.emit(entity)

func request_despawn(entity: EntityBase, reason: String = "") -> void:
	if entity == null:
		return
	_despawn_queue.append({
		"entity": entity,
		"reason": reason,
	})

func register_entity_scene(archetype: String, scene: PackedScene) -> void:
	if archetype.strip_edges().is_empty() or scene == null:
		return
	_entity_scene_registry[archetype] = scene

func spawn_entity(
	scene: PackedScene,
	initial_state: Dictionary = {},
	parent_override: Node = null
) -> EntityBase:
	if scene == null:
		return null

	var instance: Node = scene.instantiate()
	if not (instance is EntityBase):
		push_warning("Spawned scene does not inherit EntityBase")
		if instance != null:
			instance.queue_free()
		return null

	var parent_node: Node = self if parent_override == null else parent_override
	var entity: EntityBase = instance
	parent_node.add_child(entity)
	if not initial_state.is_empty():
		entity.apply_persisted_state(initial_state)
	return entity

func spawn_registered_entity(
	archetype: String,
	initial_state: Dictionary = {},
	parent_override: Node = null
) -> EntityBase:
	var scene_any: Variant = _entity_scene_registry.get(archetype, null)
	if not (scene_any is PackedScene):
		return null
	return spawn_entity(scene_any, initial_state, parent_override)

func collect_persisted_entities(excluded_entity_ids: PackedStringArray = PackedStringArray()) -> Array:
	var excluded_lookup: Dictionary = {}
	for excluded_id in excluded_entity_ids:
		excluded_lookup[String(excluded_id)] = true

	var snapshots: Array = []
	for entity_any in _entities_by_instance_id.values():
		var entity: EntityBase = entity_any
		if not is_instance_valid(entity):
			continue
		if not entity.can_persist():
			continue
		if excluded_lookup.has(entity.get_entity_id()):
			continue
		snapshots.append(entity.get_entity_snapshot())

	return snapshots

func restore_entities(entity_states: Array) -> void:
	for state_any in entity_states:
		if not (state_any is Dictionary):
			continue

		var state: Dictionary = state_any
		var entity_id := String(state.get("entity_id", "")).strip_edges()
		if not entity_id.is_empty() and get_entity(entity_id) != null:
			continue

		var archetype := String(state.get("entity_archetype", "")).strip_edges()
		if archetype.is_empty():
			continue

		var restored := spawn_registered_entity(archetype, state)
		if restored == null:
			push_warning("No registered entity scene for archetype '%s'" % archetype)

func _resolve_world() -> Node:
	if _world != null and is_instance_valid(_world):
		return _world
	_world = get_node_or_null(world_path)
	return _world

func _allocate_runtime_entity_id(entity: EntityBase, preferred_prefix: String = "") -> String:
	var prefix := preferred_prefix.strip_edges()
	if prefix.is_empty():
		prefix = entity.entity_archetype.strip_edges()
	if prefix.is_empty():
		prefix = entity.entity_category.strip_edges()
	if prefix.is_empty():
		prefix = "entity"

	var candidate := "%s_%d" % [prefix, _next_runtime_id]
	while _entities_by_id.has(candidate):
		_next_runtime_id += 1
		candidate = "%s_%d" % [prefix, _next_runtime_id]

	_next_runtime_id += 1
	return candidate

func _flush_despawn_queue() -> void:
	if _despawn_queue.is_empty():
		return

	var pending := _despawn_queue.duplicate(true)
	_despawn_queue.clear()

	for request_any in pending:
		if not (request_any is Dictionary):
			continue

		var request: Dictionary = request_any
		var entity_any: Variant = request.get("entity", null)
		if not (entity_any is EntityBase):
			continue

		var entity: EntityBase = entity_any
		if not is_instance_valid(entity):
			continue

		var entity_id: String = entity.get_entity_id()
		var reason := String(request.get("reason", ""))
		unregister_entity(entity)
		entity.queue_free()
		entity_despawned.emit(entity_id, reason)