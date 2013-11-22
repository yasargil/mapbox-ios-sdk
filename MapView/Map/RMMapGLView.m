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

static SceneVertex tileVertexSW = {{-1,  0, 0}, {0, 0}};
static SceneVertex tileVertexSE = {{ 0,  0, 0}, {1, 0}};
static SceneVertex tileVertexNW = {{-1,  1, 0}, {0, 1}};
static SceneVertex tileVertexNE = {{ 0,  1, 0}, {1, 1}};

typedef struct {
    SceneVertex vertices[3];
} SceneTriangle;

static SceneTriangle SceneTriangleMake(const SceneVertex vertexA, const SceneVertex vertexB, const SceneVertex vertexC);

@interface RMMapGLView ()

@property RMMapView *mapView;
@property id <RMTileSource>tileSource;
@property GLKBaseEffect *baseEffect;
@property GLuint bufferName;
@property RMTile lastTile;
@property NSOperationQueue *tileQueue;
@property GLKTextureInfo *textureInfo;

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

    self.alpha = 0.9;

    _mapView = aMapView;
    _tileSource = aTileSource;

    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    [EAGLContext setCurrentContext:self.context];

    _baseEffect = [GLKBaseEffect new];
    _baseEffect.useConstantColor = GL_TRUE;
    _baseEffect.constantColor = GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f);

    glClearColor(1.0f, 0.0f, 0.0f, 1.0f);

    SceneTriangle triangles[2];

    triangles[0] = SceneTriangleMake(tileVertexSE, tileVertexSW, tileVertexNW);
    triangles[1] = SceneTriangleMake(tileVertexSE, tileVertexNW, tileVertexNE);

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

    _tileQueue = [NSOperationQueue new];
    _tileQueue.maxConcurrentOperationCount = 1;

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

    [self updateTile];
}

- (CGFloat)scale
{
    return _scale;
}

- (void)setScale:(CGFloat)scale
{
    _scale = scale;

    [self updateTile];
}

- (void)updateTile
{
    CGSize contentSize = [[self.mapView valueForKeyPath:@"mapScrollView.contentSize"] CGSizeValue];

    CGFloat zoom = log2f(self.scale);

    CGFloat x = (_offset.x / contentSize.width)  * powf(2.0, zoom);
    CGFloat y = (_offset.y / contentSize.height) * powf(2.0, zoom);

    RMTile tileToDraw = RMTileMake((int)floorf(x), (int)floorf(y), (int)floorf(zoom));

    if ( ! RMTilesEqual(tileToDraw, self.lastTile))
    {
        [self.tileQueue addOperationWithBlock:^(void)
        {
            UIImage *tileImage = [self.tileSource imageForTile:tileToDraw inCache:self.mapView.tileCache];

            // TODO: check again if tile is still needed

            if (tileImage)
            {
                self.textureInfo = [GLKTextureLoader textureWithCGImage:tileImage.CGImage
                                                                options:@ { GLKTextureLoaderOriginBottomLeft : @YES }
                                                                  error:nil];

                self.lastTile = tileToDraw;

                [self display];
            }
        }];
    }
}

- (void)drawRect:(CGRect)rect
{
    glClear(GL_COLOR_BUFFER_BIT);

    if (self.textureInfo)
    {
        self.baseEffect.texture2d0.name   = self.textureInfo.name;
        self.baseEffect.texture2d0.target = self.textureInfo.target;
    }

    [self.baseEffect prepareToDraw];

    // 2
    //
    glBindBuffer(GL_ARRAY_BUFFER, self.bufferName);

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

    // 2, 4, and 5 again for texture
    //
    glBindBuffer(GL_ARRAY_BUFFER, self.bufferName);
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
                 0,            // start vertex index
                 6);           // vertex count

    // adjust aspect ratio
    //
    self.baseEffect.transform.projectionMatrix = GLKMatrix4MakeScale(1.0f,
                                                                     (GLfloat)self.drawableWidth / (GLfloat)self.drawableHeight,
                                                                     1.0f);
}

@end
