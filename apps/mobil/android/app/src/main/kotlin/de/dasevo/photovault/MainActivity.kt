package de.dasevo.photovault

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FragmentActivity: Die App-Sperre (local_auth, #376) braucht sie für den
// Dialog zum Fingerabdruck.
class MainActivity : FlutterFragmentActivity() {
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
                    // App-Sperre (#376): kein Bild im Umschalter, keine
                    // Bildschirmfotos, solange sie an ist.
                    "abdeckung" -> {
                        if (aufruf.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        antwort.success(null)
                    }
                    "akkuFrei" -> antwort.success(akkuFrei)
                    "akkuFreigeben" -> {
                        // Ein zweiter Tipp, solange der Dialog aufgeht.
                        akkuAntwort?.success(akkuFrei)
                        akkuAntwort = antwort
                        try {
                            @Suppress("BatteryLife")
                            startActivityForResult(
                                Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName"),
                                ),
                                AKKU_ANFRAGE,
                            )
                        } catch (_: ActivityNotFoundException) {
                            // Nicht jeder Hersteller hat diesen Dialog.
                            akkuAntwort = null
                            antwort.success(akkuFrei)
                        }
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
