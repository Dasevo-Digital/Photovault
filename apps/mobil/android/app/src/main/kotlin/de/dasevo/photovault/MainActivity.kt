package de.dasevo.photovault

import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var akkuAntwort: MethodChannel.Result? = null

    private val akkuFrei: Boolean
        get() =
            getSystemService(PowerManager::class.java)
                .isIgnoringBatteryOptimizations(packageName)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Neue Fotos gleich sichern (lib/sicherung/sofort.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "de.dasevo.photovault/gemeinsam")
            .setMethodCallHandler { aufruf, antwort ->
                when (aufruf.method) {
                    "sofort" -> {
                        val an = aufruf.argument<Boolean>("an") == true
                        Fotowaechter.stelle(
                            applicationContext,
                            an,
                            nurWlan = aufruf.argument<Boolean>("nurWlan") != false,
                            nurBeimLaden = aufruf.argument<Boolean>("nurBeimLaden") == true,
                        )
                        antwort.success(if (an) "an" else "aus")
                    }
                    "akkuFrei" -> antwort.success(akkuFrei)
                    "akkuFreigeben" -> {
                        akkuAntwort = antwort
                        @Suppress("BatteryLife")
                        startActivityForResult(
                            Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName"),
                            ),
                            AKKU_ANFRAGE,
                        )
                    }
                    else -> antwort.notImplemented()
                }
            }
    }

    @Deprecated("Der Kanal braucht das Ergebnis des Systemdialogs.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == AKKU_ANFRAGE) {
            akkuAntwort?.success(akkuFrei)
            akkuAntwort = null
        }
    }

    private companion object {
        const val AKKU_ANFRAGE = 4711
    }
}
