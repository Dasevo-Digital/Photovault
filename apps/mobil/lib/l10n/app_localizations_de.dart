// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppTexteDe extends AppTexte {
  AppTexteDe([String locale = 'de']) : super(locale);

  @override
  String get appTitel => 'Photo Vault';

  @override
  String get abbrechen => 'Abbrechen';

  @override
  String get weiter => 'Weiter';

  @override
  String get kopieren => 'Kopieren';

  @override
  String get navZeitleiste => 'Fotos';

  @override
  String get navSuche => 'Suche';

  @override
  String get navAlben => 'Alben';

  @override
  String get navPersonen => 'Personen';

  @override
  String get navKarte => 'Karte';

  @override
  String get navBibliothek => 'Bibliothek';

  @override
  String get bibFavoriten => 'Favoriten';

  @override
  String get bibPapierkorb => 'Papierkorb';

  @override
  String get bibAlle => 'Alle';

  @override
  String get bibFavoritenLeer => 'Noch keine Favoriten.';

  @override
  String get bibPapierkorbLeer => 'Der Papierkorb ist leer.';

  @override
  String get bibPapierkorbHinweis =>
      'Zurückholen geht hier; endgültig löschen am Rechner.';

  @override
  String get zeitleisteLeer =>
      'Noch keine Aufnahmen. Was auf den Server kommt, erscheint hier.';

  @override
  String get albenLeer => 'Noch keine Alben.';

  @override
  String get personenLeer =>
      'Noch keine benannten Personen. Personen benennt man am Rechner.';

  @override
  String get karteLeer => 'Noch keine Aufnahmen mit Ort.';

  @override
  String karteFotos(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen',
      one: '1 Aufnahme',
    );
    return '$_temp0';
  }

  @override
  String get abgemeldetHinweis =>
      'Dieses Telefon ist beim Server abgemeldet. Unter „Konto“ abmelden und neu verbinden.';

  @override
  String offline(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Server nicht erreichbar – $n Änderungen warten',
      one: 'Server nicht erreichbar – 1 Änderung wartet',
    );
    return '$_temp0';
  }

  @override
  String get sucheInhalt => 'Bildinhalt';

  @override
  String get sucheText => 'Text';

  @override
  String get sucheHinweisInhalt => 'z. B. Strand bei Sonnenuntergang';

  @override
  String get sucheHinweisText =>
      'Schlagwort, Ort, Person, Beschreibung, Dateiname …';

  @override
  String get sucheKeinModell =>
      'Der Server kann nicht nach Bildinhalt suchen (kein Modell). Gezeigt wird die Suche im Text.';

  @override
  String get sucheFehler => 'Die Suche hat nicht geklappt.';

  @override
  String get sucheNichts => 'Nichts gefunden.';

  @override
  String get betrachterFavorit => 'Favorit';

  @override
  String get betrachterTeilen => 'Teilen';

  @override
  String get betrachterAngaben => 'Angaben';

  @override
  String get betrachterPapierkorb => 'In den Papierkorb';

  @override
  String get betrachterPapierkorbTitel => 'In den Papierkorb legen?';

  @override
  String get betrachterPapierkorbText =>
      'Die Aufnahme verschwindet überall – auch am Rechner. Aus dem Papierkorb lässt sie sich am Rechner zurückholen.';

  @override
  String get betrachterLaedtOriginal => 'Das Original wird geladen …';

  @override
  String get betrachterNichtGeladen =>
      'Konnte nicht geladen werden – ist der Server erreichbar?';

  @override
  String get betrachterWirdUmgewandelt =>
      'Das Video wird für dieses Telefon umgewandelt …';

  @override
  String get betrachterLiveAbspielen => 'Live Photo abspielen';

  @override
  String get betrachterBeschreibungKi => 'Beschreibung der Bilderkennung';

  @override
  String get kontoTitel => 'Konto';

  @override
  String kontoKontoGeraet(String konto, String geraet) {
    return 'Konto $konto · Gerät $geraet';
  }

  @override
  String get kontoVerbindet => 'Verbindet …';

  @override
  String get kontoAbgeglichen => 'Abgeglichen';

  @override
  String serverSicherungStand(String wann) {
    return 'Sicherung des Servers: zuletzt $wann';
  }

  @override
  String get serverSicherungWarnung =>
      'Die Sicherung des Servers braucht Aufmerksamkeit – am Rechner unter Einstellungen → Server.';

  @override
  String get serverSicherungOffen =>
      'Die Sicherung des Servers ist noch nicht eingerichtet – am Rechner unter Einstellungen → Server.';

  @override
  String speicherStand(String frei, String gesamt) {
    return 'Speicher auf dem Server: $frei frei von $gesamt';
  }

  @override
  String speicherKnapp(String frei) {
    return 'Der Speicher des Servers wird knapp: noch $frei frei.';
  }

  @override
  String get speicherVoll =>
      'Der Speicher des Servers ist voll. Neue Fotos nimmt er erst wieder an, wenn Platz frei ist.';

  @override
  String kontoSendet(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Änderungen gehen zum Server',
      one: '1 Änderung geht zum Server',
    );
    return '$_temp0';
  }

  @override
  String get kontoAbmelden => 'Abmelden';

  @override
  String get kontoAbmeldenHinweis =>
      'Löscht die Kopie auf diesem Telefon; auf dem Server bleibt alles.';

  @override
  String get kontoAbmeldenTitel => 'Abmelden?';

  @override
  String get kontoAbmeldenText =>
      'Das Telefon meldet sich beim Server ab und löscht seine Kopie der Bibliothek samt aller geladenen Bilder. Änderungen, die noch warten, gehen verloren.';

  @override
  String get geraetVorgabe => 'Telefon';

  @override
  String get anmeldenTitel => 'Mit Server verbinden';

  @override
  String get anmeldenErklaerung =>
      'Photo Vault auf dem Telefon zeigt die Bibliothek deines Photo-Vault-Servers – mit Zeitleiste, Suche, Alben, Personen und Karte, auch ohne Verbindung.';

  @override
  String get anmeldenAdresse => 'Adresse des Servers';

  @override
  String get anmeldenAdresseHinweis => 'z. B. fotos.example.de';

  @override
  String get anmeldenName => 'Name';

  @override
  String get anmeldenPasswort => 'Passwort';

  @override
  String get anmeldenGeraet => 'Name dieses Telefons';

  @override
  String get anmeldenAnmelden => 'Anmelden';

  @override
  String get anmeldenNichtErreichbar =>
      'Unter dieser Adresse antwortet kein Server.';

  @override
  String get anmeldenKeinServer =>
      'Dort antwortet kein Photo-Vault-Server in passender Fassung.';

  @override
  String get anmeldenNurHttps =>
      'Ohne Verschlüsselung (http://) nur im eigenen Netz – für eine Adresse im Internet bitte https:// verwenden.';

  @override
  String get anmeldenFalsch => 'Name, Passwort oder Code stimmt nicht.';

  @override
  String anmeldenGebremst(int sekunden) {
    return 'Zu viele Fehlversuche – bitte in $sekunden Sekunden erneut versuchen.';
  }

  @override
  String get anmeldenCodeTitel => 'Code aus der Authenticator-App';

  @override
  String get anmeldenCodeHinweis =>
      'Sechs Ziffern – oder einer der Wiederherstellungscodes.';

  @override
  String get anmeldenBestaetigen => 'Bestätigen';

  @override
  String get anmeldenTotpTitel => 'Zwei-Faktor-Anmeldung einrichten';

  @override
  String get anmeldenTotpText =>
      'Das Geheimnis in die Authenticator-App übernehmen – mit dem Knopf oder abgetippt – und dann den ersten Code eingeben.';

  @override
  String get anmeldenTotpOeffnen => 'In der Authenticator-App öffnen';

  @override
  String get anmeldenCodesTitel => 'Wiederherstellungscodes';

  @override
  String get anmeldenCodesText =>
      'Jeder Code gilt einmal, wenn das Telefon mit der Authenticator-App fehlt. Jetzt sicher aufbewahren – sie werden nicht noch einmal gezeigt.';

  @override
  String get anmeldenLaedt => 'Die Bibliothek kommt vom Server …';

  @override
  String get anmeldenErstesTitel => 'Erstes Konto anlegen';

  @override
  String anmeldenErstesText(String name) {
    return 'Dieser Server hat noch kein Konto. Mit dem Namen „$name“ und dem Passwort von eben wird das erste angelegt. Es wird Verwalter und kann später weitere Konten anlegen.';
  }

  @override
  String get anmeldenPasswortWiederholen => 'Passwort wiederholen';

  @override
  String get anmeldenErstesAnlegen => 'Konto anlegen und anmelden';

  @override
  String get anmeldenPasswortUngleich =>
      'Die beiden Passwörter stimmen nicht überein.';

  @override
  String anmeldenPasswortZuKurz(int n) {
    return 'Das Passwort braucht mindestens $n Zeichen.';
  }

  @override
  String get anmeldenNameUngueltig =>
      'Der Name braucht 2 bis 40 Buchstaben, Ziffern, Punkt, Strich oder Unterstrich.';

  @override
  String get anmeldenErstesNurHeimnetz =>
      'Das erste Konto lässt sich nur aus dem Heimnetz anlegen, nicht über den Zugang von außen.';

  @override
  String get anmeldenSchonEingerichtet =>
      'Der Server hat inzwischen ein Konto. Bitte damit anmelden.';

  @override
  String get fehlerAllgemein => 'Hat nicht geklappt.';

  @override
  String get speichern => 'Speichern';

  @override
  String get entfernen => 'Entfernen';

  @override
  String get kontenVerwalten => 'Konten verwalten';

  @override
  String get kontenVerwaltenHinweis =>
      'Konten für die Familie anlegen, Passwörter neu setzen';

  @override
  String get kontenTitel => 'Konten auf dem Server';

  @override
  String get kontoAnlegen => 'Konto anlegen';

  @override
  String get kontoVerwalter => 'Verwalter';

  @override
  String get kontoAlsVerwalter => 'Darf ebenfalls Konten verwalten';

  @override
  String kontoGeraete(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Geräte',
      one: '1 Gerät',
      zero: 'kein Gerät',
    );
    return '$_temp0';
  }

  @override
  String get kontoMitTotp => 'mit TOTP';

  @override
  String get kontoOhneTotp => 'ohne TOTP';

  @override
  String get kontoGesperrt => 'gesperrt nach Fehlversuchen';

  @override
  String get kontoDu => 'dein Konto';

  @override
  String get kontoPasswortSetzen => 'Passwort neu setzen';

  @override
  String kontoPasswortSetzenText(String name) {
    return 'Alle Geräte von „$name“ werden dabei abgemeldet.';
  }

  @override
  String get kontoTotpZuruecksetzen => 'TOTP zurücksetzen';

  @override
  String kontoTotpZurueckgesetzt(String name) {
    return '„$name“ richtet TOTP bei der nächsten Anmeldung neu ein.';
  }

  @override
  String get kontoEntsperren => 'Entsperren';

  @override
  String kontoEntfernenTitel(String name) {
    return '„$name“ entfernen?';
  }

  @override
  String get kontoEntfernenText =>
      'Das Konto und seine Geräte werden entfernt. Die Bibliothek mit allen Fotos bleibt auf dem Server liegen: Sie wird beiseitegelegt, nicht gelöscht, und lässt sich nur dort von Hand löschen.';

  @override
  String get kontoErledigt => 'Erledigt.';

  @override
  String get sicherungTitel => 'Kamerarolle sichern';

  @override
  String get sicherungAn => 'Fotos vom Telefon sichern';

  @override
  String get sicherungAnHinweis =>
      'Neue Fotos und Videos gehen von selbst zum Server – auch, wenn die App nicht offen ist.';

  @override
  String get sicherungAus => 'Aus';

  @override
  String get sicherungLaeuft => 'Sichert gerade …';

  @override
  String get sicherungVideos => 'Videos sichern';

  @override
  String get sicherungNurWlan => 'Nur im WLAN';

  @override
  String get sicherungNurBeimLaden => 'Im Hintergrund nur beim Laden';

  @override
  String get sicherungAlben => 'Alben';

  @override
  String get sicherungAlleFotos => 'Alle Fotos';

  @override
  String sicherungAlbenAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Alben',
      one: '1 Album',
    );
    return '$_temp0';
  }

  @override
  String get sicherungHinweisIos =>
      'Ist die App offen, sichert sie sofort. Im Hintergrund lässt iOS sie arbeiten, wann es das für richtig hält – meist nachts am Ladekabel.';

  @override
  String get sicherungHinweisAndroid =>
      'Ist die App offen, sichert sie sofort; im Hintergrund schaut sie alle 15 Minuten nach. Was beim Verlassen der App noch fehlt, lädt sie mit einer Benachrichtigung weiter.';

  @override
  String get sicherungKeinZugriff => 'Kein Zugriff auf die Fotos';

  @override
  String get sicherungKeinZugriffHinweis =>
      'In den Einstellungen des Telefons erlauben.';

  @override
  String get sicherungEinstellungenOeffnen => 'Einstellungen';

  @override
  String get sicherungTeilweise => 'Nur ausgewählte Fotos freigegeben';

  @override
  String get sicherungTeilweiseHinweis =>
      'Gesichert wird nur, was die App sehen darf.';

  @override
  String get sicherungAuswahlAendern => 'Auswahl ändern';

  @override
  String get sicherungWartetWlan => 'Wartet auf WLAN';

  @override
  String get sicherungWartetNetz => 'Wartet auf eine Verbindung';

  @override
  String get sicherungImHintergrund =>
      'Die Sicherung läuft gerade im Hintergrund.';

  @override
  String get sicherungNochNicht => 'Noch nicht gesichert';

  @override
  String sicherungStand(int sicher, int gesamt) {
    return '$sicher von $gesamt gesichert';
  }

  @override
  String sicherungLaedt(String datei) {
    return 'Lädt $datei hoch';
  }

  @override
  String sicherungZuletzt(String zeit) {
    return 'Zuletzt: $zeit';
  }

  @override
  String get sicherungFehler =>
      'Der Server hat die Sicherung abgebrochen. Beim nächsten Lauf geht es weiter.';

  @override
  String sicherungProbleme(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen ließen sich nicht sichern',
      one: '1 Aufnahme ließ sich nicht sichern',
    );
    return '$_temp0';
  }

  @override
  String get sicherungErneut => 'Erneut versuchen';

  @override
  String get sicherungJetzt => 'Jetzt sichern';

  @override
  String get sicherungBenachrichtigungTitel => 'Photo Vault sichert Fotos';

  @override
  String get sicherungBenachrichtigungText =>
      'Fotos und Videos gehen zum Server.';

  @override
  String get sicherungKanal => 'Sicherung';

  @override
  String get appZuAlt =>
      'Der Server ist neuer als diese App – bitte die App aktualisieren. Bis dahin gleicht nichts ab.';

  @override
  String get serverZuAlt =>
      'Der Server ist älter als diese App – bitte den Server aktualisieren. Bis dahin gleicht nichts ab.';

  @override
  String auswahlAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n ausgewählt',
      one: '1 ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String get auswahlAufheben => 'Auswahl aufheben';

  @override
  String get auswahlZurueckholen => 'Zurückholen';

  @override
  String get auswahlTagWaehlen => 'Alle Aufnahmen dieses Tages auswählen';

  @override
  String get auswahlTagAbwaehlen => 'Auswahl dieses Tages aufheben';

  @override
  String get auswahlFavorit => 'Favorit';

  @override
  String get auswahlTeilen => 'Teilen';

  @override
  String get auswahlHerunterladen => 'Aufs Telefon';

  @override
  String get auswahlPapierkorb => 'Papierkorb';

  @override
  String auswahlPapierkorbTitel(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen in den Papierkorb legen?',
      one: 'Die Aufnahme in den Papierkorb legen?',
    );
    return '$_temp0';
  }

  @override
  String get auswahlPapierkorbText =>
      'Sie verschwinden überall – auch am Rechner. Aus dem Papierkorb lassen sie sich am Rechner zurückholen.';

  @override
  String get auswahlAlbumTitel => 'Zum Album hinzufügen';

  @override
  String get auswahlAlbumNeu => 'Neues Album';

  @override
  String get auswahlAlbumName => 'Name des Albums';

  @override
  String get auswahlAlbumAnlegen => 'Anlegen';

  @override
  String auswahlImAlbum(int n, String album) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen im Album „$album“',
      one: '1 Aufnahme im Album „$album“',
    );
    return '$_temp0';
  }

  @override
  String get auswahlLaedt => 'Die Originale werden geladen …';

  @override
  String auswahlGespeichert(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen auf dem Telefon gespeichert',
      one: '1 Aufnahme auf dem Telefon gespeichert',
    );
    return '$_temp0';
  }

  @override
  String get auswahlKeinZugriff =>
      'Kein Zugriff auf die Fotomediathek – in den Einstellungen des Telefons erlauben.';

  @override
  String get kontoZwischenspeicher => 'Zwischenspeicher auf dem Telefon';

  @override
  String kontoZwischenspeicherStand(String belegt, String grenze) {
    return '$belegt von $grenze – Vorschauen und Originale, die du angesehen hast. Antippen für die Grenze.';
  }

  @override
  String kontoZwischenspeicherOhneGrenzeStand(String belegt) {
    return '$belegt, ohne Grenze – Vorschauen und Originale, die du angesehen hast. Antippen für die Grenze.';
  }

  @override
  String get kontoZwischenspeicherLeeren => 'Leeren';

  @override
  String get kontoZwischenspeicherGrenze => 'Höchstens belegen';

  @override
  String get kontoZwischenspeicherOhneGrenze => 'Ohne Grenze';

  @override
  String get erinnerungenTitel => 'Erinnerungen';

  @override
  String erinnerungenVorJahren(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Vor $n Jahren',
      one: 'Vor 1 Jahr',
    );
    return '$_temp0';
  }

  @override
  String erinnerungenMonatVorJahren(String monat, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'vor $n Jahren',
      one: 'vor 1 Jahr',
    );
    return '$monat $_temp0';
  }

  @override
  String erinnerungenAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen',
      one: '1 Aufnahme',
    );
    return '$_temp0';
  }

  @override
  String get sicherungFreigeben => 'Speicher freigeben';

  @override
  String get sicherungFreigebenHinweis =>
      'Gesicherte Aufnahmen vom Telefon löschen – auf dem Server bleiben sie.';

  @override
  String get sicherungFreigebenSucht => 'Sucht gesicherte Aufnahmen …';

  @override
  String get sicherungFreigebenNichts =>
      'Nichts freizugeben: Was auf dem Server liegt, ist schon vom Telefon – oder noch nicht gesichert.';

  @override
  String sicherungFreigebenTitel(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen vom Telefon löschen?',
      one: '1 Aufnahme vom Telefon löschen?',
    );
    return '$_temp0';
  }

  @override
  String get sicherungFreigebenText =>
      'Nur Aufnahmen, die unverändert und sicher auf dem Server liegen. Das Telefon fragt gleich noch einmal nach.';

  @override
  String get sicherungFreigebenLoeschen => 'Löschen';

  @override
  String sicherungFreigegeben(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen vom Telefon gelöscht',
      one: '1 Aufnahme vom Telefon gelöscht',
      zero: 'Nichts gelöscht',
    );
    return '$_temp0';
  }

  @override
  String get lokalNochNichtGesichert =>
      'Nur auf dem Telefon – noch nicht auf dem Server';

  @override
  String get lokalJetztSichern => 'Jetzt sichern';

  @override
  String lokalAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen nur auf dem Telefon',
      one: '1 Aufnahme nur auf dem Telefon',
    );
    return '$_temp0';
  }

  @override
  String get kontoFassung => 'Fassung';

  @override
  String get kontoUnterstuetzen => 'Photo Vault unterstützen';

  @override
  String get kontoUnterstuetzenText =>
      'Kostenlos und ohne Werbung – wer mag, spendiert auf Ko-fi einen Kaffee.';

  @override
  String kontoFassungText(String app, String server) {
    return 'App $app · Server $server';
  }

  @override
  String get bibReisen => 'Reisen';

  @override
  String get reisenLeer => 'Noch keine Reisen.';

  @override
  String get aktivitaetenTitel => 'Aktivitäten';

  @override
  String get aktivitaetenLeer => 'Noch keine Aktivitäten.';

  @override
  String anzahlAufnahmen(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen',
      one: '1 Aufnahme',
    );
    return '$_temp0';
  }

  @override
  String gehoertZu(String reise) {
    return 'Gehört zu: $reise';
  }

  @override
  String ortWeitere(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n weitere Orte',
      one: 'ein weiterer Ort',
    );
    return '$_temp0';
  }

  @override
  String dauerMinuten(int m) {
    return '$m min';
  }

  @override
  String dauerStunden(int h, int m) {
    return '$h h $m min';
  }

  @override
  String streckeKm(String km) {
    return '$km km';
  }

  @override
  String get keineRoute => 'Zu wenige verortete Aufnahmen für eine Strecke.';

  @override
  String get aktArtSpaziergang => 'Spaziergang';

  @override
  String get aktArtWanderung => 'Wanderung';

  @override
  String get aktArtRadtour => 'Radtour';

  @override
  String get aktArtAusflug => 'Ausflug';

  @override
  String get aktArtBesichtigung => 'Besichtigung';

  @override
  String get aktArtBootsfahrt => 'Bootsfahrt';

  @override
  String get aktArtSonstiges => 'Sonstiges';

  @override
  String get angabenTitel => 'Angaben';

  @override
  String get angabenDatumGeschaetzt => 'Datum geschätzt';

  @override
  String get angabenBearbeitet => 'bearbeitet';

  @override
  String get angabenStandortBekannt => 'Standort bekannt';

  @override
  String get angabenGeerbt => 'vom Nachbarfoto übernommen';

  @override
  String get angabenBeschreibung => 'Beschreibung';

  @override
  String get angabenSpeichern => 'Speichern';

  @override
  String get angabenGespeichert => 'Gespeichert';

  @override
  String angabenAutomatisch(String text) {
    return 'Automatisch: $text';
  }

  @override
  String angabenSterne(int i) {
    return '$i von 5';
  }

  @override
  String angabenSerie(int n) {
    return 'Serie mit $n Aufnahmen';
  }

  @override
  String angabenVarianten(Object n) {
    return '$n Varianten dieser Aufnahme';
  }

  @override
  String get angabenText => 'Erkannter Text';

  @override
  String get angabenTranskript => 'Transkript';

  @override
  String angabenImportiert(String datum) {
    return 'Importiert $datum';
  }

  @override
  String angabenSerieTitel(int n) {
    return 'Serie · $n Aufnahmen';
  }

  @override
  String angabenVariantenTitel(Object n) {
    return 'Varianten · $n Fassungen';
  }

  @override
  String get bibStatistik => 'Statistik';

  @override
  String get statLeer => 'Noch keine Fotos oder Videos in der Bibliothek.';

  @override
  String get statInsgesamt => 'Medien insgesamt';

  @override
  String get statFotos => 'Fotos';

  @override
  String get statVideos => 'Videos';

  @override
  String get statFavoriten => 'Favoriten';

  @override
  String get statSpeicher => 'Speicherplatz';

  @override
  String get statPapierkorb => 'Im Papierkorb';

  @override
  String get statGesperrt => 'Gesperrter Ordner';

  @override
  String get statProJahr => 'Fotos & Videos pro Jahr';

  @override
  String get statProMonat => 'Saisonalität – Aufnahmen pro Monat';

  @override
  String get statKameras => 'Häufigste Kameras';

  @override
  String get bibDuplikate => 'Duplikate';

  @override
  String get duplAehnlichkeit => 'Ähnlichkeit';

  @override
  String get duplSuchen => 'Suchen';

  @override
  String get duplSucht => 'Suche …';

  @override
  String duplAlle(int n) {
    return '$n Kopien in den Papierkorb';
  }

  @override
  String get duplKeineEinbettungen =>
      'Noch keine Bildeinbettungen – die Auswertung auf dem Server muss zuerst gelaufen sein.';

  @override
  String duplKeine(String p) {
    return 'Keine Duplikate bei $p Ähnlichkeit.';
  }

  @override
  String duplAusnahmen(int n) {
    return '$n Paare sind ausgenommen.';
  }

  @override
  String duplGruppen(int n, String p) {
    return '$n Gruppen bei $p Ähnlichkeit. Das umrandete Foto würde beim Aufräumen behalten; Gruppen mit mehreren Favoriten oder Bewertungen bleiben unangetastet.';
  }

  @override
  String get duplKeineDuplikate => 'Keine Duplikate';

  @override
  String duplNurVonHand(int n) {
    return '$n Aufnahmen · mehrere ausgezeichnet, nur von Hand';
  }

  @override
  String get duplBehalten => 'Behalten';

  @override
  String duplBehaltenEine(String name) {
    return '„$name“ behalten und die andere Aufnahme in den Papierkorb legen?';
  }

  @override
  String duplBehaltenMehrere(String name, int n) {
    return '„$name“ behalten und die $n anderen in den Papierkorb legen?';
  }

  @override
  String duplAlleFrage(int n, int g) {
    return '$n Kopien aus $g Gruppen in den Papierkorb legen? Je Gruppe bleibt das umrandete Foto.';
  }

  @override
  String get bibEinstellungen => 'Einstellungen';

  @override
  String get einstTitel => 'Einstellungen der Bibliothek';

  @override
  String get einstHinweis =>
      'Diese Einstellungen stehen in der Bibliothek und gelten für alle verbundenen Geräte.';

  @override
  String get einstSprache => 'Sprache dieser App';

  @override
  String get einstSpracheHinweis => 'Gilt nur auf diesem Telefon.';

  @override
  String get einstAutomatisch => 'Automatisch';

  @override
  String get einstGespeichert => 'Gespeichert.';

  @override
  String get einstNach => 'nach';

  @override
  String get einstTagen => 'Tagen';

  @override
  String einstAb(String p) {
    return 'ab $p';
  }

  @override
  String get einstPapierkorb => 'Papierkorb automatisch leeren';

  @override
  String get einstPapierkorbText =>
      'Löscht Aufnahmen im Papierkorb nach Ablauf der Frist endgültig – unwiderruflich.';

  @override
  String get einstVorschlaege => 'Sichere Vorschläge automatisch übernehmen';

  @override
  String get einstVorschlaegeText =>
      'Erkannte Gesichter, die einer Person sehr ähnlich sind, werden ohne Rückfrage zugeordnet.';

  @override
  String get einstAuswerten =>
      'KI-Auswertung nach dem Import automatisch nachholen';

  @override
  String get einstAuswertenText =>
      'Neue Aufnahmen werden gleich ausgewertet: Gesichter, Bildinhalt, Text, Schlagwörter.';

  @override
  String get einstUebersetzen => 'Suche und Schlagwörter übersetzen';

  @override
  String get einstUebersetzenText =>
      'Sucht auf Deutsch und Englisch gleichzeitig und führt Schlagwörter in beiden Sprachen.';

  @override
  String get einstSchuetzen => 'Private Metadaten schützen';

  @override
  String get einstSchuetzenText =>
      'Neu gesperrte Aufnahmen legen auch Ort, Beschreibung und Text verschlüsselt ab.';

  @override
  String get einstSchwelle => 'Schwelle der Gesichtserkennung';

  @override
  String get einstSchwelleText =>
      'Wie ähnlich ein Gesicht sein muss, um einer Person vorgeschlagen zu werden. Höher heisst vorsichtiger.';

  @override
  String get verwAuswertungRuht => 'Auswertung: nichts offen';

  @override
  String verwAuswertungLaeuft(
    String stufe,
    int nr,
    int von,
    int erledigt,
    int gesamt,
  ) {
    return 'Auswertung läuft: $stufe ($nr/$von), $erledigt von $gesamt';
  }

  @override
  String get verwAnstossen => 'Auswertung anstossen';

  @override
  String get verwJetztSichern => 'Jetzt sichern';

  @override
  String get bibStammbaum => 'Stammbaum';

  @override
  String get bibEntdecken => 'Entdecken';

  @override
  String get bibVerwalten => 'Verwalten';

  @override
  String get baumPerson => 'Person';

  @override
  String get baumLebensbaum => 'Lebensbaum';

  @override
  String baumOhneVerwandtschaft(String name) {
    return '$name (ohne Verwandtschaft)';
  }

  @override
  String get baumKeinePersonen =>
      'Noch keine Personen. Lege sie am Rechner unter Personen und Stammbaum an.';

  @override
  String get baumKeineVerwandtschaft =>
      'Zu dieser Person ist noch keine Verwandtschaft eingetragen – das geht am Rechner im Stammbaum.';

  @override
  String baumVerschwiegen(int n) {
    return '$n Haushalte passen nicht mehr ins Bild.';
  }

  @override
  String get lbStil => 'Stil';

  @override
  String get lbPergament => 'Pergament';

  @override
  String get lbLandschaft => 'Landschaft';

  @override
  String get lbWappen => 'Wappen';

  @override
  String get lbGold => 'Gold';

  @override
  String get lbZeigt => 'Zeigt';

  @override
  String get lbVorfahren => 'Vorfahren';

  @override
  String get lbNachkommen => 'Nachkommen';

  @override
  String get lbPaar => 'Paar';

  @override
  String get lbFamilie => 'Familie';

  @override
  String get lbGenerationen => 'Generationen';

  @override
  String get lbNachOben => 'Nach oben';

  @override
  String get lbNachUnten => 'Nach unten';

  @override
  String get lbKreis => 'Kreis';

  @override
  String get lbDirekteLinie => 'Direkte Linie';

  @override
  String get lbMitGeschwistern => 'Mit Geschwistern';

  @override
  String get lbAlle => 'Alle';

  @override
  String get lbPortraits => 'Porträts';

  @override
  String get lbSpeichern => 'Als Bild speichern';

  @override
  String get lbStammbaum => 'Stammbaum';

  @override
  String get entwTitel => 'Entwickeln';

  @override
  String get entwBelichtung => 'Belichtung';

  @override
  String get entwKontrast => 'Kontrast';

  @override
  String get entwLichter => 'Lichter';

  @override
  String get entwSchatten => 'Schatten';

  @override
  String get entwTemperatur => 'Farbtemperatur';

  @override
  String get entwToenung => 'Tönung';

  @override
  String get entwKlarheit => 'Klarheit';

  @override
  String get entwSchaerfe => 'Schärfe';

  @override
  String get entwRauschen => 'Rauschminderung';

  @override
  String get entwVignette => 'Vignettierung';

  @override
  String get entwAutoWeiss => 'Automatischer Weissabgleich';

  @override
  String get entwVorher => 'Vorher';

  @override
  String get entwZuruecksetzen => 'Regler zurücksetzen';

  @override
  String get entwEntfernen => 'Entwicklung entfernen';

  @override
  String get entwVorschauQuelle =>
      'Rohformat oder HEIC: Das Telefon rechnet aus der Vorschau (höchstens 2048 Pixel). In voller Grösse entwickelt der Rechner.';

  @override
  String get entwVomRechner =>
      'Tonkurve, Farbmischer und Look vom Rechner wirken mit und bleiben erhalten.';

  @override
  String entwRechne(int b, int h) {
    return 'Rechne in voller Grösse ($b × $h) …';
  }

  @override
  String get entwLaedtHoch => 'Lade hoch …';

  @override
  String get entwGespeichert => 'Gespeichert.';

  @override
  String get entwVerwerfen => 'Änderungen verwerfen?';

  @override
  String get entwEntfernenFrage =>
      'Die Entwicklung entfernen und das Original zeigen?';

  @override
  String get entwNichtGeladen => 'Das Bild liess sich nicht laden.';

  @override
  String get entwSpeichern => 'Speichern';

  @override
  String get eigenGeraete => 'Geräte';

  @override
  String get eigenDiesesTelefon => '(dieses Telefon)';

  @override
  String eigenZuletzt(String datum) {
    return 'zuletzt $datum';
  }

  @override
  String get eigenGeraetAbmelden => 'Gerät abmelden';

  @override
  String eigenGeraetAbmeldenFrage(String name) {
    return '„$name“ abmelden?';
  }

  @override
  String get eigenPasswortAendern => 'Passwort ändern';

  @override
  String get eigenPasswortAlt => 'Aktuelles Passwort';

  @override
  String get eigenPasswortNeu => 'Neues Passwort';

  @override
  String get eigenPasswortNochmal => 'Noch einmal';

  @override
  String get eigenTotpCode => 'TOTP-Code';

  @override
  String get eigenAndereAbmelden => 'Andere Geräte abmelden';

  @override
  String get eigenAendern => 'Ändern';

  @override
  String get eigenPasswortUngleich =>
      'Die neuen Passwörter stimmen nicht überein.';

  @override
  String get eigenPasswortGeaendert => 'Passwort geändert.';

  @override
  String get eigenTotpEingerichtet => 'TOTP eingerichtet';

  @override
  String get gesichterOhneNamen => 'Ohne Namen';

  @override
  String gesichterAnzahl(int n) {
    return '$n Gesichter';
  }

  @override
  String gesichterVorschlagFrage(String name) {
    return '$name?';
  }

  @override
  String get gesichterWerIstDas => 'Wer ist das?';

  @override
  String gesichterAehnliche(int n) {
    return '$n ähnliche Gesichter';
  }

  @override
  String gesichterDasIst(String name) {
    return 'Das ist $name';
  }

  @override
  String get gesichterHinweis =>
      'Antippen nimmt ein Gesicht heraus, das nicht dazugehört. Das Zeichen in der Ecke zeigt es im ganzen Foto.';

  @override
  String get gesichtImFoto => 'Im Foto zeigen';

  @override
  String get gesichtFotoFehlt => 'Das Foto ist gerade nicht zu laden.';

  @override
  String get gesichterName => 'Name';

  @override
  String get gesichterNamePlatzhalter => 'Neue oder vorhandene Person';

  @override
  String get gesichterNameFehlt => 'Bitte einen Namen eingeben.';

  @override
  String get gesichterBenennen => 'Benennen';

  @override
  String get gesichterBeiseite => 'Beiseitelegen';

  @override
  String get gesichterLoesen => 'Zuordnung lösen';

  @override
  String get gesichterKeinGesicht => 'Kein Gesicht gewählt.';

  @override
  String get gesichterAntippen => 'Antippen, um zu benennen oder zu ändern';

  @override
  String get gesichterWeitereFinden => 'Weitere Fotos finden';

  @override
  String gesichterVorschlaegeFuer(String name) {
    return 'Vorschläge für $name';
  }

  @override
  String get gesichterVorschlagHinweis =>
      'Alles ist ausgewählt. Nimm heraus, was nicht stimmt – auch das lernt die Erkennung: Eine Ablehnung schiebt die Schwelle für diese Person nach oben.';

  @override
  String get gesichterAlleWaehlen => 'Alle wählen';

  @override
  String get gesichterKeineWaehlen => 'Keine wählen';

  @override
  String gesichterZuordnenAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Gesichter zuordnen',
      one: 'Ein Gesicht zuordnen',
      zero: 'Nichts ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String gesichterNichtsGefunden(String schwelle) {
    return 'Kein unbenanntes Gesicht liegt über der Schwelle $schwelle dieser Person.';
  }

  @override
  String gesichterUebernommen(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Fotos hinzugefügt.',
      one: 'Ein Foto hinzugefügt.',
      zero: 'Nichts übernommen – die Rückmeldung ist trotzdem gespeichert.',
    );
    return '$_temp0';
  }

  @override
  String get linkGaesteHochladen => 'Gäste dürfen Fotos und Videos hinzufügen';

  @override
  String get linkGaesteHinweis =>
      'Jede Datei wird abgeschottet geprüft und neu geschrieben. Ins Album kommt sie erst, wenn du sie annimmst.';

  @override
  String get linkGaesteDuerfen => 'Gäste dürfen hinzufügen';

  @override
  String linkBeitraegeOffen(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Beiträge offen',
      one: '1 Beitrag offen',
    );
    return '$_temp0';
  }

  @override
  String get beitraegeTitel => 'Beiträge von Gästen';

  @override
  String get beitraegeAlleAnnehmen => 'Alle annehmen';

  @override
  String get beitraegeAbgeschottet =>
      'Jede Datei wurde in einem eigenen Prozess ohne Netz geprüft und neu geschrieben – mit Aufnahmezeit, Ort und Kamera, sonst nichts.';

  @override
  String get beitraegeMitNetz =>
      'Jede Datei wurde in einem eigenen Prozess geprüft und neu geschrieben. Eine Netzsperre erlaubt dieses System nicht.';

  @override
  String beitraegeVon(String name) {
    return 'von $name';
  }

  @override
  String get beitraegeInPruefung => 'wird geprüft …';

  @override
  String get beitraegeAnnehmen => 'Annehmen';

  @override
  String get beitraegeAblehnen => 'Ablehnen';

  @override
  String get beitraegeEntfernen => 'Entfernen';

  @override
  String beitraegeAngenommen(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Beiträge angenommen',
      one: 'Beitrag angenommen',
    );
    return '$_temp0';
  }

  @override
  String get diashow => 'Diashow';

  @override
  String get diashowAbHier => 'Diashow ab hier';

  @override
  String get diashowKeineFotos =>
      'Hier sind keine Fotos für eine Diashow – Videos bleiben draussen.';

  @override
  String get diashowVorige => 'Vorige';

  @override
  String get diashowNaechste => 'Nächste';

  @override
  String get diashowAnhalten => 'Anhalten';

  @override
  String get diashowWeiter => 'Weiter';

  @override
  String get diashowBeenden => 'Diashow beenden';

  @override
  String get betrachterMehr => 'Mehr';

  @override
  String get bibOrte => 'Orte';

  @override
  String get orteLeer =>
      'Noch keine Orte. Sie entstehen, sobald Aufnahmen einen Ort tragen und die Ortsdaten eingerichtet sind.';

  @override
  String orteAnzahlOrte(int n) {
    return '$n Orte';
  }

  @override
  String orteAufnahmen(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen',
      one: '1 Aufnahme',
    );
    return '$_temp0';
  }

  @override
  String get personZusammenfuehren => 'Zusammenführen';

  @override
  String personZusammenfuehrenTitel(String name) {
    return 'In „$name“ aufnehmen';
  }

  @override
  String get personZusammenfuehrenText =>
      'Die gewählte Person geht in dieser auf: ihre Gesichter, Fotos und Verwandtschaft kommen hierher, ihr Name verschwindet.';

  @override
  String personZusammenfuehrenFrage(String andere, String name) {
    return '„$andere“ in „$name“ aufnehmen? Das lässt sich nicht rückgängig machen.';
  }

  @override
  String get sucheFilter => 'Filter';

  @override
  String get sucheFilterPersonen => 'Personen';

  @override
  String get sucheFilterOrt => 'Ort';

  @override
  String get sucheFilterAlleLaender => 'Alle Länder';

  @override
  String get sucheFilterAlleStaedte => 'Alle Städte';

  @override
  String get sucheFilterZeitraum => 'Zeitraum';

  @override
  String get sucheFilterVon => 'Von';

  @override
  String get sucheFilterBis => 'Bis';

  @override
  String get sucheFilterArt => 'Art';

  @override
  String get sucheFilterAlles => 'Alles';

  @override
  String get sucheFilterFotos => 'Fotos';

  @override
  String get sucheFilterVideos => 'Videos';

  @override
  String get sucheFilterKamera => 'Kamera';

  @override
  String get sucheFilterAlleKameras => 'Alle Kameras';

  @override
  String get sucheFilterFavoriten => 'Nur Favoriten';

  @override
  String get sucheFilterZuruecksetzen => 'Zurücksetzen';

  @override
  String get sucheFilterAnwenden => 'Anwenden';

  @override
  String sucheFilterZeile(String text) {
    return 'Filter: $text';
  }

  @override
  String get sucheTextOderFilter =>
      'Suchtext eingeben oder einen Filter wählen.';

  @override
  String get linkTitel => 'Als Link teilen';

  @override
  String get linkFeldTitel => 'Titel';

  @override
  String get linkGueltig => 'Gültig';

  @override
  String get linkTag1 => '1 Tag';

  @override
  String linkTage(int n) {
    return '$n Tage';
  }

  @override
  String get linkJahr1 => '1 Jahr';

  @override
  String get linkUnbegrenzt => 'Unbegrenzt';

  @override
  String get linkPasswort => 'Passwort (frei lassen für keins)';

  @override
  String get linkHerunterladen => 'Originale herunterladen erlauben';

  @override
  String get linkOhneMetadaten =>
      'Gezeigt werden Bilder ohne Orts- und Kameraangaben. Originale enthalten sie.';

  @override
  String get linkErstellen => 'Link erstellen';

  @override
  String get linkWerHatSieht => 'Wer diesen Link hat, sieht die Aufnahmen:';

  @override
  String get linkNurHeimnetz =>
      'Diese Adresse ist nur im Heimnetz erreichbar. Von aussen geht der Link über die öffentliche Adresse des Servers.';

  @override
  String get linkKopieren => 'Kopieren';

  @override
  String get linkTeilen => 'Teilen';

  @override
  String get linkKopiert => 'Link kopiert';

  @override
  String get linkTitelFehlt => 'Bitte einen Titel eingeben.';

  @override
  String get linkPasswortKurz => 'Das Passwort braucht mindestens 4 Zeichen.';

  @override
  String get linkOhneServer =>
      'Ohne Verbindung zum Server gibt es keinen Link.';

  @override
  String get linkGeteilte => 'Geteilte Links';

  @override
  String get linkNochNichts => 'Noch nichts geteilt.';

  @override
  String linkAnzahl(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen',
      one: '1 Aufnahme',
    );
    return '$_temp0';
  }

  @override
  String get linkAbgelaufen => 'abgelaufen';

  @override
  String linkBis(String datum) {
    return 'bis $datum';
  }

  @override
  String get linkMitPasswort => 'mit Passwort';

  @override
  String linkAufrufe(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufrufe',
      one: '1 Aufruf',
    );
    return '$_temp0';
  }

  @override
  String get linkLoeschen => 'Löschen';

  @override
  String linkLoeschenFrage(String titel) {
    return 'Den Link „$titel“ löschen? Wer ihn hat, sieht danach nichts mehr.';
  }

  @override
  String get auswahlLink => 'Link';

  @override
  String get albumAlsLink => 'Als Link teilen';

  @override
  String get spurTitel => 'Aufgezeichnete Spur';

  @override
  String spurKennzahlen(String km, int auf, int ab) {
    return '$km km · ▲ $auf m · ▼ $ab m';
  }

  @override
  String spurKennzahlenOhneHoehe(String km) {
    return '$km km · keine Höhenangaben';
  }

  @override
  String spurPunkte(int anzahl) {
    return '$anzahl Punkte';
  }

  @override
  String get spurHoehenprofil => 'Höhenprofil';

  @override
  String get spurOhneHoehen =>
      'Diese Datei führt keine Höhen – ohne sie gibt es kein Profil.';

  @override
  String spurProfilBeschreibung(String km, int tief, int hoch, int auf) {
    return 'Höhenprofil über $km km, von $tief bis $hoch Meter, $auf Meter Aufstieg.';
  }

  @override
  String get gelaendeOeffnen => 'Gelände ansehen';

  @override
  String get gelaendeVideoErstellen => 'Video erstellen';

  @override
  String get bibRueckblick => 'Rückblick';

  @override
  String get bibKalender => 'Kalender';

  @override
  String get rbFamilientage => 'Familientage';

  @override
  String rbHeute(String satz) {
    return 'Heute: $satz';
  }

  @override
  String rbMorgen(String satz) {
    return 'Morgen: $satz';
  }

  @override
  String rbInTagen(int n, String satz) {
    return 'In $n Tagen: $satz';
  }

  @override
  String rbGeburtstag(String name, int jahre) {
    return '$name wird $jahre';
  }

  @override
  String rbGeburtstagVerstorben(String name, int jahre) {
    return '$name wäre $jahre geworden';
  }

  @override
  String rbTodestag(String name, int jahre) {
    String _temp0 = intl.Intl.pluralLogic(
      jahre,
      locale: localeName,
      other: '$name starb vor $jahre Jahren',
      one: '$name starb vor einem Jahr',
    );
    return '$_temp0';
  }

  @override
  String rbHochzeitstag(String name, int jahre) {
    return '$jahre. Hochzeitstag von $name';
  }

  @override
  String rbJahr(Object jahr) {
    return 'Dein Jahr $jahr';
  }

  @override
  String get rbJahrUntertitel =>
      'In Zahlen und Bildern – mit Personen, Reisen und den besten Fotos';

  @override
  String get rbGemerkt => 'Gemerkt';

  @override
  String get rbVergessen => 'Nicht mehr merken';

  @override
  String get rbMerken => 'Merken';

  @override
  String get rbLetzteTage => 'Die letzten zwei Wochen';

  @override
  String get rbKeine =>
      'An keinem der letzten vierzehn Tage gibt es Fotos aus früheren Jahren.';

  @override
  String rbTagVorJahren(String datum, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'vor $n Jahren',
      one: 'vor einem Jahr',
    );
    return '$datum · $_temp0';
  }

  @override
  String get rbSchoensteReisen => 'Die schönsten Reisen';

  @override
  String rbReise(Object jahr, int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Lieblingsfotos',
      one: '1 Lieblingsfoto',
    );
    return '$jahr · $_temp0';
  }

  @override
  String get jrVorjahr => 'Vorjahr';

  @override
  String get jrFolgejahr => 'Folgejahr';

  @override
  String jrLeer(Object jahr) {
    return 'Aus $jahr gibt es keine Aufnahmen.';
  }

  @override
  String get jrFotos => 'Fotos';

  @override
  String get jrVideos => 'Videos';

  @override
  String get jrTage => 'Tage mit Fotos';

  @override
  String get jrLaender => 'Länder';

  @override
  String get jrOrte => 'Orte';

  @override
  String get jrStaerksterMonat => 'stärkster Monat';

  @override
  String get jrAuswahl => 'Die besten Fotos';

  @override
  String get jrPersonen => 'Am häufigsten dabei';

  @override
  String get jrReisen => 'Reisen';

  @override
  String get kalLeer => 'Noch keine Fotos oder Videos.';

  @override
  String get sucheAlsAlbum => 'Als intelligentes Album merken';

  @override
  String sucheAlsAlbumGemerkt(String name) {
    return '„$name“ steht jetzt unter Alben.';
  }

  @override
  String get albenIntelligent => 'Intelligente Alben';

  @override
  String get albenIntelligentHinweis =>
      'Das Album zeigt immer, was die Suche gerade findet – auch Fotos, die erst später dazukommen.';

  @override
  String get albenName => 'Name';

  @override
  String get albenMerken => 'Merken';

  @override
  String get albenLoeschen => 'Album löschen';

  @override
  String albenIntelligentLoeschen(String name) {
    return '„$name“ löschen? Die Fotos bleiben, nur die gemerkte Suche geht.';
  }

  @override
  String get betrachterGesichterZeigen => 'Gesichter zeigen';

  @override
  String get betrachterGesichterAus => 'Gesichter ausblenden';

  @override
  String get betrachterGesichtAufziehen => 'Gesicht aufziehen';

  @override
  String get betrachterAufziehenHinweis =>
      'Einen Rahmen um das Gesicht ziehen.';

  @override
  String get betrachterRahmenZuKlein =>
      'Der Rahmen ist zu klein – bitte um das ganze Gesicht ziehen.';

  @override
  String get betrachterGesichtFehler =>
      'Das Gesicht liess sich nicht anlegen – ist der Server erreichbar?';

  @override
  String get betrachterNichtMehrDurchsuchen =>
      'Nicht mehr nach Gesichtern durchsuchen';

  @override
  String get betrachterWiederDurchsuchen =>
      'Wieder nach Gesichtern durchsuchen';

  @override
  String get betrachterNichtMehrDurchsuchtHinweis =>
      'Dieses Foto wird beim erneuten Durchsuchen übersprungen. Erkannte Gesichter bleiben.';

  @override
  String get betrachterWiederDurchsuchtHinweis =>
      'Dieses Foto wird wieder mitdurchsucht.';

  @override
  String get gesichterRahmenLoeschen => 'Rahmen löschen';

  @override
  String get gesichterRahmenLoeschenFrage =>
      'Diesen Rahmen löschen? Die Erkennung verschwindet überall.';

  @override
  String get gesichterAlleIgnorieren => 'Alle unbenannten Gesichter ignorieren';

  @override
  String gesichterAlleIgnorierenHinweis(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Gesichter wandern nach „Ignoriert“',
      one: 'Ein Gesicht wandert nach „Ignoriert“',
      zero: 'Nichts mehr offen',
    );
    return '$_temp0';
  }

  @override
  String gesichterAlleIgnoriertMeldung(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other:
          '$anzahl Gesichter ignoriert. Unter „Ignoriert“ holst du einzelne zurück.',
      one: 'Ein Gesicht ignoriert. Unter „Ignoriert“ holst du einzelne zurück.',
      zero: 'Es war nichts zu ignorieren.',
    );
    return '$_temp0';
  }

  @override
  String get gesichterAlleLoeschen => 'Alle unbenannten Erkennungen löschen';

  @override
  String get gesichterAlleLoeschenHinweis =>
      'Gibt Platz frei, kommt beim nächsten Scan aber wieder';

  @override
  String get gesichterAlleLoeschenTitel => 'Erkennungen wirklich löschen?';

  @override
  String get gesichterAlleLoeschenText =>
      'Alle unbenannten Erkennungen werden samt ihrer Ausschnitte gelöscht – auch die bereits ignorierten. Benannte Personen bleiben unberührt.\n\nDas ist nicht dauerhaft: Der nächste Gesichts-Scan findet dieselben Stellen wieder. Wenn du sie dauerhaft loswerden willst, nimm stattdessen „Alle unbenannten Gesichter ignorieren“ – das überlebt auch einen erneuten Scan.';

  @override
  String get gesichterLoeschen => 'Löschen';

  @override
  String gesichterGeloeschtMeldung(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl Erkennungen gelöscht.',
      one: 'Eine Erkennung gelöscht.',
      zero: 'Es gab keine Erkennungen zum Löschen.',
    );
    return '$_temp0';
  }

  @override
  String get gesichterIgnoriert => 'Ignoriert';

  @override
  String gesichterIgnoriertErste(int n, int gesamt) {
    return 'Die ersten $n von $gesamt ignorierten Gesichtern';
  }

  @override
  String get gesichterKeineIgnorierten => 'Keine ignorierten Gesichter.';

  @override
  String gesichterZurueckholen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl zurückholen',
      zero: 'Zurückholen',
    );
    return '$_temp0';
  }

  @override
  String gesichterZurueckgeholt(int anzahl) {
    return '$anzahl zurückgeholt';
  }

  @override
  String betrachterUnbenannteIgnorieren(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl unbenannte Gesichter ignorieren',
      one: 'Unbenanntes Gesicht ignorieren',
      zero: 'Keine unbenannten Gesichter',
    );
    return '$_temp0';
  }

  @override
  String betrachterUnbenannteLoeschen(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other: '$anzahl unbenannte Erkennungen löschen',
      one: 'Unbenannte Erkennung löschen',
      zero: 'Keine unbenannten Erkennungen',
    );
    return '$_temp0';
  }

  @override
  String betrachterUnbenannteLoeschenFrage(int anzahl) {
    String _temp0 = intl.Intl.pluralLogic(
      anzahl,
      locale: localeName,
      other:
          'Die $anzahl unbenannten Erkennungen auf diesem Foto löschen? Benannte Gesichter bleiben.',
      one:
          'Die unbenannte Erkennung auf diesem Foto löschen? Benannte Gesichter bleiben.',
    );
    return '$_temp0';
  }

  @override
  String get ansichtReihenfolge => 'Reihenfolge';

  @override
  String get sortAufnahmeNeu => 'Aufnahmedatum, neueste zuerst';

  @override
  String get sortAufnahmeAlt => 'Aufnahmedatum, älteste zuerst';

  @override
  String get sortImportNeu => 'Zuletzt hinzugefügt';

  @override
  String get sortName => 'Dateiname, A–Z';

  @override
  String get sortBewertung => 'Bewertung, beste zuerst';

  @override
  String get sortGroesse => 'Dateigrösse, grösste zuerst';

  @override
  String get ansichtNurMonate => 'Nur nach Monaten gliedern';

  @override
  String get ansichtNachTagen => 'Nach Tagen gliedern';

  @override
  String get ansichtReihen => 'Bündige Reihen – jedes Foto in seinem Format';

  @override
  String get ansichtQuadrate => 'Quadratisches Raster';

  @override
  String get ansichtKleiner => 'Kleinere Kacheln – mehr Monate auf einmal';

  @override
  String get ansichtGroesser => 'Grössere Kacheln';

  @override
  String get ansichtRaster => 'Raster';

  @override
  String get ansichtListe => 'Liste';

  @override
  String get ansichtGliederung => 'Gliederung';

  @override
  String get gruppeMonat => 'Nach Monat';

  @override
  String get gruppeTag => 'Nach Tag';

  @override
  String get gruppeKamera => 'Nach Kamera';

  @override
  String get gruppeKeine => 'Ohne Gliederung';

  @override
  String get listeSpalten => 'Spalten';

  @override
  String get listeSpalteDateiname => 'Dateiname';

  @override
  String get listeSpalteDatum => 'Aufgenommen';

  @override
  String get listeSpalteKamera => 'Kamera';

  @override
  String get listeSpalteObjektiv => 'Objektiv';

  @override
  String get listeSpalteBelichtung => 'Belichtung';

  @override
  String get listeSpalteBewertung => 'Bewertung';

  @override
  String get listeSpalteFarbe => 'Farbe';

  @override
  String get listeSpalteMasse => 'Masse';

  @override
  String get listeSpalteGroesse => 'Dateigrösse';

  @override
  String get listeSpalteArt => 'Art';

  @override
  String get listeSpalteOrt => 'Ort';

  @override
  String get listeOhneKamera => 'Ohne Kameraangabe';

  @override
  String get listeGeschaetzt => 'geschätzt';

  @override
  String get listeFoto => 'Foto';

  @override
  String get listeVideo => 'Video';

  @override
  String get ansichtJahre => 'Jahre';

  @override
  String get auswahlVergleichen => 'Vergleichen';

  @override
  String get vergleichTitel => 'Zwei Fotos vergleichen';

  @override
  String get vergleichNebeneinander => 'Nebeneinander';

  @override
  String get vergleichUebereinander => 'Übereinander';

  @override
  String get vergleichKoppeln => 'Ansichten koppeln';

  @override
  String get vergleichEntkoppeln => 'Ansichten entkoppeln';

  @override
  String get vergleichZuruecksetzen => 'Zoom zurücksetzen';

  @override
  String eigenCodesUebrig(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Noch $n Codes übrig',
      one: 'Noch ein Code übrig',
      zero: 'Keine Codes mehr übrig',
    );
    return '$_temp0';
  }

  @override
  String get eigenCodesNeu => 'Neue Codes erzeugen';

  @override
  String get eigenCodesHinweis =>
      'Mit einem Code aus der Authenticator-App bestätigen. Die bisherigen Wiederherstellungscodes gelten danach nicht mehr.';

  @override
  String get eigenCodesFertig =>
      'Jeder Code gilt einmal, wenn die Authenticator-App fehlt. Bitte sicher aufbewahren, etwa im Passwortmanager – die bisherigen gelten nicht mehr.';

  @override
  String get eigenCodesKopiert => 'Kopiert';

  @override
  String get bibAufnahmedaten => 'Aufnahmedaten';

  @override
  String get datenPruefen => 'Neu prüfen';

  @override
  String get datenPrueft => 'Prüfe …';

  @override
  String get datenKeine => 'Alle Aufnahmedaten passen zu ihren Dateinamen.';

  @override
  String datenHinweis(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other:
          'Bei $n Aufnahmen nennt der Dateiname ein anderes Datum. Übernommen wird nur das Datum in der Bibliothek; die Dateien bleiben unverändert.',
      one:
          'Bei einer Aufnahme nennt der Dateiname ein anderes Datum. Übernommen wird nur das Datum in der Bibliothek; die Datei bleibt unverändert.',
    );
    return '$_temp0';
  }

  @override
  String datenUebernehmen(int n) {
    return '$n übernehmen';
  }

  @override
  String datenFrage(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Das Datum von $n Aufnahmen übernehmen?',
      one: 'Das Datum dieser Aufnahme übernehmen?',
    );
    return '$_temp0';
  }

  @override
  String get datenLautName => 'laut Dateiname';

  @override
  String get datenLautDatei => 'laut Datei und Dateiname';

  @override
  String get datenNurTag => 'nur der Tag, bleibt geschätzt';

  @override
  String get datenGeschaetzt => 'geschätzt';

  @override
  String get datenOhneServer =>
      'Die Prüfung läuft auf dem Server – dafür braucht es eine Verbindung.';

  @override
  String angabenNameNennt(String d) {
    return 'Der Dateiname nennt $d';
  }

  @override
  String angabenDateiNennt(String d) {
    return 'Datei und Dateiname nennen $d';
  }

  @override
  String get angabenUebernehmen => 'Übernehmen';

  @override
  String get jetztAus => 'Die automatische Sicherung ist ausgeschaltet.';

  @override
  String get jetztEinrichten => 'Einrichten';

  @override
  String get jetztWartetWlan => 'Kein WLAN – eingestellt ist „Nur im WLAN“.';

  @override
  String get jetztMobil => 'Mobil sichern';

  @override
  String jetztTeils(int n, int f) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen gesichert',
      one: '1 Aufnahme gesichert',
    );
    return '$_temp0, $f nicht';
  }

  @override
  String get jetztDetails => 'Details';

  @override
  String jetztGesichert(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen gesichert',
      one: '1 Aufnahme gesichert',
    );
    return '$_temp0';
  }

  @override
  String get jetztAllesSicher => 'Alles ist gesichert.';

  @override
  String get einstSicherung => 'Automatisch hochladen';

  @override
  String get einstSicherungText =>
      'Neue Fotos und Videos dieses Telefons gehen von selbst zum Server. Gilt nur für dieses Telefon.';

  @override
  String loeschenAuchTelefon(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n davon auch aus der Fotomediathek dieses Telefons löschen',
      one: 'Auch aus der Fotomediathek dieses Telefons löschen',
    );
    return '$_temp0';
  }

  @override
  String get loeschenAuchTelefonHinweis =>
      'Das Telefon fragt gleich selbst noch einmal nach.';

  @override
  String get loeschenAuchTelefonHinweisIos =>
      'Das iPhone fragt gleich selbst noch einmal nach. In Fotos liegen sie danach 30 Tage unter „Zuletzt gelöscht“.';

  @override
  String vomTelefonGeloescht(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen auch vom Telefon gelöscht',
      one: '1 Aufnahme auch vom Telefon gelöscht',
      zero: 'Vom Telefon nichts gelöscht',
    );
    return '$_temp0';
  }

  @override
  String get sicherungVomTelefon => 'Beim Löschen auch vom Telefon löschen';

  @override
  String get sicherungVomTelefonHinweis =>
      'Für Fotos, die dieses Telefon gesichert hat. Die Rückfrage beim Löschen zeigt das Häkchen so voreingestellt.';

  @override
  String get sicherungPapierkorbTelefon =>
      'Gelöschtes auch vom Telefon entfernen';

  @override
  String get sicherungPapierkorbTelefonHinweis =>
      'Was in Photo Vault im Papierkorb liegt – auch auf einem anderen Gerät gelöscht – aus der Fotomediathek dieses Telefons löschen.';

  @override
  String get sicherungPapierkorbTelefonNichts =>
      'Nichts zu entfernen: Kein Foto aus dem Papierkorb liegt noch auf dem Telefon.';

  @override
  String get sicherungPapierkorbTelefonText =>
      'Diese Aufnahmen liegen in Photo Vault im Papierkorb. Das Telefon fragt gleich noch einmal nach.';

  @override
  String get lokalVomTelefonLoeschen => 'Vom Telefon löschen';

  @override
  String get teilenOriginal => 'Original';

  @override
  String get teilenOriginalHinweis =>
      'Die Datei, wie sie aufgenommen wurde – auch RAW und Video.';

  @override
  String get jpegVolleGroesse => 'JPEG – volle Grösse';

  @override
  String jpegKante(int kante) {
    return 'JPEG – $kante px';
  }

  @override
  String get teilenJpegHinweis =>
      'Mit der Bearbeitung. Datum und Kamera kommen mit, der Ort nicht.';

  @override
  String get teilenOhneVideos => 'Videos bleiben aussen vor.';

  @override
  String get teilenWandelt => 'Die Fotos werden als JPEG geholt …';

  @override
  String get albumOfflineSpeichern => 'Auf diesem Telefon offline behalten';

  @override
  String get albumOfflineAufheben => 'Nicht mehr offline behalten';

  @override
  String albumOfflineFertig(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n Aufnahmen sind offline verfügbar.',
      one: '1 Aufnahme ist offline verfügbar.',
    );
    return '$_temp0';
  }

  @override
  String get albumOfflineEntfernt =>
      'Das Album wird nicht mehr dauerhaft auf diesem Telefon behalten.';

  @override
  String get albumOfflineFehler =>
      'Noch nicht vollständig geladen. Das Telefon setzt den Download fort, sobald der Server erreichbar ist.';

  @override
  String get eigenOidcTitel => 'Anmeldung über den Anbieter';

  @override
  String eigenOidcVerknuepft(String anbieter) {
    return 'Verknüpft mit $anbieter';
  }

  @override
  String get eigenOidcNicht =>
      'Nicht verknüpft – die Anmeldung geht dann nur mit Passwort.';

  @override
  String get eigenOidcVerknuepfen => 'Verknüpfen';

  @override
  String get eigenOidcLaeuft => 'Beim Anbieter anmelden – Photo Vault wartet …';

  @override
  String get eigenOidcFertig =>
      'Verknüpft. Künftig geht die Anmeldung auch über den Anbieter.';

  @override
  String get eigenOidcAbgelehnt =>
      'Nicht verknüpft – abgebrochen oder abgelehnt.';

  @override
  String get eigenOidcZeitUm =>
      'Nicht verknüpft – vom Anbieter kam keine Antwort.';

  @override
  String get eigenOidcVergeben =>
      'Dieses Konto beim Anbieter gehört schon zu einem anderen Konto.';

  @override
  String get eigenOidcSeite => 'Fertig – zurück zu Photo Vault.';

  @override
  String get variantenBilden => 'Als Varianten stapeln';

  @override
  String get variantenHauptWaehlen => 'Hauptversion wählen';

  @override
  String get variantenHauptText =>
      'Die Hauptversion bleibt in Übersichten sichtbar. Alle Fassungen bleiben vollständig erhalten.';

  @override
  String get variantenSchonGestapelt =>
      'Mindestens eine Aufnahme gehört bereits zu einem Stapel. Löse diesen zuerst auf.';

  @override
  String variantenGebildet(int anzahl) {
    return '$anzahl Fassungen als Varianten gestapelt';
  }

  @override
  String get variantenRueckgaengig => 'Rückgängig';

  @override
  String get variantenEinzeln => 'Varianten einzeln zeigen';

  @override
  String variantenEinzelnFrage(int anzahl) {
    return 'Die $anzahl Fassungen wieder einzeln zeigen? Keine Datei wird gelöscht.';
  }
}
