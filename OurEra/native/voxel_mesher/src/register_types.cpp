#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "greedy_mesher_native.h"

using namespace godot;

static void ourera_mesher_initialize(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	ClassDB::register_class<OurEraGreedyMesherNative>();
}

static void ourera_mesher_uninitialize(ModuleInitializationLevel level) {
	if (level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT ourera_mesher_library_init(
	GDExtensionInterfaceGetProcAddress get_proc_address,
	GDExtensionClassLibraryPtr library,
	GDExtensionInitialization *initialization
) {
	GDExtensionBinding::InitObject init_obj(get_proc_address, library, initialization);
	init_obj.register_initializer(ourera_mesher_initialize);
	init_obj.register_terminator(ourera_mesher_uninitialize);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
