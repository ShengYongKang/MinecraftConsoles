#include "greedy_mesher_native.h"

#include <array>
#include <vector>

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>

using namespace godot;

namespace {
constexpr int FACE_SIGNATURE_MULTIPLIER = 8;
const std::array<Vector3, 6> FACE_NORMALS = {
    Vector3(1, 0, 0),
    Vector3(-1, 0, 0),
    Vector3(0, 1, 0),
    Vector3(0, -1, 0),
    Vector3(0, 0, 1),
    Vector3(0, 0, -1),
};
constexpr std::array<int, 3> POSITIVE_FACE_FOR_AXIS = {0, 2, 4};
constexpr std::array<int, 3> NEGATIVE_FACE_FOR_AXIS = {1, 3, 5};
constexpr std::array<int, 6> QUAD_TRIANGLE_INDICES = {0, 2, 1, 0, 3, 2};

struct BuildBuffers {
    PackedVector3Array vertices;
    PackedVector3Array normals;
    PackedVector2Array uvs;
    PackedVector2Array uv2s;
    PackedColorArray colors;
    PackedInt32Array indices;
    PackedVector3Array collision_faces;
    int quad_count = 0;
};

inline int axis_size(const Vector3i &dims, int axis) {
    switch (axis) {
        case 0:
            return dims.x;
        case 1:
            return dims.y;
        default:
            return dims.z;
    }
}

inline Vector3 axis_vector(int axis, int length) {
    switch (axis) {
        case 0:
            return Vector3(length, 0, 0);
        case 1:
            return Vector3(0, length, 0);
        default:
            return Vector3(0, 0, length);
    }
}

inline Vector3i with_axis(Vector3i value, int axis, int axis_value) {
    switch (axis) {
        case 0:
            value.x = axis_value;
            break;
        case 1:
            value.y = axis_value;
            break;
        default:
            value.z = axis_value;
            break;
    }
    return value;
}

inline bool is_positive_face(int face_index) {
    return (face_index % 2) == 0;
}

inline int encode_face_signature(int block_id, int face_index) {
    return 1 + block_id * FACE_SIGNATURE_MULTIPLIER + face_index;
}

inline int decode_block_id(int signature) {
    return (signature - 1) / FACE_SIGNATURE_MULTIPLIER;
}

inline int decode_face_index(int signature) {
    return (signature - 1) % FACE_SIGNATURE_MULTIPLIER;
}

int sample_lookup(const PackedInt32Array &lookup, int block_id, int face_index, int component) {
    const int base = (block_id * 12) + face_index * 2;
    const int index = base + component;
    if (index < 0 || index >= lookup.size()) {
        return 0;
    }
    return lookup[index];
}

bool sample_solid(const PackedByteArray &solid_lookup, int block_id) {
    if (block_id < 0 || block_id >= solid_lookup.size()) {
        return false;
    }
    return solid_lookup[block_id] != 0;
}

int sample_neighbor_column(const PackedInt32Array &column, int lateral_index, int y, int stride) {
    const int index = lateral_index + y * stride;
    if (index < 0 || index >= column.size()) {
        return 0;
    }
    return column[index];
}

int sample_block(
    const Vector3i &local_pos,
    const Vector3i &dims,
    const PackedInt32Array &chunk_blocks,
    const PackedInt32Array &neg_x,
    const PackedInt32Array &pos_x,
    const PackedInt32Array &neg_z,
    const PackedInt32Array &pos_z
) {
    if (local_pos.y < 0 || local_pos.y >= dims.y) {
        return 0;
    }
    if (local_pos.x >= 0 && local_pos.x < dims.x && local_pos.z >= 0 && local_pos.z < dims.z) {
        const int index = local_pos.x + local_pos.z * dims.x + local_pos.y * dims.x * dims.z;
        return chunk_blocks[index];
    }
    if (local_pos.x == -1 && local_pos.z >= 0 && local_pos.z < dims.z) {
        return sample_neighbor_column(neg_x, local_pos.z, local_pos.y, dims.z);
    }
    if (local_pos.x == dims.x && local_pos.z >= 0 && local_pos.z < dims.z) {
        return sample_neighbor_column(pos_x, local_pos.z, local_pos.y, dims.z);
    }
    if (local_pos.z == -1 && local_pos.x >= 0 && local_pos.x < dims.x) {
        return sample_neighbor_column(neg_z, local_pos.x, local_pos.y, dims.x);
    }
    if (local_pos.z == dims.z && local_pos.x >= 0 && local_pos.x < dims.x) {
        return sample_neighbor_column(pos_z, local_pos.x, local_pos.y, dims.x);
    }
    return 0;
}

void append_quad(
    BuildBuffers &buffers,
    const Vector3 &base_pos,
    const Vector3 &du,
    const Vector3 &dv,
    int block_id,
    int face_index,
    const PackedInt32Array &tile_lookup,
    bool collect_collision_faces,
    bool include_vertex_colors
) {
    const Vector3 normal = FACE_NORMALS[face_index];
    const float repeat_u = du.length();
    const float repeat_v = dv.length();
    const Vector2 tile_uv(
        static_cast<float>(sample_lookup(tile_lookup, block_id, face_index, 0)),
        static_cast<float>(sample_lookup(tile_lookup, block_id, face_index, 1))
    );

    std::array<Vector3, 4> vertices;
    std::array<Vector2, 4> repeat_uvs;
    if (is_positive_face(face_index)) {
        vertices = {base_pos, base_pos + du, base_pos + du + dv, base_pos + dv};
        repeat_uvs = {
            Vector2(0.0, 0.0),
            Vector2(repeat_u, 0.0),
            Vector2(repeat_u, repeat_v),
            Vector2(0.0, repeat_v),
        };
    } else {
        vertices = {base_pos, base_pos + dv, base_pos + du + dv, base_pos + du};
        repeat_uvs = {
            Vector2(0.0, 0.0),
            Vector2(0.0, repeat_v),
            Vector2(repeat_u, repeat_v),
            Vector2(repeat_u, 0.0),
        };
    }

    for (int idx : QUAD_TRIANGLE_INDICES) {
        buffers.vertices.push_back(vertices[idx]);
        buffers.normals.push_back(normal);
        buffers.uvs.push_back(repeat_uvs[idx]);
        buffers.uv2s.push_back(tile_uv);
        if (include_vertex_colors) {
            buffers.colors.push_back(Color(1.0, 1.0, 1.0, 1.0));
        }
        if (collect_collision_faces) {
            buffers.collision_faces.push_back(vertices[idx]);
        }
    }
    buffers.quad_count += 1;
}

} // namespace

void OurEraGreedyMesherNative::_bind_methods() {
    ClassDB::bind_method(D_METHOD("build", "context"), &OurEraGreedyMesherNative::build);
}

Dictionary OurEraGreedyMesherNative::build(const Dictionary &context) const {
    Dictionary result;
    const Vector3i dims = context.get("dimensions", Vector3i(1, 1, 1));
    const PackedInt32Array chunk_blocks = context.get("chunk_blocks", PackedInt32Array());
    const Dictionary neighbor_columns = context.get("neighbor_columns", Dictionary());
    const PackedByteArray solid_lookup = context.get("solid_lookup", PackedByteArray());
    const PackedInt32Array tile_lookup = context.get("tile_lookup", PackedInt32Array());
    const bool collect_collision_faces = static_cast<bool>(context.get("collect_collision_faces", false));
    const bool include_vertex_colors = static_cast<bool>(context.get("include_vertex_colors", false));

    if (chunk_blocks.size() != dims.x * dims.y * dims.z) {
        result["arrays"] = Array();
        result["stats"] = Dictionary();
        result["collision_faces"] = PackedVector3Array();
        return result;
    }

    const PackedInt32Array neg_x = neighbor_columns.get("neg_x", PackedInt32Array());
    const PackedInt32Array pos_x = neighbor_columns.get("pos_x", PackedInt32Array());
    const PackedInt32Array neg_z = neighbor_columns.get("neg_z", PackedInt32Array());
    const PackedInt32Array pos_z = neighbor_columns.get("pos_z", PackedInt32Array());

    BuildBuffers buffers;
    std::vector<int> mask;

    for (int axis = 0; axis < 3; ++axis) {
        const int u = (axis + 1) % 3;
        const int v = (axis + 2) % 3;
        const int axis_sz = axis_size(dims, axis);
        const int u_sz = axis_size(dims, u);
        const int v_sz = axis_size(dims, v);
        mask.assign(static_cast<size_t>(u_sz * v_sz), 0);
        const Vector3i step = with_axis(Vector3i(), axis, 1);

        for (int axis_pos = -1; axis_pos < axis_sz; ++axis_pos) {
            int mask_index = 0;
            for (int vv = 0; vv < v_sz; ++vv) {
                for (int uu = 0; uu < u_sz; ++uu) {
                    Vector3i cursor = Vector3i();
                    cursor = with_axis(cursor, axis, axis_pos);
                    cursor = with_axis(cursor, u, uu);
                    cursor = with_axis(cursor, v, vv);

                    const int a = sample_block(cursor, dims, chunk_blocks, neg_x, pos_x, neg_z, pos_z);
                    const int b = sample_block(cursor + step, dims, chunk_blocks, neg_x, pos_x, neg_z, pos_z);
                    const bool a_solid = sample_solid(solid_lookup, a);
                    const bool b_solid = sample_solid(solid_lookup, b);

                    if (a_solid == b_solid) {
                        mask[mask_index] = 0;
                    } else if (a_solid) {
                        mask[mask_index] = encode_face_signature(a, POSITIVE_FACE_FOR_AXIS[axis]);
                    } else {
                        mask[mask_index] = encode_face_signature(b, NEGATIVE_FACE_FOR_AXIS[axis]);
                    }
                    mask_index += 1;
                }
            }

            for (int vv = 0; vv < v_sz; ++vv) {
                int uu = 0;
                while (uu < u_sz) {
                    const int index = uu + vv * u_sz;
                    const int signature = mask[index];
                    if (signature == 0) {
                        uu += 1;
                        continue;
                    }

                    int quad_width = 1;
                    while (uu + quad_width < u_sz && mask[index + quad_width] == signature) {
                        quad_width += 1;
                    }

                    int quad_height = 1;
                    bool keep_expanding = true;
                    while (vv + quad_height < v_sz && keep_expanding) {
                        for (int offset = 0; offset < quad_width; ++offset) {
                            if (mask[index + offset + quad_height * u_sz] != signature) {
                                keep_expanding = false;
                                break;
                            }
                        }
                        if (keep_expanding) {
                            quad_height += 1;
                        }
                    }

                    Vector3i base = Vector3i();
                    base = with_axis(base, axis, axis_pos + 1);
                    base = with_axis(base, u, uu);
                    base = with_axis(base, v, vv);
                    append_quad(
                        buffers,
                        Vector3(static_cast<float>(base.x), static_cast<float>(base.y), static_cast<float>(base.z)),
                        axis_vector(u, quad_width),
                        axis_vector(v, quad_height),
                        decode_block_id(signature),
                        decode_face_index(signature),
                        tile_lookup,
                        collect_collision_faces,
                        include_vertex_colors
                    );

                    for (int clear_v = 0; clear_v < quad_height; ++clear_v) {
                        for (int clear_u = 0; clear_u < quad_width; ++clear_u) {
                            mask[index + clear_u + clear_v * u_sz] = 0;
                        }
                    }
                    uu += quad_width;
                }
            }
        }
    }

    Array arrays;
    arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX] = buffers.vertices;
    arrays[Mesh::ARRAY_NORMAL] = buffers.normals;
    arrays[Mesh::ARRAY_TEX_UV] = buffers.uvs;
    arrays[Mesh::ARRAY_TEX_UV2] = buffers.uv2s;
    if (include_vertex_colors && !buffers.colors.is_empty()) {
        arrays[Mesh::ARRAY_COLOR] = buffers.colors;
    }
    if (!buffers.indices.is_empty()) {
        arrays[Mesh::ARRAY_INDEX] = buffers.indices;
    }

    Dictionary stats;
    stats["quad_count"] = buffers.quad_count;
    stats["triangle_count"] = buffers.quad_count * 2;
    stats["vertex_count"] = buffers.vertices.size();
    stats["mesh_geometry_usec"] = 0;
    stats["mesh_commit_usec"] = 0;

    result["arrays"] = arrays;
    result["stats"] = stats;
    result["collision_faces"] = buffers.collision_faces;
    return result;
}









