/// Was im Kopf einer Bilddatei steht, ohne sie zu entwickeln: die Grösse,
/// in der sie gezeigt wird, ihre Lage und – bei Rohdateien – das JPEG, das
/// die Kamera selbst hineingeschrieben hat.
///
/// **Warum die Grösse von hier kommt.** Formate, die Flutter nicht selbst
/// zeichnet (HEIC, RAW), werden beim Import zu einer Vorschau von höchstens
/// 2048 Pixeln gewandelt, und die Bildmasse kamen bisher aus dieser
/// Vorschau. In der Bibliothek stand damit für jedes iPhone-Foto
/// 2048 × 1536, für ein ProRAW mit 48 Megapixeln ebenso – in der
/// Info-Ansicht, im XMP und bei der Wahl des besten Duplikats. Der Kopf
/// der Datei kennt die echte Grösse, und ihn zu lesen kostet ein paar
/// Kilobyte.
///
/// **Warum das eingebettete JPEG.** Apple ProRAW ist ein lineares DNG: Die
/// Farben sind schon entwickelt, das Aussehen legen drei Angaben fest –
/// die Grundbelichtung (BaselineExposure, bei iPhone-Fotos um +2 Blenden),
/// eine Tonkurve und eine Karte, die Schatten und Ecken örtlich aufhellt.
/// LibRaw liest keine davon; was `dcraw_emu` daraus macht, ist fast zwei
/// Blenden zu dunkel und hat dunkle Ecken. Das JPEG in voller Grösse, das
/// das iPhone in jede ProRAW-Datei legt, ist genau das Bild, das die
/// Fotos-App zeigt.
library;

import 'dart:io';
import 'dart:typed_data';

/// Ein JPEG innerhalb einer Rohdatei.
class EingebettetesJpeg {
  const EingebettetesJpeg({
    required this.offset,
    required this.laenge,
    required this.breite,
    required this.hoehe,
  });

  final int offset;
  final int laenge;

  /// Wie gespeichert – also vor der Lage der Rohdatei.
  final int breite;
  final int hoehe;

  int get laengsteKante => breite > hoehe ? breite : hoehe;
}

/// Der Kopf einer TIFF-artigen Rohdatei (DNG, CR2, NEF, ARW, TIFF).
class Rohkopf {
  const Rohkopf({
    required this.ausrichtung,
    required this.jpegs,
    this.breite,
    this.hoehe,
    this.dng = false,
    this.linear = false,
    this.grundbelichtung,
  });

  /// EXIF-Lage 1 bis 8; 1, wenn die Datei keine nennt.
  final int ausrichtung;

  /// Die Grösse, in der das Bild gezeigt wird – schon gedreht.
  final int? breite;
  final int? hoehe;

  final List<EingebettetesJpeg> jpegs;
  final bool dng;

  /// Das Hauptbild ist schon entwickelt (DNG „LinearRaw“) – Apple ProRAW
  /// und andere Handy-DNGs aus mehreren Aufnahmen.
  final bool linear;

  /// BaselineExposure in Blenden, falls angegeben.
  final double? grundbelichtung;

  /// Das grösste eingebettete JPEG, oder `null`.
  EingebettetesJpeg? get groesstes {
    EingebettetesJpeg? best;
    for (final j in jpegs) {
      if (best == null || j.breite * j.hoehe > best.breite * best.hoehe) {
        best = j;
      }
    }
    return best;
  }

  /// Ob die Lage Breite und Höhe vertauscht.
  bool get quer => ausrichtung >= 5 && ausrichtung <= 8;
}

/// Liest den Kopf einer TIFF-artigen Datei, oder `null`, wenn sie keine
/// ist oder sich nicht lesen lässt.
Rohkopf? leseRohkopf(File datei) {
  RandomAccessFile? f;
  try {
    f = datei.openSync();
    return _TiffLeser(_Quelle(f)).lies();
  } catch (_) {
    return null;
  } finally {
    f?.closeSync();
  }
}

/// Die Grösse, in der die Aufnahme gezeigt wird, aus ihrem Dateikopf –
/// für TIFF-artige Rohdateien, HEIC/HEIF/AVIF, Canon CR3 und Photoshop.
/// `null`, wenn das Format keines davon ist oder der Kopf nichts hergibt.
({int breite, int hoehe})? leseOriginalmasse(File datei) {
  RandomAccessFile? f;
  try {
    f = datei.openSync();
    final q = _Quelle(f);
    final anfang = q.bytes(0, 12);
    if (anfang.length < 12) return null;
    if (_istTiff(anfang)) {
      final k = _TiffLeser(q).lies();
      final b = k?.breite, h = k?.hoehe;
      if (b == null || h == null || b <= 0 || h <= 0) return null;
      return (breite: b, hoehe: h);
    }
    // Photoshop: Höhe und Breite stehen fest im Kopf.
    if (String.fromCharCodes(anfang.sublist(0, 4)) == '8BPS') {
      final k = q.bytes(14, 8);
      if (k.length < 8) return null;
      final h = _be32(k, 0), b = _be32(k, 4);
      return (b > 0 && h > 0) ? (breite: b, hoehe: h) : null;
    }
    if (String.fromCharCodes(anfang.sublist(4, 8)) == 'ftyp') {
      final marke = String.fromCharCodes(anfang.sublist(8, 12));
      return marke == 'crx ' ? _Cr3Leser(q).masse() : _HeifLeser(q).masse();
    }
    return null;
  } catch (_) {
    return null;
  } finally {
    f?.closeSync();
  }
}

bool _istTiff(Uint8List b) =>
    (b[0] == 0x49 && b[1] == 0x49) || (b[0] == 0x4D && b[1] == 0x4D);

/// Liest Bereiche einer Datei; der Anfang liegt zwischengespeichert, weil
/// fast alles dort steht.
class _Quelle {
  _Quelle(this._f) : laenge = _f.lengthSync() {
    _f.setPositionSync(0);
    _anfang = _f.readSync(laenge < _anfangsgroesse ? laenge : _anfangsgroesse);
  }

  static const _anfangsgroesse = 1 << 20;

  final RandomAccessFile _f;
  final int laenge;
  late final Uint8List _anfang;

  Uint8List bytes(int offset, int anzahl) {
    if (offset < 0 || anzahl < 0 || offset >= laenge) return Uint8List(0);
    final ende = offset + anzahl > laenge ? laenge : offset + anzahl;
    if (ende <= _anfang.length) {
      return Uint8List.sublistView(_anfang, offset, ende);
    }
    _f.setPositionSync(offset);
    return _f.readSync(ende - offset);
  }
}

// --- TIFF ------------------------------------------------------------------

class _Ifd {
  final Map<int, List<num>> werte = {};

  int? zahl(int tag) {
    final w = werte[tag];
    return (w == null || w.isEmpty) ? null : w.first.toInt();
  }
}

class _TiffLeser {
  _TiffLeser(this.q);

  final _Quelle q;
  late final bool _klein; // little endian
  final _besucht = <int>{};
  final _ifds = <_Ifd>[];

  static const _groesse = {
    1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 6: 1, 7: 1, //
    8: 2, 9: 4, 10: 8, 11: 4, 12: 8, 13: 4, 16: 8,
  };

  int _u16(Uint8List b, int o) =>
      _klein ? b[o] | b[o + 1] << 8 : b[o] << 8 | b[o + 1];

  int _u32(Uint8List b, int o) => _klein
      ? b[o] | b[o + 1] << 8 | b[o + 2] << 16 | b[o + 3] << 24
      : b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3];

  int _s32(Uint8List b, int o) {
    final v = _u32(b, o);
    return v >= 0x80000000 ? v - 0x100000000 : v;
  }

  Rohkopf? lies() {
    final kopf = q.bytes(0, 8);
    if (kopf.length < 8 || !_istTiff(kopf)) return null;
    _klein = kopf[0] == 0x49;
    final erste = _u32(kopf, 4);
    _kette(erste);
    if (_ifds.isEmpty) return null;
    final ifd0 = _ifds.first;
    final dng = ifd0.werte.containsKey(50706);
    final ausrichtung = (ifd0.zahl(274) ?? 1).clamp(1, 8);

    final jpegs = <EingebettetesJpeg>[];
    _Ifd? haupt;
    for (final ifd in List.of(_ifds)) {
      final art = ifd.zahl(254) ?? 0;
      final kompression = ifd.zahl(259);
      final foto = ifd.zahl(262);
      // Das Hauptbild: bei DNG das Rohbild (CFA oder linear), sonst das
      // erste volle Bild.
      final rohbild = foto == 32803 || foto == 34892;
      if (art == 0 && (dng ? rohbild : true)) haupt ??= ifd;
      if (!rohbild) {
        final ist = _jpegAus(ifd, kompression, foto);
        if (ist != null) jpegs.add(ist);
      }
    }

    int? breite, hoehe;
    if (dng && haupt != null) {
      final zuschnitt = haupt.werte[50720];
      if (zuschnitt != null && zuschnitt.length >= 2) {
        breite = zuschnitt[0].round();
        hoehe = zuschnitt[1].round();
      } else {
        breite = haupt.zahl(256);
        hoehe = haupt.zahl(257);
      }
    }
    if (breite == null || hoehe == null) {
      final exif = _exifMasse(ifd0);
      breite = exif?.$1;
      hoehe = exif?.$2;
    }
    if (breite == null || hoehe == null) {
      EingebettetesJpeg? best;
      for (final j in jpegs) {
        if (best == null || j.breite * j.hoehe > best.breite * best.hoehe) {
          best = j;
        }
      }
      if (best != null) {
        breite = best.breite;
        hoehe = best.hoehe;
      } else if (!dng && (ifd0.zahl(254) ?? 0) == 0) {
        breite = ifd0.zahl(256);
        hoehe = ifd0.zahl(257);
      }
    }
    if (breite != null && hoehe != null && ausrichtung >= 5) {
      final t = breite;
      breite = hoehe;
      hoehe = t;
    }

    double? grundbelichtung;
    final be = ifd0.werte[50730] ?? haupt?.werte[50730];
    if (be != null && be.isNotEmpty) grundbelichtung = be.first.toDouble();

    return Rohkopf(
      ausrichtung: ausrichtung,
      breite: breite,
      hoehe: hoehe,
      jpegs: jpegs,
      dng: dng,
      linear: haupt?.zahl(262) == 34892,
      grundbelichtung: grundbelichtung,
    );
  }

  /// Alle IFDs ab [offset] samt ihren Unter-IFDs.
  void _kette(int offset) {
    var o = offset;
    var schritte = 0;
    while (o > 0 && schritte++ < 32) {
      final naechstes = _ifd(o);
      if (naechstes == null) break;
      o = naechstes;
    }
  }

  /// Liest ein IFD und gibt den Verweis auf das nächste zurück.
  int? _ifd(int offset) {
    if (_ifds.length > 64 || !_besucht.add(offset)) return null;
    final n0 = q.bytes(offset, 2);
    if (n0.length < 2) return null;
    final n = _u16(n0, 0);
    if (n == 0 || n > 1000) return null;
    final eintraege = q.bytes(offset + 2, n * 12 + 4);
    if (eintraege.length < n * 12 + 4) return null;
    final ifd = _Ifd();
    _ifds.add(ifd);
    final unter = <int>[];
    for (var i = 0; i < n; i++) {
      final e = i * 12;
      final tag = _u16(eintraege, e);
      final typ = _u16(eintraege, e + 2);
      final anzahl = _u32(eintraege, e + 4);
      final groesse = _groesse[typ];
      if (groesse == null) continue;
      final gesamt = groesse * anzahl;
      final daten = gesamt <= 4
          ? Uint8List.sublistView(eintraege, e + 8, e + 8 + gesamt)
          : q.bytes(_u32(eintraege, e + 8), gesamt > 4096 ? 0 : gesamt);
      if (daten.length == gesamt && anzahl <= 512) {
        ifd.werte[tag] = _zahlen(daten, typ, anzahl);
      }
      if ((tag == 330) && ifd.werte[tag] != null) {
        unter.addAll(ifd.werte[tag]!.map((v) => v.toInt()));
      }
    }
    for (final u in unter) {
      _kette(u);
    }
    return _u32(eintraege, n * 12);
  }

  List<num> _zahlen(Uint8List d, int typ, int anzahl) {
    final out = <num>[];
    for (var i = 0; i < anzahl; i++) {
      switch (typ) {
        case 1 || 6 || 7 || 2:
          out.add(d[i]);
        case 3 || 8:
          out.add(_u16(d, i * 2));
        case 4 || 9 || 13:
          out.add(typ == 9 ? _s32(d, i * 4) : _u32(d, i * 4));
        case 5:
          final z = _u32(d, i * 8), n = _u32(d, i * 8 + 4);
          out.add(n == 0 ? 0 : z / n);
        case 10:
          final z = _s32(d, i * 8), n = _s32(d, i * 8 + 4);
          out.add(n == 0 ? 0 : z / n);
        default:
          return out;
      }
    }
    return out;
  }

  (int, int)? _exifMasse(_Ifd ifd0) {
    final zeiger = ifd0.zahl(34665);
    if (zeiger == null || zeiger <= 0) return null;
    final vorher = _ifds.length;
    _ifd(zeiger);
    if (_ifds.length == vorher) return null;
    final exif = _ifds.removeLast();
    final b = exif.zahl(40962), h = exif.zahl(40963);
    if (b == null || h == null || b <= 0 || h <= 0) return null;
    return (b, h);
  }

  EingebettetesJpeg? _jpegAus(_Ifd ifd, int? kompression, int? foto) {
    int? offset, laenge;
    if (ifd.zahl(513) != null && ifd.zahl(514) != null) {
      offset = ifd.zahl(513);
      laenge = ifd.zahl(514);
    } else if ((kompression == 6 || kompression == 7) &&
        (foto == null || foto == 6 || foto == 2)) {
      final streifen = ifd.werte[273], laengen = ifd.werte[279];
      if (streifen != null &&
          laengen != null &&
          streifen.length == 1 &&
          laengen.length == 1) {
        offset = streifen.first.toInt();
        laenge = laengen.first.toInt();
      }
    }
    if (offset == null || laenge == null || laenge < 128) return null;
    final masse = jpegMasse(
      q.bytes(offset, laenge < 1 << 16 ? laenge : 1 << 16),
    );
    if (masse == null) return null;
    return EingebettetesJpeg(
      offset: offset,
      laenge: laenge,
      breite: masse.$1,
      hoehe: masse.$2,
    );
  }
}

/// Breite und Höhe aus dem SOF-Abschnitt eines JPEG, oder `null`.
(int, int)? jpegMasse(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var o = 2;
  while (o + 9 < b.length) {
    if (b[o] != 0xFF) return null;
    final marke = b[o + 1];
    if (marke == 0xFF) {
      o++;
      continue;
    }
    final laenge = b[o + 2] << 8 | b[o + 3];
    final sof =
        marke >= 0xC0 &&
        marke <= 0xCF &&
        marke != 0xC4 &&
        marke != 0xC8 &&
        marke != 0xCC;
    if (sof) {
      final h = b[o + 5] << 8 | b[o + 6];
      final w = b[o + 7] << 8 | b[o + 8];
      return (w > 0 && h > 0) ? (w, h) : null;
    }
    if (marke == 0xDA || laenge < 2) return null;
    o += 2 + laenge;
  }
  return null;
}

/// Die EXIF-Lage, die ein JPEG selbst trägt, oder `null`, wenn es keine
/// nennt.
///
/// `package:image` dreht ein JPEG beim Lesen schon nach dieser Lage. Das
/// JPEG in einem iPhone-ProRAW nennt seine eigene; die Lage der Rohdatei
/// darf dann nicht noch einmal angewendet werden – das Hochformat kam
/// sonst quer heraus.
int? jpegExifLage(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var o = 2;
  while (o + 4 < b.length) {
    if (b[o] != 0xFF) return null;
    final marke = b[o + 1];
    final laenge = b[o + 2] << 8 | b[o + 3];
    if (marke == 0xDA || laenge < 2) return null;
    if (marke == 0xE1 &&
        o + 10 + 8 <= b.length &&
        String.fromCharCodes(b.sublist(o + 4, o + 8)) == 'Exif') {
      final t = o + 10; // hinter "Exif\0\0"
      if (!_istTiff(Uint8List.sublistView(b, t, t + 2))) return null;
      final klein = b[t] == 0x49;
      int u16(int x) => klein ? b[x] | b[x + 1] << 8 : b[x] << 8 | b[x + 1];
      int u32(int x) => klein
          ? b[x] | b[x + 1] << 8 | b[x + 2] << 16 | b[x + 3] << 24
          : b[x] << 24 | b[x + 1] << 16 | b[x + 2] << 8 | b[x + 3];
      final ifd = t + u32(t + 4);
      if (ifd + 2 > b.length) return null;
      final n = u16(ifd);
      for (var i = 0; i < n; i++) {
        final e = ifd + 2 + i * 12;
        if (e + 12 > b.length) return null;
        if (u16(e) == 274) {
          final v = u16(e + 8);
          return v >= 1 && v <= 8 ? v : null;
        }
      }
      return null;
    }
    o += 2 + laenge;
  }
  return null;
}

// --- ISO-BMFF (HEIF, AVIF, CR3) ---------------------------------------------

class _Kiste {
  const _Kiste(this.typ, this.start, this.inhalt, this.ende);

  final String typ;
  final int start;

  /// Wo der Inhalt beginnt (hinter Grösse und Typ).
  final int inhalt;
  final int ende;
}

int _be32(Uint8List b, int o) =>
    b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3];

int _be16(Uint8List b, int o) => b[o] << 8 | b[o + 1];

/// Die Kisten zwischen [von] und [bis], ohne in sie hineinzusehen.
List<_Kiste> _kisten(_Quelle q, int von, int bis) {
  final out = <_Kiste>[];
  var o = von;
  while (o + 8 <= bis && out.length < 4096) {
    final k = q.bytes(o, 16);
    if (k.length < 8) break;
    var groesse = _be32(k, 0);
    final typ = String.fromCharCodes(k.sublist(4, 8));
    var inhalt = o + 8;
    if (groesse == 1) {
      if (k.length < 16) break;
      groesse = _be32(k, 8) * 0x100000000 + _be32(k, 12);
      inhalt = o + 16;
    } else if (groesse == 0) {
      groesse = bis - o;
    }
    if (groesse < 8 || o + groesse > bis) break;
    out.add(_Kiste(typ, o, inhalt, o + groesse));
    o += groesse;
  }
  return out;
}

_Kiste? _kind(_Quelle q, _Kiste k, String typ, {int ueberspringen = 0}) {
  for (final c in _kisten(q, k.inhalt + ueberspringen, k.ende)) {
    if (c.typ == typ) return c;
  }
  return null;
}

class _HeifLeser {
  _HeifLeser(this.q);

  final _Quelle q;

  ({int breite, int hoehe})? masse() {
    _Kiste? meta;
    for (final k in _kisten(q, 0, q.laenge)) {
      if (k.typ == 'meta') meta = k;
      if (k.typ == 'mdat' && meta != null) break;
    }
    if (meta == null) return null;
    // meta ist eine FullBox: vier Bytes Fassung und Merkmale vorweg.
    final pitm = _kind(q, meta, 'pitm', ueberspringen: 4);
    final iprp = _kind(q, meta, 'iprp', ueberspringen: 4);
    if (iprp == null) return null;
    final ipco = _kind(q, iprp, 'ipco');
    if (ipco == null) return null;
    final eigenschaften = _kisten(q, ipco.inhalt, ipco.ende);

    int? primaer;
    if (pitm != null) {
      final b = q.bytes(pitm.inhalt, 8);
      if (b.length >= 6) primaer = b[0] == 0 ? _be16(b, 4) : _be32(b, 4);
    }

    final zuordnung = <int, List<int>>{};
    for (final ipma in _kisten(q, ipco.ende, iprp.ende)) {
      if (ipma.typ != 'ipma') continue;
      final b = q.bytes(ipma.inhalt, ipma.ende - ipma.inhalt);
      if (b.length < 8) continue;
      final fassung = b[0];
      final breit = (b[3] & 1) == 1;
      final n = _be32(b, 4);
      var o = 8;
      for (var i = 0; i < n && o < b.length; i++) {
        final id = fassung < 1 ? _be16(b, o) : _be32(b, o);
        o += fassung < 1 ? 2 : 4;
        if (o >= b.length) break;
        final m = b[o++];
        final liste = zuordnung[id] = [];
        for (var j = 0; j < m && o < b.length; j++) {
          final index = breit ? (_be16(b, o) & 0x7FFF) : (b[o] & 0x7F);
          o += breit ? 2 : 1;
          liste.add(index);
        }
      }
    }

    ({int breite, int hoehe})? ispe(int index) {
      if (index < 1 || index > eigenschaften.length) return null;
      final k = eigenschaften[index - 1];
      if (k.typ != 'ispe') return null;
      final b = q.bytes(k.inhalt, 12);
      if (b.length < 12) return null;
      return (breite: _be32(b, 4), hoehe: _be32(b, 8));
    }

    int drehung(int index) {
      if (index < 1 || index > eigenschaften.length) return 0;
      final k = eigenschaften[index - 1];
      if (k.typ != 'irot') return 0;
      final b = q.bytes(k.inhalt, 1);
      return b.isEmpty ? 0 : b[0] & 3;
    }

    final eigene = primaer == null ? null : zuordnung[primaer];
    ({int breite, int hoehe})? masse;
    var gedreht = 0;
    if (eigene != null) {
      for (final i in eigene) {
        masse ??= ispe(i);
        final d = drehung(i);
        if (d != 0) gedreht = d;
      }
    }
    if (masse == null) {
      // Ohne Zuordnung: die grösste angegebene Fläche.
      for (var i = 1; i <= eigenschaften.length; i++) {
        final m = ispe(i);
        if (m != null &&
            (masse == null ||
                m.breite * m.hoehe > masse.breite * masse.hoehe)) {
          masse = m;
        }
      }
    }
    if (masse == null || masse.breite <= 0 || masse.hoehe <= 0) return null;
    return gedreht.isOdd ? (breite: masse.hoehe, hoehe: masse.breite) : masse;
  }
}

class _Cr3Leser {
  _Cr3Leser(this.q);

  final _Quelle q;

  ({int breite, int hoehe})? masse() {
    _Kiste? moov;
    for (final k in _kisten(q, 0, q.laenge)) {
      if (k.typ == 'moov') {
        moov = k;
        break;
      }
    }
    if (moov == null) return null;
    int? breite, hoehe;
    var ausrichtung = 1;
    for (final k in _kisten(q, moov.inhalt, moov.ende)) {
      if (k.typ == 'uuid') {
        // Canons Kiste trägt hinter 16 Bytes Kennung die TIFF-Kopfdaten.
        final cmt1 = _kind(q, k, 'CMT1', ueberspringen: 16);
        if (cmt1 != null) ausrichtung = _cmt1Lage(cmt1) ?? ausrichtung;
      }
      if (k.typ == 'trak' && breite == null) {
        final eintrag = _craw(k);
        if (eintrag != null) {
          final b = q.bytes(eintrag.inhalt, 28);
          if (b.length >= 28) {
            breite = _be16(b, 24);
            hoehe = _be16(b, 26);
          }
        }
      }
    }
    if (breite == null || hoehe == null || breite <= 0 || hoehe <= 0) {
      return null;
    }
    return ausrichtung >= 5
        ? (breite: hoehe, hoehe: breite)
        : (breite: breite, hoehe: hoehe);
  }

  /// Der Bildeintrag der ersten Spur: moov/trak/mdia/minf/stbl/stsd/CRAW.
  _Kiste? _craw(_Kiste trak) {
    final mdia = _kind(q, trak, 'mdia');
    final minf = mdia == null ? null : _kind(q, mdia, 'minf');
    final stbl = minf == null ? null : _kind(q, minf, 'stbl');
    final stsd = stbl == null ? null : _kind(q, stbl, 'stsd');
    if (stsd == null) return null;
    // stsd: FullBox (4) und die Zahl der Einträge (4).
    return _kind(q, stsd, 'CRAW', ueberspringen: 8);
  }

  int? _cmt1Lage(_Kiste cmt1) {
    final b = q.bytes(cmt1.inhalt, cmt1.ende - cmt1.inhalt);
    if (b.length < 8 || !_istTiff(b)) return null;
    final klein = b[0] == 0x49;
    int u16(int o) => klein ? b[o] | b[o + 1] << 8 : b[o] << 8 | b[o + 1];
    int u32(int o) => klein
        ? b[o] | b[o + 1] << 8 | b[o + 2] << 16 | b[o + 3] << 24
        : b[o] << 24 | b[o + 1] << 16 | b[o + 2] << 8 | b[o + 3];
    final ifd = u32(4);
    if (ifd + 2 > b.length) return null;
    final n = u16(ifd);
    for (var i = 0; i < n; i++) {
      final e = ifd + 2 + i * 12;
      if (e + 12 > b.length) break;
      if (u16(e) == 274) {
        final v = u16(e + 8);
        return v >= 1 && v <= 8 ? v : null;
      }
    }
    return null;
  }
}
