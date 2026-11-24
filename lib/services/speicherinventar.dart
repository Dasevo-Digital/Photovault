import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, listEquals;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'bibliotheksgeraetedaten.dart';
import 'library_location.dart';
import 'platform/folder_access.dart';
import 'platform/speicherlaufwerk.dart';
import 'speicherkarte.dart';

enum Speicherortart { bibliothek, dateien, sicherung }

class Speicherpruefung {
  const Speicherpruefung(this.am, this.bestaetigt, this.abgeschlossen);
  final DateTime am;
  final int bestaetigt;
  final bool abgeschlossen;
}

class Speicherorteintrag {
  const Speicherorteintrag({
    required this.id,
    required this.name,
    required this.pfad,
    required this.art,
    required this.erreichbar,
    required this.bibliothek,
    this.aktiv = false,
    this.aufgeloesterPfad,
    this.laufwerk,
    this.pruefung,
    this.katalogVorhanden = false,
    this.nachweiseUnlesbar = false,
    this.weiterePfade = const [],
    this.laufwerkHistorisch = false,
    this.standard = false,
  });
  final String id, name, pfad, bibliothek;
  final Speicherortart art;
  final bool erreichbar, aktiv, katalogVorhanden, nachweiseUnlesbar;
  final bool laufwerkHistorisch;
  final String? aufgeloesterPfad;
  final Speicherlaufwerk? laufwerk;
  final Speicherpruefung? pruefung;
  final List<String> weiterePfade;

  /// Gehört zum Standardordner der App. Der hat keinen eigenen Namen;
  /// [name] ist dann das feste „Standard“ aus [LibraryLocation.bekannte].
  final bool standard;

  /// Der Name, wie ihn die Oberfläche zeigt – wie
  /// [BibliothekMitZustand.anzeigename]: Vorher stand auch in der
  /// englischen Oberfläche „Library: Standard“ (#489).
  String anzeigename(String standardname) => standard ? standardname : name;
}

class SpeicherinventarStand {
  const SpeicherinventarStand(this.orte, {this.listeUnlesbar = false});
  final List<Speicherorteintrag> orte;
  final bool listeUnlesbar;
}

/// Inventar bekannter Ordner. Öffnet keinen Katalog und erzeugt weder
/// Ordner noch Kennungsdateien in inaktiven Bibliotheken.
class Speicherinventar {
  Speicherinventar({
    required this.aktiveWurzel,
    required this.privat,
    Future<List<BibliothekMitZustand>> Function()? bekannte,
    Future<Speicherlaufwerk?> Function(String)? laufwerk,
    FolderAccess? zugriff,
  }) : bekannte =
           bekannte ?? (() => LibraryLocation.bekannte(fehlerMelden: true)),
       laufwerk = laufwerk ?? Laufwerksauskunft.fuer,
       zugriff = zugriff ?? FolderAccess.forCurrentPlatform();

  /// Enthält library.sqlite; die Originale liegen unter library/.
  final Directory aktiveWurzel, privat;
  final Future<List<BibliothekMitZustand>> Function() bekannte;
  final Future<Speicherlaufwerk?> Function(String) laufwerk;
  final FolderAccess zugriff;

  static Future<bool> istBibliotheksordner(Directory ordner) async {
    if (!p.isAbsolute(ordner.path)) return false;
    try {
      final datei = File(p.join(ordner.path, 'library.sqlite'));
      if (await FileSystemEntity.type(datei.path, followLinks: false) !=
              FileSystemEntityType.file ||
          !await Directory(p.join(ordner.path, 'library')).exists()) {
        return false;
      }
      final bytes = <int>[];
      await for (final teil in datei.openRead(0, 16)) {
        bytes.addAll(teil);
      }
      return listEquals(bytes, [...'SQLite format 3'.codeUnits, 0]);
    } on Object {
      return false;
    }
  }

  Future<SpeicherinventarStand> laden({bool Function()? abgebrochen}) async {
    void pruefeAbbruch() {
      if (abgebrochen?.call() == true) {
        throw StateError('pv_inventar_abbruch');
      }
    }

    var listeUnlesbar = false;
    final cacheDatei = File(p.join(privat.path, 'speicherinventar.json'));
    final cache = <String, _Ortsmerkmal>{};
    String? vorherText;
    try {
      if (await cacheDatei.exists()) {
        vorherText = await _leseBegrenzt(cacheDatei, 1024 * 1024);
        final j = jsonDecode(vorherText) as Map;
        if (j['fassung'] != 1) throw const FormatException('pv_inventar_cache');
        final werte = j['orte'] as Map;
        if (werte.length > 2000) {
          throw const FormatException('pv_inventar_cache');
        }
        for (final e in werte.entries) {
          cache[e.key as String] = _Ortsmerkmal.aus(e.value as Map);
        }
      }
    } on Object {
      cache.clear();
      listeUnlesbar = true;
    }
    final neu = <String, _Ortsmerkmal>{};
    List<BibliothekMitZustand> liste;
    try {
      liste = await bekannte();
    } on Object {
      liste = [];
      listeUnlesbar = true;
    }
    pruefeAbbruch();
    // Der tatsächliche aktive Pfad bleibt auch bei einer defekten Liste
    // sichtbar. Er hat Vorrang vor einem alten gespeicherten Lesezeichen.
    final ausListe = liste.where((b) => b.istAktiv).firstOrNull;
    final aktiverEintrag = BibliothekMitZustand(
      eintrag: Bibliothekseintrag(
        path: aktiveWurzel.path,
        name: ausListe?.eintrag.name ?? p.basename(aktiveWurzel.path),
      ),
      erreichbar: true,
      istAktiv: true,
      istStandard: ausListe?.istStandard ?? false,
      aufgeloesterPfad: aktiveWurzel.path,
    );
    liste = [aktiverEintrag, ...liste];
    final gesammelt = <String, _Bibliotheksort>{};
    for (final b in liste) {
      pruefeAbbruch();
      if (!p.isAbsolute(b.eintrag.path)) {
        listeUnlesbar = true;
        continue;
      }
      String? real;
      if (b.erreichbar) {
        try {
          final dir = Directory(b.aufgeloesterPfad ?? b.eintrag.path);
          if (await dir.exists()) real = await dir.resolveSymbolicLinks();
        } on Object {
          real = null;
        }
      }
      final key = _pfadkennung(real ?? b.eintrag.path);
      final vorhanden = gesammelt[key];
      if (vorhanden != null) {
        if (!p.equals(vorhanden.eintrag.path, b.eintrag.path)) {
          vorhanden.aliase.add(b.eintrag.path);
        }
        continue;
      }
      gesammelt[key] = _Bibliotheksort(
        b.eintrag,
        real,
        identical(b, aktiverEintrag),
        standard: b.istStandard,
      );
    }
    final orte = <Speicherorteintrag>[];
    final laufwerke = <String, Future<Speicherlaufwerk?>>{};
    Future<Speicherlaufwerk?> auskunft(String? real) async {
      if (real == null) return null;
      try {
        return await laufwerke
            .putIfAbsent(real, () => laufwerk(real))
            .timeout(const Duration(seconds: 3));
      } on Object {
        return null;
      }
    }

    for (final e in gesammelt.entries) {
      pruefeAbbruch();
      final b = e.value, root = b.real;
      final ziele = <Speicherorteintrag>[];
      final dateiorte = <Speicherorteintrag>[];
      var unlesbar = false;
      var katalog = false;
      String? ortId;
      Speicherlaufwerk? letzteZuordnung;
      if (root == null) {
        final alt = cache[_pfadkennung(b.eintrag.path)];
        ortId = alt?.kennung;
        letzteZuordnung = alt?.laufwerk;
        if (alt != null) neu[_pfadkennung(b.eintrag.path)] = alt;
      }
      try {
        if (root != null) {
          katalog =
              await FileSystemEntity.type(
                p.join(root, 'library.sqlite'),
                followLinks: false,
              ) ==
              FileSystemEntityType.file;
          ortId = await Bibliotheksgeraetedaten.bestehendeKennung(
            Directory(p.join(root, 'library')),
          );
          letzteZuordnung = await auskunft(root);
          for (final relativ in ['library', p.join('library', 'originals')]) {
            final alias = p.join(root, relativ);
            if (await FileSystemEntity.type(alias, followLinks: false) !=
                FileSystemEntityType.link) {
              continue;
            }
            String? real;
            try {
              final d = Directory(alias);
              if (await d.exists()) real = await d.resolveSymbolicLinks();
            } on Object {
              real = null;
            }
            dateiorte.add(
              Speicherorteintrag(
                id: 'dateien:${e.key}:$relativ',
                name: b.eintrag.name,
                standard: b.standard,
                pfad: alias,
                aufgeloesterPfad: real,
                art: Speicherortart.dateien,
                erreichbar: real != null,
                bibliothek: e.key,
                laufwerk: await auskunft(real),
              ),
            );
          }
          final merkmal = _Ortsmerkmal(ortId, letzteZuordnung);
          for (final alias in [b.eintrag.path, ...b.aliase]) {
            neu[_pfadkennung(alias)] = merkmal;
          }
        }
        final id = ortId;
        if (id != null) {
          final datei = File(p.join(privat.path, 'speicherkarte', '$id.json'));
          if (await datei.exists()) {
            if (await FileSystemEntity.type(datei.path, followLinks: false) !=
                FileSystemEntityType.file) {
              throw const FormatException('pv_inventar_nachweis');
            }
            final text = await _leseBegrenzt(datei, 32 * 1024 * 1024);
            final angaben = await compute(_zielangaben, text);
            final gesehen = <String>{};
            for (final n in angaben) {
              pruefeAbbruch();
              if (!p.isAbsolute(n.ziel)) {
                throw const FormatException('pv_inventar_ziel');
              }
              String? ziel;
              try {
                ziel = n.token.isEmpty
                    ? n.ziel
                    : await zugriff.resolveRoot(path: n.ziel, token: n.token);
                if (ziel != null) {
                  final dir = Directory(ziel);
                  ziel = await dir.exists()
                      ? await dir.resolveSymbolicLinks()
                      : null;
                }
              } on Object {
                ziel = null;
              }
              final key = _pfadkennung(ziel ?? n.ziel);
              if (!gesehen.add(key)) continue;
              final zielLaufwerk = ziel == null
                  ? cache[_pfadkennung(n.ziel)]?.laufwerk
                  : await auskunft(ziel);
              final merkmal = _Ortsmerkmal(
                neu.containsKey(_pfadkennung(n.ziel))
                    ? neu[_pfadkennung(n.ziel)]!.kennung
                    : cache[_pfadkennung(n.ziel)]?.kennung,
                zielLaufwerk,
              );
              neu[_pfadkennung(n.ziel)] = merkmal;
              ziele.add(
                Speicherorteintrag(
                  id: 'sicherung:${e.key}:$key',
                  name: b.eintrag.name,
                  standard: b.standard,
                  pfad: n.ziel,
                  aufgeloesterPfad: ziel,
                  art: Speicherortart.sicherung,
                  erreichbar: ziel != null,
                  bibliothek: e.key,
                  laufwerk: zielLaufwerk,
                  laufwerkHistorisch: ziel == null && zielLaufwerk != null,
                  pruefung: Speicherpruefung(
                    n.am,
                    n.bestaetigt,
                    n.abgeschlossen,
                  ),
                ),
              );
            }
          }
        }
      } on Object {
        pruefeAbbruch();
        unlesbar = true;
        ziele.clear();
      }
      orte.add(
        Speicherorteintrag(
          id: 'bibliothek:${e.key}',
          name: b.eintrag.name,
          standard: b.standard,
          pfad: b.eintrag.path,
          aufgeloesterPfad: root,
          art: Speicherortart.bibliothek,
          erreichbar: root != null,
          bibliothek: e.key,
          aktiv: b.aktiv,
          katalogVorhanden: katalog,
          laufwerk: letzteZuordnung,
          laufwerkHistorisch: root == null && letzteZuordnung != null,
          nachweiseUnlesbar: unlesbar,
          weiterePfade: List.unmodifiable(b.aliase),
        ),
      );
      orte.addAll(dateiorte);
      orte.addAll(ziele);
    }
    pruefeAbbruch();
    if (listeUnlesbar) {
      for (final e in cache.entries) {
        neu.putIfAbsent(e.key, () => e.value);
      }
    }
    try {
      if (neu.length <= 2000) {
        final text = jsonEncode({
          'fassung': 1,
          'orte': {for (final e in neu.entries) e.key: e.value.json()},
        });
        if (utf8.encode(text).length > 1024 * 1024) {
          throw const FormatException('pv_inventar_cache');
        }
        if (vorherText != text) {
          await cacheDatei.parent.create(recursive: true);
          final teil = File('${cacheDatei.path}.${const Uuid().v4()}.neu');
          try {
            await teil.writeAsString(text, flush: true);
            pruefeAbbruch();
            await teil.rename(cacheDatei.path);
          } finally {
            if (await teil.exists()) await teil.delete();
          }
        }
      } else {
        listeUnlesbar = true;
      }
    } on Object {
      listeUnlesbar = true;
    }
    return SpeicherinventarStand(
      List.unmodifiable(orte),
      listeUnlesbar: listeUnlesbar,
    );
  }
}

class _Bibliotheksort {
  _Bibliotheksort(
    this.eintrag,
    this.real,
    this.aktiv, {
    required this.standard,
  });
  final Bibliothekseintrag eintrag;
  final String? real;
  final bool aktiv, standard;
  final Set<String> aliase = {};
}

String _pfadkennung(String pfad) {
  final normal = p.normalize(p.absolute(pfad));
  return Platform.isWindows ? normal.toLowerCase() : normal;
}

Future<String> _leseBegrenzt(File datei, int maximum) async {
  final bytes = BytesBuilder(copy: false);
  await for (final teil in datei.openRead()) {
    if (bytes.length + teil.length > maximum) {
      throw const FormatException('pv_inventar_umfang');
    }
    bytes.add(teil);
  }
  return utf8.decode(bytes.takeBytes());
}

class _Zielangabe {
  const _Zielangabe(
    this.ziel,
    this.token,
    this.am,
    this.bestaetigt,
    this.abgeschlossen,
  );
  final String ziel, token;
  final DateTime am;
  final int bestaetigt;
  final bool abgeschlossen;
}

List<_Zielangabe> _zielangaben(String text) {
  final n = dekodiereSicherungsnachweise(text)
    ..sort((a, b) => b.am.compareTo(a.am));
  return [
    for (final e in n)
      _Zielangabe(e.ziel, e.token, e.am, e.bestaetigt, e.vollstaendig),
  ];
}

class _Ortsmerkmal {
  const _Ortsmerkmal(this.kennung, this.laufwerk);
  final String? kennung;
  final Speicherlaufwerk? laufwerk;
  static _Ortsmerkmal aus(Map j) {
    final id = j['kennung'] as String?;
    if (id != null && !RegExp(r'^[a-f0-9-]{36}$').hasMatch(id)) {
      throw const FormatException('pv_inventar_kennung');
    }
    final l = j['laufwerk'] as Map?;
    return _Ortsmerkmal(
      id,
      l == null
          ? null
          : Speicherlaufwerk(
              l['id'] as String,
              l['name'] as String,
              l['pfad'] as String,
            ),
    );
  }

  Map<String, Object?> json() => {
    'kennung': kennung,
    'laufwerk': laufwerk == null
        ? null
        : {'id': laufwerk!.id, 'name': laufwerk!.name, 'pfad': laufwerk!.pfad},
  };
}
