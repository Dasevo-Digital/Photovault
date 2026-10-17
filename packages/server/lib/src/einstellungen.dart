import 'dart:io';

import 'package:kern/auswertung/auswertungen.dart' show Analysestufe;
import 'package:path/path.dart' as p;

import 'beschleuniger.dart';
import 'oidc.dart';

/// Wie der Server läuft.
///
/// Alles kommt aus Umgebungsvariablen, damit Docker, systemd und ein Aufruf
/// von Hand dieselben Schalter haben und kein Schalter nur in einer der drei
/// Welten existiert.
///
/// | Variable             | Vorgabe               |                                       |
/// |----------------------|-----------------------|---------------------------------------|
/// | `PV_DATEN`           | `./daten`             | Konten, Bibliotheken, Uploads         |
/// | `PV_ADRESSE`         | `127.0.0.1`           | worauf gehört wird                    |
/// | `PV_PORT`            | `8790`                |                                       |
/// | `PV_MODELLE`         | `<PV_DATEN>/modelle`  | die KI-Modelle                        |
/// | `PV_ONNXRUNTIME`     | im Bündel `lib/`      | `libonnxruntime.so` für die Modelle   |
/// | `PV_WEB`             | im Bündel `web/`      | Dateien der Weboberfläche; `aus` = keine |
/// | `PV_BESCHLEUNIGER`   | `cpu`                 | `openvino`, `cuda`, … (siehe `Beschleuniger`) |
/// | `PV_SELBST_RECHNEN`  | `alles`               | welche Stufen der Server selbst rechnet: `alles`, `nichts` oder eine Liste wie `schlagwoerter,wiedererkennung,spracherkennung` |
/// | `PV_GEODATEN`        | `<PV_DATEN>/geodaten` | GeoNames für Ortsnamen                |
/// | `PV_TOTP`            | `pflicht`             | `frei`: TOTP nur, wer es einrichtet   |
/// | `PV_PROXY`           | –                     | vertraute Proxys (Adressen, Netze, `privat`) |
/// | `PV_OEFFENTLICH`     | –                     | die Adresse von aussen (für OIDC)     |
/// | `PV_OIDC_AUSSTELLER` | –                     | `issuer` des OIDC-Anbieters           |
/// | `PV_OIDC_CLIENT`     | –                     | Client-ID beim Anbieter               |
/// | `PV_OIDC_GEHEIMNIS`  | –                     | Client-Geheimnis (oder `…_DATEI`)     |
///
/// Ohne `PV_ONNXRUNTIME` rechnet kein Modell: Der Server nimmt Fotos an und
/// zeigt sie, wertet aber nichts aus, was ein Modell braucht. Ohne die drei
/// GeoNames-Dateien bleiben die Ortsnamen leer, die Koordinaten nicht.
///
/// **Die Vorgabe ist nur der eigene Rechner.** Wer von aussen erreichbar
/// sein will, sagt es ausdrücklich (im Docker-Bild `0.0.0.0` hinter dem
/// Reverse Proxy) – ein Server mit allen Familienfotos soll nicht aus
/// Versehen im Netz stehen.
class Einstellungen {
  Einstellungen({
    required this.daten,
    this.web,
    this.adresse = '127.0.0.1',
    this.port = 8790,
    Directory? modelle,
    this.onnxRuntime,
    this.beschleuniger = Beschleuniger.cpu,
    this.selbstRechnen = const {...Analysestufe.values},
    this.speicherWarnung = 0.85,
    this.speicherMindestGb = 2,
    this.sicherung,
    this.sicherungUm = (stunde: 3, minute: 30),
    Directory? geodaten,
    this.totpPflicht = true,
    this.proxys = const [],
    this.oeffentlich,
    this.oidc,
  }) : modelle = modelle ?? Directory(p.join(daten.path, 'modelle')),
       geodaten = geodaten ?? Directory(p.join(daten.path, 'geodaten'));

  factory Einstellungen.ausUmgebung([Map<String, String>? umgebung]) {
    final u = umgebung ?? Platform.environment;
    final daten = Directory(p.absolute(u['PV_DATEN'] ?? 'daten'));
    final port = int.tryParse(u['PV_PORT'] ?? '');
    final oeffentlich = u['PV_OEFFENTLICH'] == null
        ? null
        : Uri.parse(u['PV_OEFFENTLICH']!);
    return Einstellungen(
      daten: daten,
      adresse: u['PV_ADRESSE'] ?? '127.0.0.1',
      port: port ?? 8790,
      modelle: u['PV_MODELLE'] == null
          ? null
          : Directory(p.absolute(u['PV_MODELLE']!)),
      onnxRuntime: u['PV_ONNXRUNTIME'] == null
          ? onnxImBuendel()
          : File(p.absolute(u['PV_ONNXRUNTIME']!)),
      web: switch (u['PV_WEB']) {
        null => webImBuendel(),
        'aus' => null,
        final w => Directory(p.absolute(w)),
      },
      beschleuniger: Beschleuniger.aus(u['PV_BESCHLEUNIGER']),
      selbstRechnen: selbstRechnenAus(u['PV_SELBST_RECHNEN']),
      speicherWarnung: _prozent(u['PV_SPEICHER_WARNUNG'], 85) / 100,
      speicherMindestGb: _zahl(u['PV_SPEICHER_MINDEST'], 2),
      sicherung: (u['PV_SICHERUNG'] ?? '').trim().isEmpty
          ? null
          : Directory(p.absolute(u['PV_SICHERUNG']!.trim())),
      sicherungUm: _uhrzeit(u['PV_SICHERUNG_UM']),
      geodaten: u['PV_GEODATEN'] == null
          ? null
          : Directory(p.absolute(u['PV_GEODATEN']!)),
      totpPflicht: switch (u['PV_TOTP']) {
        null || 'pflicht' => true,
        'frei' => false,
        final w => throw ArgumentError('PV_TOTP: „$w“ (pflicht oder frei)'),
      },
      proxys: [
        for (final s in (u['PV_PROXY'] ?? '').split(','))
          if (s.trim().isNotEmpty) s.trim(),
      ],
      oeffentlich: oeffentlich,
      oidc: _oidcAus(u, oeffentlich),
    );
  }

  static OidcEinstellungen? _oidcAus(Map<String, String> u, Uri? oeffentlich) {
    final aussteller = u['PV_OIDC_AUSSTELLER'];
    if (aussteller == null || aussteller.isEmpty) return null;
    final client = u['PV_OIDC_CLIENT'];
    if (client == null || client.isEmpty) {
      throw ArgumentError('PV_OIDC_AUSSTELLER braucht PV_OIDC_CLIENT');
    }
    if (oeffentlich == null) {
      throw ArgumentError(
        'PV_OIDC_AUSSTELLER braucht PV_OEFFENTLICH – die Adresse, unter der '
        'der Anbieter den Browser zurückschickt',
      );
    }
    var geheimnis = u['PV_OIDC_GEHEIMNIS'];
    final datei = u['PV_OIDC_GEHEIMNIS_DATEI'];
    if (geheimnis == null && datei != null) {
      geheimnis = File(datei).readAsStringSync().trim();
    }
    return OidcEinstellungen(
      aussteller: Uri.parse(aussteller),
      client: client,
      geheimnis: geheimnis == null || geheimnis.isEmpty ? null : geheimnis,
      oeffentlich: oeffentlich,
    );
  }

  /// Die Weboberfläche im Bündel (`web/` neben `bin/`); bei `dart run`
  /// der Ordner im Quelltext.
  static Directory? webImBuendel([String? programm]) {
    for (final d in [
      Directory(
        p.join(p.dirname(programm ?? Platform.resolvedExecutable), '..', 'web'),
      ),
      Directory(p.join(Directory.current.path, 'web')),
    ]) {
      if (File(p.join(d.path, 'index.html')).existsSync()) {
        return Directory(p.normalize(d.absolute.path));
      }
    }
    return null;
  }

  /// Die ONNX Runtime, die im Bündel neben dem Programm liegt
  /// (`bin/photo_vault_server` und `lib/libonnxruntime.so.*`) – so findet
  /// der Server sie ohne Einstellung, im Docker-Bild wie unter systemd.
  /// Bei `dart run` liegt dort keine.
  static File? onnxImBuendel([String? programm]) {
    final lib = Directory(
      p.join(p.dirname(programm ?? Platform.resolvedExecutable), '..', 'lib'),
    );
    if (!lib.existsSync()) return null;
    final da = [
      for (final f in lib.listSync().whereType<File>())
        if (p.basename(f.path).startsWith('libonnxruntime.so')) f,
    ]..sort((a, b) => a.path.compareTo(b.path));
    return da.isEmpty ? null : File(p.normalize(da.last.path));
  }

  final Directory daten;

  /// Die Dateien der Weboberfläche; `null` heisst keine.
  final Directory? web;
  final String adresse;
  final int port;
  final Directory modelle;

  /// Welche Stufen der Auswertung der Server selbst rechnet. Die übrigen
  /// rechnen verbundene Rechner mit eingeschalteter Rechenhilfe – eine
  /// schwache Maschine überlässt so die Bildmodelle dem Rechner.
  final Set<Analysestufe> selbstRechnen;

  /// Ab welchem Anteil belegt der Speicher als knapp gilt
  /// (`PV_SPEICHER_WARNUNG` in Prozent, Vorgabe 85).
  final double speicherWarnung;

  /// Unter so vielen GB frei nimmt der Server keine Uploads mehr an
  /// (`PV_SPEICHER_MINDEST`, Vorgabe 2).
  final int speicherMindestGb;

  /// Wohin der Server jede Nacht sichert (`PV_SICHERUNG`, z. B. die
  /// eingehängte Freigabe eines NAS) – `null`: keine Sicherung.
  final Directory? sicherung;

  /// Wann (`PV_SICHERUNG_UM`, Vorgabe 03:30, Ortszeit).
  final ({int stunde, int minute}) sicherungUm;

  static ({int stunde, int minute}) _uhrzeit(String? text) {
    final t = (text ?? '').trim();
    if (t.isEmpty) return (stunde: 3, minute: 30);
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t);
    final h = int.tryParse(m?.group(1) ?? '');
    final min = int.tryParse(m?.group(2) ?? '');
    if (h == null || min == null || h > 23 || min > 59) {
      throw ArgumentError('PV_SICHERUNG_UM: „$t“ – Uhrzeit wie 03:30');
    }
    return (stunde: h, minute: min);
  }

  static int _prozent(String? text, int vorgabe) {
    final w = _zahl(text, vorgabe);
    if (w < 1 || w > 99) {
      throw ArgumentError('PV_SPEICHER_WARNUNG: „$text“ – 1 bis 99 Prozent');
    }
    return w;
  }

  static int _zahl(String? text, int vorgabe) {
    final t = (text ?? '').trim();
    if (t.isEmpty) return vorgabe;
    return int.tryParse(t) ??
        (throw ArgumentError('„$t“ ist keine ganze Zahl'));
  }

  /// Liest `PV_SELBST_RECHNEN`.
  static Set<Analysestufe> selbstRechnenAus(String? text) {
    final t = (text ?? '').trim();
    if (t.isEmpty || t == 'alles') return {...Analysestufe.values};
    if (t == 'nichts') return {};
    final namen = Analysestufe.values.asNameMap();
    return {
      for (final teil in t.split(','))
        if (teil.trim().isNotEmpty)
          namen[teil.trim()] ??
              (throw ArgumentError(
                'PV_SELBST_RECHNEN: „${teil.trim()}“ – bekannt sind '
                '${namen.keys.join(', ')}',
              )),
    };
  }

  /// Womit die Modelle rechnen (siehe [Beschleuniger]).
  final Beschleuniger beschleuniger;

  /// Wohin OpenVINO die für die Grafik übersetzten Modelle legt.
  Directory get beschleunigerZwischenspeicher =>
      Directory(p.join(daten.path, 'beschleuniger'));

  final File? onnxRuntime;
  final Directory geodaten;
  final bool totpPflicht;
  final List<String> proxys;
  final Uri? oeffentlich;
  final OidcEinstellungen? oidc;

  /// Eine Bibliothek je Konto.
  Directory get bibliotheken => Directory(p.join(daten.path, 'bibliotheken'));

  /// Uploads, die noch nicht vollständig sind – je Konto ein Ordner.
  Directory get eingang => Directory(p.join(daten.path, 'eingang'));

  /// Konten und Geräte.
  File get serverdatenbank => File(p.join(daten.path, 'server.sqlite'));

  /// Der Schlüssel für die TOTP-Geheimnisse.
  File get tresorschluessel => File(p.join(daten.path, 'server.schluessel'));

  /// Der eine Schlüssel aus der Zeit vor den Konten – gilt nicht mehr.
  File get alteZugangsdatei => File(p.join(daten.path, 'zugang.txt'));
}
