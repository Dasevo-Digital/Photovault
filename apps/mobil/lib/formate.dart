import 'package:intl/intl.dart';

// Datum und Uhrzeit wie im Browser (Intl `dateStyle: 'medium'`,
// `timeStyle: 'short'`) – damit Telefon und Weboberfläche dieselben
// Zeilen zeigen.

/// „30.08.2026“ bzw. „Aug 30, 2026“.
DateFormat datumMittel(String sprache) => sprache.startsWith('de')
    ? DateFormat('dd.MM.yyyy', sprache)
    : DateFormat.yMMMd(sprache);

/// „30.08.2026, 14:05“ bzw. „Aug 30, 2026, 2:05 PM“.
DateFormat datumZeitMittel(String sprache) => sprache.startsWith('de')
    ? DateFormat('dd.MM.yyyy, HH:mm', sprache)
    : DateFormat('MMM d, y, h:mm a', sprache);
