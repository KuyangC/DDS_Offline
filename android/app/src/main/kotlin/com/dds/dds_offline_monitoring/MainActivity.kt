package com.dds.dds_offline_monitoring

import android.os.Build
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.FileReader

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.dds.dds_offline_monitoring/arp"
    private val METHOD_GET_ARP_TABLE = "getArpTable"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == METHOD_GET_ARP_TABLE) {
                try {
                    val arpTable = getArpTable()
                    result.success(arpTable)
                } catch (e: Exception) {
                    result.error("ARP_ERROR", "Failed to read ARP table: ${e.message}", null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    /**
     * Reads the ARP table from /proc/net/arp
     * Returns a JSON string with array of ARP entries
     *
     * /proc/net/arp format:
     * IP address       HW type  Flags    HW address         Mask  Device
     * 192.168.1.1      0x1      0x2      aa:bb:cc:dd:ee:ff  *     wlan0
     */
    private fun getArpTable(): String {
        val arpEntries = mutableListOf<Map<String, String>>()

        try {
            val reader = BufferedReader(FileReader("/proc/net/arp"))
            var line: String?

            // Skip header line
            reader.readLine()

            while (reader.readLine().also { line = it } != null) {
                val parts = line!!.trim().split("\\s+".toRegex())
                if (parts.size >= 6) {
                    val ipAddress = parts[0]
                    val hwType = parts[1]
                    val flags = parts[2]
                    val macAddress = parts[3]
                    val mask = parts[4]
                    val device = parts[5]

                    // Skip incomplete entries (MAC address is "00:00:00:00:00:00")
                    if (macAddress != "00:00:00:00:00:00" && macAddress.length == 17) {
                        arpEntries.add(mapOf(
                            "ip" to ipAddress,
                            "mac" to macAddress.uppercase(),
                            "device" to device,
                            "flags" to flags
                        ))
                    }
                }
            }
            reader.close()
        } catch (e: Exception) {
            // Return empty list if error reading ARP table
            return "[]"
        }

        // Convert to JSON array string
        val jsonEntries = arpEntries.joinToString(",") { entry ->
            """{"ip":"${entry["ip"]}","mac":"${entry["mac"]}","device":"${entry["device"]}"}"""
        }

        return "[$jsonEntries]"
    }
}
