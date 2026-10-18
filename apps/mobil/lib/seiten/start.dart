import 'package:flutter/material.dart';
import 'package:kern/services/groessentext.dart';

import '../l10n/app_localizations.dart';
import '../sitzung.dart';
import 'alben.dart';
import 'bibliothek.dart';
import 'konto.dart';
import 'suche.dart';
import 'zeitleiste.dart';

/// Die vier Bereiche der App, unten umzuschalten – wie in Immich: Fotos,
/// Suche, Alben und die Bibliothek mit Favoriten, Papierkorb, Karte und
/// Personen. Jeder behält seinen
/// Stand (Scrollposition, Suchtext), während man die anderen ansieht.
class Start extends StatefulWidget {
  const Start({super.key, required this.sitzung});

  final Sitzung sitzung;

  @override
  State<Start> createState() => _StartState();
}

class _StartState extends State<Start> {
  var _bereich = 0;
  final _gebaut = <int>{0};

  /// Zurück in der App: sichern, was dazukam. In den Hintergrund: unter
  /// Android an den Vordergrunddienst übergeben.
  late final _lebenslauf = AppLifecycleListener(
    onResume: () => widget.sitzung.sicherung?.sichere(),
    onHide: () => widget.sitzung.sicherung?.imHintergrund(),
  );

  @override
  void initState() {
    super.initState();
    _lebenslauf;
  }

  @override
  void dispose() {
    _lebenslauf.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final s = widget.sitzung;
    final titel = [t.navZeitleiste, t.navSuche, t.navAlben, t.navBibliothek];
    Widget seite(int i) => switch (i) {
      0 => Zeitleiste(sitzung: s),
      1 => Suche(sitzung: s),
      2 => Alben(sitzung: s),
      _ => Bibliothek(sitzung: s),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(titel[_bereich]),
        actions: [
          // Das Konto als Kreis mit dem Anfangsbuchstaben – wie im Browser.
          IconButton(
            tooltip: t.kontoTitel,
            icon: _Kontokreis(name: s.verbindung?.konto ?? ''),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute<void>(builder: (_) => Konto(sitzung: s))),
          ),
        ],
      ),
      body: Column(
        children: [
          ListenableBuilder(
            listenable: s,
            builder: (context, _) {
              final z = s.abgleichszustand;
              final sp = s.serverspeicher;
              final verbindung = z == null
                  ? null
                  : z.schemaAnders
                  ? (z.appZuAlt ? t.appZuAlt : t.serverZuAlt)
                  : z.abgemeldet
                  ? t.abgemeldetHinweis
                  : !z.erreichbar
                  ? t.offline(z.ausstehend)
                  : null;
              final speicher = sp == null
                  ? null
                  : sp.voll
                  ? t.speicherVoll
                  : sp.knapp
                  ? t.speicherKnapp(groessentext(sp.frei ?? 0))
                  : null;
              final sicherung = s.serversicherung?.warnt ?? false
                  ? t.serverSicherungWarnung
                  : null;
              final text = verbindung ?? speicher ?? sicherung;
              if (text == null) return const SizedBox.shrink();
              return Material(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    verbindung != null
                        ? Icons.cloud_off_outlined
                        : speicher != null
                        ? Icons.storage_outlined
                        : Icons.backup_outlined,
                  ),
                  title: Text(text),
                ),
              );
            },
          ),
          Expanded(
            child: IndexedStack(
              index: _bereich,
              children: [
                // Erst gebaut, wenn man ihn zum ersten Mal öffnet.
                for (var i = 0; i < titel.length; i++)
                  _gebaut.contains(i) ? seite(i) : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _bereich,
        onDestinationSelected: (i) => setState(() {
          _bereich = i;
          _gebaut.add(i);
        }),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.photo_library_outlined),
            selectedIcon: const Icon(Icons.photo_library),
            label: t.navZeitleiste,
          ),
          NavigationDestination(
            icon: const Icon(Icons.search),
            label: t.navSuche,
          ),
          NavigationDestination(
            icon: const Icon(Icons.photo_album_outlined),
            selectedIcon: const Icon(Icons.photo_album),
            label: t.navAlben,
          ),
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view_rounded),
            label: t.navBibliothek,
          ),
        ],
      ),
    );
  }
}

class _Kontokreis extends StatelessWidget {
  const _Kontokreis({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final farben = Theme.of(context).colorScheme;
    final n = name.trim();
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Bibliotheksfarben.personen, farben.primary],
        ),
      ),
      child: Text(
        n.isEmpty ? '?' : n.characters.first.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    );
  }
}
