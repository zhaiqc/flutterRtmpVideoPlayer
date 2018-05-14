package com.yourcompany.videoplayer;

import android.media.AudioManager;
import android.os.Build;
import android.view.Surface;

import java.io.IOException;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import com.ksyun.media.player.IMediaPlayer;
import com.ksyun.media.player.KSYMediaPlayer;

import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import io.flutter.view.TextureRegistry;

/**
 * VideoPlayerPlugin
 */
public class VideoPlayerPlugin implements MethodCallHandler {
    private static class VideoPlayer {
        private final TextureRegistry.SurfaceTextureEntry textureEntry;
        private final KSYMediaPlayer mediaPlayer;
        private EventChannel.EventSink eventSink;
        private final EventChannel eventChannel;
        private boolean isInitialized = false;

        VideoPlayer(
                final EventChannel eventChannel,
                final TextureRegistry.SurfaceTextureEntry textureEntry,
                String dataSource,
                final Result result,
                final Registrar registrar) {
            this.eventChannel = eventChannel;
            eventChannel.setStreamHandler(
                    new EventChannel.StreamHandler() {
                        @Override
                        public void onListen(Object o, EventChannel.EventSink sink) {
                            eventSink = sink;
                            sendInitialized();
                        }

                        @Override
                        public void onCancel(Object o) {
                            eventSink = null;
                        }
                    });
            this.textureEntry = textureEntry;
            this.mediaPlayer = new KSYMediaPlayer.Builder(registrar.context()).build();
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.ICE_CREAM_SANDWICH) {
                    mediaPlayer.setSurface(new Surface(textureEntry.surfaceTexture()));
                }
                mediaPlayer.setDataSource(dataSource);
                setAudioAttributes(mediaPlayer);


                mediaPlayer.setOnPreparedListener(new IMediaPlayer.OnPreparedListener() {
                    @Override
                    public void onPrepared(IMediaPlayer iMediaPlayer) {

                        mediaPlayer.setOnBufferingUpdateListener(new IMediaPlayer.OnBufferingUpdateListener() {
                            @Override
                            public void onBufferingUpdate(IMediaPlayer iMediaPlayer, int percent) {
                                if (eventSink != null) {
                                    Map<String, Object> event = new HashMap<>();
                                    event.put("event", "bufferingUpdate");
                                    List<Integer> range = Arrays.asList(0, (int) (percent * mediaPlayer.getDuration() / 100));
                                    // iOS supports a list of buffered ranges, so here is a list with a single range.
                                    event.put("values", Collections.singletonList(range));
                                    eventSink.success(event);
                                }
                            }
                        });

                        isInitialized = true;
                        sendInitialized();
                    }
                });

                mediaPlayer.setOnErrorListener(new IMediaPlayer.OnErrorListener() {
                    @Override
                    public boolean onError(IMediaPlayer iMediaPlayer, int i, int extra) {
                        eventSink.error(
                                "VideoError", "Video player had error " + i + " extra " + extra, null);
                        return true;
                    }
                });


//        mediaPlayer.setOnErrorListener(
//            new MediaPlayer.OnErrorListener() {
//              @Override
//              public boolean onError(MediaPlayer mp, int what, int extra) {
//                eventSink.error(
//                    "VideoError", "Video player had error " + what + " extra " + extra, null);
//                return true;
//              }
//            });


                mediaPlayer.setOnCompletionListener(new IMediaPlayer.OnCompletionListener() {
                    @Override
                    public void onCompletion(IMediaPlayer iMediaPlayer) {
                        Map<String, Object> event = new HashMap<>();
                        event.put("event", "completed");
                        eventSink.success(event);
                    }
                });
//
//        mediaPlayer.setOnCompletionListener(
//            new KSYMediaPlayer.OnCompletionListener() {
//              @Override
//              public void onCompletion(KSYMediaPlayer mediaPlayer) {
//                Map<String, Object> event = new HashMap<>();
//                event.put("event", "completed");
//                eventSink.success(event);
//              }
//            });

                mediaPlayer.prepareAsync();
            } catch (IOException e) {
                result.error("VideoError", "IOError when initializing video player " + e.toString(), null);
            }
            Map<String, Object> reply = new HashMap<>();
            reply.put("textureId", textureEntry.id());
            result.success(reply);
        }

        @SuppressWarnings("deprecation")
        private static void setAudioAttributes(IMediaPlayer mediaPlayer) {

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
//        mediaPlayer.setAudioAttributes(new AudioAttributes.Builder()
//                .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
//                .build());

            } else {
                mediaPlayer.setAudioStreamType(AudioManager.STREAM_MUSIC);
            }
        }

        void play() {
            if (!mediaPlayer.isPlaying()) {
                mediaPlayer.start();
            }
        }

        void pause() {
            if (mediaPlayer.isPlaying()) {
                mediaPlayer.pause();
            }
        }

        void setLooping(boolean value) {
            mediaPlayer.setLooping(value);
        }

        void setVolume(double value) {
            float bracketedValue = (float) Math.max(0.0, Math.min(1.0, value));
            mediaPlayer.setVolume(bracketedValue, bracketedValue);
        }

        void seekTo(int location) {
            mediaPlayer.seekTo(location);
        }

        long getPosition() {
            return mediaPlayer.getCurrentPosition();
        }

        private void sendInitialized() {
            if (isInitialized && eventSink != null) {
                Map<String, Object> event = new HashMap<>();
                event.put("event", "initialized");
                event.put("duration", mediaPlayer.getDuration());
                event.put("width", mediaPlayer.getVideoWidth());
                event.put("height", mediaPlayer.getVideoHeight());
                eventSink.success(event);
            }
        }

        void dispose() {
            if (isInitialized && mediaPlayer.isPlaying()) {
                mediaPlayer.stop();
            }
            mediaPlayer.reset();
            mediaPlayer.release();
            textureEntry.release();
            eventChannel.setStreamHandler(null);
        }
    }

    public static void registerWith(Registrar registrar) {
        final MethodChannel channel = new MethodChannel(registrar.messenger(), "flutter.io/videoPlayer");
        channel.setMethodCallHandler(new VideoPlayerPlugin(registrar));
    }

    private VideoPlayerPlugin(Registrar registrar) {
        this.registrar = registrar;
        this.videoPlayers = new HashMap<>();
    }

    private final Map<Long, VideoPlayer> videoPlayers;
    private final Registrar registrar;

    @Override
    public void onMethodCall(MethodCall call, Result result) {
        TextureRegistry textures = registrar.textures();
        if (textures == null) {
            result.error("no_activity", "video_player plugin requires a foreground activity", null);
            return;
        }
        switch (call.method) {
            case "init":
                for (VideoPlayer player : videoPlayers.values()) {
                    player.dispose();
                }
                videoPlayers.clear();
                break;
            case "create": {
                TextureRegistry.SurfaceTextureEntry handle = textures.createSurfaceTexture();
                EventChannel eventChannel =
                        new EventChannel(
                                registrar.messenger(), "flutter.io/videoPlayer/videoEvents" + handle.id());
                VideoPlayer player = new VideoPlayer(eventChannel, handle, (String) call.argument("dataSource"), result, registrar);
                videoPlayers.put(handle.id(), player);
                break;
            }
            default: {
                long textureId = ((Number) call.argument("textureId")).longValue();
                VideoPlayer player = videoPlayers.get(textureId);
                if (player == null) {
                    result.error(
                            "Unknown textureId",
                            "No video player associated with texture id " + textureId,
                            null);
                    return;
                }
                onMethodCall(call, result, textureId, player);
                break;
            }
        }
    }

    private void onMethodCall(MethodCall call, Result result, long textureId, VideoPlayer player) {
        switch (call.method) {
            case "setLooping":
                player.setLooping((Boolean) call.argument("looping"));
                result.success(null);
                break;
            case "setVolume":
                player.setVolume((Double) call.argument("volume"));
                result.success(null);
                break;
            case "play":
                player.play();
                result.success(null);
                break;
            case "pause":
                player.pause();
                result.success(null);
                break;
            case "seekTo":
                int location = ((Number) call.argument("location")).intValue();
                player.seekTo(location);
                result.success(null);
                break;
            case "position":
                result.success(player.getPosition());
                break;
            case "dispose":
                player.dispose();
                videoPlayers.remove(textureId);
                result.success(null);
                break;
            default:
                result.notImplemented();
                break;
        }
    }
}
