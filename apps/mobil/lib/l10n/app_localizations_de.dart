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
}
