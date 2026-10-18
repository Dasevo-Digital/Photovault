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
  String get sucheHinweisText => 'Dateiname, Beschreibung, erkannter Text …';

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
}
