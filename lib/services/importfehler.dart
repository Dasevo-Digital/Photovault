import 'dart:io';

import 'package:kern/abgleich/verbindung.dart';

import '../l10n/app_localizations.dart';

/// Ein Satz dazu, woran eine Datei oder ein ganzer Lauf scheiterte (#335) –
/// aus dem, was [ImportProgress.grund] mitbringt.
///
/// Eine Kennung kann als Ausnahme kommen oder als Text: als Text etwa vom
/// Server, der den Grund in einer Kopfzeile weiterreicht. Beides wird
/// gleich übersetzt (IMP-028).
String importFehlertext(AppTexte t, Object? grund) => switch (grund) {
  null || '' => t.importFehlerUnbekannt,
  KeineVerbindung() => t.importFehlerKeineVerbindung,
  Serverfehler(:final status, :final text) => t.importFehlerServer(
    status,
    _kurzerServertext(text),
  ),
  FormatException(:final message) => _kennungstext(t, message),
  FileSystemException(:final message, :final osError) =>
    osError == null ? message : '$message (${osError.message})',
  final String text => _kennungstext(t, text),
  _ => '$grund',
};

/// Bekannte Kennungen als Satz, alles andere unverändert. Ältere Server
/// schicken die Kennung noch mit dem Namen der Ausnahme davor; gelesen wird
/// deshalb die Kennung am Ende des Textes.
String _kennungstext(AppTexte t, String text) {
  final kennung = RegExp(r'pv_[a-z0-9_]+$').firstMatch(text)?.group(0);
  return switch (kennung) {
    'pv_import_quelle_geaendert' => t.importFehlerQuelleGeaendert,
    'pv_import_regeln_geaendert' ||
    'pv_import_auswahl' => t.importPlanGeaendert,
    'pv_import_server_zu_alt' => t.importPlanServerAlt,
    _ => text,
  };
}

/// Aus der Antwort eines Servers oder Proxys das Wesentliche: der Titel
/// einer HTML-Fehlerseite, der Text eines JSON-Fehlers, sonst der Anfang.
String _kurzerServertext(String text) {
  final titel = RegExp(
    r'<title>(.*?)</title>',
    caseSensitive: false,
    dotAll: true,
  ).firstMatch(text);
  if (titel != null) return titel.group(1)!.trim();
  final json = RegExp(r'"fehler"\s*:\s*"([^"]*)"').firstMatch(text);
  if (json != null) return json.group(1)!;
  final rein = text
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return rein.length > 80 ? '${rein.substring(0, 80)} …' : rein;
}
