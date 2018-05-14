// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#import "VideoPlayerPlugin.h"
#import <KSYMediaPlayer/KSYMediaPlayer.h>

int64_t FLTCMTimeToMillis(CMTime time) { return time.value * 1000 / time.timescale; }

@interface FLTFrameUpdater : NSObject
@property(nonatomic) int64_t textureId;
@property(nonatomic, readonly) NSObject<FlutterTextureRegistry>* registry;
- (void)onDisplayLink:(CADisplayLink*)link;
@end

@implementation FLTFrameUpdater
- (FLTFrameUpdater*)initWithRegistry:(NSObject<FlutterTextureRegistry>*)registry {
  NSAssert(self, @"super init cannot be nil");
  if (self == nil) return nil;
  _registry = registry;
  return self;
}

- (void)onDisplayLink:(CADisplayLink*)link {
  [_registry textureFrameAvailable:_textureId];
}
@end

@interface FLTVideoPlayer : NSObject<FlutterTexture, FlutterStreamHandler>
@property(readonly, nonatomic) KSYMoviePlayerController* player;
@property(readonly, nonatomic) CADisplayLink* displayLink;
@property(nonatomic) FlutterEventChannel* eventChannel;
@property(nonatomic) FlutterEventSink eventSink;
@property(nonatomic, readonly) bool disposed;
@property(nonatomic, readonly) bool isPlaying;
@property(nonatomic, readonly) bool isLooping;
@property(nonatomic, readonly) bool isInitialized;
- (instancetype)initWithURL:(NSURL*)url frameUpdater:(FLTFrameUpdater*)frameUpdater;
- (void)play;
- (void)pause;
- (void)setIsLooping:(bool)isLooping;
- (void)updatePlayingState;
@end



@implementation FLTVideoPlayer
#define KIsiPhoneX ([UIScreen instancesRespondToSelector:@selector(currentMode)] ? CGSizeEqualToSize(CGSizeMake(1125, 2436), [[UIScreen mainScreen] currentMode].size) : NO)

- (void)VideoView {
    [UIApplication.sharedApplication.keyWindow.subviews.firstObject addSubview:_player.view];
    dispatch_time_t timer = dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC);
    dispatch_after(timer, dispatch_get_main_queue(), ^{
        for (UIView * item in UIApplication.sharedApplication.keyWindow.subviews) {
            [self setPlayerView:item];
        }
    });
}

- (void)setPlayerView:(UIView *)v {
    if ([v conformsToProtocol:@protocol(FLTMainView)]) {
        [v addSubview:_player.view];
    }
    
    for (UIView * item in v.subviews) {
        [self setPlayerView:item];
    }
}



- (instancetype)initWithURL:(NSURL*)url frameUpdater:(FLTFrameUpdater*)frameUpdater {
  self = [super init];
  NSAssert(self, @"super init cannot be nil");
  _isInitialized = false;
  _isPlaying = false;
  _disposed = false;
    _player = [[KSYMoviePlayerController alloc] initWithContentURL:url];
    _player.controlStyle = MPMovieControlStyleNone;
    _player.scalingMode = MPMovieScalingModeFill;
    _player.view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [_player prepareToPlay];
    _player.view.frame = CGRectMake(0, KIsiPhoneX?100:56, UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height*0.34);
    [self VideoView];
   
  return self;
}

- (void)observeValueForKeyPath:(NSString*)path
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {
 
}

- (void)updatePlayingState {
  if (!_isInitialized) {
    return;
  }
  if (_isPlaying) {
    [_player play];
  } else {
    [_player pause];
  }
  _displayLink.paused = !_isPlaying;
}

- (void)sendInitialized {
  if (_eventSink && _isInitialized) {
      CGSize size = self.player.naturalSize;
    _eventSink(@{
      @"event" : @"initialized",
      @"duration" : @([self duration]),
      @"width" : @(size.width),
      @"height" : @(size.height),
    });
  }
}

- (void)play {
  _isPlaying = true;
  [self updatePlayingState];
}

- (void)pause {
  _isPlaying = false;
  [self updatePlayingState];
}

- (int64_t)position {
//  return FLTCMTimeToMillis([_player currentTime]);
    return 100;
}

- (int64_t)duration {
//  return FLTCMTimeToMillis([[_player currentItem] duration]);
    return self.player.duration;
}

- (void)seekTo:(int)location {
//  [_player seekToTime:CMTimeMake(location, 1000)];
//    self.player
}

- (void)setIsLooping:(bool)isLooping {
  _isLooping = isLooping;
}

- (void)setVolume:(double)volume {
//  _player.volume = (volume < 0.0) ? 0.0 : ((volume > 1.0) ? 1.0 : volume);
}


- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {
  _eventSink = nil;
  return nil;
}

- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments
                                       eventSink:(nonnull FlutterEventSink)events {
  _eventSink = events;
  [self sendInitialized];
  return nil;
}

- (void)dispose {
  _disposed = true;
  [_displayLink invalidate];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
      _player.view.frame = CGRectMake(0, 0, 0, 0);
    [_player stop];
  [_eventChannel setStreamHandler:nil];
}

@end

@interface FLTVideoPlayerPlugin ()
@property(readonly, nonatomic) NSObject<FlutterTextureRegistry>* registry;
@property(readonly, nonatomic) NSObject<FlutterBinaryMessenger>* messenger;
@property(readonly, nonatomic) NSMutableDictionary* players;
@end

@implementation FLTVideoPlayerPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel =
      [FlutterMethodChannel methodChannelWithName:@"flutter.io/videoPlayer"
                                  binaryMessenger:[registrar messenger]];
  FLTVideoPlayerPlugin* instance =
      [[FLTVideoPlayerPlugin alloc] initWithRegistry:[registrar textures]
                                           messenger:[registrar messenger]];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithRegistry:(NSObject<FlutterTextureRegistry>*)registry
                       messenger:(NSObject<FlutterBinaryMessenger>*)messenger {
  self = [super init];
  NSAssert(self, @"super init cannot be nil");
  _registry = registry;
  _messenger = messenger;
  _players = [NSMutableDictionary dictionaryWithCapacity:1];
  return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"init" isEqualToString:call.method]) {
    for (NSNumber* textureId in _players) {
      [_registry unregisterTexture:[textureId unsignedIntegerValue]];
      [[_players objectForKey:textureId] dispose];
    }
    [_players removeAllObjects];
  } else if ([@"create" isEqualToString:call.method]) {
    NSDictionary* argsMap = call.arguments;
    NSString* dataSource = argsMap[@"dataSource"];
    FLTFrameUpdater* frameUpdater = [[FLTFrameUpdater alloc] initWithRegistry:_registry];
    FLTVideoPlayer* player = [[FLTVideoPlayer alloc] initWithURL:[NSURL URLWithString:dataSource]
                                                    frameUpdater:frameUpdater];
    int64_t textureId = [_registry registerTexture:player];
    frameUpdater.textureId = textureId;
    FlutterEventChannel* eventChannel = [FlutterEventChannel
        eventChannelWithName:[NSString stringWithFormat:@"flutter.io/videoPlayer/videoEvents%lld",
                                                        textureId]
             binaryMessenger:_messenger];
    [eventChannel setStreamHandler:player];
    player.eventChannel = eventChannel;
    _players[@(textureId)] = player;
    result(@{ @"textureId" : @(textureId) });
  } else {
    NSDictionary* argsMap = call.arguments;
    int64_t textureId = ((NSNumber*)argsMap[@"textureId"]).unsignedIntegerValue;
    FLTVideoPlayer* player = _players[@(textureId)];
    if ([@"dispose" isEqualToString:call.method]) {
      [_registry unregisterTexture:textureId];
      [_players removeObjectForKey:@(textureId)];
      [player dispose];
    } else if ([@"setLooping" isEqualToString:call.method]) {
      [player setIsLooping:[argsMap objectForKey:@"looping"]];
      result(nil);
    } else if ([@"setVolume" isEqualToString:call.method]) {
      [player setVolume:[[argsMap objectForKey:@"volume"] doubleValue]];
      result(nil);
    } else if ([@"play" isEqualToString:call.method]) {
      [player play];
      result(nil);
    } else if ([@"position" isEqualToString:call.method]) {
      result(@([player position]));
    } else if ([@"seekTo" isEqualToString:call.method]) {
      [player seekTo:[[argsMap objectForKey:@"location"] intValue]];
      result(nil);
    } else if ([@"pause" isEqualToString:call.method]) {
      [player pause];
      result(nil);
    } else {
      result(FlutterMethodNotImplemented);
    }
  }
}

@end
