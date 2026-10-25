import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Die öffentliche Beschreibung muss lokale und verbundene Bibliotheken
/// auseinanderhalten. Sonst kann eine neue Funktion die Datenschutzerklärung
/// überholen, obwohl die reine Sperrlistenprüfung weiter grün bleibt.
void main() {
  late String readme;
  late String deutsch;
  late String englisch;
  late String version;

  setUpAll(() {
    readme = File('README.md').readAsStringSync();
    deutsch = File('docs/datenschutz.md').readAsStringSync();
    englisch = File('docs/privacy.md').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    version = RegExp(
      r'^version:\s*([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
  });

  test('Datenschutztexte tragen die aktuelle Fassung', () {
    expect(deutsch, contains('Photo Vault $version'));
    expect(englisch, contains('Photo Vault $version'));
  });

  test('README trennt lokalen Betrieb und eigenen Server', () {
    expect(readme, contains('Optionaler eigener Server'));
    expect(readme, contains('Im lokalen Betrieb'));
    expect(readme, contains('Im optionalen Serverbetrieb'));
    expect(readme, isNot(contains('aber **ohne Server, ohne Konto')));
    expect(readme, isNot(contains('Alles andere ist rein lokal')));
  });

  test('deutsche Erklärung nennt alle Übertragungswege', () {
    for (final begriff in [
      'Eigener Photo Vault Server',
      'Handy-App',
      'Konten und Anmeldung',
      'OIDC-Anbieter',
      'Browser, Freigaben und Gastbeiträge',
      'Unterstützungslink',
      'Rechenhilfen',
      'Bearer-Token',
    ]) {
      expect(deutsch, contains(begriff), reason: begriff);
    }
    expect(deutsch, isNot(contains('Es gibt kein Benutzerkonto')));
  });

  test('englische Erklärung nennt dieselben Übertragungswege', () {
    for (final begriff in [
      'Your Photo Vault Server',
      'Mobile app',
      'Accounts and sign-in',
      'OIDC provider',
      'Browser, shares and guest contributions',
      'Support link',
      'Compute helpers',
      'bearer token',
    ]) {
      expect(englisch, contains(begriff), reason: begriff);
    }
    expect(englisch, isNot(contains('There is no user account')));
  });
}
