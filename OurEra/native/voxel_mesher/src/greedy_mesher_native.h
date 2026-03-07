#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

class OurEraGreedyMesherNative : public RefCounted {
	GDCLASS(OurEraGreedyMesherNative, RefCounted);

protected:
	static void _bind_methods();

public:
	Dictionary build(const Dictionary &context) const;
};

} // namespace godot
