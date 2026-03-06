class_name RecipeDefs
extends RefCounted

const TYPE_CRAFTING := &"crafting"
const PATTERN_SHAPED := &"shaped"
const PATTERN_SHAPELESS := &"shapeless"

const _RECIPES_BY_ID := {}
const _RECIPES_BY_OUTPUT := {}

static func has_recipe(recipe_id: StringName) -> bool:
	return _RECIPES_BY_ID.has(recipe_id)

static func get_recipe(recipe_id: StringName) -> Dictionary:
	if not _RECIPES_BY_ID.has(recipe_id):
		return {}
	return _RECIPES_BY_ID[recipe_id].duplicate(true)

static func get_recipes_for_output(item_id: int) -> Array[Dictionary]:
	var recipes: Array[Dictionary] = []
	var recipe_ids: Array = _RECIPES_BY_OUTPUT.get(item_id, [])

	for recipe_id in recipe_ids:
		recipes.append(get_recipe(recipe_id))

	return recipes

static func get_all_recipe_ids() -> Array[StringName]:
	var recipe_ids: Array[StringName] = []

	for recipe_id in _RECIPES_BY_ID.keys():
		recipe_ids.append(recipe_id)

	return recipe_ids
