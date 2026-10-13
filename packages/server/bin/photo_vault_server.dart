import 'dart:async';
import 'dart:io';

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
  final konten = Kontodienst(
    sdb,
    Tresorschluessel.ladeOderLegeAn(e.tresorschluessel),
    totpPflicht: e.totpPflicht,
  );
  if (e.alteZugangsdatei.existsSync()) {
    protokoll(
      '${e.alteZugangsdatei.path} gilt nicht mehr – angemeldet wird mit '
      'Konto und Gerät. Die Datei kann weg.',
    );
  }
  if (konten.alle().isEmpty) {
    protokoll(
      'Noch kein Konto. Anlegen mit: photo_vault_server konto anlegen NAME',
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
  );
  // Jede Bibliothek holt beim Öffnen nach, was offen blieb (Neustart
  // mitten in der Auswertung, neue Modelle).
  for (final k in konten.alle()) {
    await bibliotheken.fuer(k.id);
  }
  final oidc = e.oidc == null ? null : Oidc(e.oidc!);

  final server = await shelf_io.serve(
    baueApi(
      konten: konten,
      bibliotheken: bibliotheken,
      absender: Absender(e.proxys),
      oidc: oidc,
      beschleunigerZustand: onnx?.zustand,
    ),
    e.adresse,
    e.port,
  );
  server.autoCompress = true;
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
