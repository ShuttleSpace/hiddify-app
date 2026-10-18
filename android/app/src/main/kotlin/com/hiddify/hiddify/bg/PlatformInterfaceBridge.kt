package com.hiddify.hiddify.bg

import com.hiddify.core.libbox.ConnectionOwner
import com.hiddify.core.libbox.InterfaceUpdateListener
import com.hiddify.core.libbox.LocalDNSTransport
import com.hiddify.core.libbox.NetworkInterfaceIterator
import com.hiddify.core.libbox.Notification
import com.hiddify.core.libbox.PlatformInterface
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

    override fun useProcFS(): Boolean = platform().useProcFS()
}
