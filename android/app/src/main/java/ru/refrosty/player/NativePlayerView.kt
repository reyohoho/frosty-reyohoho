package ru.refrosty.player

import android.content.Context
import android.media.audiofx.DynamicsProcessing
import android.os.Build
import android.util.Log
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.media3.common.C as MediaC
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import android.net.Uri
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.hls.HlsManifest
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

/**
 * Native Twitch live-stream player backed by Media3 ExoPlayer.
 *
 * * Uses a patched [ru.refrosty.player.lowlatency.HlsPlaylistParser] to honour
 *   Twitch's `#EXT-X-TWITCH-PREFETCH` low-latency tags (~2s latency target).
 * * Exposes a [MethodChannel] for commands (play/pause/setDataSource/quality)
 *   and an [EventChannel] for playback state / errors / variants / video size.
 *
 * Each Flutter-created PlatformView owns its own ExoPlayer instance.
 */
@UnstableApi
class NativePlayerView(
    context: Context,
    viewId: Int,
    messenger: io.flutter.plugin.common.BinaryMessenger,
    creationParams: Map<String?, Any?>?,
) : PlatformView, MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private val tag = "NativePlayerView"

    private val container: FrameLayout = FrameLayout(context).apply {
        layoutParams = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
        setBackgroundColor(0xFF000000.toInt())
    }

    private val playerView: PlayerView = PlayerView(context).apply {
        useController = false
        setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING)
        resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
        setBackgroundColor(0xFF000000.toInt())
        setKeepContentOnPlayerReset(true)
        layoutParams = FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.MATCH_PARENT,
        )
    }

    private val methodChannel = MethodChannel(messenger, "ru.refrosty/native_player/$viewId")
    private val eventChannel = EventChannel(messenger, "ru.refrosty/native_player/events/$viewId")
    private var eventSink: EventChannel.EventSink? = null

    private val player: ExoPlayer
    private var dynamicsProcessing: DynamicsProcessing? = null
    private var dynamicsProcessingRequested: Boolean = false
    private var mirrored: Boolean = false
    private var released: Boolean = false

    // Ads state (Xtra-style "hideAds" fallback).
    //
    // When Twitch stitches a pre-roll / mid-roll ad into the HLS stream we
    // parse `#EXT-X-DATERANGE CLASS="twitch-stitched-ad"` (see the patched
    // [HlsPlaylistParser]) and enter "ad mode": the video track is disabled
    // and the volume is muted. When the segment exits the ad interval, we
    // restore both. This mirrors Xtra's [ExoPlayerService]  `hideAds` branch
    // since we don't run a TTV.LOL-style ad-stripping proxy.
    private var hideAdsEnabled: Boolean = true
    private var playingAds: Boolean = false
    private var savedVolume: Float = 1f

    // Last user-requested video quality. Retained across mediaSource swaps
    // (e.g. `setDataSource` is called again after an ad-end playerType
    // upgrade) so we can reinstall the [TrackSelectionOverride] as soon as
    // the fresh master playlist's tracks arrive in [PlayerListener.onTracksChanged].
    //
    // Contract:
    // * [desiredVideoWidth] == null → "Auto" (no override, ABR free).
    // * [desiredVideoWidth] == 1 && [desiredVideoHeight] == 1 → "Audio only"
    //   (video track type disabled).
    // * Otherwise → pinned to that exact resolution.
    private var desiredVideoWidth: Int? = null
    private var desiredVideoHeight: Int? = null
    private var desiredVideoBitrate: Int? = null

    init {
        container.addView(playerView)

        val initialBufferMs = (creationParams?.get("initialBufferMs") as? Int) ?: 2000
        val minBufferMs = (creationParams?.get("minBufferMs") as? Int) ?: 15000
        val maxBufferMs = (creationParams?.get("maxBufferMs") as? Int) ?: 50000
        val rebufferMs = (creationParams?.get("rebufferMs") as? Int) ?: 2000

        player = ExoPlayer.Builder(context)
            .setLoadControl(
                DefaultLoadControl.Builder()
                    .setBufferDurationsMs(minBufferMs, maxBufferMs, initialBufferMs, rebufferMs)
                    .build()
            )
            .setHandleAudioBecomingNoisy(true)
            .build()

        playerView.player = player
        player.addListener(PlayerListener())

        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)

        // Honour initial creation params if provided.
        (creationParams?.get("mirror") as? Boolean)?.let { setMirror(it) }
        (creationParams?.get("hideAds") as? Boolean)?.let { hideAdsEnabled = it }
    }

    override fun getView(): View = container

    override fun onFlutterViewAttached(flutterView: View) {}

    override fun onFlutterViewDetached() {}

    override fun dispose() {
        if (released) return
        released = true
        try {
            methodChannel.setMethodCallHandler(null)
        } catch (_: Exception) {
        }
        try {
            eventChannel.setStreamHandler(null)
        } catch (_: Exception) {
        }
        releaseDynamicsProcessing()
        try {
            playerView.player = null
        } catch (_: Exception) {
        }
        try {
            player.release()
        } catch (t: Throwable) {
            Log.w(tag, "player.release() failed", t)
        }
    }

    // region MethodChannel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (released) {
            result.error("released", "Player already released", null)
            return
        }
        try {
            when (call.method) {
                "setDataSource" -> {
                    val url = call.argument<String>("url")
                    if (url.isNullOrBlank()) {
                        result.error("arg", "url is required", null)
                        return
                    }
                    val userAgent = call.argument<String>("userAgent")
                    val headers = call.argument<Map<String, String>>("headers")
                    val proxyBase = call.argument<String>("proxyBase")
                    setDataSource(url, userAgent, headers, proxyBase)
                    result.success(null)
                }
                "play" -> {
                    player.playWhenReady = true
                    result.success(null)
                }
                "pause" -> {
                    player.playWhenReady = false
                    result.success(null)
                }
                "release" -> {
                    dispose()
                    result.success(null)
                }
                "setVolume" -> {
                    val v = (call.argument<Number>("volume") ?: 1).toFloat()
                    val clamped = v.coerceIn(0f, 1f)
                    savedVolume = clamped
                    // While ads are playing we keep the player muted; the new
                    // volume will be applied once the ad interval exits.
                    if (!playingAds) player.volume = clamped
                    result.success(null)
                }
                "setHideAds" -> {
                    hideAdsEnabled = call.argument<Boolean>("enabled") ?: true
                    // If we were currently hiding an ad and the user turned
                    // this off, bring video/audio back right away.
                    if (!hideAdsEnabled && playingAds) exitAdMode()
                    result.success(null)
                }
                "seekToLive" -> {
                    player.seekToDefaultPosition()
                    result.success(null)
                }
                "setMaxVideoSize" -> {
                    val w = call.argument<Int>("width")
                    val h = call.argument<Int>("height")
                    val bitrate = call.argument<Int>("bitrate")
                    applyMaxVideoSize(w, h, bitrate)
                    result.success(null)
                }
                "getVariants" -> {
                    result.success(collectVariants())
                }
                "setMirror" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setMirror(enabled)
                    result.success(null)
                }
                "setDynamicsProcessing" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    setDynamicsProcessing(enabled)
                    result.success(null)
                }
                "setResizeMode" -> {
                    val mode = call.argument<String>("mode") ?: "fit"
                    playerView.resizeMode = when (mode) {
                        "fill" -> AspectRatioFrameLayout.RESIZE_MODE_FILL
                        "zoom" -> AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                        "fixed_width" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_WIDTH
                        "fixed_height" -> AspectRatioFrameLayout.RESIZE_MODE_FIXED_HEIGHT
                        else -> AspectRatioFrameLayout.RESIZE_MODE_FIT
                    }
                    result.success(null)
                }
                "getLatencyMs" -> {
                    result.success(computeLatencyMs())
                }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            Log.e(tag, "method ${call.method} failed", t)
            result.error("exception", t.message, null)
        }
    }

    // endregion

    // region EventChannel

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        emitPlayingState()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emit(event: String, data: Map<String, Any?>) {
        val payload = HashMap<String, Any?>(data.size + 1)
        payload["event"] = event
        payload.putAll(data)
        eventSink?.success(payload)
    }

    private fun emitPlayingState() {
        emit(
            "playing",
            mapOf(
                "isPlaying" to player.isPlaying,
                "playWhenReady" to player.playWhenReady,
                "playbackState" to playbackStateName(player.playbackState),
            ),
        )
    }

    private fun playbackStateName(state: Int): String = when (state) {
        Player.STATE_IDLE -> "idle"
        Player.STATE_BUFFERING -> "buffering"
        Player.STATE_READY -> "ready"
        Player.STATE_ENDED -> "ended"
        else -> "unknown"
    }

    // endregion

    // region Playback

    private fun setDataSource(
        url: String,
        userAgent: String?,
        headers: Map<String, String>?,
        proxyBase: String?,
    ) {
        // Any previous TrackSelectionOverride references stale Tracks.Group
        // instances and — more importantly — an old quality ladder (e.g.
        // "360p only" from a picture-by-picture master) that is about to be
        // replaced with the full Source..160p ladder. Drop it so ABR is free
        // to pick on the new manifest and Dart can reapply the user's choice.
        desiredVideoWidth = null
        desiredVideoHeight = null
        desiredVideoBitrate = null
        val resetParams = player.trackSelectionParameters.buildUpon()
        resetParams.clearOverridesOfType(MediaC.TRACK_TYPE_VIDEO)
        resetParams.clearVideoSizeConstraints()
        resetParams.setMaxVideoBitrate(
            TrackSelectionParameters.DEFAULT_WITHOUT_CONTEXT.maxVideoBitrate,
        )
        resetParams.setTrackTypeDisabled(MediaC.TRACK_TYPE_VIDEO, false)
        player.trackSelectionParameters = resetParams.build()

        val httpFactory = DefaultHttpDataSource.Factory().apply {
            setAllowCrossProtocolRedirects(true)
            if (!userAgent.isNullOrBlank()) setUserAgent(userAgent)
            if (!headers.isNullOrEmpty()) setDefaultRequestProperties(headers)
            setKeepPostFor302Redirects(true)
        }
        val baseFactory: DataSource.Factory =
            DefaultDataSource.Factory(container.context, httpFactory)

        // If the user configured a playlist proxy (RTE quality proxy or a
        // manual one) we wrap the data source so every HLS *playlist* request
        // (master + per-quality media playlists on `*.hls.ttvnw.net`) is
        // rewritten to `{proxy}/{original_url}`. Segments (*.ts) go direct to
        // avoid bouncing 100% of traffic through the proxy.
        val dataSourceFactory: DataSource.Factory = if (!proxyBase.isNullOrBlank()) {
            val trimmed = proxyBase.trimEnd('/')
            Log.i(tag, "setDataSource: proxy enabled base=$trimmed masterUrl=$url")
            ResolvingDataSource.Factory(baseFactory) { spec ->
                val original = spec.uri.toString()
                if (!shouldProxyForHls(original, trimmed)) {
                    spec
                } else {
                    val rewritten = "$trimmed/$original"
                    Log.d(tag, "proxy rewrite: $original -> $rewritten")
                    spec.buildUpon().setUri(Uri.parse(rewritten)).build()
                }
            }
        } else {
            Log.i(tag, "setDataSource: proxy disabled masterUrl=$url")
            baseFactory
        }

        val mediaItem = MediaItem.Builder()
            .setUri(url)
            .setMimeType(MimeTypes.APPLICATION_M3U8)
            .setLiveConfiguration(
                MediaItem.LiveConfiguration.Builder()
                    .setTargetOffsetMs(2000)
                    .setMinPlaybackSpeed(0.98f)
                    .setMaxPlaybackSpeed(1.05f)
                    .build()
            )
            .build()

        // Note: we deliberately raise the min-load-error retry count to 10
        // (Media3 default is 3) so a flaky network or a brief CDN blip
        // doesn't take down a live stream permanently. The playlist tracker
        // will keep polling the media playlist at `targetDuration` cadence
        // between retries, which is exactly what's needed for LL-HLS.
        val source = HlsMediaSource.Factory(dataSourceFactory)
            .setAllowChunklessPreparation(true)
            .setPlaylistParserFactory(TwitchHlsPlaylistParserFactory())
            .setLoadErrorHandlingPolicy(DefaultLoadErrorHandlingPolicy(10))
            .createMediaSource(mediaItem)

        player.setMediaSource(source)
        player.prepare()
        player.playWhenReady = true
    }

    /**
     * True if [url] is a Twitch HLS playlist that we should route through the
     * configured [proxyBase]. Matches `usher.ttvnw.net` (master) and any host
     * under `*.hls.ttvnw.net` with an `.m3u8` suffix (media playlists). Skips
     * already-proxied URLs to avoid double-wrapping.
     */
    private fun shouldProxyForHls(url: String, proxyBase: String): Boolean {
        if (url.startsWith(proxyBase)) return false
        val uri = try { Uri.parse(url) } catch (_: Throwable) { return false }
        val host = uri.host ?: return false
        val path = uri.path ?: ""
        val isPlaylistHost = host == "usher.ttvnw.net" || host.endsWith(".hls.ttvnw.net")
        if (!isPlaylistHost) return false
        // Usher returns m3u8 without the extension in the path; accept it
        // regardless. For hls.ttvnw.net, only proxy `.m3u8` requests.
        return host == "usher.ttvnw.net" || path.endsWith(".m3u8")
    }

    /**
     * Applies a quality selection. Semantics:
     *
     * * `w == null || h == null || w <= 0 || h <= 0` → "Auto". Clears every
     *   video constraint/override so ABR is free to pick any rung.
     * * `w == 1 && h == 1` → special "Audio only" sentinel from Dart. Disables
     *   the whole video track type.
     * * Otherwise → pin the exact variant by installing a
     *   [TrackSelectionOverride] on the matching video [Tracks.Group] so
     *   ExoPlayer's ABR can never drop below the user's choice even when the
     *   bandwidth meter is pessimistic after a 360p ad.
     *
     * [bitrate] (when provided) is used purely as a tie-breaker when several
     * video formats share the same resolution (e.g. 720p vs 720p60 on Twitch).
     */
    private fun applyMaxVideoSize(w: Int?, h: Int?, bitrate: Int?) {
        desiredVideoWidth = w
        desiredVideoHeight = h
        desiredVideoBitrate = bitrate
        reapplyDesiredQuality()
    }

    /**
     * Installs [TrackSelectionParameters] matching [desiredVideoWidth] /
     * [desiredVideoHeight] / [desiredVideoBitrate]. Safe to call any time —
     * in particular, called again from [PlayerListener.onTracksChanged] once
     * the new master playlist after a `setDataSource` re-preparation (ad-end
     * playerType upgrade) has reported its track groups.
     */
    private fun reapplyDesiredQuality() {
        val w = desiredVideoWidth
        val h = desiredVideoHeight
        val bitrate = desiredVideoBitrate

        val params = player.trackSelectionParameters.buildUpon()
        params.clearOverridesOfType(MediaC.TRACK_TYPE_VIDEO)

        if (w == null || h == null || w <= 0 || h <= 0) {
            params.clearVideoSizeConstraints()
            params.setMaxVideoBitrate(
                TrackSelectionParameters.DEFAULT_WITHOUT_CONTEXT.maxVideoBitrate,
            )
            params.setTrackTypeDisabled(MediaC.TRACK_TYPE_VIDEO, false)
            player.trackSelectionParameters = params.build()
            return
        }

        if (w == 1 && h == 1) {
            params.setTrackTypeDisabled(MediaC.TRACK_TYPE_VIDEO, true)
            player.trackSelectionParameters = params.build()
            return
        }

        params.setTrackTypeDisabled(MediaC.TRACK_TYPE_VIDEO, false)
        params.clearVideoSizeConstraints()
        params.setMaxVideoBitrate(
            TrackSelectionParameters.DEFAULT_WITHOUT_CONTEXT.maxVideoBitrate,
        )

        val override = findBestVideoOverride(w, h, bitrate)
        if (override != null) {
            params.addOverride(override)
        } else {
            // Tracks may not be loaded yet (e.g. called immediately after
            // prepare, before onTracksChanged fires). Fall back to a narrow
            // min/max size window and reapply from onTracksChanged.
            params.setMinVideoSize(w, h)
            params.setMaxVideoSize(w, h)
            if (bitrate != null && bitrate > 0) {
                params.setMaxVideoBitrate(bitrate)
            }
        }

        player.trackSelectionParameters = params.build()
    }

    /**
     * Walks the current [Tracks] and returns a [TrackSelectionOverride] pinned
     * to the single video format whose width/height match [w]/[h]. When more
     * than one format shares the resolution (Twitch 720p vs 720p60) [bitrate]
     * is used as a tie-breaker. Returns `null` when nothing matches yet.
     */
    private fun findBestVideoOverride(
        w: Int,
        h: Int,
        bitrate: Int?,
    ): TrackSelectionOverride? {
        val tracks: Tracks = player.currentTracks
        var best: TrackSelectionOverride? = null
        var bestScore = Int.MAX_VALUE
        for (group in tracks.groups) {
            if (group.type != MediaC.TRACK_TYPE_VIDEO) continue
            val tg = group.mediaTrackGroup
            for (i in 0 until tg.length) {
                val f = tg.getFormat(i)
                if (f.width != w || f.height != h) continue
                val score = if (bitrate != null && bitrate > 0) {
                    Math.abs(f.bitrate - bitrate)
                } else {
                    // No bitrate hint — prefer the highest-bitrate rung at
                    // this resolution (covers 60fps > 30fps on Twitch).
                    -f.bitrate
                }
                if (score < bestScore) {
                    bestScore = score
                    best = TrackSelectionOverride(tg, listOf(i))
                }
            }
        }
        return best
    }

    private fun collectVariants(): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        val tracks: Tracks = player.currentTracks
        for (group in tracks.groups) {
            if (group.type != MediaC.TRACK_TYPE_VIDEO) continue
            val tg = group.mediaTrackGroup
            for (i in 0 until tg.length) {
                val f = tg.getFormat(i)
                out += mapOf(
                    "index" to i,
                    "width" to f.width,
                    "height" to f.height,
                    "bitrate" to f.bitrate,
                    "frameRate" to (if (f.frameRate > 0f) f.frameRate else null),
                    "codecs" to f.codecs,
                    "label" to f.label,
                )
            }
        }
        return out
    }

    private fun setMirror(enabled: Boolean) {
        if (mirrored == enabled) return
        mirrored = enabled
        val surface = playerView.videoSurfaceView ?: return
        if (surface is SurfaceView) {
            surface.scaleX = if (enabled) -1f else 1f
        } else {
            surface.scaleX = if (enabled) -1f else 1f
        }
    }

    private fun setDynamicsProcessing(enabled: Boolean) {
        dynamicsProcessingRequested = enabled
        if (!enabled) {
            releaseDynamicsProcessing()
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return
        if (dynamicsProcessing != null) return
        val sessionId = player.audioSessionId
        if (sessionId == MediaC.AUDIO_SESSION_ID_UNSET) {
            // Will retry from onAudioSessionIdChanged once the session is assigned.
            return
        }
        try {
            dynamicsProcessing = buildDynamicsProcessing(sessionId)
        } catch (t: Throwable) {
            Log.w(tag, "DynamicsProcessing init failed", t)
        }
    }

    private fun buildDynamicsProcessing(sessionId: Int): DynamicsProcessing? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return null
        // Multi-band compressor preset borrowed from Xtra: pulls up quiet
        // speech without crushing transients. Applied to every band of every
        // channel of the currently-attached audio session.
        return DynamicsProcessing(0, sessionId, null).apply {
            for (channelIdx in 0 until channelCount) {
                val mbc = getMbcByChannelIndex(channelIdx)
                for (bandIdx in 0 until mbc.bandCount) {
                    setMbcBandByChannelIndex(
                        channelIdx,
                        bandIdx,
                        getMbcBandByChannelIndex(channelIdx, bandIdx).apply {
                            attackTime = 0f
                            releaseTime = 0.25f
                            ratio = 1.6f
                            threshold = -50f
                            kneeWidth = 40f
                            preGain = 0f
                            postGain = 10f
                        },
                    )
                }
            }
            enabled = true
        }
    }

    private fun releaseDynamicsProcessing() {
        try {
            dynamicsProcessing?.release()
        } catch (_: Throwable) {
        }
        dynamicsProcessing = null
    }

    private fun computeLatencyMs(): Long? {
        // ExoPlayer already computes distance from the live edge using the
        // current HLS media playlist (honours our LL-HLS prefetch patches).
        // MediaC.TIME_UNSET is reported when the manifest has not yet been
        // parsed or the stream is VOD.
        val offset = player.currentLiveOffset
        return if (offset == MediaC.TIME_UNSET) null else offset
    }

    // endregion

    // region Ad detection

    /**
     * Inspects the freshly-parsed HLS media playlist. If the **last** segment
     * falls inside a `twitch-stitched-ad` DATERANGE interstitial, we enter
     * "ad mode" (disable video + mute). Otherwise, if we previously were in
     * ad mode, restore video + volume. Call after every
     * `TIMELINE_CHANGE_REASON_SOURCE_UPDATE`.
     */
    private fun evaluateAdState() {
        if (!hideAdsEnabled) return
        val manifest = player.currentManifest as? HlsManifest ?: return
        val playlist = manifest.mediaPlaylist
        val lastSegment = playlist.segments.lastOrNull() ?: return
        val segmentStartTime = playlist.startTimeUs + lastSegment.relativeStartTimeUs

        val isAd = listOf("Amazon", "Adform", "DCM").any { lastSegment.title.contains(it) } ||
            playlist.interstitials.any { interstitial ->
                val startTime = interstitial.startDateUnixUs
                val endTime = interstitial.endDateUnixUs
                    .takeIf { it != MediaC.TIME_UNSET }
                    ?: interstitial.durationUs
                        .takeIf { it != MediaC.TIME_UNSET }
                        ?.let { startTime + it }
                    ?: interstitial.plannedDurationUs
                        .takeIf { it != MediaC.TIME_UNSET }
                        ?.let { startTime + it }
                val isStitched = interstitial.id.startsWith("stitched-ad-") ||
                    interstitial.clientDefinedAttributes.any {
                        (it.name == "CLASS" && it.textValue == "twitch-stitched-ad") ||
                            it.name.startsWith("X-TV-TWITCH-AD-")
                    }
                endTime != null && isStitched && segmentStartTime in startTime..endTime
            }

        if (isAd && !playingAds) enterAdMode() else if (!isAd && playingAds) exitAdMode()
    }

    private fun enterAdMode() {
        if (playingAds) return
        playingAds = true
        // Kill audio; Twitch typically loops the ad audio, which is the worst
        // part of pre-rolls. Video goes black automatically because we also
        // disable the video track selection below.
        savedVolume = player.volume
        player.volume = 0f
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(MediaC.TRACK_TYPE_VIDEO, true)
            .build()
        emit("ad", mapOf("active" to true))
    }

    private fun exitAdMode() {
        if (!playingAds) return
        playingAds = false
        player.trackSelectionParameters = player.trackSelectionParameters
            .buildUpon()
            .setTrackTypeDisabled(MediaC.TRACK_TYPE_VIDEO, false)
            .build()
        player.volume = savedVolume
        emit("ad", mapOf("active" to false))
    }

    // endregion

    private inner class PlayerListener : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            emitPlayingState()
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            emitPlayingState()
            // If Twitch's SSAI injected a weird end-of-window + HLS refresh
            // stalls (the LL-HLS prefetch chain ran out and the playlist
            // tracker gave up), kick the player: re-prepare to force a
            // media-playlist refresh. Applies to live only.
            if (playbackState == Player.STATE_ENDED && player.isCurrentMediaItemLive) {
                Log.w(tag, "Live stream hit STATE_ENDED, re-preparing")
                try {
                    player.prepare()
                } catch (t: Throwable) {
                    Log.w(tag, "prepare() after ENDED failed", t)
                }
            }
        }

        override fun onTimelineChanged(timeline: Timeline, reason: Int) {
            if (reason == Player.TIMELINE_CHANGE_REASON_SOURCE_UPDATE) {
                evaluateAdState()
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            emit(
                "error",
                mapOf(
                    "code" to error.errorCodeName,
                    "message" to (error.message ?: ""),
                ),
            )
        }

        override fun onTracksChanged(tracks: Tracks) {
            emit("tracks", mapOf("variants" to collectVariants()))
            // When a new master playlist is loaded (initial prepare, ad-end
            // playerType upgrade, error retry, …) the previous
            // TrackSelectionOverride references a now-stale Tracks.Group and
            // ExoPlayer silently discards it. Rebind against the new groups
            // so the user's picked quality survives the swap.
            if (!tracks.isEmpty && desiredVideoWidth != null && desiredVideoHeight != null) {
                reapplyDesiredQuality()
            }
        }

        override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) {
            emit(
                "videoSize",
                mapOf(
                    "width" to videoSize.width,
                    "height" to videoSize.height,
                ),
            )
        }

        override fun onAudioSessionIdChanged(audioSessionId: Int) {
            if (dynamicsProcessingRequested &&
                dynamicsProcessing == null &&
                audioSessionId != MediaC.AUDIO_SESSION_ID_UNSET
            ) {
                try {
                    dynamicsProcessing = buildDynamicsProcessing(audioSessionId)
                } catch (t: Throwable) {
                    Log.w(tag, "DynamicsProcessing lazy init failed", t)
                }
            }
            emit("audioSession", mapOf("audioSessionId" to audioSessionId))
        }
    }
}
