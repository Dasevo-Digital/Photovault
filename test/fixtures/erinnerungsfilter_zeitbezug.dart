import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/erinnerungsfilter.dart';

Future<void> main(List<String> args) async {
  if (args.first == 'anlegen') {
    stdout.write(
      Erinnerungsfilter(
        zeitraeume: [
          (von: '2020-01-02', bis: '2020-01-02'),
          (von: '2020-03-29', bis: '2020-03-29'),
          (von: '2019-01-01', bis: '2019-01-01'),
        ],
      ).kodiert(),
    );
    return;
  }
  final filter = Erinnerungsfilter.ausJson(jsonDecode(args[1]));
  final db = AppDatabase(NativeDatabase.memory());
  try {
    await db.setzeErinnerungsfilter(filter);
    for (final (id, datum) in [
      ('davor', DateTime.utc(2020, 1, 1, 22, 59, 59)),
      ('anfang', DateTime.utc(2020, 1, 1, 23)),
      ('mitte', DateTime.utc(2020, 1, 1, 23, 30)),
      ('ende', DateTime.utc(2020, 1, 2, 23)),
      ('sommer', DateTime.utc(2020, 3, 29, 21, 59, 59)),
      ('danach', DateTime.utc(2020, 3, 29, 22)),
      ('jahresdavor', DateTime.utc(2018, 12, 31, 22, 59, 59)),
      ('jahreswechsel', DateTime.utc(2018, 12, 31, 23, 30)),
      ('jahresdanach', DateTime.utc(2019, 1, 1, 23)),
    ]) {
      await db
          .into(db.assets)
          .insert(
            AssetsCompanion.insert(
              id: id,
              originalFileName: '$id.jpg',
              relativePath: '$id.jpg',
              checksum: id,
              type: 'IMAGE',
              fileCreatedAt: datum,
              importedAt: DateTime.utc(2026),
              datumGeschaetzt: const Value(false),
            ),
          );
    }
    final erlaubt = await db.filtereErinnerungsaufnahmen(
      await db.select(db.assets).get(),
    );
    final ids = erlaubt.map((a) => a.id).toList()..sort();
    stdout.write(
      jsonEncode({
        'erlaubt': ids,
        'filter': filter.kodiert(),
        'direkt': filter.schliesstTagAus(DateTime.utc(2020, 1, 1, 23, 30)),
      }),
    );
  } finally {
    await db.close();
  }
}
