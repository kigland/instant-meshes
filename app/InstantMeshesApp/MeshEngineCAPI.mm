#include "MeshEngineCAPI.h"
#include "common.h"
#include "adjacency.h"
#include "bvh.h"
#include "dedge.h"
#include "extract.h"
#include "field.h"
#include "hierarchy.h"
#include "meshio.h"
#include "meshstats.h"
#include "normal.h"
#include "subdivide.h"
#include <map>
#include <set>
#include <string>
#include <memory>

struct MeshEngineHandle {
    bool meshLoaded = false;
    bool orientationComputed = false;
    bool positionComputed = false;
    bool meshExtracted = false;

    float creaseAngle = -1;
    float targetScale = -1;
    int rosy = 4, posy = 4;
    bool extrinsic = true;

    std::unique_ptr<MultiResolutionHierarchy> mRes;
    MatrixXu F;
    MatrixXf V, N;
    MatrixXf O_extracted, Nf_extracted, N_extracted;
    MatrixXu F_extracted;
    std::vector<std::vector<TaggedLink>> adj_extracted;

    MeshEngineHandle() : mRes(std::make_unique<MultiResolutionHierarchy>()) {}
};

extern "C" {

MeshEngineHandle *mesh_engine_create(void) {
    return new MeshEngineHandle();
}

void mesh_engine_destroy(MeshEngineHandle *e) {
    if (e) {
        if (e->mRes) e->mRes->free();
        delete e;
    }
}

MeshInfoRaw *mesh_engine_load(MeshEngineHandle *e, const char *path,
                               float creaseAngle, bool deterministic,
                               ProgressCallbackRaw progress) {
    if (!e) return nullptr;
    e->meshLoaded = false;
    e->orientationComputed = false;
    e->positionComputed = false;
    e->meshExtracted = false;
    if (e->mRes) e->mRes->free();
    e->mRes = std::make_unique<MultiResolutionHierarchy>();
    e->creaseAngle = creaseAngle;

    auto cb = [&](const std::string &stage, Float pct) {
        if (progress) progress(stage.c_str(), (float)pct);
    };

    try {
        load_mesh_or_pointcloud(std::string(path), e->F, e->V, e->N, cb);
    } catch (...) { return nullptr; }
    if (e->F.cols() == 0 && e->V.cols() == 0) return nullptr;

    MeshStats stats;
    try { stats = compute_mesh_stats(e->F, e->V, deterministic, cb); }
    catch (...) { return nullptr; }

    if (e->F.size() > 0) {
        Float maxLength = stats.mMaximumEdgeLength * 2;
        for (int it = 0; it < 5; ++it) {
            VectorXu V2E, E2E; VectorXb boundary, nonManifold;
            build_dedge(e->F, e->V, V2E, E2E, boundary, nonManifold, cb);
            if (stats.mMaximumEdgeLength > maxLength) {
                subdivide(e->F, e->V, V2E, E2E, boundary, nonManifold, maxLength, deterministic, cb);
                stats = compute_mesh_stats(e->F, e->V, deterministic, cb);
                maxLength = stats.mMaximumEdgeLength * 2;
            } else break;
        }
    }

    e->mRes->free();
    e->mRes->setF(std::move(MatrixXu(e->F)));
    e->mRes->setV(std::move(MatrixXf(e->V)));

    if (e->F.size() > 0) {
        VectorXu V2E, E2E; VectorXb boundary, nonManifold;
        build_dedge(e->F, e->V, V2E, E2E, boundary, nonManifold, cb);
        AdjacencyMatrix adj = generate_adjacency_matrix_uniform(e->F, V2E, E2E, nonManifold, cb);
        MatrixXf Ns(3, e->V.cols());
        if (creaseAngle >= 0) {
            std::map<uint32_t,uint32_t> creaseMap;
            generate_crease_normals(e->F, e->V, V2E, E2E, boundary, nonManifold,
                                     creaseAngle, Ns, creaseMap, cb);
        } else {
            generate_smooth_normals(e->F, e->V, V2E, E2E, nonManifold, Ns, cb);
        }
        e->N = Ns;
        VectorXf A(e->V.cols());
        compute_dual_vertex_areas(e->F, e->V, V2E, E2E, nonManifold, A, cb);
        e->mRes->setAdj(std::move(AdjacencyMatrix(adj)));
        e->mRes->setN(std::move(MatrixXf(e->N)));
        e->mRes->setA(std::move(VectorXf(A)));
    }

    if (e->targetScale > 0) e->mRes->setScale(e->targetScale);
    e->mRes->build(deterministic, cb);
    e->mRes->resetSolution();
    e->V = e->mRes->V(); e->N = e->mRes->N(); e->F = e->mRes->F();
    e->meshLoaded = true;

    MeshInfoRaw *info = new MeshInfoRaw();
    info->vertexCount = (uint32_t)e->V.cols();
    info->faceCount = (uint32_t)e->F.cols();
    info->minX = stats.mAABB.min.x();
    info->minY = stats.mAABB.min.y();
    info->minZ = stats.mAABB.min.z();
    info->maxX = stats.mAABB.max.x();
    info->maxY = stats.mAABB.max.y();
    info->maxZ = stats.mAABB.max.z();
    return info;
}

void mesh_engine_set_scale(MeshEngineHandle *e, float s)  { e->targetScale = s; if (e->mRes) e->mRes->setScale(s); }
void mesh_engine_set_rosy(MeshEngineHandle *e, int r)     { e->rosy = r; }
void mesh_engine_set_posy(MeshEngineHandle *e, int p)     { e->posy = p; }
void mesh_engine_set_extrinsic(MeshEngineHandle *e, bool x) { e->extrinsic = x; }

static void propQ(MultiResolutionHierarchy &mr, int fl) {
    for (int i = fl; i >= 0; --i) {
        const MatrixXf &s = mr.Q(i+1);
        const MatrixXu &tu = mr.toUpper(i);
        MatrixXf &d = mr.Q(i);
        const MatrixXf &N = mr.N(i);
        for (uint32_t j = 0; j < (uint32_t)s.cols(); ++j)
            for (int k = 0; k < 2; ++k) {
                uint32_t t = tu(k,j);
                if (t == (uint32_t)-1) continue;
                Vector3f q = s.col(j), n = N.col(t);
                d.col(t) = q - n*n.dot(q);
            }
    }
}

static void propO(MultiResolutionHierarchy &mr, int fl) {
    for (int i = fl; i >= 0; --i) {
        const MatrixXf &s = mr.O(i+1);
        MatrixXf &d = mr.O(i);
        const MatrixXf &N = mr.N(i), &V = mr.V(i);
        const MatrixXu &tu = mr.toUpper(i);
        for (uint32_t j = 0; j < (uint32_t)s.cols(); ++j)
            for (int k = 0; k < 2; ++k) {
                uint32_t t = tu(k,j);
                if (t == (uint32_t)-1) continue;
                Vector3f o = s.col(j), n = N.col(t), v = V.col(t);
                o -= n*n.dot(o-v);
                d.col(t) = o;
            }
    }
}

bool mesh_engine_compute_orientation(MeshEngineHandle *e, ProgressCallbackRaw progress) {
    if (!e || !e->meshLoaded) return false;
    try {
        int nL = e->mRes->levels();
        for (int l = nL-1; l >= 0; --l) {
            if (progress) progress("Solving orientations", 1.f-(float)l/(float)nL);
            for (int it=0;it<6;++it) optimize_orientations(*e->mRes,l,e->extrinsic,e->rosy,[](uint32_t){});
            if (l>0) propQ(*e->mRes,l-1);
        }
        e->orientationComputed = true;
        return true;
    } catch(...) { return false; }
}

bool mesh_engine_compute_position(MeshEngineHandle *e, ProgressCallbackRaw progress) {
    if (!e || !e->meshLoaded || !e->orientationComputed) return false;
    try {
        int nL = e->mRes->levels();
        for (int l = nL-1; l >= 0; --l) {
            if (progress) progress("Solving positions", 1.f-(float)l/(float)nL);
            for (int it=0;it<6;++it) optimize_positions(*e->mRes,l,e->extrinsic,e->posy,[](uint32_t){});
            if (l>0) propO(*e->mRes,l-1);
        }
        e->positionComputed = true;
        return true;
    } catch(...) { return false; }
}

bool mesh_engine_extract(MeshEngineHandle *e, ProgressCallbackRaw progress) {
    if (!e || !e->meshLoaded || !e->orientationComputed || !e->positionComputed) return false;
    try {
        if (progress) progress("Extracting graph", 0.25f);
        e->adj_extracted.clear();
        e->O_extracted.resize(3, e->mRes->size());
        e->N_extracted.resize(3, e->mRes->size());
        std::set<uint32_t> ci, co;
        extract_graph(*e->mRes, e->extrinsic, e->rosy, e->posy, e->adj_extracted,
                      e->O_extracted, e->N_extracted, ci, co, true);
        if (progress) progress("Extracting faces", 0.6f);
        extract_faces(e->adj_extracted, e->O_extracted, e->N_extracted,
                      e->Nf_extracted, e->F_extracted, e->posy, e->mRes->scale(), co, true, true);
        e->meshExtracted = true;
        if (progress) progress("Done", 1.f);
        return true;
    } catch(...) { return false; }
}

const char *mesh_engine_export(MeshEngineHandle *e, const char *path) {
    if (!e || !e->meshExtracted) return nullptr;
    try {
        write_mesh(std::string(path), e->F_extracted, e->O_extracted, MatrixXf(), e->Nf_extracted);
        return path;
    } catch(...) { return nullptr; }
}

const float *mesh_engine_get_positions(MeshEngineHandle *e, int *count) {
    if (!e || !e->meshLoaded) { *count = 0; return nullptr; }
    const MatrixXf &V = e->mRes->V(0);
    *count = (int)V.size();
    return V.data();
}

const float *mesh_engine_get_normals(MeshEngineHandle *e, int *count) {
    if (!e || !e->meshLoaded) { *count = 0; return nullptr; }
    const MatrixXf &N = e->mRes->N(0);
    *count = (int)N.size();
    return N.data();
}

const uint32_t *mesh_engine_get_faces(MeshEngineHandle *e, int *count) {
    if (!e || !e->meshLoaded) { *count = 0; return nullptr; }
    const MatrixXu &F = e->mRes->F();
    *count = (int)F.size();
    return F.data();
}

bool mesh_engine_has_mesh(MeshEngineHandle *e)        { return e && e->meshLoaded; }
bool mesh_engine_has_orientation(MeshEngineHandle *e)   { return e && e->orientationComputed; }
bool mesh_engine_has_position(MeshEngineHandle *e)      { return e && e->positionComputed; }
bool mesh_engine_has_extracted(MeshEngineHandle *e)     { return e && e->meshExtracted; }
uint32_t mesh_engine_extracted_faces(MeshEngineHandle *e) { return e && e->meshExtracted ? (uint32_t)e->F_extracted.cols() : 0; }

} // extern "C"
