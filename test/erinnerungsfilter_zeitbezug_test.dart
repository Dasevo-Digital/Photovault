import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kern/db/database.dart';
import 'package:kern/services/erinnerungsfilter.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'Gleiche Kalendertage mit unterschiedlichen bestätigten Grenzen bleiben erhalten',
    () {
      final filter = Erinnerungsfilter.ausJson({
        'fassung': 2,
        'personen': [],
        'alben': [],
        'zeitraeume': [
          {
            'von': '2020-01-02',
            'bis': '2020-01-02',
            'vonUtc': '2020-01-01T23:00:00Z',
            'bisUtc': '2020-01-02T23:00:00Z',
          },
          {
            'von': '2020-01-02',
            'bis': '2020-01-02',
            'vonUtc': '2020-01-02T00:00:00Z',
            'bisUtc': '2020-01-03T00:00:00Z',
          },
        ],
      });
      expect(
        filter
            .mitAuswahl(personen: [], alben: [], zeitraeume: filter.zeitraeume)
            .zeitgrenzen,
        filter.zeitgrenzen,
      );
    },
  );

  test(
    'UTC-Grenzen und Sommerzeit bleiben über Prozesszeitzonen stabil',
    () async {
      final sdk = Platform.environment['FLUTTER_ROOT'];
      final dart = sdk == null
          ? 'dart'
          : p.join(
              sdk,
              'bin',
              'cache',
              'dart-sdk',
              'bin',
              Platform.isWindows ? 'dart.exe' : 'dart',
            );
      Future<String> lauf(String zone, List<String> args) async {
        final r = await Process.run(
          dart,
          ['run', 'test/fixtures/erinnerungsfilter_zeitbezug.dart', ...args],
          environment: {'TZ': zone},
        );
        expect(r.exitCode, 0, reason: r.stderr.toString());
        return r.stdout.toString();
      }

      // Windows kennt die TZ-Zonendaten nicht in derselben Form. Die
      // festgelegten Grenzen werden dort trotzdem mit DB und Serialisierung
      // geprüft; der Erzeuger über zwei Zeitzonen läuft auf Unix.
      final gespeichert = Platform.isWindows
          ? jsonEncode({
              'fassung': 2,
              'personen': [],
              'alben': [],
              'zeitraeume': [
                {
                  'von': '2020-01-02',
                  'bis': '2020-01-02',
                  'vonUtc': '2020-01-01T23:00:00.000Z',
                  'bisUtc': '2020-01-02T23:00:00.000Z',
                },
                {
                  'von': '2020-03-29',
                  'bis': '2020-03-29',
                  'vonUtc': '2020-03-28T23:00:00.000Z',
                  'bisUtc': '2020-03-29T22:00:00.000Z',
                },
                {
                  'von': '2019-01-01',
                  'bis': '2019-01-01',
                  'vonUtc': '2018-12-31T23:00:00.000Z',
                  'bisUtc': '2019-01-01T23:00:00.000Z',
                },
              ],
            })
          : await lauf('Europe/Berlin', ['anlegen']);
      final berlin =
          jsonDecode(await lauf('Europe/Berlin', ['lesen', gespeichert]))
              as Map;
      final utc = jsonDecode(await lauf('UTC', ['lesen', gespeichert])) as Map;
      expect(berlin, utc);
      expect(utc['erlaubt'], [
        'danach',
        'davor',
        'ende',
        'jahresdanach',
        'jahresdavor',
      ]);
      expect(utc['direkt'], isTrue);
      expect(utc['filter'], gespeichert);
      final filter = Erinnerungsfilter.ausJson(jsonDecode(gespeichert));
      expect(
        filter
            .mitAuswahl(
              personen: ['p'],
              alben: [],
              zeitraeume: filter.zeitraeume,
            )
            .zeitgrenzen,
        filter.zeitgrenzen,
      );
      expect(
        filter.vereinigtMit(Erinnerungsfilter(personen: ['q'])).zeitgrenzen,
        filter.zeitgrenzen,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('Alte Kalendergrenzen verlangen Bestätigung und bleiben erhalten', () {
    final alt = Erinnerungsfilter.ausJson({
      'fassung': 1,
      'personen': ['p'],
      'alben': ['a'],
      'zeitraeume': [
        {'von': '2020-01-02', 'bis': '2020-01-02'},
      ],
    });
    expect(alt.zeitbezugFehlt, isTrue);
    expect(
      () => alt.schliesstTagAus(DateTime.utc(2020)),
      throwsFormatException,
    );
    expect(
      () => ErinnerungsfilterSetzen.aus({'filter': alt.alsJson()}),
      throwsFormatException,
    );
    final vereinigt = Erinnerungsfilter(
      personen: ['q'],
    ).vereinigtMit(alt, albenZuordnung: {'a': 'neu'});
    expect(vereinigt.zeitbezugFehlt, isTrue);
    expect(vereinigt.alben, ['neu']);
    expect(vereinigt.personen, ['p', 'q']);
    final bestaetigt = vereinigt.mitAuswahl(
      personen: vereinigt.personen,
      alben: vereinigt.alben,
      zeitraeume: vereinigt.zeitraeume,
    );
    expect(bestaetigt.zeitbezugFehlt, isFalse);
    expect(bestaetigt.zeitraeume, alt.zeitraeume);
  });
}
