import 'package:drift/native.dart';
import 'package:photo_vault/db/database.dart';

/// Eine Bibliothek, die ein Test absichtlich NEBEN einer anderen offen hält.
///
/// drift zählt offene Datenbanken je Klasse und warnt, sobald eine zweite
/// `AppDatabase` entsteht, bevor die erste geschlossen ist – weil sich zwei
/// Instanzen auf DEMSELBEN Executor gegenseitig die Daten zerschießen.
/// Sicherungs- und Migrationstests brauchen aber zwei getrennte Bibliotheken
/// mit je eigenem Executor: Quelle und Ziel einer Wiederherstellung, die
/// Datenbank aus `setUp` und eine Datei, die migriert wird. Die Warnung war
/// dort ein Fehlalarm, und weil sie in zwei Dutzend Tests kam, ging eine
/// echte zwischen ihnen unter.
///
/// Abschalten (`dontWarnAboutMultipleDatabases`) hätte auch die echten
/// verschluckt – und setzt den Zähler obendrein auf 1 zurück, statt ihn
/// hochzuzählen. Eine eigene Klasse dagegen bekommt einen eigenen Zähler:
/// Die Warnung bleibt für `AppDatabase` scharf, und zwei offene
/// `ZweiteDatenbank` warnen untereinander genauso.
class ZweiteDatenbank extends AppDatabase {
  ZweiteDatenbank(super.executor);
}

/// Die Fassung, auf die diese App migriert – aus einer frisch angelegten
/// Datenbank abgelesen statt als Zahl hingeschrieben.
///
/// Eine feste Nummer im Test bricht bei jedem Schemaschritt, und zwar an
/// einer Stelle, die mit dem Schritt nichts zu tun hat (so geschehen bei
/// 56 -> 57). Die Abfrage läuft neben der Datenbank des Tests, deshalb
/// als [ZweiteDatenbank].
Future<int> aktuelleFassung() async {
  final frisch = ZweiteDatenbank(NativeDatabase.memory());
  final v = await frisch
      .customSelect('PRAGMA user_version')
      .map((r) => r.read<int>('user_version'))
      .getSingle();
  await frisch.close();
  return v;
}
