part of 'befehl.dart';

/// Ein Schlagwort an eine oder mehrere Aufnahmen hängen. [quelle] sagt, wer
/// es vergibt (siehe [Tagquelle]): von Hand oder die Bilderkennung.
final class SchlagwortAnheften extends Befehl<void> {
  const SchlagwortAnheften(this.ids, this.name, {this.quelle = Tagquelle.hand});

  static SchlagwortAnheften aus(Map<String, Object?> w) => SchlagwortAnheften(
    _kennungen(w['ids']),
    w['name']! as String,
    quelle: w['quelle']! as String,
  );

  final List<String> ids;
  final String name;
  final String quelle;

  @override
  String get art => 'schlagwortAnheften';

  @override
  Map<String, Object?> get werte => {
    'ids': ids,
    'name': name,
    'quelle': quelle,
  };

  @override
  Future<void> anwenden(AppDatabase db) async {
    // Mehrere von Hand in einem Zug; die Bilderkennung je Aufnahme, weil
    // sie eine Handvergabe nicht überschreiben darf (siehe tagAsset).
    if (ids.length > 1 && quelle == Tagquelle.hand) {
      return db.tagAssetsBulk(ids, name);
    }
    for (final id in ids) {
      await db.tagAsset(id, name, quelle: quelle);
    }
  }
}

/// Ein schon angelegtes Schlagwort über seine Kennung anhängen – so, wie
/// Kameravorgaben und Regeln es beim Import tun.
final class SchlagwortAnheftenPerKennung extends Befehl<void> {
  const SchlagwortAnheftenPerKennung(this.id, this.schlagwortId);

  static SchlagwortAnheftenPerKennung aus(Map<String, Object?> w) =>
      SchlagwortAnheftenPerKennung(
        w['id']! as String,
        w['schlagwortId']! as String,
      );

  final String id;
  final String schlagwortId;

  @override
  String get art => 'schlagwortAnheftenPerKennung';

  @override
  Map<String, Object?> get werte => {'id': id, 'schlagwortId': schlagwortId};

  @override
  Future<void> anwenden(AppDatabase db) => db.tagAssetById(id, schlagwortId);
}

/// Ein Schlagwort von einer Aufnahme lösen; das Schlagwort selbst bleibt.
final class SchlagwortLoesen extends Befehl<void> {
  const SchlagwortLoesen(this.id, this.schlagwortId);

  static SchlagwortLoesen aus(Map<String, Object?> w) =>
      SchlagwortLoesen(w['id']! as String, w['schlagwortId']! as String);

  final String id;
  final String schlagwortId;

  @override
  String get art => 'schlagwortLoesen';

  @override
  Map<String, Object?> get werte => {'id': id, 'schlagwortId': schlagwortId};

  @override
  Future<void> anwenden(AppDatabase db) => db.untagAsset(id, schlagwortId);
}

/// Ein Schlagwort von mehreren Aufnahmen abnehmen; hängt es danach nirgends
/// mehr, verschwindet es (das Rückgängig nach dem Anhängen).
final class SchlagwortAbnehmen extends Befehl<void> {
  const SchlagwortAbnehmen(this.ids, this.name);

  static SchlagwortAbnehmen aus(Map<String, Object?> w) =>
      SchlagwortAbnehmen(_kennungen(w['ids']), w['name']! as String);

  final List<String> ids;
  final String name;

  @override
  String get art => 'schlagwortAbnehmen';

  @override
  Map<String, Object?> get werte => {'ids': ids, 'name': name};

  @override
  Future<void> anwenden(AppDatabase db) => db.nimmSchlagwortAb(ids, name);
}

/// Alle Schlagwörter der Bilderkennung zurücknehmen; liefert ihre Zahl.
final class KiSchlagwoerterZuruecknehmen extends Befehl<int> {
  const KiSchlagwoerterZuruecknehmen();

  static KiSchlagwoerterZuruecknehmen aus(Map<String, Object?> w) =>
      const KiSchlagwoerterZuruecknehmen();

  @override
  String get art => 'kiSchlagwoerterZuruecknehmen';

  @override
  Map<String, Object?> get werte => const {};

  @override
  Future<int> anwenden(AppDatabase db) => db.nimmKiTagsZurueck();
}

/// Ein Begriff mehr, nach dem die Bilderkennung sucht.
final class KiBegriffHinzufuegen extends Befehl<void> {
  const KiBegriffHinzufuegen(this.begriff);

  static KiBegriffHinzufuegen aus(Map<String, Object?> w) =>
      KiBegriffHinzufuegen(w['begriff']! as String);

  final String begriff;

  @override
  String get art => 'kiBegriffHinzufuegen';

  @override
  Map<String, Object?> get werte => {'begriff': begriff};

  @override
  Future<void> anwenden(AppDatabase db) => db.addAiTagTerm(begriff);
}

/// Einen Begriff aus dem Vokabular der Bilderkennung nehmen.
final class KiBegriffEntfernen extends Befehl<void> {
  const KiBegriffEntfernen(this.begriffId);

  static KiBegriffEntfernen aus(Map<String, Object?> w) =>
      KiBegriffEntfernen(w['begriffId']! as int);

  final int begriffId;

  @override
  String get art => 'kiBegriffEntfernen';

  @override
  Map<String, Object?> get werte => {'begriffId': begriffId};

  @override
  Future<void> anwenden(AppDatabase db) => db.removeAiTagTerm(begriffId);
}

/// Vokabular und vergebene Schlagwörter in die andere Sprache bringen
/// (alt → neu); liefert, wie viele sich geändert haben.
final class VokabularUebersetzen extends Befehl<int> {
  const VokabularUebersetzen(this.zuordnung);

  static VokabularUebersetzen aus(Map<String, Object?> w) =>
      VokabularUebersetzen((w['zuordnung']! as Map).cast<String, String>());

  final Map<String, String> zuordnung;

  @override
  String get art => 'vokabularUebersetzen';

  @override
  Map<String, Object?> get werte => {'zuordnung': zuordnung};

  @override
  Future<int> anwenden(AppDatabase db) => db.uebersetzeVokabular(zuordnung);
}
