import 'dart:io';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:kern/abgleich/verbindung.dart';
import 'package:kern/abgleich/verbindungsdatei.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:workmanager/workmanager.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'lauf.dart';
import 'photo_manager_rolle.dart';
import 'stand.dart';

/// Die Sicherung, wenn die App nicht offen ist.
///
/// **Android:** eine periodische Aufgabe von WorkManager (alle 15 Minuten,
/// mit den Bedingungen WLAN und Laden aus den Einstellungen). Eine solche
/// Aufgabe darf rund zehn Minuten laufen. Geht die App mit offener Arbeit
/// in den Hintergrund, übernimmt eine einmalige Aufgabe als
/// Vordergrunddienst mit Benachrichtigung ([uebergib]) – so kommt auch die
/// erste grosse Sicherung durch.
///
/// **iOS:** eine Verarbeitungsaufgabe (`BGProcessingTask`). Wann sie läuft,
/// bestimmt das System – meist nachts am Ladekabel; sie darf dann Minuten
/// arbeiten und wird abgebrochen, wenn das Telefon gebraucht wird. Danach
/// plant sie sich neu.
///
/// Angefangene Uploads gehen beim nächsten Lauf an derselben Stelle weiter.
const sicherungsaufgabe = 'de.dasevo.photovault.sicherung';
const _uebergabe = 'de.dasevo.photovault.sicherung.weiter';

var _gestoppt = false;

@pragma('vm:entry-point')
void sicherungImHintergrund() {
  Workmanager().executeTask((aufgabe, daten) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    _gestoppt = false;
    // Android beendet eine Aufgabe nach zehn Minuten; vorher sauber
    // aufhören, damit der Stand geschrieben ist. iOS meldet das Ende
    // über onTaskStopped.
    final frist = DateTime.now().add(
      Platform.isAndroid
          ? const Duration(minutes: 9)
          : const Duration(minutes: 30),
    );
    try {
      await sichereImHintergrund(
        abbrechen: () => _gestoppt || DateTime.now().isAfter(frist),
      );
    } catch (e) {
      debugPrint('Sicherung im Hintergrund: $e');
    }
    if (Platform.isIOS) await _planeIos();
    return true;
  }, onTaskStopped: (aufgabe, grund) async => _gestoppt = true);
}

/// Ein Lauf ohne Oberfläche. Tut nichts, wenn die Sicherung aus ist, das
/// Telefon abgemeldet ist oder das Netz nicht passt.
Future<Laufbericht?> sichereImHintergrund({
  required bool Function() abbrechen,
}) async {
  final ordner = await Sitzung.vorgabeOrdner();
  final v = await Verbindungsdatei.lies(ordner);
  if (v == null) return null;
  final stand = Sicherungsstand.oeffne(ordner);
  final verbindung = Serververbindung(v.server, v.token);
  try {
    final e = stand.einstellungen;
    if (!e.an || !await netzPasst(e)) return null;
    // Ohne Activity kann photo_manager die Berechtigung nicht prüfen;
    // erteilt wurde sie in der App.
    await PhotoManager.setIgnorePermissionCheck(true);
    final lauf = Sicherungslauf(
      rolle: PhotoManagerRolle(alben: e.alben),
      verbindung: verbindung,
      stand: stand,
      wer: 'hintergrund',
    );
    // Übergibt die App gerade (siehe [uebergib]), hält ihr Lauf die
    // Sperre noch, bis sein letztes Stück angekommen ist.
    for (var versuch = 0; ; versuch++) {
      try {
        return await lauf.laufe(abbrechen: abbrechen);
      } on Gesperrt {
        if (versuch >= 12 || abbrechen()) return null;
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
  } finally {
    verbindung.schliesse();
    stand.schliesse();
  }
}

/// Ob gerade gesichert werden darf: mit „nur im WLAN“ nicht über das
/// Mobilfunknetz (ein Hotspot zählt als WLAN – das weiss das Telefon
/// nicht).
Future<bool> netzPasst(Sicherungseinstellungen e) async {
  final art = await Connectivity().checkConnectivity();
  if (art.contains(ConnectivityResult.none) || art.isEmpty) return false;
  if (!e.nurWlan) return true;
  return art.contains(ConnectivityResult.wifi) ||
      art.contains(ConnectivityResult.ethernet);
}

/// Plant (oder streicht) die Aufgabe nach [e].
Future<void> planeSicherung(Sicherungseinstellungen e) async {
  if (!e.an) {
    await Workmanager().cancelByUniqueName(sicherungsaufgabe);
    await Workmanager().cancelByUniqueName(_uebergabe);
    return;
  }
  if (Platform.isAndroid) {
    await Workmanager().registerPeriodicTask(
      sicherungsaufgabe,
      sicherungsaufgabe,
      frequency: const Duration(minutes: 15),
      constraints: _bedingungen(e),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  } else if (Platform.isIOS) {
    await _planeIos(e);
  }
}

Constraints _bedingungen(Sicherungseinstellungen e) => Constraints(
  networkType: e.nurWlan ? NetworkType.unmetered : NetworkType.connected,
  requiresCharging: e.nurBeimLaden,
  requiresBatteryNotLow: true,
);

Future<void> _planeIos([Sicherungseinstellungen? e]) async {
  e ??= await _einstellungen();
  if (e == null || !e.an) return;
  await Workmanager().registerProcessingTask(
    sicherungsaufgabe,
    sicherungsaufgabe,
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresCharging: e.nurBeimLaden,
    ),
  );
}

Future<Sicherungseinstellungen?> _einstellungen() async {
  final stand = Sicherungsstand.oeffne(await Sitzung.vorgabeOrdner());
  try {
    return stand.einstellungen;
  } finally {
    stand.schliesse();
  }
}

/// Android: Die App geht mit offener Arbeit in den Hintergrund – eine
/// einmalige Aufgabe als Vordergrunddienst macht weiter.
Future<void> uebergib(Sicherungseinstellungen e) async {
  if (!Platform.isAndroid || !e.an) return;
  final t = lookupAppTexte(_sprache());
  await Workmanager().registerOneOffTask(
    _uebergabe,
    sicherungsaufgabe,
    constraints: _bedingungen(e),
    existingWorkPolicy: ExistingWorkPolicy.keep,
    foregroundServiceConfig: ForegroundServiceConfig(
      notificationTitle: t.sicherungBenachrichtigungTitel,
      notificationText: t.sicherungBenachrichtigungText,
      notificationChannelId: 'sicherung',
      notificationChannelName: t.sicherungKanal,
      foregroundServiceType: ForegroundServiceType.dataSync,
    ),
  );
}

Locale _sprache() {
  final l = PlatformDispatcher.instance.locale;
  return AppTexte.supportedLocales.any((s) => s.languageCode == l.languageCode)
      ? Locale(l.languageCode)
      : const Locale('de');
}
