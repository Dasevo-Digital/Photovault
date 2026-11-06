package de.dasevo.photovault

import android.content.Context
import android.provider.MediaStore
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import dev.fluttercommunity.workmanager.BackgroundWorker
import java.util.concurrent.TimeUnit

/**
 * Wartet auf neue Fotos und Videos im MediaStore und startet die Sicherung,
 * statt bis zur nächsten periodischen Aufgabe zu warten (#308).
 *
 * Ein Auslöser auf Inhalte gilt nur einmal und lässt sich nicht periodisch
 * planen; darum stellt sich der Wächter nach jedem Treffer neu. Gesichert
 * wird in der Aufgabe von workmanager (hintergrund.dart), mit denselben
 * Bedingungen wie dort.
 */
class Fotowaechter(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val nurWlan = inputData.getBoolean(NUR_WLAN, true)
        val nurBeimLaden = inputData.getBoolean(NUR_BEIM_LADEN, false)
        val lauf =
            OneTimeWorkRequestBuilder<BackgroundWorker>()
                .setInputData(workDataOf(BackgroundWorker.DART_TASK_KEY to SICHERUNG))
                .setConstraints(bedingungen(nurWlan, nurBeimLaden))
                .build()
        // Läuft gerade ein Lauf, kennt er das neue Foto womöglich nicht
        // mehr: Der nächste schliesst sich an.
        WorkManager.getInstance(applicationContext)
            .enqueueUniqueWork(LAUF, ExistingWorkPolicy.APPEND_OR_REPLACE, lauf)
        reihe(applicationContext, nurWlan, nurBeimLaden, ExistingWorkPolicy.APPEND_OR_REPLACE)
        return Result.success()
    }

    companion object {
        private const val WAECHTER = "de.dasevo.photovault.sicherung.waechter"
        private const val LAUF = "de.dasevo.photovault.sicherung.sofort"

        /** Der Name der Aufgabe in hintergrund.dart. */
        private const val SICHERUNG = "de.dasevo.photovault.sicherung"
        private const val NUR_WLAN = "nurWlan"
        private const val NUR_BEIM_LADEN = "nurBeimLaden"

        private fun bedingungen(nurWlan: Boolean, nurBeimLaden: Boolean) =
            Constraints.Builder()
                .setRequiredNetworkType(
                    if (nurWlan) NetworkType.UNMETERED else NetworkType.CONNECTED,
                )
                .setRequiresCharging(nurBeimLaden)
                .setRequiresBatteryNotLow(true)
                .build()

        private fun reihe(
            context: Context,
            nurWlan: Boolean,
            nurBeimLaden: Boolean,
            art: ExistingWorkPolicy,
        ) {
            val ausloeser =
                Constraints.Builder()
                    .addContentUriTrigger(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true)
                    .addContentUriTrigger(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, true)
                    // Eine Serie kommt in Schüben.
                    .setTriggerContentUpdateDelay(3, TimeUnit.SECONDS)
                    .setTriggerContentMaxDelay(20, TimeUnit.SECONDS)
                    .build()
            val waechter =
                OneTimeWorkRequestBuilder<Fotowaechter>()
                    .setInputData(
                        workDataOf(NUR_WLAN to nurWlan, NUR_BEIM_LADEN to nurBeimLaden),
                    )
                    .setConstraints(ausloeser)
                    .build()
            WorkManager.getInstance(context).enqueueUniqueWork(WAECHTER, art, waechter)
        }

        /** Stellt den Wächter nach den Einstellungen – oder hebt ihn auf. */
        fun stelle(context: Context, an: Boolean, nurWlan: Boolean, nurBeimLaden: Boolean) {
            if (an) {
                reihe(context, nurWlan, nurBeimLaden, ExistingWorkPolicy.REPLACE)
            } else {
                val wm = WorkManager.getInstance(context)
                wm.cancelUniqueWork(WAECHTER)
                wm.cancelUniqueWork(LAUF)
            }
        }
    }
}
