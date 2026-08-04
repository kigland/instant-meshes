#import "MeshEngineBridge.h"
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

@interface MeshEngine () {
    BOOL _meshLoaded;
    BOOL _orientationComputed;
    BOOL _positionComputed;
    BOOL _meshExtracted;

    Float _creaseAngle;
    Float _targetScale;
    int32_t _faceCount;
    int32_t _vertexCount;
    int _rosy;
    int _posy;
    BOOL _extrinsic;

    std::unique_ptr<MultiResolutionHierarchy> _mRes;

    // Preprocessed data
    MatrixXu _F;
    MatrixXf _V;
    MatrixXf _N;

    // Extracted mesh
    MatrixXf _O_extracted;
    MatrixXf _Nf_extracted;
    MatrixXf _N_extracted;
    MatrixXu _F_extracted;
    std::vector<std::vector<TaggedLink>> _adj_extracted;
}
@end

@implementation MeshEngine

- (instancetype)init {
    self = [super init];
    if (self) {
        _meshLoaded = NO;
        _orientationComputed = NO;
        _positionComputed = NO;
        _meshExtracted = NO;
        _creaseAngle = -1;
        _targetScale = -1;
        _faceCount = -1;
        _vertexCount = -1;
        _rosy = 4;
        _posy = 4;
        _extrinsic = YES;
        _mRes = std::make_unique<MultiResolutionHierarchy>();
    }
    return self;
}

- (void)dealloc {
    if (_mRes) _mRes->free();
    [super dealloc];
}

- (void)resetState {
    _meshLoaded = NO;
    _orientationComputed = NO;
    _positionComputed = NO;
    _meshExtracted = NO;
    if (_mRes) _mRes->free();
    _mRes = std::make_unique<MultiResolutionHierarchy>();
}

- (nullable MeshInfo *)loadMesh:(NSString *)path
                    creaseAngle:(float)creaseAngle
                  deterministic:(BOOL)deterministic
                       progress:(nullable ProgressBlock)progress {
    [self resetState];
    _creaseAngle = creaseAngle;

    std::string filename = [path UTF8String];
    auto cb = [&](const std::string &stage, Float pct) {
        if (progress) progress([NSString stringWithUTF8String:stage.c_str()], (float)pct);
    };

    // Load
    try {
        load_mesh_or_pointcloud(filename, _F, _V, _N, cb);
    } catch (const std::exception &e) {
        NSLog(@"Failed to load mesh: %s", e.what());
        return nil;
    }
    if (_F.cols() == 0 && _V.cols() == 0) return nil;

    // Stats
    MeshStats stats;
    try {
        stats = compute_mesh_stats(_F, _V, deterministic, cb);
    } catch (const std::exception &e) {
        NSLog(@"Stats failed: %s", e.what());
        return nil;
    }

    // Subdivide coarse meshes
    if (_F.size() > 0) {
        Float maxLength = stats.mMaximumEdgeLength * 2;
        for (int iter = 0; iter < 5; ++iter) {
            VectorXu V2E, E2E;
            VectorXb boundary, nonManifold;
            build_dedge(_F, _V, V2E, E2E, boundary, nonManifold, cb);
            if (stats.mMaximumEdgeLength > maxLength) {
                subdivide(_F, _V, V2E, E2E, boundary, nonManifold, maxLength, deterministic, cb);
                stats = compute_mesh_stats(_F, _V, deterministic, cb);
                maxLength = stats.mMaximumEdgeLength * 2;
            } else {
                break;
            }
        }
    }

    _mRes->free();
    _mRes->setF(std::move(MatrixXu(_F)));
    _mRes->setV(std::move(MatrixXf(_V)));

    // Adjacency + normals + areas
    if (_F.size() > 0) {
        VectorXu V2E, E2E;
        VectorXb boundary, nonManifold;
        build_dedge(_F, _V, V2E, E2E, boundary, nonManifold, cb);

        AdjacencyMatrix adj = generate_adjacency_matrix_uniform(_F, V2E, E2E, nonManifold, cb);

        MatrixXf N_smooth(3, _V.cols());
        if (creaseAngle >= 0) {
            std::map<uint32_t, uint32_t> creaseMap;
            generate_crease_normals(_F, _V, V2E, E2E, boundary, nonManifold,
                                     creaseAngle, N_smooth, creaseMap, cb);
        } else {
            generate_smooth_normals(_F, _V, V2E, E2E, nonManifold, N_smooth, cb);
        }
        _N = N_smooth;

        VectorXf A(_V.cols());
        compute_dual_vertex_areas(_F, _V, V2E, E2E, nonManifold, A, cb);

        _mRes->setAdj(std::move(AdjacencyMatrix(adj)));
        _mRes->setN(std::move(MatrixXf(_N)));
        _mRes->setA(std::move(VectorXf(A)));
    } else {
        // Point cloud mode
        AABB aabb(stats.mAABB);
        BVH bvh(&_F, &_V, &_N, aabb);
        bvh.build(cb);

        AdjacencyMatrix adj = generate_adjacency_matrix_pointcloud(
            _V, _N, &bvh, stats, 10, deterministic, cb);
        VectorXf A = VectorXf::Constant(_V.cols(), 1.0f);

        _mRes->setAdj(std::move(AdjacencyMatrix(adj)));
        _mRes->setN(std::move(MatrixXf(_N)));
        _mRes->setA(std::move(VectorXf(A)));
    }

    // Density target
    if (_targetScale > 0) {
        _mRes->setScale(_targetScale);
    } else if (_faceCount > 0) {
        _mRes->setScale(std::sqrt((Float)_mRes->size() / (Float)_faceCount));
    } else if (_vertexCount > 0) {
        _mRes->setScale(std::sqrt((Float)_mRes->size() / (Float)_vertexCount));
    }

    _mRes->build(deterministic, cb);
    _mRes->resetSolution();

    // Save references for GL rendering
    _V = _mRes->V();
    _N = _mRes->N();
    _F = _mRes->F();

    _meshLoaded = YES;

    MeshInfo *info = [[MeshInfo alloc] init];
    info.vertexCount = (uint32_t)_V.cols();
    info.faceCount = (uint32_t)_F.cols();
    info.minX = stats.mAABB.min.x();
    info.minY = stats.mAABB.min.y();
    info.minZ = stats.mAABB.min.z();
    info.maxX = stats.mAABB.max.x();
    info.maxY = stats.mAABB.max.y();
    info.maxZ = stats.mAABB.max.z();
    return info;
}

#pragma mark - Settings

- (void)setScale:(float)s        { _targetScale = s; if (_mRes) _mRes->setScale(s); }
- (void)setFaceCount:(uint32_t)fc  { _faceCount = fc; _targetScale = -1; _vertexCount = -1; }
- (void)setVertexCount:(uint32_t)vc { _vertexCount = vc; _targetScale = -1; _faceCount = -1; }
- (void)setRoSy:(int)r           { _rosy = r; }
- (void)setPoSy:(int)p           { _posy = p; }
- (void)setExtrinsic:(BOOL)e     { _extrinsic = e; }

#pragma mark - Computation

static void propagateQtoFine(MultiResolutionHierarchy &mRes, int fromLevel) {
    for (int i = fromLevel; i >= 0; --i) {
        const MatrixXf &src = mRes.Q(i + 1);
        const MatrixXu &toUpper = mRes.toUpper(i);
        MatrixXf &dest = mRes.Q(i);
        const MatrixXf &N = mRes.N(i);
        for (uint32_t j = 0; j < (uint32_t)src.cols(); ++j) {
            for (int k = 0; k < 2; ++k) {
                uint32_t d = toUpper(k, j);
                if (d == INVALID) continue;
                Vector3f q = src.col(j), n = N.col(d);
                dest.col(d) = q - n * n.dot(q);
            }
        }
    }
}

static void propagateOtoFine(MultiResolutionHierarchy &mRes, int fromLevel) {
    for (int i = fromLevel; i >= 0; --i) {
        const MatrixXf &src = mRes.O(i + 1);
        MatrixXf &dest = mRes.O(i);
        const MatrixXf &N = mRes.N(i), &V = mRes.V(i);
        const MatrixXu &toUpper = mRes.toUpper(i);
        for (uint32_t j = 0; j < (uint32_t)src.cols(); ++j) {
            for (int k = 0; k < 2; ++k) {
                uint32_t d = toUpper(k, j);
                if (d == INVALID) continue;
                Vector3f o = src.col(j), n = N.col(d), v = V.col(d);
                o -= n * n.dot(o - v);
                dest.col(d) = o;
            }
        }
    }
}

- (BOOL)computeOrientationFieldWithProgress:(nullable ProgressBlock)progress {
    if (!_meshLoaded) return NO;
    @try {
        int nLevels = _mRes->levels();
        for (int lvl = nLevels - 1; lvl >= 0; --lvl) {
            if (progress) progress(@"Solving orientations", 1.f - (float)lvl/(float)nLevels);
            for (int it = 0; it < 6; ++it)
                optimize_orientations(*_mRes, lvl, _extrinsic, _rosy, [](uint32_t){});
            if (lvl > 0) propagateQtoFine(*_mRes, lvl - 1);
        }
        _orientationComputed = YES;
        return YES;
    } @catch (...) { return NO; }
}

- (BOOL)computePositionFieldWithProgress:(nullable ProgressBlock)progress {
    if (!_meshLoaded || !_orientationComputed) return NO;
    @try {
        int nLevels = _mRes->levels();
        for (int lvl = nLevels - 1; lvl >= 0; --lvl) {
            if (progress) progress(@"Solving positions", 1.f - (float)lvl/(float)nLevels);
            for (int it = 0; it < 6; ++it)
                optimize_positions(*_mRes, lvl, _extrinsic, _posy, [](uint32_t){});
            if (lvl > 0) propagateOtoFine(*_mRes, lvl - 1);
        }
        _positionComputed = YES;
        return YES;
    } @catch (...) { return NO; }
}

- (BOOL)extractMeshWithProgress:(nullable ProgressBlock)progress {
    if (!_meshLoaded || !_orientationComputed || !_positionComputed) return NO;
    @try {
        if (progress) progress(@"Extracting graph", 0.25f);
        _adj_extracted.clear();
        _O_extracted.resize(3, _mRes->size());
        _N_extracted.resize(3, _mRes->size());
        std::set<uint32_t> crease_in, crease_out;
        extract_graph(*_mRes, _extrinsic, _rosy, _posy, _adj_extracted,
                      _O_extracted, _N_extracted, crease_in, crease_out, true);

        if (progress) progress(@"Extracting faces", 0.6f);
        Float scale = _mRes->scale();
        extract_faces(_adj_extracted, _O_extracted, _N_extracted,
                      _Nf_extracted, _F_extracted, _posy, scale, crease_out, true, true);

        _meshExtracted = YES;
        if (progress) progress(@"Done", 1.f);
        return YES;
    } @catch (...) { return NO; }
}

- (nullable NSString *)exportMesh:(NSString *)path {
    if (!_meshExtracted) return nil;
    @try {
        write_mesh([path UTF8String], _F_extracted, _O_extracted, MatrixXf(), _Nf_extracted);
        return path;
    } @catch (...) { return nil; }
}

- (uint32_t)extractedVertexCount { return _meshExtracted ? (uint32_t)_O_extracted.cols() : 0; }
- (uint32_t)extractedFaceCount  { return _meshExtracted ? (uint32_t)_F_extracted.cols() : 0; }

#pragma mark - Data for Rendering

- (nullable NSArray<NSData *> *)getVertexData {
    if (!_meshLoaded) return nil;
    const MatrixXf &V = _mRes->V(0);
    const MatrixXf &N = _mRes->N(0);
    return @[
        [NSData dataWithBytes:V.data() length:V.size() * sizeof(Float)],
        [NSData dataWithBytes:N.data() length:N.size() * sizeof(Float)]
    ];
}

- (nullable NSArray<NSData *> *)getFaceData {
    if (!_meshLoaded) return nil;
    const MatrixXu &F = _mRes->F();
    if (_meshExtracted)
        return @[
            [NSData dataWithBytes:F.data() length:F.size() * sizeof(uint32_t)],
            [NSData dataWithBytes:_F_extracted.data()
                           length:_F_extracted.size() * sizeof(uint32_t)]
        ];
    return @[
        [NSData dataWithBytes:F.data() length:F.size() * sizeof(uint32_t)],
        [NSData data]
    ];
}

- (BOOL)hasMesh             { return _meshLoaded; }
- (BOOL)hasOrientationField { return _orientationComputed; }
- (BOOL)hasPositionField    { return _positionComputed; }
- (BOOL)hasExtractedMesh    { return _meshExtracted; }

@end
