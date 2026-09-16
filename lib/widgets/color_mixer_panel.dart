import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../services/develop_color.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// Anzeigename und Kennfarbe je Band. Die Kennfarbe entsteht nicht aus dem
/// Mittelpunkt-Farbton gerechnet, sondern steht fest: Ein aus HSL bei voller
/// Sättigung erzeugtes Gelb und Blau haben sehr verschiedene wahrgenommene
/// Helligkeiten, die Knopfreihe sähe dann ungleichmässig aus.
const _bandFarbe = <ColorBand, Color>{
  ColorBand.rot: Color(0xFFE05252),
  ColorBand.orange: Color(0xFFE08A3C),
  ColorBand.gelb: Color(0xFFD8C049),
  ColorBand.gruen: Color(0xFF5BAF5B),
  ColorBand.aqua: Color(0xFF4FAFAF),
  ColorBand.blau: Color(0xFF5A82D8),
  ColorBand.violett: Color(0xFF8B6FD0),
  ColorBand.magenta: Color(0xFFC65FA8),
};

/// Der Anzeigename eines Bandes – nicht in [_bandFarbe], weil die Tabelle
/// `const` ist und ein übersetzter Text den Kontext braucht.
String bandName(AppTexte t, ColorBand band) => switch (band) {
      ColorBand.rot => t.bandRot,
      ColorBand.orange => t.bandOrange,
      ColorBand.gelb => t.bandGelb,
      ColorBand.gruen => t.bandGruen,
      ColorBand.aqua => t.bandAqua,
      ColorBand.blau => t.bandBlau,
      ColorBand.violett => t.bandViolett,
      ColorBand.magenta => t.bandMagenta,
    };

/// Farbmischer: acht Farbbänder mit je Farbton, Sättigung und Helligkeit.
///
/// Immer nur ein Band sichtbar bearbeitbar. Alle acht mal drei Regler
/// gleichzeitig wären vierundzwanzig Schieber untereinander – unbenutzbar,
/// und der übliche Grund, warum Lightroom und darktable hier ebenfalls
/// umschalten.
class ColorMixerPanel extends StatefulWidget {
  final ColorMixer mixer;

  /// Während des Ziehens, für die Live-Vorschau.
  final ValueChanged<ColorMixer> onChanged;

  /// Nach dem Loslassen – Anlass für den massgeblichen nativen Render.
  final VoidCallback onChangeEnd;

  const ColorMixerPanel({
    super.key,
    required this.mixer,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<ColorMixerPanel> createState() => _ColorMixerPanelState();
}

class _ColorMixerPanelState extends State<ColorMixerPanel> {
  ColorBand _band = ColorBand.rot;

  BandAnpassung get _aktuell => widget.mixer.band(_band);

  void _setze(BandAnpassung neu) =>
      widget.onChanged(widget.mixer.mitBand(_band, neu));

  @override
  Widget build(BuildContext context) {
    final anpassung = _aktuell;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Flexible, weil das Bedienfeld nur 300 px breit ist: Ohne das
            // läuft die Zeile über, sobald der Knopftext etwas länger wird.
            Flexible(
              child: Text(
                AppTexte.of(context).mischerTitel,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: anpassung.istNeutral
                  ? null
                  : () {
                      _setze(BandAnpassung.neutral);
                      widget.onChangeEnd();
                    },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(AppTexte.of(context).einstZuruecksetzen,
                  style: const TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final band in ColorBand.values)
              _BandKnopf(
                band: band,
                ausgewaehlt: band == _band,
                // Ein Punkt an den Bändern, die tatsächlich etwas tun –
                // sonst müsste man alle acht durchklicken, um zu sehen, wo
                // etwas eingestellt ist.
                verwendet: !widget.mixer.band(band).istNeutral,
                onTap: () => setState(() => _band = band),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _regler(
          AppTexte.of(context).mischerFarbton,
          anpassung.farbton,
          (v) => _setze(BandAnpassung(
            farbton: v,
            saettigung: anpassung.saettigung,
            helligkeit: anpassung.helligkeit,
          )),
        ),
        _regler(
          AppTexte.of(context).mischerSaettigung,
          anpassung.saettigung,
          (v) => _setze(BandAnpassung(
            farbton: anpassung.farbton,
            saettigung: v,
            helligkeit: anpassung.helligkeit,
          )),
        ),
        _regler(
          AppTexte.of(context).mischerHelligkeit,
          anpassung.helligkeit,
          (v) => _setze(BandAnpassung(
            farbton: anpassung.farbton,
            saettigung: anpassung.saettigung,
            helligkeit: v,
          )),
        ),
        Text(
          AppTexte.of(context).mischerHinweis,
          style: const TextStyle(color: DunkleFlaeche.hinweis, fontSize: 11),
        ),
      ],
    );
  }

  /// Wie `_slider` im Entwickeln-Bildschirm, nur fest auf -1..1 und mit
  /// Live-Vorschau: Der Farbwürfel wird auf der GPU nachgeschlagen, dort
  /// gibt es keine Näherung wie beim Weissabgleich.
  Widget _regler(String label, double wert, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
              Text(
                wert.toStringAsFixed(2),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          Slider(
            value: wert,
            min: -1,
            max: 1,
            onChanged: onChanged,
            onChangeEnd: (_) => widget.onChangeEnd(),
          ),
        ],
      ),
    );
  }
}

class _BandKnopf extends StatelessWidget {
  final ColorBand band;
  final bool ausgewaehlt;
  final bool verwendet;
  final VoidCallback onTap;

  const _BandKnopf({
    required this.band,
    required this.ausgewaehlt,
    required this.verwendet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final farbe = _bandFarbe[band]!;
    return Tooltip(
      message: bandName(AppTexte.of(context), band),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: farbe,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: ausgewaehlt ? Colors.white : Colors.white24,
              width: ausgewaehlt ? 2 : 1,
            ),
          ),
          alignment: Alignment.bottomRight,
          padding: const EdgeInsets.all(3),
          child: verwendet
              ? Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
