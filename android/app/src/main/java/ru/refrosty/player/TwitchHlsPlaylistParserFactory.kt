package ru.refrosty.player

import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.hls.playlist.HlsMultivariantPlaylist
import androidx.media3.exoplayer.hls.playlist.HlsPlaylist
import androidx.media3.exoplayer.hls.playlist.HlsPlaylistParserFactory
import androidx.media3.exoplayer.upstream.ParsingLoadable
import ru.refrosty.player.lowlatency.HlsPlaylistParser

/**
 * Factory that builds a patched [HlsPlaylistParser] for every HLS playlist
 * request made by ExoPlayer. Used by [HlsMediaSource.Factory.setPlaylistParserFactory].
 *
 * The returned parser:
 *  * treats Twitch-proprietary `#EXT-X-TWITCH-PREFETCH:<url>` tags as regular
 *    ~2s HLS segments so playback actually stays at low latency (without this
 *    Media3 silently ignores the tag and latency drifts to 6-10s);
 *  * rewrites VOD segment URIs ending in `-unmuted` to `-muted` so that
 *    playback does not break when Twitch has purged the unmuted variant;
 *  * preserves client-defined attributes on `#EXT-X-DATERANGE` tags so that
 *    ad-detection logic can see Twitch stitched-ad metadata.
 */
@UnstableApi
class TwitchHlsPlaylistParserFactory : HlsPlaylistParserFactory {
    override fun createPlaylistParser(): ParsingLoadable.Parser<HlsPlaylist> =
        HlsPlaylistParser()

    override fun createPlaylistParser(
        multivariantPlaylist: HlsMultivariantPlaylist,
        previousMediaPlaylist: androidx.media3.exoplayer.hls.playlist.HlsMediaPlaylist?,
    ): ParsingLoadable.Parser<HlsPlaylist> =
        HlsPlaylistParser(multivariantPlaylist, previousMediaPlaylist)
}
