//
//  RMMapnikSource.m
//
// Copyright (c) 2008-2012, Route-Me Contributors
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#import "RMMapnikSource.h"

#import "RMMapView.h"
#import "RMFractalTileProjection.h"
#import "RMProjection.h"

@interface RMMapView (RMMapnikSource)

- (RMProjectedRect)projectedRectFromLatitudeLongitudeBounds:(RMSphericalTrapezium)bounds;

@end

#pragma mark -

@interface RMMapnikSource ()

@property (nonatomic, assign) RMMapView *mapView;
@property (nonatomic, strong) RMFractalTileProjection *tileProjection;

@end

#pragma mark -

@implementation RMMapnikSource

@synthesize minZoom;
@synthesize maxZoom;
@synthesize cacheable;
@synthesize opaque;
@synthesize mapView=_mapView;
@synthesize tileProjection=_tileProjection;

- (id)initForMapView:(RMMapView *)mapView
{
    if (!(self = [super init]))
        return nil;

    self.minZoom = 0;
    self.maxZoom = 22;

    self.cacheable = NO;
    self.opaque    = YES;

    _tileProjection = [[RMFractalTileProjection alloc] initFromProjection:self.projection
                                                           tileSideLength:self.tileSideLength
                                                                  maxZoom:self.maxZoom
                                                                  minZoom:self.minZoom];

    _mapView = mapView;

    return self;
}

- (UIImage *)imageForTile:(RMTile)tile inCache:(RMTileCache *)tileCache
{
    if ([self.delegate respondsToSelector:@selector(tileSource:rawImageForTile:)])
        return [UIImage imageWithCGImage:[self.delegate tileSource:self rawImageForTile:tile]];

    if ([self.delegate respondsToSelector:@selector(tileSource:imageForTile:)])
        return [self.delegate tileSource:self imageForTile:tile];

    return [UIImage imageNamed:@"LoadingTile.png"];
}

- (RMFractalTileProjection *)mercatorToTileProjection
{
    return _tileProjection;
}

- (RMProjection *)projection
{
	return [RMProjection googleProjection];
}

- (RMSphericalTrapezium)latitudeLongitudeBoundingBox
{
    RMSphericalTrapezium bbox = {
        .northEast = {
            .latitude  = kMaxLat,
            .longitude = kMaxLong
        },
        .southWest = {
            .latitude  = -kMaxLat,
            .longitude = -kMaxLong
        }
    };

    return bbox;
}

- (NSString *)uniqueTilecacheKey
{
    return @"Mapnik";
}

- (NSUInteger)tileSideLength
{
    return 256;
}

- (NSString *)shortName
{
    return @"Mapnik";
}

- (NSString *)longDescription
{
    return @"Custom Mapnik source with live renderer";
}

- (NSString *)shortAttribution
{
    return @"Copyright © 2013 Mapnik";
}

- (NSString *)longAttribution
{
    return [self shortAttribution];
}

- (BOOL)tileSourceHasTile:(RMTile)tile
{
    return YES;
}

- (void)cancelAllDownloads
{
    LogMethod();
}

- (void)didReceiveMemoryWarning
{
    LogMethod();
}

@end
