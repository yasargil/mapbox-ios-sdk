//
//  RMMapGLView.h
//  MapView
//
//  Created by Justin R. Miller on 11/5/13.
//
//

#import <GLKit/GLKit.h>

#import "RMTileSource.h"

@class RMMapView;

@interface RMMapGLView : GLKView

@property (nonatomic, assign) BOOL useSnapshotRenderer;

@property (nonatomic, readonly) id <RMTileSource>tileSource;

@property CGFloat scale;
@property CGPoint offset;

- (id)initWithFrame:(CGRect)frame mapView:(RMMapView *)aMapView forTileSource:(id <RMTileSource>)aTileSource;

@end
