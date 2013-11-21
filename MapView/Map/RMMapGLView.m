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

    self.alpha = 0.9;

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

- (void)drawRect:(CGRect)rect
{
    glClear(GL_COLOR_BUFFER_BIT);
}

@end
