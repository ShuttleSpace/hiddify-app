package com.hiddify.hiddify.bg

import com.hiddify.core.libbox.AutoRedirectHandler
import com.hiddify.core.libbox.AutoRedirectSession
import com.hiddify.core.libbox.BridgeOptions
import com.hiddify.core.libbox.BridgeSession
import com.hiddify.core.libbox.ConnectionOwner
import com.hiddify.core.libbox.InterfaceUpdateListener
import com.hiddify.core.libbox.LocalDNSTransport
import com.hiddify.core.libbox.NeighborUpdateListener
import com.hiddify.core.libbox.NetworkInterfaceIterator
import com.hiddify.core.libbox.Notification
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.libbox.PlatformUser
import com.hiddify.core.libbox.ShellSession
import com.hiddify.core.libbox.StringIterator
import com.hiddify.core.libbox.TunOptions
import com.hiddify.core.libbox.WIFIState
import go.Seq

/**
 * Process-stable Java object handed to gomobile.
 *
 * Android may recreate the actual VpnService/ProxyService, which creates a new Java object and
 * therefore a new gomobile refnum. Keeping one pinned bridge prevents Go from holding a stale
 * foreign reference when the service instance changes.
 */
object PlatformInterfaceBridge : PlatformInterface {
    @Volatile
    var delegate: PlatformInterface? = null

    init {
        Seq.incRef(this)
    }

    private fun platform(): PlatformInterface =
        delegate ?: error("PlatformInterfaceBridge delegate is not attached")

    override fun autoDetectInterfaceControl(fd: Int) {
        platform().autoDetectInterfaceControl(fd)
    }

    override fun clearDNSCache() {
        platform().clearDNSCache()
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        platform().closeDefaultInterfaceMonitor(listener)
    }

    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner =
        platform().findConnectionOwner(
            ipProtocol,
            sourceAddress,
            sourcePort,
            destinationAddress,
            destinationPort,
        )

    override fun getInterfaces(): NetworkInterfaceIterator = platform().getInterfaces()

    override fun includeAllNetworks(): Boolean = platform().includeAllNetworks()

    override fun localDNSTransport(): LocalDNSTransport? = platform().localDNSTransport()

    override fun openTun(options: TunOptions): Int = platform().openTun(options)

    override fun readWIFIState(): WIFIState? = platform().readWIFIState()

    override fun sendNotification(notification: Notification) {
        platform().sendNotification(notification)
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        platform().startDefaultInterfaceMonitor(listener)
    }

    override fun systemCertificates(): StringIterator = platform().systemCertificates()

    override fun underNetworkExtension(): Boolean = platform().underNetworkExtension()

    override fun usePlatformAutoDetectInterfaceControl(): Boolean =
        platform().usePlatformAutoDetectInterfaceControl()

    override fun cancelNotification(identifier: String, typeID: Int) {
        platform().cancelNotification(identifier, typeID)
    }

    override fun writeLog(message: String) = platform().writeLog(message)

    // the rest of the core's platform interface (neighbor monitor, shell, bridge, auto redirect):
    // the wrapper answers "not supported", so the bridge only has to ask it
    override fun startNeighborMonitor(listener: NeighborUpdateListener?) =
        platform().startNeighborMonitor(listener)

    override fun closeNeighborMonitor(listener: NeighborUpdateListener?) =
        platform().closeNeighborMonitor(listener)

    override fun registerMyInterface(name: String?) = platform().registerMyInterface(name)

    override fun usePlatformShell(): Boolean = platform().usePlatformShell()

    override fun checkPlatformShell() = platform().checkPlatformShell()

    override fun openShellSession(
        user: PlatformUser?,
        command: String?,
        environ: StringIterator?,
        term: String?,
        rows: Int,
        cols: Int,
    ): ShellSession = platform().openShellSession(user, command, environ, term, rows, cols)

    override fun lookupUser(username: String?): PlatformUser = platform().lookupUser(username)

    override fun lookupSFTPServer(): String = platform().lookupSFTPServer()

    override fun readSystemSSHHostKey(): String = platform().readSystemSSHHostKey()

    override fun tailscaleHostname(): String = platform().tailscaleHostname()

    override fun usePlatformBridge(): Boolean = platform().usePlatformBridge()

    override fun createBridge(options: BridgeOptions?): BridgeSession = platform().createBridge(options)

    override fun usePlatformAutoRedirect(): Boolean = platform().usePlatformAutoRedirect()

    override fun createAutoRedirect(
        options: ByteArray?,
        handler: AutoRedirectHandler?,
    ): AutoRedirectSession = platform().createAutoRedirect(options, handler)
}
