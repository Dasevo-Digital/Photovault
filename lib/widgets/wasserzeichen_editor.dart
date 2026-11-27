import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:kern/services/wasserzeichen.dart';
import 'package:zierbild/wasserzeichen_text.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_spacing.dart';
import 'einfuegbares_menue.dart';

/// Der Name eines Ankerpunkts in der Oberflächensprache – wie bei
/// `exportgroesseBezeichnung` nicht im Enum, das im Kern liegt und keine
/// Texte kennt.
String wasserzeichenLageName(AppTexte t, Wasserzeichenlage l) => switch (l) {
  Wasserzeichenlage.obenLinks => t.wasserzeichenLageObenLinks,
  Wasserzeichenlage.oben => t.wasserzeichenLageOben,
  Wasserzeichenlage.obenRechts => t.wasserzeichenLageObenRechts,
  Wasserzeichenlage.links => t.wasserzeichenLageLinks,
  Wasserzeichenlage.mitte => t.wasserzeichenLageMitte,
  Wasserzeichenlage.rechts => t.wasserzeichenLageRechts,
  Wasserzeichenlage.untenLinks => t.wasserzeichenLageUntenLinks,
  Wasserzeichenlage.unten => t.wasserzeichenLageUnten,
  Wasserzeichenlage.untenRechts => t.wasserzeichenLageUntenRechts,
};

/// Liest eine Bilddatei für das Logo; `null` bei Abbruch.
typedef Logowahl = Future<Uint8List?> Function(BuildContext context);

Future<Uint8List?> _logoAusDatei(BuildContext context) async {
  final wahl = await FilePicker.pickFile(
    dialogTitle: AppTexte.of(context).wasserzeichenLogoWaehlen,
    type: FileType.custom,
    allowedExtensions: const ['png'],
  );
  final pfad = wahl?.path;
  if (pfad == null) return null;
  return File(pfad).readAsBytes();
}

/// Die Einstellungen eines Wasserzeichens (#497): Text oder Logo, Lage,
/// Grösse, Deckkraft, Rand – und eine Vorschau, die das Zeichen nach
/// derselben Rechnung setzt wie der Export ([wasserzeichenRechteck]).
///
/// Gebraucht im Editor der Exportvorgaben und im Dialog „Fotobuch
/// gestalten“. Ob überhaupt ein Zeichen gilt, entscheidet der Aufrufer;
/// hier geht es nur um seine Gestalt.
class WasserzeichenEditor extends StatefulWidget {
  const WasserzeichenEditor({
    super.key,
    required this.wert,
    required this.beiAenderung,
    this.logoWaehlen,
  });

  final Wasserzeichen wert;
  final ValueChanged<Wasserzeichen> beiAenderung;

  /// Für Tests; sonst der Dateidialog.
  final Logowahl? logoWaehlen;

  @override
  State<WasserzeichenEditor> createState() => _WasserzeichenEditorState();
}

class _WasserzeichenEditorState extends State<WasserzeichenEditor> {
  late Wasserzeichen _w = widget.wert;
  late final _text = TextEditingController(text: widget.wert.text);
  var _logoUngueltig = false;
  var _laedt = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _setze(Wasserzeichen neu) {
    setState(() => _w = neu);
    widget.beiAenderung(neu);
  }

  Future<void> _logo() async {
    final roh = await (widget.logoWaehlen ?? _logoAusDatei)(context);
    if (roh == null || !mounted) return;
    setState(() => _laedt = true);
    // Ein grosses PNG zu dekodieren und zu verkleinern dauert – nicht im
    // Haupt-Isolate, sonst stünde der Dialog still.
    final fertig = await compute(Wasserzeichenbild.bereiteVor, roh);
    if (!mounted) return;
    setState(() {
      _laedt = false;
      _logoUngueltig = fertig == null;
    });
    if (fertig != null) _setze(_w.kopieMit(bild: fertig));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final stil = Theme.of(context).textTheme.labelLarge;
    final klein = Theme.of(context).textTheme.bodySmall;
    final farben = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<Wasserzeichenart>(
          segments: [
            ButtonSegment(
              value: Wasserzeichenart.text,
              icon: const Icon(Icons.text_fields),
              label: Text(t.wasserzeichenArtText),
            ),
            ButtonSegment(
              value: Wasserzeichenart.bild,
              icon: const Icon(Icons.image_outlined),
              label: Text(t.wasserzeichenArtLogo),
            ),
          ],
          selected: {_w.art},
          showSelectedIcon: false,
          onSelectionChanged: (w) => _setze(_w.kopieMit(art: w.first)),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_w.art == Wasserzeichenart.text)
          TextField(
            contextMenuBuilder: einfuegbaresMenue,
            controller: _text,
            maxLength: Wasserzeichen.hoechstensText,
            decoration: InputDecoration(
              labelText: t.wasserzeichenText,
              hintText: t.wasserzeichenTextBeispiel,
            ),
            onChanged: (s) => _setze(_w.kopieMit(text: s)),
          )
        else ...[
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _laedt ? null : _logo,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(t.wasserzeichenLogoWaehlen),
              ),
              const SizedBox(width: AppSpacing.md),
              if (_laedt)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (_w.bild case final b?)
                Container(
                  height: 40,
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  color: farben.surfaceContainerHighest,
                  child: Image.memory(b, gaplessPlayback: true),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _logoUngueltig
                ? t.wasserzeichenLogoUngueltig
                : t.wasserzeichenLogoHinweis,
            style: _logoUngueltig
                ? klein?.copyWith(color: farben.error)
                : klein,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.wasserzeichenLage, style: stil),
                const SizedBox(height: AppSpacing.xs),
                _Lagewahl(
                  lage: _w.lage,
                  beiWahl: (l) => _setze(_w.kopieMit(lage: l)),
                ),
              ],
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.wasserzeichenVorschau, style: stil),
                  const SizedBox(height: AppSpacing.xs),
                  _Vorschau(wasserzeichen: _w),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(t.wasserzeichenGroesse((_w.groesse * 100).round()), style: stil),
        Slider(
          value: _w.groesse.clamp(
            Wasserzeichen.groesseMin,
            Wasserzeichen.groesseMax,
          ),
          min: Wasserzeichen.groesseMin,
          max: Wasserzeichen.groesseMax,
          divisions: 57,
          onChanged: (v) => _setze(_w.kopieMit(groesse: v)),
        ),
        Text(
          t.wasserzeichenDeckkraft((_w.deckkraft * 100).round()),
          style: stil,
        ),
        Slider(
          value: _w.deckkraft.clamp(
            Wasserzeichen.deckkraftMin,
            Wasserzeichen.deckkraftMax,
          ),
          min: Wasserzeichen.deckkraftMin,
          max: Wasserzeichen.deckkraftMax,
          divisions: 18,
          onChanged: (v) => _setze(_w.kopieMit(deckkraft: v)),
        ),
        Text(t.wasserzeichenRand((_w.rand * 100).round()), style: stil),
        Slider(
          value: _w.rand.clamp(Wasserzeichen.randMin, Wasserzeichen.randMax),
          min: Wasserzeichen.randMin,
          max: Wasserzeichen.randMax,
          divisions: 15,
          onChanged: (v) => _setze(_w.kopieMit(rand: v)),
        ),
      ],
    );
  }
}

/// Neun Knöpfe im Quadrat – die Lage so, wie sie im Bild liegt.
class _Lagewahl extends StatelessWidget {
  const _Lagewahl({required this.lage, required this.beiWahl});

  final Wasserzeichenlage lage;
  final ValueChanged<Wasserzeichenlage> beiWahl;

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final werte = Wasserzeichenlage.values;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var zeile = 0; zeile < 3; zeile++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final l in werte.skip(zeile * 3).take(3))
                SizedBox(
                  width: 40,
                  height: 40,
                  child: l == lage
                      ? IconButton.filled(
                          key: ValueKey('wasserzeichenLage_${l.name}'),
                          tooltip: wasserzeichenLageName(t, l),
                          iconSize: 14,
                          onPressed: () => beiWahl(l),
                          icon: const Icon(Icons.circle),
                        )
                      : IconButton.outlined(
                          key: ValueKey('wasserzeichenLage_${l.name}'),
                          tooltip: wasserzeichenLageName(t, l),
                          iconSize: 14,
                          onPressed: () => beiWahl(l),
                          icon: const Icon(Icons.circle_outlined),
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

/// Ein Bild im Querformat mit dem Zeichen darauf – nach derselben Rechnung
/// wie beim Export, damit „unten rechts, 20 %“ hier aussieht wie dort.
class _Vorschau extends StatelessWidget {
  const _Vorschau({required this.wasserzeichen});

  final Wasserzeichen wasserzeichen;

  /// Die Schriftgrösse, mit der die Vorschau den Text setzt, bevor sie ihn
  /// in sein Rechteck einpasst – wie [wasserzeichentextVerhaeltnis].
  static const _mess = 100.0;

  @override
  Widget build(BuildContext context) {
    final w = wasserzeichen;
    final text = w.text.trim();
    final bild = w.bild;
    ({int breite, int hoehe})? zeichen;
    if (w.art == Wasserzeichenart.text && text.isNotEmpty) {
      final verhaeltnis = wasserzeichentextVerhaeltnis(text);
      zeichen = (breite: 1000, hoehe: (1000 / verhaeltnis).round());
    } else if (w.art == Wasserzeichenart.bild && bild != null) {
      zeichen = Wasserzeichenbild.masse(bild);
    }
    return AspectRatio(
      aspectRatio: 3 / 2,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.xs),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            // Hell oben, dunkel unten wie ein Landschaftsfoto: So zeigt die
            // Vorschau, ob das Zeichen auf beidem lesbar bleibt.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFB9CCDA), Color(0xFF6F7F5C), Color(0xFF3E4634)],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, groesse) {
              final r = zeichen == null
                  ? null
                  : wasserzeichenRechteck(
                      bildBreite: groesse.maxWidth.floor(),
                      bildHoehe: groesse.maxHeight.floor(),
                      zeichenBreite: zeichen.breite,
                      zeichenHoehe: zeichen.hoehe,
                      wasserzeichen: w,
                    );
              return Stack(
                children: [
                  if (r != null)
                    Positioned(
                      left: r.x.toDouble(),
                      top: r.y.toDouble(),
                      width: r.breite.toDouble(),
                      height: r.hoehe.toDouble(),
                      child: Opacity(
                        opacity: w.deckkraft.clamp(0, 1),
                        child: w.art == Wasserzeichenart.text
                            ? FittedBox(
                                child: Padding(
                                  padding: const EdgeInsets.all(_mess * 0.15),
                                  child: Text(
                                    text,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: wasserzeichenTextstil(_mess),
                                  ),
                                ),
                              )
                            : Image.memory(
                                bild!,
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                              ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
