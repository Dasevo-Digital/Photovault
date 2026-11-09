import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import 'package:kern/services/develop_color.dart';
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
              child: Text(
                AppTexte.of(context).einstZuruecksetzen,
                style: const TextStyle(fontSize: 11),
              ),
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
          (v) => _setze(
            BandAnpassung(
              farbton: v,
              saettigung: anpassung.saettigung,
              helligkeit: anpassung.helligkeit,
            ),
          ),
        ),
        _regler(
          AppTexte.of(context).mischerSaettigung,
          anpassung.saettigung,
          (v) => _setze(
            BandAnpassung(
              farbton: anpassung.farbton,
              saettigung: v,
              helligkeit: anpassung.helligkeit,
            ),
          ),
        ),
        _regler(
          AppTexte.of(context).mischerHelligkeit,
          anpassung.helligkeit,
          (v) => _setze(
            BandAnpassung(
              farbton: anpassung.farbton,
              saettigung: anpassung.saettigung,
              helligkeit: v,
            ),
          ),
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
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
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

enum _Bereich { schatten, mitten, lichter }

/// Sättigung, Dynamik und die Tönung je Helligkeitsbereich (#352, #355).
/// Immer nur ein Bereich sichtbar: wie beim Farbmischer, sonst stünden
/// sechs Schieber untereinander.
class FarbePanel extends StatefulWidget {
  final ColorMixer mixer;
  final ValueChanged<ColorMixer> onChanged;
  final VoidCallback onChangeEnd;

  const FarbePanel({
    super.key,
    required this.mixer,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  State<FarbePanel> createState() => _FarbePanelState();
}

class _FarbePanelState extends State<FarbePanel> {
  var _bereich = _Bereich.schatten;

  Toenung _toenung(_Bereich b) => switch (b) {
    _Bereich.schatten => widget.mixer.schatten,
    _Bereich.mitten => widget.mixer.mitten,
    _Bereich.lichter => widget.mixer.lichter,
  };

  void _setze(Toenung t) => widget.onChanged(switch (_bereich) {
    _Bereich.schatten => widget.mixer.kopie(schatten: t),
    _Bereich.mitten => widget.mixer.kopie(mitten: t),
    _Bereich.lichter => widget.mixer.kopie(lichter: t),
  });

  String _name(AppTexte t, _Bereich b) => switch (b) {
    _Bereich.schatten => t.toenungSchatten,
    _Bereich.mitten => t.toenungMitten,
    _Bereich.lichter => t.toenungLichter,
  };

  @override
  Widget build(BuildContext context) {
    final t = AppTexte.of(context);
    final aktuell = _toenung(_bereich);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _schieber(
          t.mischerSaettigung,
          widget.mixer.saettigung,
          -1,
          1,
          (v) => widget.onChanged(widget.mixer.kopie(saettigung: v)),
        ),
        _schieber(
          t.farbeDynamik,
          widget.mixer.dynamik,
          -1,
          1,
          (v) => widget.onChanged(widget.mixer.kopie(dynamik: v)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          t.toenungTitel,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: 6,
          children: [
            for (final b in _Bereich.values)
              ChoiceChip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  '${_name(t, b)}${_toenung(b).istNeutral ? '' : ' •'}',
                  style: const TextStyle(fontSize: 12),
                ),
                selected: b == _bereich,
                onSelected: (_) => setState(() => _bereich = b),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        // Der Regenbogen zeigt, wohin der Schieber darunter führt.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFF0000),
                  Color(0xFFFFFF00),
                  Color(0xFF00FF00),
                  Color(0xFF00FFFF),
                  Color(0xFF0000FF),
                  Color(0xFFFF00FF),
                  Color(0xFFFF0000),
                ],
              ),
            ),
          ),
        ),
        _schieber(
          t.mischerFarbton,
          aktuell.farbton,
          0,
          360,
          (v) => _setze(Toenung(farbton: v, staerke: aktuell.staerke)),
          nachkomma: 0,
        ),
        _schieber(
          t.toenungStaerke,
          aktuell.staerke,
          0,
          1,
          (v) => _setze(Toenung(farbton: aktuell.farbton, staerke: v)),
        ),
      ],
    );
  }

  Widget _schieber(
    String label,
    double wert,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    int nachkomma = 2,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            Text(
              wert.toStringAsFixed(nachkomma),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
        Slider(
          value: wert.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
          onChangeEnd: (_) => widget.onChangeEnd(),
        ),
      ],
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
