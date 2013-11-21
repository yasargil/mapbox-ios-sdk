//
//  RMMapGLView.m
//  MapView
//
//  Created by Justin R. Miller on 11/21/13.
//
//

#import "RMMapGLView.h"

#import "RMMapView.h"

@interface RMMapGLView ()

@property RMMapView *mapView;
@property id <RMTileSource>tileSource;
@property GLKBaseEffect *baseEffect;

@end

#pragma mark -

@implementation RMMapGLView

@synthesize tileSource=_tileSource;
@synthesize mapView=_mapView;
@synthesize scale=_scale;
@synthesize offset=_offset;

- (id)initWithFrame:(CGRect)frame mapView:(RMMapView *)aMapView forTileSource:(id <RMTileSource>)aTileSource
{
    if (!(self = [super initWithFrame:frame]))
        return nil;

    self.alpha = 0.75;

    _mapView = aMapView;
    _tileSource = aTileSource;

    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    [EAGLContext setCurrentContext:self.context];

    self.baseEffect = [GLKBaseEffect new];

    self.baseEffect.useConstantColor = GL_TRUE;

    self.baseEffect.constantColor = GLKVector4Make(1.0f, 1.0f, 1.0f, 1.0f);

    glClearColor(1.0f, 0.0f, 0.0f, 1.0f);
    
    return self;
}

- (void)dealloc
{
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

    RMLogTile(tileToDraw);

    [self display];
}

- (void)drawRect:(CGRect)rect
{
    glClear(GL_COLOR_BUFFER_BIT);
}

@end
