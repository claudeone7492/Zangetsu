package sx.proxies.peer

/**
 * Copy for the sharing service's ongoing notification.
 *
 * The rest of this package is vendored verbatim from upstream
 * android-peer-sdk v1.3.2 (MIT), which hardcodes "Proxies.sx Peer" as the title
 * and "Connected as <deviceId>" as the connected text in
 * [sx.proxies.peer.service.PeerProxyService]. Neither is configurable through
 * the published API, and both leak the vendor's brand and a device identifier
 * into the user's notification shade.
 *
 * [ProxiesPeerSDK.init] fills these in from [ProxiesPeerSDK.Config], so the
 * host app owns the wording and this copy stays a thin shim over upstream.
 */
object PeerNotification {
    /**
     * Notification title, also used as the channel name. Null means "use the
     * host app's label", which keeps the notification reading as the app the
     * user installed.
     */
    @Volatile
    var title: String? = null

    /** Text shown once the relay connection is up. */
    @Volatile
    var connectedText: String = "Connected"
}
