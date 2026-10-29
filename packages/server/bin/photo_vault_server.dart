import 'dart:async';
import 'dart:io';

import 'package:kern/auswertung/auswertungen.dart' show Analysestufe;
import 'package:kern/auswertung/modelle.dart';
import 'package:kern/protokoll.dart';
import 'package:kern/services/bildwerkzeuge.dart';
import 'package:kern/services/geo_data_catalog.dart';
import 'package:kern/services/reverse_geocoder.dart';
import 'package:onnxruntime_api/onnxruntime_api.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault_server/photo_vault_server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> argumente) async {
  // Der abgeschottete Prüfprozess für Dateien von Gästen – ohne die
  // Einstellungen des Servers, die er nicht braucht und nicht sehen soll.
  if (argumente.isNotEmpty && argumente.first == 'gast-pruefen') {
    gastProzessEinrichten();
    exit(await gastPruefen(argumente.sublist(1)));
  }
  if (argumente.contains('--lebenszeichen')) {
    exit(await _lebenszeichen(Einstellungen.ausUmgebung()));
  }
  final Einstellungen e;
  try {
    e = Einstellungen.ausUmgebung();
  } on ArgumentError catch (f) {
    stderr.writeln(f.message);
    exit(78);
  }
  if (argumente.isNotEmpty) exit(await verwalte(argumente, e));

  protokollZiel = (meldung) =>
      stdout.writeln('${DateTime.now().toIso8601String()} $meldung');
  // Auf dem Server gibt es keinen nativen Kanal einer App: Bilder, Videos
  // und Ton gehen über die Werkzeuge (ffmpeg, libheif, LibRaw).
  Bildwerkzeuge.standard = const WerkzeugBildwerkzeuge();

  final sdb = Serverdatenbank.oeffne(e.serverdatenbank);
  final tresor = Tresorschluessel.ladeOderLegeAn(e.tresorschluessel);
  final konten = Kontodienst(sdb, tresor, totpPflicht: e.totpPflicht);
  if (e.alteZugangsdatei.existsSync()) {
    protokoll(
      '${e.alteZugangsdatei.path} gilt nicht mehr – angemeldet wird mit '
      'Konto und Gerät. Die Datei kann weg.',
    );
  }
  if (konten.alle().isEmpty) {
    protokoll(
      'Noch kein Konto. Das erste legt die App beim Verbinden an (aus dem '
      'Heimnetz) – oder: photo_vault_server konto anlegen NAME',
    );
  }

  final onnx = await _starteOnnx(e);
  final modelle = Modelle();
  if (onnx != null) modelle.richteEin(e.modelle.path);
  final bibliotheken = Bibliotheken(
    wurzel: e.bibliotheken,
    eingang: e.eingang,
    modelle: modelle,
    ortsverzeichnis: await _ladeOrtsverzeichnis(e.geodaten),
    selbst: e.selbstRechnen,
  );
  if (e.selbstRechnen.isEmpty) {
    protokoll(
      'Selbst gerechnet wird nichts – alles übernimmt die Rechenhilfe '
      'verbundener Rechner',
    );
  } else if (e.selbstRechnen.length < Analysestufe.values.length) {
    protokoll(
      'Selbst gerechnet wird nur: '
      '${e.selbstRechnen.map((s) => s.name).join(', ')} – den Rest '
      'übernimmt die Rechenhilfe verbundener Rechner',
    );
  }
  final oidc = e.oidc == null ? null : Oidc(e.oidc!);
  final speicher = Speicherwaechter(
    e.daten,
    warnAnteil: e.speicherWarnung,
    mindestFrei: e.speicherMindestGb * 1000 * 1000 * 1000,
  )..starte();
  final sicherung = Serversicherung(
    daten: e.daten,
    ziel: e.sicherung,
    tresor: tresor,
    konten: konten,
    bibliotheken: bibliotheken,
    um: e.sicherungUm,
  )..starte();
  if (e.sicherung != null) {
    protokoll(
      'Sicherung nach ${e.sicherung!.path}, täglich um '
      '${e.sicherungUm.stunde.toString().padLeft(2, '0')}:'
      '${e.sicherungUm.minute.toString().padLeft(2, '0')}'
      '${sicherung.eingerichtet ? '' : ' – noch nicht eingerichtet (App: Einstellungen → Server)'}',
    );
  }

  // Dateien von Gästen: in einem eigenen Prozess, wenn möglich ohne Netz.
  final gastpruefung = Gastpruefung(
    verbotenePfade: [await e.daten.resolveSymbolicLinks()],
  );
  unawaited(
    gastpruefung.abschottung.then(
      (a) => protokoll(
        a.ohneNetz
            ? 'Dateien von Gästen: isolierte Prüfung bereit'
            : 'Dateien von Gästen: isolierte Prüfung nicht verfügbar; Uploads werden abgewiesen',
      ),
    ),
  );
  final server = await shelf_io.serve(
    baueApi(
      konten: konten,
      bibliotheken: bibliotheken,
      absender: Absender(e.proxys),
      oidc: oidc,
      beschleunigerZustand: onnx?.zustand,
      speicher: speicher,
      sicherung: sicherung,
      web: e.web,
      oeffentlich: e.oeffentlich,
      gastpruefung: gastpruefung,
    ),
    e.adresse,
    e.port,
  );
  protokoll(
    e.web == null
        ? 'Weboberfläche: keine (PV_WEB)'
        : 'Weboberfläche unter /app/ aus ${e.web!.path}',
  );
  server.autoCompress = true;
  // Jede Bibliothek holt beim Öffnen nach, was offen blieb (Neustart
  // mitten in der Auswertung, neue Modelle) – erst, wenn der Server schon
  // lauscht. Vorher stand er dafür sieben Sekunden taub, und der Proxy
  // meldete nach jedem Neustart 502. Wer währenddessen eine Bibliothek
  // braucht, wartet auf dasselbe Öffnen (`fuer` hält es fest).
  unawaited(() async {
    for (final k in konten.alle()) {
      try {
        await bibliotheken.fuer(k.id);
      } catch (fehler) {
        protokoll('Bibliothek von ${k.name} nicht geöffnet: $fehler');
      }
    }
  }());
  protokoll(
    'Photo Vault Server auf http://${e.adresse}:${server.port} – '
    'Daten in ${e.daten.path}',
  );
  protokoll(
    'Anmeldung: TOTP ${e.totpPflicht ? 'Pflicht' : 'freiwillig'}'
    '${oidc == null ? '' : ', OIDC über ${e.oidc!.aussteller} '
              '(Weiterleitung: ${e.oidc!.rueckruf})'}'
    '${e.proxys.isEmpty ? '' : ', vertraute Proxys: ${e.proxys.join(', ')}'}',
  );
  final installiert = [
    for (final h in modelle.alle)
      if (h.installiert) h.name,
  ];
  protokoll(
    installiert.isEmpty
        ? 'Keine Modelle eingerichtet – es wird nichts ausgewertet, was eines '
              'braucht'
        : 'Modelle: ${installiert.join(', ')}',
  );

  await Future.any([
    ProcessSignal.sigint.watch().first,
    if (!Platform.isWindows) ProcessSignal.sigterm.watch().first,
  ]);
  protokoll('Beende …');
  await server.close();
  speicher.beende();
  sicherung.beende();
  await bibliotheken.schliesseAlle();
  oidc?.schliesse();
  sdb.schliesse();
  onnx?.beende();
  exit(0);
}

/// ONNX Runtime über FFI, falls eine Bibliothek angegeben ist. Ohne sie
/// rechnet kein Modell – der Server läuft trotzdem.
Future<FfiOnnxPlattform?> _starteOnnx(Einstellungen e) async {
  final bibliothek = e.onnxRuntime;
  if (bibliothek == null) {
    protokoll('PV_ONNXRUNTIME nicht gesetzt – ohne KI-Auswertung');
    return null;
  }
  try {
    final plattform = await FfiOnnxPlattform.starte(
      bibliothek.path,
      beschleuniger: e.beschleuniger,
      zwischenspeicher: e.beschleunigerZwischenspeicher.path,
    );
    OnnxRuntimePlatform.instance = plattform;
    protokoll('ONNX Runtime ${plattform.fassung} aus ${bibliothek.path}');
    if (plattform.fassung != geprueftFassung) {
      protokoll(
        'Die App rechnet mit ONNX Runtime $geprueftFassung – auf der CPU '
        'können Ergebnisse minimal abweichen',
      );
    }
    if (!e.beschleuniger.istCpu) {
      final verfuegbar = await plattform.getAvailableProviders();
      protokoll(
        'Beschleuniger ${e.beschleuniger} (die Bibliothek kennt '
        '${verfuegbar.join(', ')}); jedes Modell rechnet zur Gegenprobe '
        'zuerst auch auf der CPU',
      );
    }
    return plattform;
  } catch (fehler) {
    protokoll('ONNX Runtime nicht ladbar (${bibliothek.path}): $fehler');
    return null;
  }
}

/// Das GeoNames-Verzeichnis für Ortsnamen, falls seine drei Dateien da
/// sind.
Future<ReverseGeocoder?> _ladeOrtsverzeichnis(Directory ordner) async {
  final staedte = File(p.join(ordner.path, GeoDataCatalog.citiesFileName));
  final regionen = File(p.join(ordner.path, GeoDataCatalog.admin1FileName));
  final laender = File(p.join(ordner.path, GeoDataCatalog.countryFileName));
  if (!staedte.existsSync() ||
      !regionen.existsSync() ||
      !laender.existsSync()) {
    protokoll('Keine GeoNames-Daten in ${ordner.path} – ohne Ortsnamen');
    return null;
  }
  try {
    return await ReverseGeocoder.loadFromFiles(
      citiesFile: staedte,
      admin1File: regionen,
      countryFile: laender,
    );
  } catch (fehler) {
    protokoll('GeoNames-Daten nicht lesbar: $fehler');
    return null;
  }
}

/// Fragt den laufenden Server nach seinem Lebenszeichen – für den
/// HEALTHCHECK im Docker-Bild, das dafür kein curl braucht. 0 heisst: er
/// antwortet.
Future<int> _lebenszeichen(Einstellungen e) async {
  final adresse = switch (e.adresse) {
    '0.0.0.0' => '127.0.0.1',
    '::' => '::1',
    final a => a,
  };
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final anfrage = await client.getUrl(
      Uri(scheme: 'http', host: adresse, port: e.port, path: '/api/v1/zustand'),
    );
    final antwort = await anfrage.close().timeout(const Duration(seconds: 5));
    await antwort.drain<void>();
    return antwort.statusCode == 200 ? 0 : 1;
  } catch (_) {
    return 1;
  } finally {
    client.close(force: true);
  }
}
