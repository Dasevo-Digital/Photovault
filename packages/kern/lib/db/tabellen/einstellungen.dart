part of '../database.dart';

// Tabellen: Einstellungen, Sicherung, Papierkorb, Aufgabenläufe.

/// Wann eine Hintergrundaufgabe zuletzt vollständig durchgelaufen ist
/// (Issue #15).
///
/// **Wozu.** Manche Aufgaben haben je Aufnahme keine Notiz „angesehen“ –
/// der Dateiarten-Lauf etwa liest jedes Video, und die Live-Photo-Suche
/// jedes Foto ohne Partner. Ihre Zahl blieb deshalb nach jedem Lauf gleich
/// hoch, obwohl er nichts mehr zu tun hatte. Mit dem Zeitpunkt zählt die
/// Karte danach nur, was seitdem dazugekommen ist.
class Aufgabenlaeufe extends Table {
  TextColumn get schluessel => text()();
  DateTimeColumn get fertigAm => dateTime()();

  @override
  Set<Column> get primaryKey => {schluessel};
}

/// Einzeilige Tabelle (id immer 0) für den PIN-Schutz des gesperrten
/// Ordners – "Envelope Encryption": ein zufälliger Master-Key verschlüsselt
/// tatsächlich die Dateien (siehe VaultCrypto), der PIN verschlüsselt nur
/// diesen Master-Key (über Argon2id abgeleitet). Es wird nie der PIN selbst
/// gespeichert; die einzige PIN-Prüfung ist der Versuch, den Master-Key
/// damit zu entpacken (schlägt bei falschem PIN durch die
/// GCM-Authentifizierung fehl). `pinHash`/`pinSalt` sind Altlasten aus einer
/// früheren, rein anzeige-filternden (nicht verschlüsselnden) Version und
/// werden nicht mehr genutzt.
@DataClassName('PrivacySettingsData')
class PrivacySettings extends Table {
  IntColumn get id => integer()();
  TextColumn get pinHash => text().nullable()();
  TextColumn get pinSalt => text().nullable()();
  BlobColumn get kdfSalt => blob().nullable()();
  BlobColumn get wrappedMasterKeyNonce => blob().nullable()();
  BlobColumn get wrappedMasterKey => blob().nullable()();

  /// Entfernt bei neu gesperrten Aufnahmen zusätzlich lesbare Angaben aus
  /// der SQLite-Datei. Die Werte liegen dann authentifiziert verschlüsselt
  /// neben den ebenfalls verschlüsselten Mediendateien und kehren erst beim
  /// dauerhaften Entsperren zurück.
  BoolColumn get protectMetadata =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BackupRecordData')
class BackupRecords extends Table {
  TextColumn get id => text()();
  DateTimeColumn get performedAt => dateTime()();
  TextColumn get destinationPath => text()();
  IntColumn get fileCount => integer()();
  IntColumn get totalBytes => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Einzeilige Tabelle (id immer 0) für die Backup-Verschlüsselung: derselbe
/// Envelope-Ansatz wie [PrivacySettings], aber mit eigenem Master-Key und
/// eigener Passphrase (bewusst getrennt vom PIN des gesperrten Ordners –
/// ein Backup landet oft extern, z.B. in einem Cloud-Sync-Ordner, und muss
/// unabhängig von der lokalen Bibliothek entschlüsselbar sein). Der
/// verpackte Schlüssel wird deshalb zusätzlich als kleine Datei ins Backup
/// selbst geschrieben (siehe BackupService), nicht nur hier lokal.
///
/// [autoBackupEnabled]/[autoBackupDestination]/[autoBackupIntervalHours]/
/// [lastAutoBackupAt] konfigurieren das automatische Backup (läuft nur,
/// während die App offen ist – kein Hintergrunddienst).
@DataClassName('BackupSettingsData')
class BackupSettings extends Table {
  IntColumn get id => integer()();
  BlobColumn get kdfSalt => blob().nullable()();
  BlobColumn get wrappedMasterKeyNonce => blob().nullable()();
  BlobColumn get wrappedMasterKey => blob().nullable()();

  BoolColumn get autoBackupEnabled =>
      boolean().withDefault(const Constant(false))();
  TextColumn get autoBackupDestination => text().nullable()();
  IntColumn get autoBackupIntervalHours =>
      integer().withDefault(const Constant(24))();
  DateTimeColumn get lastAutoBackupAt => dateTime().nullable()();

  /// Obergrenze je Sicherungslauf in Megabyte, 0 = unbegrenzt.
  ///
  /// Gedacht für Cloud-Ordner: Ohne Grenze landen bei der ersten Sicherung
  /// zigtausend Dateien auf einmal im Sync-Ordner, und der Upload läuft
  /// danach stunden- bis tagelang. Mit Grenze wird portionsweise gesichert,
  /// der Rest folgt beim nächsten Intervall.
  IntColumn get autoBackupMaxMbPerRun =>
      integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Einzeilige Tabelle (id immer 0) für den automatischen Papierkorb-Ablauf:
/// löscht in den Papierkorb verschobene Assets nach [autoDeleteAfterDays]
/// Tagen endgültig (Dateien + DB-Zeile) – läuft, wie das automatische
/// Backup, nur während die App geöffnet ist (siehe
/// [LibraryState.purgeExpiredTrashIfDue]). Standardmäßig deaktiviert, damit
/// niemand unerwartet Fotos verliert, die "nur eben" im Papierkorb lagen.
@DataClassName('TrashSettingsData')
class TrashSettings extends Table {
  IntColumn get id => integer()();
  BoolColumn get autoDeleteEnabled =>
      boolean().withDefault(const Constant(false))();
  IntColumn get autoDeleteAfterDays =>
      integer().withDefault(const Constant(30))();
  DateTimeColumn get lastPurgeAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Einzeilige Tabelle (id immer 0, gleiches Muster wie [TrashSettings]) für
/// app-weite Oberflächen-Einstellungen – aktuell nur das Erscheinungsbild.
/// [themeMode] als Text ('system'|'light'|'dark') statt als Enum-Index
/// gespeichert, damit eine künftige Umsortierung von [ThemeMode] die
/// gespeicherte Bedeutung nicht verschiebt.
@DataClassName('AppSettingsData')
class AppSettings extends Table {
  IntColumn get id => integer()();
  TextColumn get themeMode => text().withDefault(const Constant('system'))();

  /// Oberflächensprache: `'system'`, `'de'` oder `'en'`.
  ///
  /// Dasselbe Muster wie [themeMode], und aus demselben Grund als Text
  /// statt als Aufzählung: Eine unbekannte Angabe (etwa aus einer
  /// neueren Fassung) fällt beim Lesen auf den Standard zurück, statt
  /// den Start zu verhindern.
  TextColumn get sprache => text().withDefault(const Constant('system'))();

  /// Ob die rechenintensiven KI-Auswertungen (Gesichter, Texterkennung,
  /// CLIP, Bildbeschreibung, Unschärfe) nach einem Import automatisch als
  /// Hintergrundaufgabe nachlaufen. Standard an – sonst blieben frisch
  /// importierte Fotos ohne Suche und ohne Personenzuordnung, bis jemand
  /// die Werkzeuge von Hand anstößt.
  BoolColumn get autoAnalyzeAfterImport =>
      boolean().withDefault(const Constant(true))();

  /// Ordner, der laufend auf neue Dateien geprüft wird (siehe
  /// LibraryState.pruefeUeberwachtenOrdner). Null = keiner eingerichtet.
  ///
  /// Der Zugriff braucht unter macOS zusätzlich das Sandbox-Merkmal aus der
  /// Ordnerauswahl, sonst erlischt er beim nächsten Programmstart – deshalb
  /// beide Angaben zusammen, wie bei den Bibliotheksorten auch.
  TextColumn get watchedFolderPath => text().nullable()();
  TextColumn get watchedFolderToken => text().nullable()();

  /// Allgemeine Schwelle für "dasselbe Gesicht" (Kosinus-Ähnlichkeit).
  ///
  /// 0,363 ist der von OpenCV Zoo für SFace dokumentierte Wert. Die
  /// Einstellung lag bisher nur im Speicher – der Regler unter "Werkzeuge"
  /// war bei jedem Programmstart wieder auf dem Ausgangswert, ohne dass
  /// das irgendwo stand.
  RealColumn get faceSimilarityThreshold =>
      real().withDefault(const Constant(0.363))();

  /// Ab welcher Sicherheit die Wiedererkennung einen Vorschlag von selbst
  /// übernimmt (Issue #135). `null` heisst: nie – jeder Vorschlag wartet
  /// auf ein Ja. Auch mit Schwelle bleiben unsichere Treffer Vorschläge.
  RealColumn get vorschlaegeAutomatischAb => real().nullable()();

  /// Zuletzt gewählte Kartenansicht: `'hell'`, `'dunkel'`, `'topo'` oder
  /// `'globus'` (siehe `Kartenansicht` in map_screen.dart).
  ///
  /// Als Text und nicht als Zahl, aus demselben Grund wie bei [themeMode]:
  /// Eine unbekannte Angabe fällt beim Lesen auf die dunkle Karte zurück,
  /// statt den Start zu verhindern.
  ///
  /// Die Wahl lag bisher nur im Bildschirmzustand. Wer die
  /// Topografiekarte einstellte und die Ansicht verliess, fand beim
  /// nächsten Öffnen wieder die dunkle vor - ohne dass das irgendwo
  /// stand. Derselbe Fall wie seinerzeit bei
  /// [faceSimilarityThreshold].
  TextColumn get kartenansicht =>
      text().withDefault(const Constant('dunkel'))();

  /// Schlüssel für die CARTO-Kacheln der dunklen Karte. Null = keiner.
  ///
  /// **Warum das überhaupt eine Einstellung ist.** CARTO hat die
  /// kostenlose Nutzung ohne Schlüssel beendet und schreibt seither
  /// quer über jede einzelne Kachel „API KEY REQUIRED" – auf jeder
  /// Zoomstufe, auch über den alten Fastly-Namen. Nachgemessen an einer
  /// Kachel Berlin-Mitte, Stufen 10 bis 20: der Stempel steht auf allen.
  ///
  /// Ohne Schlüssel zeichnet die dunkle Karte deshalb invertierte
  /// OpenStreetMap-Kacheln (siehe `Kartenstil.dunkel`). Wer den
  /// gewohnten Dark-Matter-Schnitt zurückwill, trägt hier seinen
  /// Schlüssel ein – CARTO gibt ihn kostenlos und **ohne Konto** aus,
  /// bis zu 5 Millionen Kacheln im Monat.
  ///
  /// In der Datenbank und nicht im Quelltext, und das ist der Punkt:
  /// Ein mitgelieferter Schlüssel wäre über den öffentlichen Spiegel
  /// für jeden lesbar und liefe auf eine Zugangskennung im Repository
  /// hinaus. Er gehört dem, der ihn beantragt.
  TextColumn get cartoSchluessel => text().nullable()();

  /// Anzeigename der eigenen Kartenquelle, z. B. „Mapbox Streets".
  ///
  /// **Warum es diese Quelle überhaupt gibt.** Die drei mitgelieferten
  /// Stile hängen an frei betriebenen Servern: OpenStreetMap trägt bis
  /// Zoomstufe 19, OpenTopoMap nur bis 17. Wer Hausnummern und
  /// Gebäudeumrisse braucht oder ein Luftbild, kommt an einem
  /// Anbieter mit Schlüssel nicht vorbei – und der gehört dem, der ihn
  /// beantragt, genau wie beim CARTO-Schlüssel.
  ///
  /// Als vier lose Spalten und nicht als Tabelle: Es ist **eine**
  /// Quelle, nicht eine Liste. Wer zwischen mehreren wechseln will,
  /// tauscht die Angaben – eine Verwaltung mit Anlegen, Umbenennen und
  /// Löschen wäre für einen einzigen Eintrag zu viel Maschine.
  TextColumn get eigeneKarteName => text().nullable()();

  /// Adressvorlage der eigenen Kartenquelle, mit `{z}`, `{x}`, `{y}`.
  ///
  /// Der Schlüssel steht **mit in dieser Adresse** und nicht in einer
  /// eigenen Spalte. Das ist Absicht: Jeder Anbieter hängt ihn woanders
  /// hin – Mapbox als `?access_token=`, MapTiler als `?key=`,
  /// Thunderforest als `?apikey=`, Google als `?session=…&key=`. Eine
  /// eigene Spalte müsste all diese Formen kennen und wäre bei jedem
  /// weiteren Anbieter wieder falsch.
  TextColumn get eigeneKarteUrl => text().nullable()();

  /// Die Namensnennung, die unter der eigenen Karte stehen muss.
  ///
  /// Keine Zierde, sondern die Lizenzauflage praktisch jedes Anbieters.
  /// Deshalb ist sie ein Pflichtfeld in der Einstellung: Ohne sie lässt
  /// sich die Quelle nicht einschalten.
  TextColumn get eigeneKarteNennung => text().nullable()();

  /// Höchste Stufe, für die der eigene Anbieter echte Kacheln liefert.
  ///
  /// Ohne Angabe gilt 19. Zu hoch angesetzt heisst: leere oder
  /// einfarbige Kacheln, ohne Fehlermeldung – genau die Falle, die bei
  /// OpenTopoMap gemessen wurde (siehe `Kartenstil.topo`).
  IntColumn get eigeneKarteStufe => integer().nullable()();

  /// Ob der Hinweis zu Datenübermittlung und Offline-Nutzung bestätigt
  /// wurde.
  ///
  /// **Ein eigener Wert und keine blosse Dialogfrage**, weil er etwas
  /// anderes bedeutet als „Adresse eingetragen": Diese App holt ihre
  /// Kacheln sonst von Servern, die niemandem Rechenschaft schulden.
  /// Eine Fremdquelle mit Schlüssel sieht dagegen jede angesehene
  /// Stelle **und** weiss, wer hinsieht. Wer das einschaltet, soll es
  /// einmal ausdrücklich gelesen haben – und nicht bei jedem Start neu
  /// gefragt werden.
  BoolColumn get eigeneKarteZugestimmt =>
      boolean().withDefault(const Constant(false))();

  /// Ob die Karte auf einem Bildschirm mit doppelter Punktdichte auch in
  /// doppelter Auflösung zeichnet.
  ///
  /// **Ein Handel, und beide Seiten sind gemessen.** Eine Kachel ist 256
  /// Pixel breit und wird auf 256 Punkte gezeichnet – auf einem
  /// Retina-Schirm also auf 512 Gerätepunkte, jeder Kachelpixel deckt
  /// vier. Dagegen holt die Karte vier Kacheln der nächsttieferen Stufe
  /// und setzt sie an die Stelle einer: viermal so viele Bildpunkte auf
  /// derselben Fläche (Schärfe bei Topo z16 von 11,70 auf 44,27), aber
  /// eben auch **2,6-mal so viele Kacheln je Bildschirm** – auf einem
  /// 1440×900-Fenster 165 statt 63. Jede davon ist ein Griff auf die
  /// Platte und ein Dekodiervorgang, und beim Zoomen fallen sie alle auf
  /// einmal an.
  ///
  /// Vorgabe an: Schärfe ist der Regelfall. Wer eine langsamere Maschine
  /// hat oder viel zoomt, schaltet sie ab und bekommt die Karte von
  /// vorher.
  BoolColumn get karteHochaufloesend =>
      boolean().withDefault(const Constant(true))();

  /// Welche Tageszeit über der Geländeansicht steht – als Nummer aus
  /// [Tageszeit].
  ///
  /// Als Zahl und nicht als Name, aus demselben Grund wie beim
  /// Kartenstil: Ein Name aus einer aelteren Fassung koennte einer sein,
  /// den es nicht mehr gibt. Eine Nummer ausserhalb der Reihe faellt
  /// ueber [tageszeit] auf die Vorgabe zurueck.
  IntColumn get gelaendeStimmungNr =>
      integer().withDefault(Constant(lichtstimmungVorgabe.index))();

  /// Was unter der Landschaft liegt – als Nummer aus [Gelaendegrund].
  ///
  /// **Vorgabe Luftbild und nicht die Wanderkarte, die es bisher als
  /// einzige gab.** Das ist eine sichtbare Aenderung fuer alle, und sie
  /// ist Absicht: Eine Wanderkarte in Schraeglage beantwortet „wie hiess
  /// der Weg"; ein Luftbild beantwortet „wie sah es dort aus", und das
  /// ist die Frage, wegen der jemand einen Ueberflug ansieht. Zurueck
  /// geht es mit einem Griff ins Kartenmenue.
  IntColumn get gelaendeGrundNr =>
      integer().withDefault(Constant(Gelaendegrund.luftbild.index))();

  /// Ob die Wanderwege ueber der Landschaft liegen.
  ///
  /// **Vorgabe an, und der Grund steht in einer Kachel.** An der echten
  /// Kachel des Ilsetals nachgesehen (51,8433 N / 10,6553 O, Stufe 17):
  /// Das Luftbild zeigt dichten Wald – der Weg, auf dem die Wanderung
  /// verlief, ist darauf NICHT zu sehen. Ohne diese Ebene waere das
  /// Luftbild als Wanderkarte unbrauchbar.
  BoolColumn get gelaendeWege => boolean().withDefault(const Constant(true))();

  /// Ob Strassen, Grenzen und Ortsnamen darueber liegen.
  BoolColumn get gelaendeBeschriftung =>
      boolean().withDefault(const Constant(true))();

  /// Ob Hoehenlinien eingezeichnet werden.
  ///
  /// Sie werden nicht geladen, sondern aus demselben Hoehengitter
  /// gerechnet, aus dem die Landschaft gebaut ist (siehe
  /// `hoehenlinien.dart`) – sie kosten also keinen einzigen Abruf und
  /// koennen gar nicht neben dem Hang liegen, den sie beschreiben.
  BoolColumn get gelaendeHoehenlinien =>
      boolean().withDefault(const Constant(true))();

  /// Ob Gipfel, Huetten und Quellen als Schilder ueber der Landschaft
  /// stehen.
  ///
  /// **Eigener Schalter und nicht an [gelaendeBeschriftung] gehaengt.**
  /// Die anderen Ebenen sind Kacheln von einem Auslieferungsnetz; diese
  /// hier kostet eine Abfrage bei Overpass, einem oeffentlichen Dienst
  /// mit Grenzen. Wer sie nicht braucht, soll ihn nicht fragen muessen.
  BoolColumn get gelaendeWanderobjekte =>
      boolean().withDefault(const Constant(true))();

  /// Ob ein Video oder ein Live Photo von selbst anlaeuft, wenn die Maus
  /// einen Augenblick darauf stehen bleibt.
  ///
  /// Vorgabe an: Es ist der Grund, warum es die Einstellung gibt. Wer die
  /// Bewegung im Raster nicht mag oder auf einer langsamen Maschine
  /// sitzt, schaltet sie ab und bekommt die stillen Kacheln von vorher.
  ///
  /// Der Ton bleibt in jedem Fall aus – siehe
  /// [Schwebevorschau.starte]. Eine Wand aus Kacheln, die beim
  /// Ueberstreichen zu toenen anfaengt, waere niemandem eine Hilfe.
  BoolColumn get schwebeVorschau =>
      boolean().withDefault(const Constant(true))();

  /// Welche Ansicht des Stammbaums zuletzt offen war und wer darin in der
  /// Mitte stand.
  ///
  /// Sechs Ansichten (Baum, Fächer, Sanduhr, Nachfahren, Verwandte,
  /// Zeitleiste) und je nach Familie hunderte Personen: Wer den
  /// Stammbaum schliesst und wieder aufschlägt, fing bis hierher jedes
  /// Mal beim Baum und bei der Person mit den meisten Verwandten an.
  ///
  /// Als Text und nullbar, aus demselben Grund wie bei [kartenansicht]:
  /// Eine Ansicht, die es nicht mehr gibt, oder eine Person, die
  /// gelöscht wurde, fällt beim Lesen auf die bisherige Wahl zurück,
  /// statt den Bildschirm zu verhindern.
  TextColumn get stammbaumAnsicht => text().nullable()();
  TextColumn get stammbaumPerson => text().nullable()();

  /// Wie der Lebensbaum zuletzt aussah: Richtung und Stil als Name, die
  /// Generationen als Zahl. Nullbar und als Text aus demselben Grund wie
  /// [stammbaumAnsicht] – ein Name, den es nicht mehr gibt, fällt beim
  /// Lesen auf die Vorgabe zurück.
  TextColumn get lebensbaumRichtung => text().nullable()();
  TextColumn get lebensbaumStil => text().nullable()();
  IntColumn get lebensbaumGenerationen => integer().nullable()();

  /// Wie weit der Lebensbaum „Familie" reicht: Generationen darüber und
  /// darunter und der Kreis der Verwandtschaft als Name aus
  /// `Verwandtenkreis`. `null` heisst Vorgabe – so weit wie der Zierbaum,
  /// die ganze Familie.
  IntColumn get lebensbaumFamilieOben => integer().nullable()();
  IntColumn get lebensbaumFamilieUnten => integer().nullable()();
  TextColumn get lebensbaumFamilieKreis => text().nullable()();

  /// Wie gross die Kacheln der Zeitleiste sind – als Stufe, siehe
  /// [zeitleisteKachelstufen].
  ///
  /// Als Zahl und nicht als Breite in Punkten: Eine Breite aus einer
  /// alten Fassung koennte eine sein, die es nicht mehr gibt, und jede
  /// Zwischengroesse waere ein eigener Schluessel im Bildspeicher.
  IntColumn get zeitleisteKachelstufe =>
      integer().withDefault(const Constant(zeitleisteKachelstufeVorgabe))();

  /// Ob die Zeitleiste Quadrate zeigt oder buendige Reihen – als Nummer
  /// aus [Zeitleistenform].
  ///
  /// Als Zahl und nicht als Name: Ein Name aus einer aelteren Fassung
  /// koennte einer sein, den es nicht mehr gibt. Eine Nummer ausserhalb
  /// der Reihe faellt ueber [zeitleisteForm] auf die Vorgabe zurueck,
  /// statt den Bildschirm zu verhindern – dieselbe Regel wie beim
  /// Kartenstil.
  IntColumn get zeitleisteFormNr =>
      integer().withDefault(Constant(zeitleisteFormVorgabe.index))();

  /// Wonach die Zeitleiste ordnet – als Nummer aus [Rastersortierung].
  ///
  /// Als Zahl und aus demselben Grund wie bei [zeitleisteFormNr]: Ein
  /// Name aus einer aelteren Fassung koennte einer sein, den es nicht
  /// mehr gibt.
  IntColumn get zeitleisteSortierungNr =>
      integer().withDefault(Constant(rastersortierungVorgabe.index))();

  /// Ob die Zeitleiste innerhalb der Monate nach Tagen gliedert – mit
  /// kleinen Tagen nebeneinander (siehe `zeitleisteTageszeilen`).
  ///
  /// Gemerkt aus demselben Grund wie Form und Kachelgroesse: Es ist keine
  /// Wahl, die man im Lauf einer Sichtung umlegt, sondern wie man seine
  /// Bibliothek ansieht. Vorgabe aus – wer nichts umstellt, sieht das
  /// Bisherige.
  BoolColumn get zeitleisteMitTagen =>
      boolean().withDefault(const Constant(false))();

  /// Welche Spalten die Listenansicht zeigt und wie breit sie sind –
  /// als Text, siehe [Listenspaltenwahl.alsText].
  ///
  /// `null` heisst Vorgabe: genau die fuenf Angaben, die es vorher gab.
  TextColumn get listenspalten => text().nullable()();

  /// Wie viele rechenintensive Aufgaben gleichzeitig laufen dürfen.
  ///
  /// **Warum das eine Einstellung ist und keine Konstante.** Bis hierher
  /// wurde eine zweite schwere Aufgabe schlicht **abgewiesen**: Wer
  /// Gesichter scannen liess und danach die Bildbeschreibungen anstiess,
  /// bekam eine Meldung und musste sich das Ende der ersten merken. Jetzt
  /// wird sie eingereiht — und wie viele nebeneinander laufen dürfen,
  /// hängt an der Maschine. Ein Rechner mit 64 GB verkraftet zwei Modelle
  /// nebeneinander, einer mit 8 GB nicht (allein CLIP-Bild 335 MB und die
  /// Bildbeschreibung 235 MB, gemessen).
  ///
  /// Vorgabe **eins**, also genau das bisherige Verhalten – nur ohne die
  /// Abweisung. Aufgaben ohne Modell (Orte einlesen, XMP schreiben,
  /// Live-Photo-Paare) zählen hier nicht mit; sie kosten nichts, was sich
  /// gegenseitig im Weg stünde.
  IntColumn get maxGleichzeitig => integer().withDefault(const Constant(1))();

  /// Bildbeschreibungen ins Deutsche übersetzen (Modell `translation_en_de`).
  BoolColumn get translateCaptions =>
      boolean().withDefault(const Constant(false))();

  /// Deutsche Suchanfragen und Schlagwörter vor der KI-Bildsuche ins
  /// Englische übersetzen (Modell `translation_de_en`).
  ///
  /// Standard aus, und zwar bewusst: An 103 Fotos der Testbibliothek
  /// gemessen trennt die englische Fassung eines Vokabelbegriffs bei 33
  /// von 56 Begriffen schärfer, bei 19 schlechter. Der Gewinn ist real,
  /// aber weder gross noch durchgängig – und die Zahl vergebener Tags
  /// sinkt bei gleicher Schwelle von 402 auf 248. Eine solche Änderung
  /// gehört nicht stillschweigend eingeschaltet.
  BoolColumn get translateSearchAndTags =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
