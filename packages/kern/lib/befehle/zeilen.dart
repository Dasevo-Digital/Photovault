part of 'befehl.dart';

/// Eine Zeile oder ein Teil davon, wie ein Befehl sie trägt: nur die
/// gesetzten Spalten, mit den Werten, die drift in die Datenbank schreibt
/// (Umwandler schon angewandt).
///
/// Gelesen wird sie erst beim Anwenden ([_zeileAus]), mit den Spaltentypen
/// der Tabelle. So braucht nicht jede Tabelle einen eigenen Befehlstyp, der
/// „gesetzt“, „nicht gesetzt“ und „leer“ auseinanderhält – das tut die
/// Abbildung selbst: Eine fehlende Spalte bleibt unberührt, `null` leert
/// sie.
Map<String, Object?> _zeileAlsWerte(Insertable<Object?> zeile) => {
  for (final e in zeile.toColumns(false).entries)
    e.key: switch ((e.value as Variable).value) {
      final DateTime zeit => zeit.toIso8601String(),
      final Uint8List bytes => base64Encode(bytes),
      final BigInt zahl => zahl.toString(),
      final wert => wert,
    },
};

/// Die Zeile aus [_zeileAlsWerte] zurück, als Einfügbares für [tabelle].
RawValuesInsertable<D> _zeileAus<D>(
  TableInfo<Table, D> tabelle,
  Map<String, Object?> werte,
) => RawValuesInsertable({
  for (final e in werte.entries)
    e.key: _variable(
      tabelle.columnsByName[e.key] ??
          (throw FormatException(
            'Spalte ${e.key} gibt es in ${tabelle.actualTableName} nicht',
          )),
      e.value,
    ),
});

Variable _variable(GeneratedColumn spalte, Object? wert) =>
    switch (spalte.type) {
      DriftSqlType.string => Variable<String>(wert as String?),
      DriftSqlType.int => Variable<int>(wert as int?),
      DriftSqlType.bool => Variable<bool>(wert as bool?),
      DriftSqlType.double => Variable<double>((wert as num?)?.toDouble()),
      DriftSqlType.dateTime => Variable<DateTime>(
        wert == null ? null : DateTime.parse(wert as String),
      ),
      DriftSqlType.blob => Variable<Uint8List>(
        wert == null ? null : base64Decode(wert as String),
      ),
      DriftSqlType.bigInt => Variable<BigInt>(
        wert == null ? null : BigInt.parse(wert as String),
      ),
      _ => throw FormatException(
        'Spaltentyp ${spalte.type} von ${spalte.name} kann kein Befehl tragen',
      ),
    };

Map<String, Object?> _abbildung(Object? wert) =>
    (wert! as Map).cast<String, Object?>();
