//
//  RMMapGLView.m
//  MapView
//
//  Created by Justin R. Miller on 11/5/13.
//
//

#import "RMMapGLView.h"

#import "RMMapView.h"

#import "AGLKVertexAttribArrayBuffer.h"

#define TILE_WIDTH 1.5f
#define BUILDING_HEIGHT 0.5f

typedef struct {
    GLKVector3 position;
    GLKVector2 textureCoords;
    GLKVector3 normal;
} SceneVertex;

static SceneVertex tileVertexSW = {{-TILE_WIDTH / 2.0f, -TILE_WIDTH / 2.0f, 0.0}, {0.0, 0.0}, {0, 0, 1}};
static SceneVertex tileVertexSE = {{ TILE_WIDTH / 2.0f, -TILE_WIDTH / 2.0f, 0.0}, {1.0, 0.0}, {0, 0, 1}};
static SceneVertex tileVertexNW = {{-TILE_WIDTH / 2.0f,  TILE_WIDTH / 2.0f, 0.0}, {0.0, 1.0}, {0, 0, 1}};
static SceneVertex tileVertexNE = {{ TILE_WIDTH / 2.0f,  TILE_WIDTH / 2.0f, 0.0}, {1.0, 1.0}, {0, 0, 1}};

//static SceneVertex buildingAVertexSW1 = {{-0.1, -0.1, 0.0}, {1.0, 0.0}};
//static SceneVertex buildingAVertexNW1 = {{-0.1,  0.0, 0.0}, {0.0, 0.0}};
//static SceneVertex buildingAVertexSW2 = {{-0.1, -0.1, BUILDING_HEIGHT}, {1.0, 1.0}};
//static SceneVertex buildingAVertexNW2 = {{-0.1,  0.0, BUILDING_HEIGHT}, {0.0, 1.0}};
//static SceneVertex buildingAVertexSE1 = {{ 0.0, -0.1, 0.0}, {1.0, 0.0}};
//static SceneVertex buildingAVertexSE2 = {{ 0.0, -0.1, BUILDING_HEIGHT}, {1.0, 1.0}};

typedef struct {
    SceneVertex vertices[3];
} SceneTriangle;

static SceneTriangle SceneTriangleMake(const SceneVertex vertexA,
                                       const SceneVertex vertexB,
                                       const SceneVertex vertexC);

@interface RMMapGLView ()

@property RMMapView *mapView;
@property id <RMTileSource>tileSource;
@property GLKBaseEffect *baseEffect;
@property AGLKVertexAttribArrayBuffer *vertexBuffer;
@property GLKTextureLoader *textureLoader;
@property UIImage *latestImage;
@property GLKTextureInfo *brickTextureInfo;
@property GLKTextureInfo *textureInfo;
@property NSTimer *timer;
@property dispatch_queue_t groundQueue;
@property dispatch_queue_t buildingQueue;
@property RMTile lastGroundTile;
@property RMTile lastBuildingTile;
@property NSMutableArray *triangleObjects;

@end

#pragma mark -

@implementation RMMapGLView

@synthesize useSnapshotRenderer=_useSnapshotRenderer;
@synthesize tileSource=_tileSource;
@synthesize mapView=_mapView;
@synthesize scale=_scale;
@synthesize offset=_offset;

- (id)initWithFrame:(CGRect)frame mapView:(RMMapView *)aMapView forTileSource:(id <RMTileSource>)aTileSource
{
    if (!(self = [super initWithFrame:frame]))
        return nil;

//    self.opaque = NO;

    self.alpha = 0.9;

    _mapView = aMapView;
    _tileSource = aTileSource;

    self.useSnapshotRenderer = NO;

    self.drawableDepthFormat = GLKViewDrawableDepthFormat16;

    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    [EAGLContext setCurrentContext:self.context];

    self.textureLoader = [[GLKTextureLoader alloc] initWithSharegroup:self.context.sharegroup];

    self.baseEffect = [GLKBaseEffect new];

//    self.baseEffect.useConstantColor = GL_TRUE;

//    self.baseEffect.constantColor = GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f);

    self.baseEffect.light0.enabled = GL_TRUE;
    self.baseEffect.light0.diffuseColor = GLKVector4Make(
                                                         0.9f, // Red
                                                         0.9f, // Green
                                                         0.9f, // Blue
                                                         1.0f);// Alpha
    self.baseEffect.light0.position = GLKVector4Make(
                                                     -1.0f,
                                                     0.0f,  
                                                     -0.8f,  
                                                     0.0f);

    GLKMatrix4 modelViewMatrix = GLKMatrix4MakeRotation(GLKMathDegreesToRadians(-60.0f), 1.0f, 0.0f, 0.0f);
    modelViewMatrix = GLKMatrix4Rotate(modelViewMatrix, GLKMathDegreesToRadians(-30.0f), 0.0f, 0.0f, 1.0f);
    modelViewMatrix = GLKMatrix4Translate(modelViewMatrix, 0.0f, 0.0f, -0.25f);
    self.baseEffect.transform.modelviewMatrix = modelViewMatrix;

    glClearColor(0.0f, 0.0f, 0.0f, 1.0f);

    self.brickTextureInfo = [GLKTextureLoader textureWithCGImage:[[RMMapView resourceImageNamed:@"brick.jpg"] CGImage]
                                                         options:@{ GLKTextureLoaderOriginBottomLeft : @YES }
                                                           error:nil];

    SceneTriangle triangles[2]; //6];

    triangles[0] = SceneTriangleMake(tileVertexSE, tileVertexSW, tileVertexNW);
    triangles[1] = SceneTriangleMake(tileVertexSE, tileVertexNW, tileVertexNE);
//    triangles[2] = SceneTriangleMake(buildingAVertexSW1, buildingAVertexNW1, buildingAVertexSW2);
//    triangles[3] = SceneTriangleMake(buildingAVertexNW1, buildingAVertexSW2, buildingAVertexNW2);
//    triangles[4] = SceneTriangleMake(buildingAVertexSW1, buildingAVertexSE1, buildingAVertexSE2);
//    triangles[5] = SceneTriangleMake(buildingAVertexSW1, buildingAVertexSW2, buildingAVertexSE2);

    self.vertexBuffer = [[AGLKVertexAttribArrayBuffer alloc] initWithAttribStride:sizeof(SceneVertex)
                                                                 numberOfVertices:sizeof(triangles) / sizeof(SceneVertex)
                                                                            bytes:triangles
                                                                            usage:GL_DYNAMIC_DRAW];

    self.lastGroundTile = RMTileDummy();

    self.timer = [NSTimer timerWithTimeInterval:1.0/10.0 target:self selector:@selector(rotate:) userInfo:nil repeats:YES];

//    [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];

//    glEnable(GL_DEPTH_TEST);

    self.triangleObjects = [NSMutableArray array];

    self.groundQueue   = dispatch_queue_create("mapgl.ground",    DISPATCH_QUEUE_SERIAL);
    self.buildingQueue = dispatch_queue_create("mapgl.buildling", DISPATCH_QUEUE_SERIAL);

    return self;
}

- (void)dealloc
{
//    [_tileSource cancelAllDownloads];
//    self.layer.contents = nil;
    _mapView = nil;

    dispatch_release(self.groundQueue);
    dispatch_release(self.buildingQueue);

    [EAGLContext setCurrentContext:self.context];

    self.vertexBuffer = nil;

    self.context = nil;
    [EAGLContext setCurrentContext:nil];
}

- (void)rotate:(NSTimer *)timer
{
    self.baseEffect.transform.modelviewMatrix = GLKMatrix4Rotate(self.baseEffect.transform.modelviewMatrix, GLKMathDegreesToRadians(0.5), 0.0f, 0.0f, 1.0f);

    [self display];
}


- (CGPoint)offset
{
    return _offset;
}

- (void)setOffset:(CGPoint)offset
{
    _offset = offset;

//    NSLog(@"offset: %@", [NSValue valueWithCGPoint:offset]);

//    NSLog(@"%@", [self.superview valueForKeyPath:@"_mapScrollView.contentSize"]);

//    NSLog(@"zoom: %f", floorf(powf(2.0, self.scale)));


//    CGFloat tileScale = (powf(2.0, self.scale) * 256.0) / (powf(2.0, floorf(self.scale)) * 256.0);
//
//    NSLog(@"%f", tileScale);


    CGSize contentSize = [[self.mapView valueForKeyPath:@"mapScrollView.contentSize"] CGSizeValue];

//    NSLog(@"%@", contentSize);



//    CGFloat fraction = floorf(self.scale) / self.scale;

//    NSLog(@"%f", fraction);




//    CGFloat edgeSize = (floorf(powf(2.0, floorf(self.scale))) * 256.0) / fraction;

//    NSLog(@"edge: %f", edgeSize);

//    NSLog(@"%f,%f (%f)", offset.x, offset.y, edgeSize);

    CGFloat x = (_offset.x / contentSize.width) * powf(2.0, self.scale);
    CGFloat y = (_offset.y / contentSize.height) * powf(2.0, self.scale);

//    NSLog(@"%i,%i,%i", (int)floorf(self.scale), (int)floorf(x), (int)floorf(y));

    RMTile tileToDraw = RMTileMake((int)floorf(x), (int)floorf(y), (int)floorf(self.scale));

    if ( ! RMTilesEqual(self.lastGroundTile, tileToDraw) && self.scale >= 17)
    {
        self.lastGroundTile = tileToDraw;

        dispatch_async(self.groundQueue, ^(void)
        {
//            NSLog(@"redrawing ground");

            self.latestImage = [self.tileSource imageForTile:tileToDraw inCache:self.mapView.tileCache];

            if (self.latestImage)
            {
//                [UIImagePNGRepresentation(self.latestImage) writeToFile:@"/tmp/blah.png" atomically:YES];

                [self.textureLoader textureWithCGImage:self.latestImage.CGImage
                                               options:@{ GLKTextureLoaderOriginBottomLeft : @YES }
                                                 queue:nil
                                     completionHandler:^(GLKTextureInfo *textureInfo, NSError *outError)
                                     {
                                         if ( ! textureInfo)
                                         {
                                             NSLog(@"%@", outError);
                                         }
                                         else
                                         {
                                             if (self.textureInfo)
                                             {
                                                 GLuint name = self.textureInfo.name;
                                                 glDeleteTextures(1, &name);
                                             }

                                             self.textureInfo = textureInfo;

                                             self.latestImage = nil;
                                         }

//                                         self.lastGroundTile = tileToDraw;

                                         [self.triangleObjects removeAllObjects];



                                         [self display];
                                     }];
            }
        });

//        return;

        if (RMTilesEqual(self.lastGroundTile, self.lastBuildingTile))
            return;

        dispatch_async(self.buildingQueue, ^(void)
        {
            if (self.lastGroundTile.zoom < 17)
                return;

            self.lastBuildingTile = self.lastGroundTile;

            NSURL *buildingTileURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://tile.openstreetmap.us/vectiles-buildings/%i/%i/%i.json", self.lastBuildingTile.zoom, self.lastBuildingTile.x, self.lastBuildingTile.y]];

//            NSLog(@"%@", buildingTileURL);

            NSData *buildingData = [NSURLConnection sendSynchronousRequest:[NSURLRequest requestWithURL:buildingTileURL] returningResponse:nil error:nil];

            NSDictionary *buildingsJSON = [NSJSONSerialization JSONObjectWithData:buildingData options:0 error:nil];

//            NSLog(@"%@", buildingsJSON);

            RMSphericalTrapezium tileBox = [self.mapView latitudeLongitudeBoundingBoxForTile:self.lastBuildingTile];

            CLLocationCoordinate2D sw = tileBox.southWest;
            CLLocationCoordinate2D ne = tileBox.northEast;

            double latDelta = ne.latitude  - sw.latitude;
            double lonDelta = ne.longitude - sw.longitude;

//            NSLog(@"%f, %f to %f, %f", sw.latitude, sw.longitude, ne.latitude, ne.longitude);

            CLLocationCoordinate2D tileMid = CLLocationCoordinate2DMake(sw.latitude + (latDelta / 2.0), ne.longitude - (lonDelta / 2.0));

            CLLocationCoordinate2D c[3];

            for (NSDictionary *building in buildingsJSON[@"features"])
            {
                CGFloat height = (CGFloat)(rand() % 10) / 10.0 * BUILDING_HEIGHT;

//                NSLog(@"height: %f", height);

                if ([building[@"geometry"][@"type"] isEqualToString:@"Polygon"])
                {
                    NSArray *coordinateStrings = building[@"geometry"][@"coordinates"][0];

                    for (NSUInteger i = 0; i < [coordinateStrings count]; i++)
                    {
                        if (i == [coordinateStrings count] - 1)
                            break;

                        NSArray *coordinateString1 = coordinateStrings[i];
                        NSArray *coordinateString2 = coordinateStrings[i + 1];

                        c[0] = CLLocationCoordinate2DMake([coordinateString1[1] doubleValue], [coordinateString1[0] doubleValue]);         // ground start
                        c[1] = CLLocationCoordinate2DMake([coordinateString2[1] doubleValue], [coordinateString2[0] doubleValue]);         // ground end
                        c[2] = CLLocationCoordinate2DMake((c[0].latitude + c[1].latitude) / 2.0, (c[0].longitude + c[1].longitude) / 2.0); // elevated mid

                        if (c[0].latitude < sw.latitude || c[0].latitude > ne.latitude || c[0].longitude < sw.longitude || c[0].longitude > ne.longitude ||
                            c[1].latitude < sw.latitude || c[1].latitude > ne.latitude || c[1].longitude < sw.longitude || c[1].longitude > ne.longitude)
                            break;

                        NSMutableArray *vertices = [NSMutableArray arrayWithCapacity:3];

                        CGFloat x, y;

                        y = ((c[0].latitude - tileMid.latitude) / (latDelta / 2.0)) * (TILE_WIDTH / 2.0);

                        x = ((c[0].longitude - tileMid.longitude) / (lonDelta / 2.0)) * (TILE_WIDTH / 2.0);

//                        NSLog(@"%f, %f to %f, %f", sw.latitude, sw.longitude, ne.latitude, ne.longitude);
//                        NSLog(@"c[0]: %f, %f - tileMid: %f, %f", c[0].latitude, c[0].longitude, tileMid.latitude, tileMid.longitude);
//                        NSLog(@"latDelta: %f, lonDelta: %f", latDelta, lonDelta);
//                        NSLog(@"x: %f, y: %f", x, y);

                        [vertices addObject:@[ @(x), @(y), @0 ]];

                        y = ((c[1].latitude - tileMid.latitude) / (latDelta / 2.0)) * (TILE_WIDTH / 2.0);

                        x = ((c[1].longitude - tileMid.longitude) / (lonDelta / 2.0)) * (TILE_WIDTH / 2.0);

                        [vertices addObject:@[ @(x), @(y), @0 ]];

                        y = ((c[2].latitude - tileMid.latitude) / (latDelta / 2.0)) * (TILE_WIDTH / 2.0);

                        x = ((c[2].longitude - tileMid.longitude) / (lonDelta / 2.0)) * (TILE_WIDTH / 2.0);

                        [vertices addObject:@[ @(x), @(y), @(height) ]];

                        [self.triangleObjects performSelectorOnMainThread:@selector(addObject:) withObject:vertices waitUntilDone:YES];
                    }
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^(void)
            {
                if ( ! [self.triangleObjects count])
                    return;

//                NSLog(@"filed %i triangles", [self.triangleObjects count]);

                [self prepBuffer];
            });
        });
    }   
}

- (void)prepBuffer
{
    if ( ! [self.triangleObjects count])
        return;

    SceneTriangle triangles[2 + [self.triangleObjects count]];

    triangles[0] = SceneTriangleMake(tileVertexSE, tileVertexSW, tileVertexNW);
    triangles[1] = SceneTriangleMake(tileVertexSE, tileVertexNW, tileVertexNE);

    triangles[0] = [self updatedNormalForTriangle:triangles[0]];
    triangles[1] = [self updatedNormalForTriangle:triangles[1]];

//    NSLog(@"working with %i triangles", [self.triangleObjects count]);

    for (NSUInteger j = 0; j < [self.triangleObjects count]; j++)
    {
        NSArray *t = self.triangleObjects[j];

//        NSLog(@"t[%i]: %@", j, t);

        SceneVertex v1 = {{[[t[0] objectAtIndex:0] floatValue], [[t[0] objectAtIndex:1] floatValue], [[t[0] objectAtIndex:2] floatValue]}, {0, 0}, {0, 0, 1}};
        SceneVertex v2 = {{[[t[1] objectAtIndex:0] floatValue], [[t[1] objectAtIndex:1] floatValue], [[t[1] objectAtIndex:2] floatValue]}, {1, 0}, {0, 0, 1}};
        SceneVertex v3 = {{[[t[2] objectAtIndex:0] floatValue], [[t[2] objectAtIndex:1] floatValue], [[t[2] objectAtIndex:2] floatValue]}, {0.5, 1}, {0, 0, 1}};

        SceneTriangle triangle = SceneTriangleMake(v1, v2, v3);

        triangles[j + 2] = [self updatedNormalForTriangle:triangle];
    }

    [self.vertexBuffer reinitWithAttribStride:sizeof(SceneVertex)
                             numberOfVertices:sizeof(triangles) / sizeof(SceneVertex)
                                        bytes:triangles];

    [self display];
}

- (SceneTriangle)updatedNormalForTriangle:(SceneTriangle)triangle
{
    GLKVector3 vectorA = GLKVector3Subtract(triangle.vertices[1].position, triangle.vertices[0].position);
    GLKVector3 vectorB = GLKVector3Subtract(triangle.vertices[2].position, triangle.vertices[0].position);

    GLKVector3 faceNormal = GLKVector3Normalize(GLKVector3CrossProduct(vectorA, vectorB));

    triangle.vertices[0].normal = faceNormal;
    triangle.vertices[1].normal = faceNormal;
    triangle.vertices[2].normal = faceNormal;

    return triangle;
}

- (CGFloat)scale
{
    return _scale;
}

- (void)setScale:(CGFloat)scale
{
    _scale = log2f(scale);

//    NSLog(@"tile size: %f", 256.0 / (1 - fabs(floorf(scale) - scale)));



//    NSLog(@"%f", _scale);
}

- (void)drawRect:(CGRect)rect
{
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (self.textureInfo)
    {
        self.baseEffect.texture2d0.name   = self.textureInfo.name;
        self.baseEffect.texture2d0.target = self.textureInfo.target;

        [self.baseEffect prepareToDraw];
    }

    [self.vertexBuffer prepareToDrawWithAttrib:GLKVertexAttribPosition
                           numberOfCoordinates:3
                                  attribOffset:offsetof(SceneVertex, position)
                                  shouldEnable:YES];

    [self.vertexBuffer prepareToDrawWithAttrib:GLKVertexAttribTexCoord0
                           numberOfCoordinates:2
                                  attribOffset:offsetof(SceneVertex, textureCoords)
                                  shouldEnable:YES];

    [self.vertexBuffer prepareToDrawWithAttrib:GLKVertexAttribNormal
                           numberOfCoordinates:3
                                  attribOffset:offsetof(SceneVertex, normal)
                                  shouldEnable:YES];

    [self.vertexBuffer drawArrayWithMode:GL_TRIANGLES
                        startVertexIndex:0
                        numberOfVertices:6];

    if ([self.triangleObjects count])
    {
//        NSLog(@"here to draw %i building triangles", [self.triangleObjects count]);

        self.baseEffect.texture2d0.name   = self.brickTextureInfo.name;
        self.baseEffect.texture2d0.target = self.brickTextureInfo.target;

        [self.baseEffect prepareToDraw];

        [self.vertexBuffer prepareToDrawWithAttrib:GLKVertexAttribPosition
                               numberOfCoordinates:3
                                      attribOffset:offsetof(SceneVertex, position)
                                      shouldEnable:YES];

        [self.vertexBuffer prepareToDrawWithAttrib:GLKVertexAttribTexCoord0
                               numberOfCoordinates:2
                                      attribOffset:offsetof(SceneVertex, textureCoords)
                                      shouldEnable:YES];

        [self.vertexBuffer drawArrayWithMode:GL_TRIANGLES
                            startVertexIndex:6
                            numberOfVertices:[self.triangleObjects count] * 3];
    }

    const GLfloat aspectRatio = (GLfloat)self.drawableWidth / (GLfloat)self.drawableHeight;

    self.baseEffect.transform.projectionMatrix = GLKMatrix4MakeScale(1.0f, aspectRatio, 1.0f);
}

static SceneTriangle SceneTriangleMake(const SceneVertex vertexA,
                                       const SceneVertex vertexB,
                                       const SceneVertex vertexC)
{
    SceneTriangle   result;

    result.vertices[0] = vertexA;
    result.vertices[1] = vertexB;
    result.vertices[2] = vertexC;
    
    return result;
} 

@end
