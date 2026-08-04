#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Mesh metadata returned after loading.
@interface MeshInfo : NSObject
@property (nonatomic) uint32_t vertexCount;
@property (nonatomic) uint32_t faceCount;
@property (nonatomic) float minX, minY, minZ;
@property (nonatomic) float maxX, maxY, maxZ;
@end

typedef void (^ProgressBlock)(NSString * _Nullable stage, float progress);

/// Wraps the C++ Instant Meshes algorithm engine.
@interface MeshEngine : NSObject

- (nullable MeshInfo *)loadMesh:(NSString *)path
                    creaseAngle:(float)creaseAngle
                  deterministic:(BOOL)deterministic
                       progress:(nullable ProgressBlock)progress;

- (void)setScale:(float)scale;
- (void)setFaceCount:(uint32_t)faceCount;
- (void)setVertexCount:(uint32_t)vertexCount;
- (void)setRoSy:(int)rosy;
- (void)setPoSy:(int)posy;
- (void)setExtrinsic:(BOOL)extrinsic;

- (BOOL)computeOrientationFieldWithProgress:(nullable ProgressBlock)progress;
- (BOOL)computePositionFieldWithProgress:(nullable ProgressBlock)progress;
- (BOOL)extractMeshWithProgress:(nullable ProgressBlock)progress;

- (nullable NSString *)exportMesh:(NSString *)path;

- (nullable NSArray<NSData *> *)getVertexData;
- (nullable NSArray<NSData *> *)getFaceData;

- (BOOL)hasMesh;
- (BOOL)hasOrientationField;
- (BOOL)hasPositionField;
- (BOOL)hasExtractedMesh;

- (uint32_t)extractedVertexCount;
- (uint32_t)extractedFaceCount;

@end

NS_ASSUME_NONNULL_END
