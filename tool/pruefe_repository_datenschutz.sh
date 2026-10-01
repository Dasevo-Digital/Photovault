#!/usr/bin/env bash
# Prüft den Quellstand und die Git-Metadaten auf personenbezogene Spuren.
#
# Aufruf: tool/pruefe_repository_datenschutz.sh
#
# Das Werkzeug behandelt weder Produkttexte wie „E-Mail-Export" noch
# technische @-Zeichen als Kontaktangaben. Es findet ausschließlich
# E-Mail-Formate und stellt sicher, dass Commits anonym signiert sind.
set -euo pipefail

wurzel="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$wurzel"

fehler=0

email_treffer="$(git grep -I -n -E '[A-Za-z0-9._%+-]+@[A-Za-z][A-Za-z0-9.-]*\.[A-Za-z]{2,}' HEAD -- \
    . ':!assets/fonts/**' 2>/dev/null | \
  grep -v 'noreply@photo-vault.invalid' || true)"
if [ -n "$email_treffer" ]; then
  printf '%s\n' "$email_treffer"
  echo 'E-Mail-Adresse im getrackten Quellstand gefunden.' >&2
  fehler=1
fi

if git log --all --format='%an%x09%ae%x09%cn%x09%ce' | \
    awk -F '\t' '$1 != "Photo Vault" || $2 != "noreply@photo-vault.invalid" || $3 != "Photo Vault" || $4 != "noreply@photo-vault.invalid" { exit 1 }'; then
  :
else
  echo 'Nicht anonyme Autor- oder Commit-Identität in der Historie gefunden.' >&2
  fehler=1
fi

# `grep -E` und nicht `rg`: Mit ripgrep meldete diese Pruefung
# "bestanden", obwohl sie gar nicht lief. Fehlt das Werkzeug, endet der
# Aufruf mit "command not found" und damit ungleich null - die
# Bedingung ist dann falsch, der Zweig wird uebersprungen, und die
# Zusicherung am Ende steht trotzdem da. Eine Pruefung, die ohne ihr
# Werkzeug still durchwinkt, ist schlimmer als keine.
#
# Und kein `grep -q`: Es hoert beim ersten Treffer auf zu lesen, `git log`
# stirbt daran mit SIGPIPE (141), und `pipefail` macht aus dem ganzen
# Ausdruck einen Fehlschlag - also genau dann "kein Treffer", wenn es
# einen gibt. So lief es durch, obwohl zwei Commits eine Adresse trugen.
# Ohne `-q` liest `grep` bis zum Ende.
if git log --all --format='%B' | \
    grep -E '[A-Za-z0-9._%+-]+@[A-Za-z][A-Za-z0-9.-]*\.[A-Za-z]{2,}' >/dev/null; then
  echo 'E-Mail-Adresse in einer Commit-Nachricht gefunden.' >&2
  fehler=1
fi

if [ "$fehler" -ne 0 ]; then
  exit 1
fi

echo 'Datenschutz-Prüfung bestanden: Quellstand und Git-Identitäten sind anonym.'
