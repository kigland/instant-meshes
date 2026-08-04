#ifndef MeshEngineCAPI_h
#define MeshEngineCAPI_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct MeshEngineHandle MeshEngineHandle;
typedef struct MeshInfoRaw {
    uint32_t vertexCount;
    uint32_t faceCount;
    float minX, minY, minZ;
    float maxX, maxY, maxZ;
} MeshInfoRaw;

typedef void (*ProgressCallbackRaw)(const char *stage, float progress);

// Engine lifecycle
MeshEngineHandle *mesh_engine_create(void);
void mesh_engine_destroy(MeshEngineHandle *e);

// Loading
MeshInfoRaw *mesh_engine_load(MeshEngineHandle *e, const char *path,
                               float creaseAngle, bool deterministic,
                               ProgressCallbackRaw progress);

// Settings
void mesh_engine_set_scale(MeshEngineHandle *e, float scale);
void mesh_engine_set_rosy(MeshEngineHandle *e, int rosy);
void mesh_engine_set_posy(MeshEngineHandle *e, int posy);
void mesh_engine_set_extrinsic(MeshEngineHandle *e, bool ext);

// Computation
bool mesh_engine_compute_orientation(MeshEngineHandle *e, ProgressCallbackRaw progress);
bool mesh_engine_compute_position(MeshEngineHandle *e, ProgressCallbackRaw progress);
bool mesh_engine_extract(MeshEngineHandle *e, ProgressCallbackRaw progress);

// Export
const char *mesh_engine_export(MeshEngineHandle *e, const char *path);

// Data access for rendering
const float *mesh_engine_get_positions(MeshEngineHandle *e, int *count);
const float *mesh_engine_get_normals(MeshEngineHandle *e, int *count);
const uint32_t *mesh_engine_get_faces(MeshEngineHandle *e, int *count); // input faces

// Status
bool mesh_engine_has_mesh(MeshEngineHandle *e);
bool mesh_engine_has_orientation(MeshEngineHandle *e);
bool mesh_engine_has_position(MeshEngineHandle *e);
bool mesh_engine_has_extracted(MeshEngineHandle *e);
uint32_t mesh_engine_extracted_faces(MeshEngineHandle *e);

#ifdef __cplusplus
}
#endif

#endif /* MeshEngineCAPI_h */
