#!/usr/bin/env bash
# Prüft Quellstand, Historie und Release-Texte auf personenbezogene und
# geheime Spuren.
#
# Aufruf: tool/pruefe_repository_datenschutz.sh [--freigaben] [Datei ...]
#
#   --freigaben  Zusätzlich die Texte aller Releases auf `origin` prüfen.
#                Holt sie über die Gitea-API mit dem Token aus dem
#                Schlüsselbund (`security find-internet-password -s <Host>`);
#                nur auf dem Mac, nicht in der CI.
#   Datei ...    Weitere Texte, etwa ein RELEASE-TEXT-v<version>.md vor dem
#                Hochladen. Die Release-Texte in den Upload-Ordnern auf dem
#                Schreibtisch werden ohnehin mitgeprüft, wenn es sie gibt.
#
# Geprüft wird auf:
#   - E-Mail-Adressen (außer der neutralen Projektkennung)
#   - IPv4-Adressen aus privaten Netzen (10/8, 172.16/12, 192.168/16,
#     169.254/16 und 100.64/10, das Netz von Tailscale und Carrier-NAT)
#   - private Schlüssel (PEM, OpenSSH, PGP)
#   - Zugangstoken mit festem Präfix (GitHub, GitLab, AWS, Slack, Google,
#     Stripe), JWTs und Token in Authorization-Köpfen
#   - interne Hostnamen (.local, .lan, .internal, .home.arpa, .fritz.box …)
#   - Heimatverzeichnisse mit echtem Benutzernamen (/Users/<name>/ …)
#   - die Begriffe der Sperrliste: Echtnamen, eigene Domains, Hostnamen
#
# Die Sperrliste steht NICHT im Repo – sonst stünden die Namen, die sie
# fernhalten soll, öffentlich auf GitHub. Sie liegt lokal unter
# tool/datenschutz_sperrliste.txt (in .gitignore; ein Begriff je Zeile,
# `#` leitet Kommentare ein) oder kommt in der CI aus der Variablen
# DATENSCHUTZ_SPERRLISTE (ein Begriff je Zeile, als Secret hinterlegt).
# Fehlt beides, wird dieser eine Teil übersprungen und das gemeldet.
#
# **Die Ausgabe nennt nur Art, Fundort und Commit, nie den Inhalt.** Ein
# CI-Protokoll ist so öffentlich wie das Repo: Stünde dort die Fundzeile,
# stünde dort genau das Token, der Schlüssel oder die Adresse, die diese
# Prüfung fernhalten soll. Den Inhalt zeigt `git show <commit>` bzw. die
# genannte Datei und Zeile - auf dem eigenen Rechner.
#
# Das Werkzeug behandelt weder Produkttexte wie „E-Mail-Export" noch
# technische @-Zeichen als Kontaktangaben. Es findet ausschließlich
# E-Mail-Formate und stellt sicher, dass Commits nur die Kennung des
# GitHub-Kontos tragen, ohne Klarnamen und ohne echtes Postfach.
set -euo pipefail

wurzel="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$wurzel"

# Byteweise statt nach UTF-8: Die Historie enthält Binärdiffs und
# Dateien in fremden Kodierungen. Unter UTF-8 bricht BSD-grep dort ab
# ("Binary file matches") und braucht für -i ein Vielfaches der Zeit.
# Sperrbegriffe mit Umlauten passen dadurch nur in der Schreibung, in
# der sie in der Liste stehen - also beide Formen eintragen.
export LC_ALL=C

# `grep -E` und nicht `rg`: Mit ripgrep meldete diese Pruefung
# "bestanden", obwohl sie gar nicht lief. Fehlt das Werkzeug, endet der
# Aufruf mit "command not found" und damit ungleich null - die
# Bedingung ist dann falsch, der Zweig wird uebersprungen, und die
# Zusicherung am Ende steht trotzdem da. Eine Pruefung, die ohne ihr
# Werkzeug still durchwinkt, ist schlimmer als keine. Deshalb steht hier
# vorab, was gebraucht wird.
for werkzeug in git grep awk sed; do
  if ! command -v "$werkzeug" >/dev/null 2>&1; then
    echo "Datenschutz-Prüfung nicht möglich: $werkzeug fehlt." >&2
    exit 2
  fi
done

freigaben=0
texte=()
for arg in "$@"; do
  case "$arg" in
    --freigaben) freigaben=1 ;;
    -*) echo "Unbekannte Option: $arg" >&2; exit 2 ;;
    *) texte+=("$arg") ;;
  esac
done

fehler=0
arbeit="$(mktemp -d)"
trap 'rm -rf "$arbeit"' EXIT

# --- Muster -------------------------------------------------------------
#
# Je Eintrag: Name|Schalter|Muster (ERE). Schalter `i` = ohne Rücksicht auf
# Groß- und Kleinschreibung. Die Muster sind so gefasst, dass sie im
# heutigen Quellstand und in der ganzen Historie keinen Fehlalarm
# auslösen; wer eines lockert, prüft das vorher mit
# `git log --all -p | grep -E '<Muster>'`.
email='[A-Za-z0-9._%+-]+@[A-Za-z][A-Za-z0-9.-]*\.[A-Za-z]{2,}'
oktett='[0-9]{1,3}'
muster=(
  "E-Mail-Adresse||$email"
  "private IPv4-Adresse||(^|[^0-9.])(10\.$oktett\.$oktett\.$oktett|192\.168\.$oktett\.$oktett|172\.(1[6-9]|2[0-9]|3[01])\.$oktett\.$oktett|169\.254\.$oktett\.$oktett|100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.$oktett\.$oktett)([^0-9.]|$)"
  "privater Schlüssel||-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY( BLOCK)?-----"
  "Zugangstoken||(gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[abprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|sk_live_[0-9A-Za-z]{16,}|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,})"
  "Token im Authorization-Kopf|i|authorization:? *(token|bearer|basic) +[A-Za-z0-9._~+/=-]{20,}"
  "interner Hostname|i|[a-z0-9-]+\.(local|lan|internal|intranet|home\.arpa|fritz\.box|corp)([^a-z0-9_.-]|$)"
  "Heimatverzeichnis mit Benutzernamen||(^|[^A-Za-z0-9.])(/Users/|/home/|[A-Za-z]:\\\\+Users\\\\+)[a-z][a-z0-9._-]{2,}"
)

# Platzhalter, die so aussehen wie ein Treffer, aber keiner sind.
erlaubt='noreply@photo-vault\.invalid|/home/(test|runner|user|nutzer|benutzer)([^a-z0-9._-]|$)|/Users/(test|runner|user|nutzer|benutzer|shared)([^a-z0-9._-]|$)'

# Sucht in einer Datei mit `Pfad:Zeile:Inhalt`-Zeilen bzw. `Zeile:Inhalt`
# nach einem Muster und lässt die erlaubten Platzhalter weg.
treffer_in() {
  local schalter="$1" regex="$2" datei="$3"
  local opt=(-a -n -E)
  [ "$schalter" = i ] && opt+=(-i)
  # Ohne `-q` (siehe unten) und mit `|| true`: kein Treffer ist hier kein
  # Fehler.
  { grep "${opt[@]}" -e "$regex" "$datei" || true; } | \
    { grep -a -v -E -e "$erlaubt" || true; }
}

# [orte] sind Fundorte (Pfad:Zeile, Commit), nie Fundzeilen - siehe Kopf.
melde() {
  local was="$1" wo="$2" orte="$3"
  printf '%s\n' "$orte" | sort -u | sed 's/^/  /' | cut -c1-240
  echo "$was in $wo gefunden." >&2
  fehler=1
}

# --- Sperrliste ---------------------------------------------------------
sperrliste="$arbeit/sperrliste"
: > "$sperrliste"
lokale_liste="tool/datenschutz_sperrliste.txt"
if git ls-files --error-unmatch "$lokale_liste" >/dev/null 2>&1; then
  echo "$lokale_liste ist eingecheckt - sie darf nie ins Repo." >&2
  fehler=1
fi
if [ -f "$lokale_liste" ]; then
  cat "$lokale_liste" >> "$sperrliste"
fi
if [ -n "${DATENSCHUTZ_SPERRLISTE:-}" ]; then
  printf '%s\n' "$DATENSCHUTZ_SPERRLISTE" >> "$sperrliste"
fi
# Kommentare, Leerzeilen und Ränder weg: Eine leere Zeile in `grep -f`
# passt auf JEDE Zeile.
sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$sperrliste" | \
  { grep -v '^$' || true; } > "$sperrliste.rein"
mv "$sperrliste.rein" "$sperrliste"
sperrbegriffe="$(wc -l < "$sperrliste" | tr -d ' ')"

# Nur Fundort, nie der Inhalt: siehe Kopf.
sperrtreffer_in() {
  local datei="$1"
  [ "$sperrbegriffe" -gt 0 ] || return 0
  { grep -a -n -i -w -F -f "$sperrliste" "$datei" || true; } | cut -d: -f1
}

# --- 1. Quellstand -----------------------------------------------------
quellstand="$arbeit/quellstand"
git grep -I -n -e '' HEAD -- . ':!assets/fonts/**' > "$quellstand" || true

for eintrag in "${muster[@]}"; do
  IFS='|' read -r was schalter regex <<< "$eintrag"
  # `Nr:HEAD:Pfad:Zeile:Inhalt` (grep -n stellt die Nummer voran) - weiter
  # geht nur Pfad:Zeile.
  orte="$(treffer_in "$schalter" "$regex" "$quellstand" | cut -d: -f3,4)"
  [ -z "$orte" ] || melde "$was" "getracktem Quellstand" "$orte"
done
zeilen="$(sperrtreffer_in "$quellstand")"
if [ -n "$zeilen" ]; then
  orte="$(for z in $zeilen; do sed -n "${z}p" "$quellstand" | cut -d: -f2,3; done)"
  melde "Begriff der Sperrliste" "getracktem Quellstand" "$orte"
fi

# --- 2. Historie -------------------------------------------------------
#
# Alle Commits mit ihren Nachrichten und Änderungen, dazu die Texte der
# annotierten Tags. Was einmal hinzugefügt wurde, steht in der Historie,
# auch wenn es heute gelöscht ist - und genau das spiegelt Gitea nach
# GitHub.
historie="$arbeit/historie"
{
  git log --all -p -U0 --no-color --no-ext-diff --format='commit %H%n%B'
  git for-each-ref refs/tags --format='commit %(refname:short)%n%(contents)'
} > "$historie"

# Ordnet Zeilennummern der Historie Commit und Datei zu - als Fundort
# ohne den Inhalt der Zeile.
fundorte_in_historie() {
  awk -v ziele="$1" '
    BEGIN { n = split(ziele, z, " "); for (i = 1; i <= n; i++) suche[z[i]] = 1 }
    /^commit / { aktuell = substr($2, 1, 12); datei = "(Nachricht)" }
    /^diff --git / { datei = $NF; sub(/^b\//, "", datei) }
    (NR in suche) { print aktuell " " datei }
  ' "$historie" | sort -u
}

for eintrag in "${muster[@]}"; do
  IFS='|' read -r was schalter regex <<< "$eintrag"
  funde="$(treffer_in "$schalter" "$regex" "$historie" | cut -d: -f1)"
  if [ -n "$funde" ]; then
    melde "$was" "der Historie" \
      "$(fundorte_in_historie "$(printf '%s\n' "$funde" | tr '\n' ' ')")"
  fi
done
zeilen="$(sperrtreffer_in "$historie")"
if [ -n "$zeilen" ]; then
  melde "Begriff der Sperrliste" "der Historie" \
    "$(fundorte_in_historie "$(printf '%s\n' "$zeilen" | tr '\n' ' ')")"
fi

# Autor und Committer sind der GitHub-Login mit der noreply-Adresse von
# GitHub. Beides steht zerlegt hier, damit weder die Suche nach Adressen
# noch die Sperrliste den Quellstand dieser Prüfung selbst meldet.
kennung_name='super''kuh86'
kennung_mail='335995236+super''kuh86'@'users.noreply.github.com'
if git log --all --format='%an%x09%ae%x09%cn%x09%ce' | \
    awk -F '\t' -v n="$kennung_name" -v m="$kennung_mail" \
      '$1 != n || $2 != m || $3 != n || $4 != m { exit 1 }'; then
  :
else
  echo 'Nicht anonyme Autor- oder Commit-Identität in der Historie gefunden.' >&2
  fehler=1
fi

# Kein `grep -q` hinter `git log`: Es hoert beim ersten Treffer auf zu
# lesen, `git log` stirbt daran mit SIGPIPE (141), und `pipefail` macht aus
# dem ganzen Ausdruck einen Fehlschlag - also genau dann "kein Treffer",
# wenn es einen gibt. So lief es durch, obwohl zwei Commits eine Adresse
# trugen. Deshalb liest oben alles aus einer Datei.

# --- 3. Release-Texte --------------------------------------------------
shopt -s nullglob
for datei in "$HOME"/Desktop/PhotoVault-Release-*/RELEASE-TEXT-*.md; do
  texte+=("$datei")
done
shopt -u nullglob

if [ "$freigaben" -eq 1 ]; then
  for werkzeug in curl python3 security; do
    if ! command -v "$werkzeug" >/dev/null 2>&1; then
      echo "--freigaben braucht $werkzeug." >&2
      exit 2
    fi
  done
  # Host und Repo aus `origin`, damit hier kein Hostname im Quelltext steht.
  ursprung="$(git remote get-url origin)"
  ursprung="${ursprung%.git}"
  gitea_host="$(printf '%s' "$ursprung" | sed -E 's#^https?://([^/]+)/.*#\1#')"
  gitea_repo="$(printf '%s' "$ursprung" | sed -E 's#^https?://[^/]+/##')"
  GITEA_TOKEN="$(security find-internet-password -s "$gitea_host" -w 2>/dev/null || true)"
  if [ -z "$GITEA_TOKEN" ]; then
    echo "Kein Gitea-Token im Schlüsselbund - Release-Texte nicht geprüft." >&2
    exit 2
  fi
  seite=1
  while :; do
    antwort="$arbeit/freigaben_$seite.json"
    # Der Token geht per Kopf aus einer Datei, nicht über die Befehlszeile:
    # Die ist für jeden Prozess auf dem Rechner lesbar.
    printf 'header = "Authorization: token %s"\n' "$GITEA_TOKEN" > "$arbeit/kopf"
    curl -fsS -K "$arbeit/kopf" -o "$antwort" \
      "https://$gitea_host/api/v1/repos/$gitea_repo/releases?limit=50&page=$seite"
    rm -f "$arbeit/kopf"
    # JSON mit Python auswerten, nicht mit echo: zsh macht aus `\n` echte
    # Zeilenumbrüche.
    anzahl="$(python3 - "$antwort" "$arbeit" <<'PY'
import json, sys
eintraege = json.load(open(sys.argv[1]))
for r in eintraege:
    with open(f"{sys.argv[2]}/freigabe_{r['tag_name']}.md", "w") as f:
        f.write(f"{r.get('name') or ''}\n{r.get('body') or ''}\n")
print(len(eintraege))
PY
)"
    [ "$anzahl" -ge 50 ] || break
    seite=$((seite + 1))
  done
  unset GITEA_TOKEN
  shopt -s nullglob
  for datei in "$arbeit"/freigabe_*.md; do texte+=("$datei"); done
  shopt -u nullglob
fi

for datei in ${texte[@]+"${texte[@]}"}; do
  if [ ! -f "$datei" ]; then
    echo "Datei nicht gefunden: $datei" >&2
    fehler=1
    continue
  fi
  name="$(basename "$datei")"
  case "$datei" in "$arbeit"/*) name="Release ${name#freigabe_}"; name="${name%.md}" ;; esac
  for eintrag in "${muster[@]}"; do
    IFS='|' read -r was schalter regex <<< "$eintrag"
    zeilen="$(treffer_in "$schalter" "$regex" "$datei" | cut -d: -f1)"
    [ -z "$zeilen" ] || melde "$was" "$name" \
      "Zeilen: $(printf '%s\n' "$zeilen" | tr '\n' ' ')"
  done
  zeilen="$(sperrtreffer_in "$datei")"
  [ -z "$zeilen" ] || melde "Begriff der Sperrliste" "$name" \
    "Zeilen: $(printf '%s\n' "$zeilen" | tr '\n' ' ')"
done

if [ "$fehler" -ne 0 ]; then
  exit 1
fi

if [ "$sperrbegriffe" -eq 0 ]; then
  echo 'Hinweis: keine Sperrliste - Echtnamen und eigene Hostnamen nicht geprüft.' >&2
fi
echo "Datenschutz-Prüfung bestanden: Quellstand, Historie und ${#texte[@]} Release-Text(e) sind anonym (Sperrliste: $sperrbegriffe Begriff(e))."
