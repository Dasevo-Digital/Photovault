import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:kern/db/database.dart';
import '../../services/aktualisierungspruefung.dart';
import '../../services/kachelvorrat.dart';
import '../../services/library_location.dart';
import '../../services/storage_paths.dart';
import '../../state/library_state.dart';
import '../../widgets/eigene_karte_einstellung.dart';

/// Die Abfragen, die [Einstellungsstand.einmal] zwischenspeichert.
enum EinstellungsAbfrage { autoanalyse, kiTags, datenschutz, uebersetzung }

/// Was die Gruppen der Einstellungen gemeinsam brauchen – und alles, was
/// das Zuklappen einer Gruppe überdauern muss.
///
/// **Warum der Zustand nicht in den Gruppen liegt.** Eine Gruppe baut ihren
/// Inhalt erst beim Aufklappen und verwirft ihn beim Zuklappen (siehe
/// `_Gruppe.inhalt` im Bildschirm). Läge das Häkchen „verschlüsseln“ oder
/// ein halb getippter Schlüssel in der Gruppe, wäre es beim Wiederöffnen
/// weg; das Vorladen der Kartenkacheln bräche ab. Deshalb gehört dieser
/// Stand dem Bildschirm, wie vor der Aufteilung (#41), und die Gruppen
/// lesen und ändern ihn nur.
///
/// **Warum die Abläufe den Kontext des Bildschirms nehmen.** Beim
/// Sprachwechsel ändern sich die Gruppentitel, und damit baut die App jede
/// Gruppe neu – die Rückfrage zum Vokabular muss das überdauern. [kontext]
/// und [aktiv] sind deshalb die des Bildschirms, nicht der Gruppe.
///
/// [aendere] steht für das `setState` des Bildschirms: Es meldet die
/// Änderung, und der Bildschirm baut sich neu – genau wie vorher.
class Einstellungsstand extends ChangeNotifier {
  Einstellungsstand(
    this.library, {
    required this._kontext,
    required this._aktiv,
  }) {
    refresh();
    isCustomLocationFuture = LibraryLocation.isCustom;
    bibliothekenFuture = LibraryLocation.bekannte();
    ueberwachterOrdnerFuture = library.db.ueberwachterOrdner();
    versionFuture = PackageInfo.fromPlatform();
    hasPinSetFuture = library.db.hasPinSet();
    hasBackupKeyFuture = library.db.hasBackupKey();
    backupSettingsFuture = library.db.backupSettingsRow();
    trashSettingsFuture = library.db.trashSettingsRow();
    library.addListener(_bibliothekMeldet);
  }

  final LibraryState library;
  final BuildContext Function() _kontext;
  final bool Function() _aktiv;

  /// Der Kontext des Bildschirms – für Dialoge, Meldungen und Navigation.
  BuildContext get kontext => _kontext();

  /// Ob der Bildschirm noch steht (sein `mounted`).
  bool get aktiv => _aktiv();

  /// Ändert den Stand und baut den Bildschirm neu.
  void aendere(VoidCallback aenderung) {
    aenderung();
    notifyListeners();
  }

  @override
  void dispose() {
    // Ohne das läuft das Vorladen weiter, nachdem der Bildschirm zu ist –
    // und `setState` auf einem abgeräumten Zustand wirft.
    vorratLauf?.cancel();
    library.removeListener(_bibliothekMeldet);
    aiTagVocabularyController.dispose();
    cartoSchluessel.dispose();
    super.dispose();
  }

  /// Der Griff zum Formular für die eigene Kartenquelle. Über ihn
  /// schreibt die Quellenübersicht darüber eine Vorlage hinein und
  /// scrollt sie ins Bild.
  final eigeneKarte = GlobalKey<EigeneKarteEinstellungState>();

  /// Was die Bibliothek belegt – aufgeschlüsselt, nicht nur die
  /// Originale. Siehe [StoragePaths.belegung].
  Bibliotheksbelegung? belegung;
  BackupRecordData? lastBackup;
  final Set<String> downloading = {};

  /// Wo die Reihe steht, wenn alle fehlenden Modelle am Stueck geholt
  /// werden: (das wievielte, wie viele). `null`, wenn keine Reihe laeuft.
  (int, int)? reihenstand;
  bool encryptManualBackup = false;
  bool downloadingGeoData = false;
  double geoDataProgress = 0;
  final TextEditingController aiTagVocabularyController =
      TextEditingController();

  /// Der eingetippte CARTO-Schlüssel.
  ///
  /// Nicht an einen `StreamBuilder` gebunden: Ein Feld, dessen Inhalt bei
  /// jedem Datenbankereignis von aussen neu gesetzt wird, springt beim
  /// Tippen mit dem Textzeiger. Der gespeicherte Wert wird einmal
  /// hineingeschrieben (siehe karte.dart), danach gehört das Feld dem
  /// Nutzer.
  final TextEditingController cartoSchluessel = TextEditingController();
  bool cartoGeladen = false;

  // Als Felder statt inline im FutureBuilder erzeugt: ein dort direkt
  // aufgerufenes `future: someQuery()` würde bei JEDEM Rebuild dieses
  // Screens (z.B. durch den App-weiten Consumer<LibraryState>) ein neues
  // Future anstoßen und den jeweiligen FutureBuilder kurz in den Ladezustand
  // zurückfallen lassen. Gezielt per reloadX() nach den Aktionen aktualisiert,
  // die den jeweiligen Wert tatsächlich ändern können.
  late Future<bool> isCustomLocationFuture;
  late Future<bool> hasPinSetFuture;
  late Future<bool> hasBackupKeyFuture;
  late Future<BackupSettingsData?> backupSettingsFuture;
  late Future<TrashSettingsData?> trashSettingsFuture;
  late Future<List<BibliothekMitZustand>> bibliothekenFuture;
  late Future<({String pfad, String? token})?> ueberwachterOrdnerFuture;
  late Future<PackageInfo> versionFuture;
  Aktualisierungsstand? aktualisierungsstand;
  String? aktualisierungsfehler;
  bool pruefeAktualisierung = false;

  /// Läuft gerade ein Vorladen der Kartenkacheln? Dann steht hier der Stand.
  Vorratsstand? vorrat;
  StreamSubscription<Vorratsstand>? vorratLauf;

  /// Ob die Karte in doppelter Auflösung zeichnet. Beim Aufbau der
  /// Kartengruppe aus der Einstellung geholt (siehe karte.dart).
  bool karteScharf = true;
  bool karteScharfGeladen = false;

  /// Die Bibliothek meldet sich beim Beginn und Ende einer Analyse. Dabei
  /// kann sich die Zahl der KI-Schlagwörter ändern; die Schalter nicht.
  void _bibliothekMeldet() {
    if (aktiv) neuFragen(EinstellungsAbfrage.kiTags);
  }

  /// Abfragen, die die einzelnen Schalter brauchen, je Schlüssel einmal.
  ///
  /// Dasselbe wie die Felder oben, nur ohne je ein eigenes Feld: Bis hier
  /// standen fünf Schalter noch mit `future: abfrage()` direkt im Aufbau
  /// und fragten bei jedem Tastendruck in der Einstellungssuche neu – und
  /// zeigten dazwischen kurz ihren Vorgabewert statt des echten.
  final _abfragen = <Object, Future<Object?>>{};

  Future<T> einmal<T>(Object schluessel, Future<T> Function() abfrage) =>
      (_abfragen[schluessel] ??= abfrage()) as Future<T>;

  /// Fragt [schluessel] beim nächsten Aufbau neu – nach einer Änderung.
  ///
  /// Hier und in den `reload…` darunter steht der Rückruf als Block, nicht
  /// als `=> …`: `remove` und eine Zuweisung liefern ihren Wert, hier ein
  /// Future, und ein setState-Rückruf, der ein Future liefert, bricht im
  /// Debug-Modus mit einer Assertion ab. In der ausgelieferten App sind
  /// Assertions aus; aufgefallen ist es erst beim Test jeder Gruppe (#41).
  void neuFragen(Object schluessel) => aendere(() {
    _abfragen.remove(schluessel);
  });

  void reloadPinState() => aendere(() {
    hasPinSetFuture = library.db.hasPinSet();
  });
  void reloadBackupKeyState() => aendere(() {
    hasBackupKeyFuture = library.db.hasBackupKey();
  });
  void reloadBackupSettings() => aendere(() {
    backupSettingsFuture = library.db.backupSettingsRow();
  });
  void reloadTrashSettings() => aendere(() {
    trashSettingsFuture = library.db.trashSettingsRow();
  });

  Future<void> refresh() async {
    final belegt = await library.paths.belegung();
    final last = await library.db.lastBackupRecord();
    if (aktiv) {
      aendere(() {
        belegung = belegt;
        lastBackup = last;
      });
    }
  }
}
