/// Baut aus einem Namensmuster den Dateinamen für einen Export.
///
/// Das Muster ist bewusst simpel gehalten – geschweifte Platzhalter, sonst
/// nichts. Kein Ausdrucks-Dialekt, keine Bedingungen: Wer beim Export einen
/// Dateinamen zusammensetzt, will „Datum, Unterstrich, laufende Nummer",
/// und alles darüber hinaus wäre eine kleine Programmiersprache, die
/// niemand dokumentiert bekommt.
///
/// Die Endung wird NIE aus dem Muster genommen, sondern immer aus der
/// tatsächlich geschriebenen Datei ergänzt (siehe [dateiname]) – sonst
/// entstünde beim Rendern nach JPEG ein `.dng`, das keines ist.
library;

import 'dart:convert';

import 'package:path/path.dart' as p;

import '../db/database.dart';

/// Ein Platzhalter mit seiner Bedeutung – die Liste ist zugleich die
/// Hilfe, die im Editor unter dem Eingabefeld steht.
enum Namensbaustein {
  name('{name}'),
  datum('{datum}'),
  zeit('{zeit}'),
  jahr('{jahr}'),
  monat('{monat}'),
  tag('{tag}'),
  kamera('{kamera}'),
  nummer('{nr}');

  const Namensbaustein(this.muster);

  /// Wie der Baustein im Muster geschrieben wird.
  final String muster;
}

/// Zeichen, die in keinem Dateinamen etwas verloren haben.
///
/// `/` und `\` trennen Pfade – ein Muster, das sie enthält, würde sonst aus
/// dem Zielordner herausführen. Der Rest ist unter Windows verboten und
/// unter macOS zumindest lästig; die Liste gilt überall gleich, damit ein
/// Export auf einem Stick auf jedem System lesbar bleibt.
final _verboten = RegExp(r'[/\\:*?"<>|\x00-\x1f]');

/// Führende und schliessende Punkte/Leerzeichen: Ein Name, der mit einem
/// Punkt beginnt, wäre versteckt; einer, der auf einen Punkt endet, ist
/// unter Windows gar nicht anlegbar.
final _randmuell = RegExp(r'^[.\s]+|[.\s]+$');

/// Setzt [muster] für [asset] ein und liefert einen Dateinamen OHNE Endung.
///
/// [nummer] ist die laufende Nummer innerhalb dieses Export-Laufs, beginnend
/// bei 1; sie wird vierstellig aufgefüllt, damit die Dateien in jedem
/// Dateimanager in der Reihenfolge stehen, in der sie exportiert wurden.
///
/// Läuft das Einsetzen auf einen leeren Namen hinaus – ein Muster aus
/// lauter Platzhaltern, die für dieses Foto alle leer sind –, greift der
/// ursprüngliche Dateiname. Ein Export darf nicht an einem unglücklichen
/// Muster scheitern.
String namenAusMuster(
  String muster,
  AssetData asset, {
  required int nummer,
}) {
  final zeitpunkt = asset.fileCreatedAt;
  String zwei(int wert) => wert.toString().padLeft(2, '0');

  final werte = <String, String>{
    Namensbaustein.name.muster: p.basenameWithoutExtension(asset.originalFileName),
    Namensbaustein.datum.muster:
        '${zeitpunkt.year}-${zwei(zeitpunkt.month)}-${zwei(zeitpunkt.day)}',
    Namensbaustein.zeit.muster: '${zwei(zeitpunkt.hour)}${zwei(zeitpunkt.minute)}',
    Namensbaustein.jahr.muster: '${zeitpunkt.year}',
    Namensbaustein.monat.muster: zwei(zeitpunkt.month),
    Namensbaustein.tag.muster: zwei(zeitpunkt.day),
    Namensbaustein.kamera.muster: _kamera(asset),
    Namensbaustein.nummer.muster: nummer.toString().padLeft(4, '0'),
  };

  var name = muster;
  werte.forEach((platzhalter, wert) => name = name.replaceAll(platzhalter, wert));

  name = name.replaceAll(_verboten, '_').replaceAll(_randmuell, '');
  if (name.isEmpty) {
    name = p.basenameWithoutExtension(asset.originalFileName);
  }
  return _gekuerzt(name);
}

/// Kürzt auf 200 UTF-8-**Bytes**, nicht auf 200 Zeichen.
///
/// Der Unterschied ist keine Feinheit: 200 Umlaute sind 400 Bytes. APFS
/// zählt Zeichen und nimmt das noch an, ext4 und exFAT zählen Bytes und
/// lehnen ab – und ein Exportziel sucht der Nutzer selbst aus, gern einen
/// USB-Stick oder eine Netzfreigabe. Die 55 Bytes Reserve bis 255 sind für
/// die Endung und die „(1)"-Nummerierung bei Namenskollisionen.
///
/// Geschnitten wird an Zeichengrenzen, nie mitten in eine Mehrbyte-Folge –
/// sonst entstünde ein ungültiger Dateiname.
String _gekuerzt(String name) {
  const grenze = 200;
  if (utf8.encode(name).length <= grenze) return name;
  final zeichen = name.runes.toList();
  var bytes = 0;
  final behalten = <int>[];
  for (final r in zeichen) {
    final breite = utf8.encode(String.fromCharCode(r)).length;
    if (bytes + breite > grenze) break;
    bytes += breite;
    behalten.add(r);
  }
  return String.fromCharCodes(behalten);
}

/// Wie [namenAusMuster], aber mit der Endung – die kommt aus [endung], nicht
/// aus dem Muster.
String dateiname(
  String muster,
  AssetData asset, {
  required int nummer,
  required String endung,
}) =>
    '${namenAusMuster(muster, asset, nummer: nummer)}$endung';

/// Hersteller und Modell zu einem Wort, ohne Doppelung.
///
/// Canon schreibt „Canon" in beide EXIF-Felder („Canon" + „Canon EOS R10"),
/// deshalb der Test auf den Präfix – sonst stünde „Canon Canon EOS R10" im
/// Dateinamen.
String _kamera(AssetData asset) {
  final hersteller = asset.cameraMake?.trim() ?? '';
  final modell = asset.cameraModel?.trim() ?? '';
  if (modell.isEmpty) return hersteller;
  if (hersteller.isEmpty) return modell;
  if (modell.toLowerCase().startsWith(hersteller.toLowerCase())) return modell;
  return '$hersteller $modell';
}
