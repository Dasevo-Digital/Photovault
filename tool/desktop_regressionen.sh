#!/usr/bin/env bash
# Eigenständige Tests mit temporären Bibliotheken, ohne installierte App.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter test --reporter expanded \
  test/umzugsquelle_test.dart \
  test/umzugsabbruch_test.dart \
  test/erinnerungsfilter_und_beschriftungen_test.dart \
  test/erinnerungsfilter_zeitbezug_test.dart \
  test/beschriftungen_wiederherstellung_test.dart \
  test/erinnerungsfilter_dialog_test.dart \
  test/beschriftungen_dialog_test.dart \
  test/sicherungs_auswahl_und_importquittung_test.dart
