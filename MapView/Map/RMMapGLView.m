//
//  RMMapGLView.m
//  MapView
//
//  Created by Justin R. Miller on 11/21/13.
//
//

#import "RMMapGLView.h"

#import "RMMapView.h"

typedef struct {
    GLKVector3 position;
    GLKVector2 texture;
} SceneVertex;

typedef struct {
    SceneVertex vertices[3];
} SceneTriangle;

static SceneTriangle SceneTriangleMake(const SceneVertex vertexA, const SceneVertex vertexB, const SceneVertex vertexC);

@interface RMMapView (PrivateMethods)

- (RMProjectedRect)projectedRectFromLatitudeLongitudeBounds:(RMSphericalTrapezium)bounds;

@end

#pragma mark -

@interface RMMapGLView ()

@property RMMapView *mapView;
@property id <RMTileSource>tileSource;
@property GLKBaseEffect *baseEffect;
@property NSUInteger tileColumns;
@property NSUInteger tileRows;
@property GLuint bufferName;
@property RMTile lastTile;
@property NSMutableDictionary *textures;

@end

#pragma mark -

@implementation RMMapGLView

@synthesize tileSource=_tileSource;
@synthesize mapView=_mapView;
@synthesize scale=_scale;
@synthesize offset=_offset;

static SceneTriangle SceneTriangleMake(const SceneVertex vertexA, const SceneVertex vertexB, const SceneVertex vertexC)
{
    SceneTriangle result;

    result.vertices[0] = vertexA;
    result.vertices[1] = vertexB;
    result.vertices[2] = vertexC;

    return result;
}

- (id)initWithFrame:(CGRect)frame mapView:(RMMapView *)aMapView forTileSource:(id <RMTileSource>)aTileSource
{
    if (!(self = [super initWithFrame:frame]))
        return nil;

    self.alpha = 0.95;

    _mapView = aMapView;
    _tileSource = aTileSource;

    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    [EAGLContext setCurrentContext:self.context];

    _baseEffect = [GLKBaseEffect new];
    _baseEffect.useConstantColor = GL_TRUE;
    _baseEffect.constantColor = GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f);

    glClearColor(1.0f, 0.0f, 0.0f, 1.0f);

    _tileColumns = 3;
    _tileRows    = 4;

    CGSize tileSize = CGSizeMake(2.0 / _tileColumns, 2.0 / _tileRows);

    SceneTriangle triangles[(_tileColumns * _tileRows * 2)];

    NSUInteger index = 0;

    for (NSUInteger c = 0; c < _tileColumns; c++)
    {
        for (NSUInteger r = 0; r < _tileRows; r++)
        {
            // assume origin at lower left & 2.0 for height/width, then substract 1.0 off
            //
            SceneVertex tileVertexSW = {{((CGFloat)c * tileSize.width) - 1.0, ((CGFloat)r * tileSize.height) - 1.0, 0}, {0, 0}};
            SceneVertex tileVertexSE = {{tileVertexSW.position.v[0] + tileSize.width, tileVertexSW.position.v[1], 0}, {1, 0}};
            SceneVertex tileVertexNW = {{tileVertexSW.position.v[0], tileVertexSW.position.v[1] + tileSize.height, 0}, {0, 1}};
            SceneVertex tileVertexNE = {{tileVertexSE.position.v[0], tileVertexNW.position.v[1], 0}, {1, 1}};

            triangles[index]       = SceneTriangleMake(tileVertexSE, tileVertexSW, tileVertexNW);
            triangles[(index + 1)] = SceneTriangleMake(tileVertexSE, tileVertexNW, tileVertexNE);

            index += 2;
        }
    }

    // 1
    //
    glGenBuffers(1, &_bufferName);

    // 2
    //
    glBindBuffer(GL_ARRAY_BUFFER, _bufferName);

    // 3
    //
    GLsizei    vertexCount     = sizeof(triangles) / sizeof(SceneVertex);
    GLsizeiptr stride          = sizeof(SceneVertex);
    GLsizeiptr bufferSizeBytes = stride * vertexCount;

    glBufferData(GL_ARRAY_BUFFER,  // initialize buffer
                 bufferSizeBytes,  // number of bytes to copy
                 triangles,        // address of bytes to copy
                 GL_DYNAMIC_DRAW); // cache in GPU memory

    _textures = [NSMutableDictionary dictionary];

    return self;
}

- (void)dealloc
{
    if (_bufferName)
    {
        glDeleteBuffers(1, &_bufferName);
        _bufferName = 0;
    }

    [EAGLContext setCurrentContext:self.context];
    self.context = nil;
    [EAGLContext setCurrentContext:nil];
}

- (CGPoint)offset
{
    return _offset;
}

- (void)setOffset:(CGPoint)offset
{
    _offset = offset;

    [self updateTiles];
}

- (CGFloat)scale
{
    return _scale;
}

- (void)setScale:(CGFloat)scale
{
    if (floorf(log2f(scale)) != floorf(log2f(_scale)))
        [self.textures removeAllObjects];

    _scale = scale;

    [self updateTiles];
}

- (void)updateTiles
{
    CGSize contentSize = [[self.mapView valueForKeyPath:@"mapScrollView.contentSize"] CGSizeValue];

    CGFloat zoom = floorf(log2f(self.scale));

    CGFloat x = floorf((_offset.x / contentSize.width)  * powf(2.0, zoom));
    CGFloat y = floorf((_offset.y / contentSize.height) * powf(2.0, zoom));

    RMTile topLeftTile = RMTileMake(x, y, zoom);

    if ( ! RMTilesEqual(topLeftTile, self.lastTile))
    {
        for (NSUInteger c = 0; c < self.tileColumns; c++)
        {
            for (NSUInteger r = 0; r < self.tileRows; r++)
            {
                RMTile tile = RMTileMake(topLeftTile.x + c, topLeftTile.y - r, topLeftTile.zoom);

                uint64_t tileKey = RMTileKey(tile);

                // TODO: clean up old textures

                if ( ! [self.textures objectForKey:@(tileKey)])
                {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void)
                    {
                        UIImage *tileImage = [self.tileSource imageForTile:tile inCache:self.mapView.tileCache];

                        dispatch_async(dispatch_get_main_queue(), ^(void)
                        {
                            BOOL tileStillNeeded = (RMProjectedRectIntersectsProjectedRect([self.mapView projectedBounds], [self.mapView projectedRectFromLatitudeLongitudeBounds:[self.mapView latitudeLongitudeBoundingBoxForTile:tile]]) && ! [self.textures objectForKey:@(tileKey)]);

                            if (tileStillNeeded && tileImage)
                            {
                                CFBridgingRetain((id)tileImage.CGImage);

                                [[[GLKTextureLoader alloc] initWithSharegroup:self.context.sharegroup] textureWithCGImage:tileImage.CGImage
                                                                                                                  options:@{ GLKTextureLoaderOriginBottomLeft : @YES }
                                                                                                                    queue:nil
                                                                                                        completionHandler:^(GLKTextureInfo *textureInfo, NSError *outError)
                                                                                                        {
                                                                                                            if (textureInfo)
                                                                                                            {
                                                                                                                [self.textures setObject:textureInfo forKey:@(tileKey)];

                                                                                                                [self display];
                                                                                                            }

                                                                                                            CFBridgingRelease(tileImage.CGImage);
                                                                                                        }];
                            }
                        });

                    });
                }
            }
        }

        self.lastTile = topLeftTile;
    }
}

- (void)drawRect:(CGRect)rect
{
    glClear(GL_COLOR_BUFFER_BIT);

    GLint index = 0;

    for (NSUInteger c = 0; c < self.tileColumns; c++)
    {
        for (NSUInteger r = 0; r < self.tileRows; r++)
        {
            uint64_t tileKey = RMTileKey(RMTileMake(self.lastTile.x + c, self.lastTile.y - r, self.lastTile.zoom));

            GLKTextureInfo *texture = [self.textures objectForKey:@(tileKey)];

            if (texture)
            {
                self.baseEffect.texture2d0.name   = texture.name;
                self.baseEffect.texture2d0.target = texture.target;

                [self.baseEffect prepareToDraw];

                // 4
                //
                glEnableVertexAttribArray(GLKVertexAttribPosition);

                // 5
                //
                glVertexAttribPointer(GLKVertexAttribPosition,                 // use position attribute
                                      3,                                       // number of coordinates per attribute
                                      GL_FLOAT,                                // data is floating point
                                      GL_FALSE,                                // no fixed point scaling
                                      sizeof(SceneVertex),                     // total bytes per vertex
                                      NULL + offsetof(SceneVertex, position)); // offset in each vertex for position

                // 4 and 5 again for texture
                //
                glEnableVertexAttribArray(GLKVertexAttribTexCoord0);
                glVertexAttribPointer(GLKVertexAttribTexCoord0,
                                      2,
                                      GL_FLOAT,
                                      GL_FALSE,
                                      sizeof(SceneVertex),
                                      NULL + offsetof(SceneVertex, texture));

                // 6
                //
                glDrawArrays(GL_TRIANGLES, // draw mode
                             index * 6,    // start vertex index
                             6);           // vertex count (1 tile * 2 triangles * 3 vertices)

                index++;
            }
        }
    }
}

@end
