'use strict';

// --- Sprache der Weboberfläche ------------------------------------------------
//
// Deutsch ist die Vorlage: Im Code und im HTML steht der deutsche Text, und
// er ist zugleich der Schlüssel. t('…') schlägt ihn im englischen Wörterbuch
// nach, wenn Englisch gilt; fehlt ein Eintrag, bleibt das Deutsche stehen.
// Platzhalter in geschweiften Klammern: t('{n} Aufnahmen', { n: 3 }).
//
// Welche Sprache gilt: die in den Einstellungen gewählte (nur in diesem
// Browser gemerkt), sonst die des Browsers – Deutsch für de-*, sonst
// Englisch.

const SPRACHE_MERKER = 'pv-sprache';

const SPRACHE = (() => {
  let gewaehlt = null;
  try { gewaehlt = localStorage.getItem(SPRACHE_MERKER); } catch (_) { /* privat */ }
  if (gewaehlt === 'de' || gewaehlt === 'en') return gewaehlt;
  return (navigator.language || 'de').toLowerCase().startsWith('de') ? 'de' : 'en';
})();

// Für Intl: die Region des Browsers, wenn sie zur Sprache passt.
const GEBIET = (navigator.language || '').toLowerCase().startsWith(SPRACHE) ? navigator.language : SPRACHE;

function spracheJetzt() { return SPRACHE; }

function spracheWaehlen(wert) {
  try {
    if (wert === 'de' || wert === 'en') localStorage.setItem(SPRACHE_MERKER, wert);
    else localStorage.removeItem(SPRACHE_MERKER);
  } catch (_) { /* privat */ }
  location.reload();
}

const EN = {
  // Kopf und Wege
  'Fotos': 'Photos',
  'Suche': 'Search',
  'Alben': 'Albums',
  'Personen': 'People',
  'Bibliothek': 'Library',
  'Entdecken': 'Explore',
  'Verwalten': 'Manage',
  'Bereiche': 'Sections',
  'Seitenleiste ein- oder ausklappen': 'Collapse or expand the sidebar',
  'Karte': 'Map',
  'Reisen': 'Trips',
  'Stammbaum': 'Family tree',
  'Statistik': 'Statistics',
  'Duplikate': 'Duplicates',
  'Papierkorb': 'Trash',
  'Einstellungen': 'Settings',
  'Konto': 'Account',
  'Auswählen': 'Select',
  'Mehrere auswählen': 'Select several',
  // Anmeldung
  'Anmelden': 'Sign in',
  'Passwort': 'Password',
  'Code': 'Code',
  'Bestätigen': 'Confirm',
  'Richte den Code in deiner Authenticator-App ein:': 'Set up the code in your authenticator app:',
  'In der App öffnen': 'Open in the app',
  'Dieses Konto braucht einen zweiten Faktor.': 'This account needs a second factor.',
  'Gib den Code aus deiner Authenticator-App ein.': 'Enter the code from your authenticator app.',
  'Deine Wiederherstellungscodes – bitte sicher aufbewahren:': 'Your recovery codes – please keep them safe:',
  'Fehler {n}': 'Error {n}',
  // Fehler vom Server
  'unbekannt': 'unknown',
  'name und passwort fehlen': 'name and password are missing',
  'vorgang und code fehlen': 'missing request or code',
  'text fehlt': 'text is missing',
  'kein Modell für die Bildsuche': 'no model for image search',
  'Nur für Verwalter.': 'Administrators only.',
  'Name, Passwort oder Code stimmt nicht': 'Name, password or code is wrong',
  'Passwort oder Code stimmt nicht': 'Password or code is wrong',
  'Code stimmt nicht': 'The code is wrong',
  'Code ungültig oder abgelaufen': 'Code invalid or expired',
  'Zu viele Fehlversuche': 'Too many failed attempts',
  'Die Sicherung ist nicht eingerichtet.': 'Backup is not set up.',
  'Kein Sicherungsziel eingestellt.': 'No backup destination set.',
  'Kein solches Konto.': 'No such account.',
  'Das eigene Konto nicht hier.': 'Not your own account here.',
  'Der Speicher des Servers ist voll.': 'The server storage is full.',
  'Der Suchtext liess sich nicht einbetten': 'The search text could not be embedded',
  'dorthin legt der Server nichts': 'the server does not store files there',
  'zu gross': 'too large',
  // Raster
  '{n} Aufnahmen': '{n} items',
  '1 Aufnahme': '1 item',
  'Keine Aufnahmen.': 'No items.',
  'Noch keine Aufnahmen.': 'No items yet.',
  'Der Papierkorb ist leer.': 'The trash is empty.',
  'Erinnerungen': 'Memories',
  'Vor einem Jahr': 'One year ago',
  'Vor {n} Jahren': '{n} years ago',
  '{monat} vor einem Jahr': '{monat}, one year ago',
  '{monat} vor {n} Jahren': '{monat}, {n} years ago',
  'Noch keine Alben.': 'No albums yet.',
  'Noch keine Reisen.': 'No trips yet.',
  'Noch keine Personen.': 'No people yet.',
  'Serie · {n} Aufnahmen': 'Stack · {n} items',
  // Auswahl
  '{n} ausgewählt': '{n} selected',
  'Auswahl aufheben': 'Clear selection',
  '♥ Favorit': '♥ Favorite',
  'Album': 'Album',
  'Herunterladen': 'Download',
  'Zurückholen': 'Restore',
  'Zum Album hinzufügen': 'Add to album',
  'Neues Album': 'New album',
  'Name': 'Name',
  'Abbrechen': 'Cancel',
  'Hinzufügen': 'Add',
  'Eine Aufnahme in den Papierkorb legen? Sie verschwindet überall – zurückholen geht am Rechner und hier im Papierkorb.': 'Move one item to the trash? It disappears everywhere – you can restore it on the computer or here in the trash.',
  '{n} Aufnahmen in den Papierkorb legen? Sie verschwinden überall – zurückholen geht am Rechner und hier im Papierkorb.': 'Move {n} items to the trash? They disappear everywhere – you can restore them on the computer or here in the trash.',
  '{n} zurückgeholt': '{n} restored',
  '{n} im Album „{name}“': '{n} in the album “{name}”',
  // Betrachter und Angaben
  'Schliessen': 'Close',
  'Vorige': 'Previous',
  'Nächste': 'Next',
  'Favorit': 'Favorite',
  'Original herunterladen': 'Download original',
  'Angaben': 'Details',
  'Entwickeln': 'Edit',
  'Lade …': 'Loading …',
  'Datum geschätzt': 'Date estimated',
  'bearbeitet': 'edited',
  'Standort bekannt': 'Location known',
  'vom Nachbarfoto übernommen': 'taken from a neighbouring photo',
  'Beschreibung': 'Description',
  'Speichern': 'Save',
  'Gespeichert': 'Saved',
  'Gespeichert.': 'Saved.',
  'Automatisch: {text}': 'Automatic: {text}',
  '{i} von 5': '{i} of 5',
  'Serie mit {n} Aufnahmen': 'Stack with {n} items',
  'Erkannter Text': 'Recognized text',
  'Transkript': 'Transcript',
  'Importiert {datum}': 'Imported {datum}',
  // Suche
  'Wonach suchst du?': 'What are you looking for?',
  'Bildinhalt': 'Image content',
  'Text': 'Text',
  'Suchen': 'Search',
  'Sucht …': 'Searching …',
  'Nichts gefunden.': 'Nothing found.',
  'Der Server hat kein Modell für die Bildsuche – suche nach Text.': 'The server has no model for image search – search by text.',
  // Karte, Reisen, Statistik
  '{n} Aufnahme an diesem Ort': '{n} item at this place',
  '{n} Aufnahmen an diesem Ort': '{n} items at this place',
  'Medien insgesamt': 'Total items',
  'Videos': 'Videos',
  'Favoriten': 'Favorites',
  'Speicherplatz': 'Storage',
  'Im Papierkorb': 'In the trash',
  'Gesperrter Ordner': 'Locked folder',
  'Noch keine Fotos oder Videos in der Bibliothek.': 'No photos or videos in the library yet.',
  'Fotos & Videos pro Jahr': 'Photos & videos per year',
  'Saisonalität – Aufnahmen pro Monat': 'Seasonality – items per month',
  'Häufigste Kameras': 'Most used cameras',
  // Duplikate
  'Ähnlichkeit': 'Similarity',
  'Suche …': 'Searching …',
  '{n} Kopien in den Papierkorb': '{n} copies to the trash',
  'Noch keine Bildeinbettungen – die Auswertung auf dem Server muss zuerst gelaufen sein.': 'No image embeddings yet – the analysis on the server has to run first.',
  'Keine Duplikate bei {p} Ähnlichkeit.': 'No duplicates at {p} similarity.',
  '{n} Paare sind ausgenommen.': '{n} pairs are excluded.',
  '{n} Gruppen bei {p} Ähnlichkeit. Das umrandete Foto würde beim Aufräumen behalten; Gruppen mit mehreren Favoriten oder Bewertungen bleiben unangetastet.': '{n} groups at {p} similarity. The outlined photo would be kept when cleaning up; groups with several favorites or ratings stay untouched.',
  'Keine Duplikate': 'Not duplicates',
  '{n} Aufnahmen · mehrere ausgezeichnet, nur von Hand': '{n} items · several marked, by hand only',
  'Behalten': 'Keep',
  '„{name}“ behalten und die andere Aufnahme in den Papierkorb legen?': 'Keep “{name}” and move the other item to the trash?',
  '„{name}“ behalten und die {n} anderen in den Papierkorb legen?': 'Keep “{name}” and move the {n} others to the trash?',
  '{n} Kopien aus {g} Gruppen in den Papierkorb legen? Je Gruppe bleibt das umrandete Foto.': 'Move {n} copies from {g} groups to the trash? In each group the outlined photo stays.',
  // Stammbaum und Lebensbaum
  'Person': 'Person',
  'Zoom': 'Zoom',
  'Lebensbaum': 'Life tree',
  '{name} (ohne Verwandtschaft)': '{name} (no relatives)',
  'Noch keine Personen. Lege sie am Rechner unter Personen und Stammbaum an.': 'No people yet. Add them on the computer under People and Family tree.',
  'Zu dieser Person ist noch keine Verwandtschaft eingetragen – das geht am Rechner im Stammbaum.': 'No relatives are recorded for this person yet – that is done on the computer in the family tree.',
  '{n} Haushalte passen nicht mehr ins Bild.': '{n} households no longer fit in the picture.',
  'Stil': 'Style',
  'Pergament': 'Parchment',
  'Landschaft': 'Landscape',
  'Wappen': 'Heraldic',
  'Gold': 'Gold',
  'Zeigt': 'Shows',
  'Vorfahren': 'Ancestors',
  'Nachkommen': 'Descendants',
  'Paar': 'Couple',
  'Familie': 'Family',
  'Generationen': 'Generations',
  'Nach oben': 'Upwards',
  'Nach unten': 'Downwards',
  'Kreis': 'Circle',
  'Direkte Linie': 'Direct line',
  'Mit Geschwistern': 'With siblings',
  'Alle': 'All',
  'Porträts': 'Portraits',
  'Als Bild speichern': 'Save as image',
  'Das Vorlagenbild fehlt auf dem Server.': 'The template image is missing on the server.',
  // Entwickeln
  'Belichtung': 'Exposure',
  'Kontrast': 'Contrast',
  'Lichter': 'Highlights',
  'Schatten': 'Shadows',
  'Farbtemperatur': 'Temperature',
  'Tönung': 'Tint',
  'Klarheit': 'Clarity',
  'Schärfe': 'Sharpness',
  'Rauschminderung': 'Noise reduction',
  'Vignettierung': 'Vignette',
  'Automatischer Weissabgleich': 'Automatic white balance',
  'Vorher': 'Before',
  'Gedrückt halten zeigt das Original': 'Hold to show the original',
  'Regler zurücksetzen': 'Reset sliders',
  'Entwicklung entfernen': 'Remove edits',
  'Dieser Browser kann kein WebGL 2 – Entwickeln geht hier nicht.': 'This browser has no WebGL 2 – editing is not possible here.',
  'Das Bild liess sich nicht laden ({n}).': 'The image could not be loaded ({n}).',
  'Das Bild ist für diesen Browser zu gross.': 'The image is too large for this browser.',
  'Rohformat oder HEIC: Der Browser rechnet aus der Vorschau (höchstens 2048 Pixel). In voller Grösse entwickelt der Rechner.': 'RAW or HEIC: the browser works from the preview (at most 2048 pixels). The computer edits at full size.',
  'Tonkurve, Farbmischer und Look vom Rechner wirken mit und bleiben erhalten.': 'Tone curve, color mixer and look from the computer apply and are kept.',
  'Rechne in voller Grösse ({b} × {h}) …': 'Rendering at full size ({b} × {h}) …',
  'Das Bild liess sich nicht kodieren.': 'The image could not be encoded.',
  'Lade hoch …': 'Uploading …',
  'Hochladen gescheitert ({n}).': 'Upload failed ({n}).',
  'Änderungen verwerfen?': 'Discard changes?',
  'Die Entwicklung entfernen und das Original zeigen?': 'Remove the edits and show the original?',
  // Einstellungen
  'Einstellungen der Bibliothek': 'Library settings',
  'Diese Einstellungen stehen in der Bibliothek und gelten für alle verbundenen Geräte.': 'These settings are stored in the library and apply to all connected devices.',
  'Sprache dieser Oberfläche': 'Language of this interface',
  'Gilt nur in diesem Browser.': 'Applies to this browser only.',
  'Automatisch': 'Automatic',
  'Papierkorb automatisch leeren': 'Empty trash automatically',
  'Löscht Aufnahmen im Papierkorb nach Ablauf der Frist endgültig – unwiderruflich.': 'Permanently deletes items in the trash after the period – irreversibly.',
  'nach': 'after',
  'Tagen': 'days',
  'ab {p}': 'from {p}',
  'Sichere Vorschläge automatisch übernehmen': 'Accept confident suggestions automatically',
  'Erkannte Gesichter, die einer Person sehr ähnlich sind, werden ohne Rückfrage zugeordnet.': 'Detected faces that are very similar to a person are assigned without asking.',
  'KI-Auswertung nach dem Import automatisch nachholen': 'Run AI analysis automatically after import',
  'Neue Aufnahmen werden gleich ausgewertet: Gesichter, Bildinhalt, Text, Schlagwörter.': 'New items are analysed right away: faces, image content, text, keywords.',
  'Suche und Schlagwörter übersetzen': 'Translate search and keywords',
  'Sucht auf Deutsch und Englisch gleichzeitig und führt Schlagwörter in beiden Sprachen.': 'Searches in German and English at once and keeps keywords in both languages.',
  'Private Metadaten schützen': 'Protect private metadata',
  'Neu gesperrte Aufnahmen legen auch Ort, Beschreibung und Text verschlüsselt ab.': 'Newly locked items also store location, description and text encrypted.',
  'Schwelle der Gesichtserkennung': 'Face recognition threshold',
  'Wie ähnlich ein Gesicht sein muss, um einer Person vorgeschlagen zu werden. Höher heisst vorsichtiger.': 'How similar a face must be to be suggested for a person. Higher means more cautious.',
  // Konto und Verwaltung
  'Server': 'Server',
  'Auswertung anstossen': 'Start analysis',
  'Jetzt sichern': 'Back up now',
  'Konten': 'Accounts',
  'Neues Konto': 'New account',
  'Passwort (mind. 12 Zeichen)': 'Password (at least 12 characters)',
  'Verwalter': 'Administrator',
  'Anlegen': 'Create',
  'Geräte': 'Devices',
  'Passwort ändern': 'Change password',
  'Aktuelles Passwort': 'Current password',
  'Neues Passwort': 'New password',
  'Noch einmal': 'Repeat',
  'TOTP-Code': 'TOTP code',
  'Andere Geräte abmelden': 'Sign out other devices',
  'Ändern': 'Change',
  'Abmelden': 'Sign out',
  'Gerät abmelden': 'Sign out device',
  '(dieser Browser)': '(this browser)',
  'zuletzt {datum}': 'last {datum}',
  '„{name}“ abmelden?': 'Sign out “{name}”?',
  'Die neuen Passwörter stimmen nicht überein.': 'The new passwords do not match.',
  'Passwort geändert.': 'Password changed.',
  'TOTP eingerichtet': 'TOTP set up',
  'gesperrt': 'locked',
  '{n} Gerät': '{n} device',
  '{n} Geräte': '{n} devices',
  'Entsperren': 'Unlock',
  'Entfernen': 'Remove',
  '„{name}“ entfernen? Die Bibliothek bleibt auf dem Server liegen.': 'Remove “{name}”? The library stays on the server.',
  'Speicher: {frei} frei von {gesamt}': 'Storage: {frei} free of {gesamt}',
  'Sicherung: {stufe}': 'Backup: {stufe}',
  'Auswertung: nichts offen': 'Analysis: nothing pending',
  'Auswertung läuft: {stufe} ({nr}/{von}), {erledigt} von {gesamt}': 'Analysis running: {stufe} ({nr}/{von}), {erledigt} of {gesamt}',
  'Protokoll': 'Protocol',
  'angemeldet als {name}': 'signed in as {name}',
  'nächste {datum}': 'next {datum}',
  'du': 'you',
  // Stufen von Speicher und Sicherung, wie der Server sie nennt
  'ausreichend': 'sufficient',
  'knapp': 'low',
  'voll': 'full',
  'aus': 'off',
  'nichtEingerichtet': 'not set up',
  'zielFehlt': 'destination missing',
  'fehler': 'error',
  'veraltet': 'out of date',
  'ok': 'ok',
  // Wie die Handy-App: Auswahl, Teilen, Favoriten, Hochladen
  'Ganzen Tag auswählen': 'Select the whole day',
  'Ganzen Tag abwählen': 'Deselect the whole day',
  'Teilen': 'Share',
  'In ein Album': 'Add to an album',
  'Dieses Format kann der Browser nicht teilen.': 'The browser cannot share this format.',
  'Bereit – zum Teilen noch einmal tippen.': 'Ready – tap again to share.',
  'In den Papierkorb': 'Move to trash',
  'Noch keine Favoriten.': 'No favorites yet.',
  'Hochladen': 'Upload',
  'Fotos und Videos hochladen': 'Upload photos and videos',
  'Dateien hier ablegen zum Hochladen': 'Drop files here to upload',
  '{i} von {n}': '{i} of {n}',
  '{n} neu': '{n} new',
  '{n} schon da': '{n} already there',
  '{n} abgelehnt': '{n} rejected',
  'Abgebrochen': 'Cancelled',
  'Fertig': 'Done',
  'Format nicht unterstützt': 'Format not supported',
  'Kein Platz auf dem Server': 'No space left on the server',
  'Der Server konnte die Datei nicht aufnehmen': 'The server could not import the file',
  // Reisen und Aktivitäten
  'Aktivitäten': 'Activities',
  'Noch keine Aktivitäten.': 'No activities yet.',
  'Gehört zu: {reise}': 'Part of: {reise}',
  'ein weiterer Ort': 'one more place',
  '{n} weitere Orte': '{n} more places',
  '{m}\u00a0min': '{m}\u00a0min',
  '{h}\u00a0h {m}\u00a0min': '{h}\u00a0h {m}\u00a0min',
  '{km}\u00a0km': '{km}\u00a0km',
  'Spaziergang': 'Walk',
  'Wanderung': 'Hike',
  'Radtour': 'Bike ride',
  'Ausflug': 'Outing',
  'Besichtigung': 'Sightseeing',
  'Bootsfahrt': 'Boat trip',
  'Sonstiges': 'Other',
  'Zu wenige verortete Aufnahmen für eine Strecke.': 'Too few located photos for a route.',
};

function t(deutsch, werte) {
  let s = SPRACHE === 'en' && Object.prototype.hasOwnProperty.call(EN, deutsch) ? EN[deutsch] : deutsch;
  if (werte) {
    for (const [k, v] of Object.entries(werte)) s = s.split(`{${k}}`).join(String(v));
  }
  return s;
}

// Die festen Texte im HTML: Textknoten und die Merkmale, die man liest.
function uebersetzeSeite(wurzel = document.body) {
  document.documentElement.lang = SPRACHE;
  if (SPRACHE === 'de') return;
  const gang = document.createTreeWalker(wurzel, NodeFilter.SHOW_TEXT);
  const knoten = [];
  while (gang.nextNode()) knoten.push(gang.currentNode);
  for (const k of knoten) {
    const roh = k.nodeValue;
    const text = roh.trim();
    if (text && Object.prototype.hasOwnProperty.call(EN, text)) k.nodeValue = roh.replace(text, EN[text]);
  }
  for (const e of wurzel.querySelectorAll('[placeholder], [title], [aria-label]')) {
    for (const merkmal of ['placeholder', 'title', 'aria-label']) {
      const wert = e.getAttribute(merkmal);
      if (wert && Object.prototype.hasOwnProperty.call(EN, wert)) e.setAttribute(merkmal, EN[wert]);
    }
  }
}

uebersetzeSeite();
