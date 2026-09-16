import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

import '../db/database.dart';
import '../services/asset_format.dart';
import '../services/exif_camera.dart';
import '../theme/app_spacing.dart';

/// Dialog zum direkten Bearbeiten der Kamera-/Aufnahme-Metadaten eines
/// Assets (Hersteller, Modell, Objektiv, Brennweite, Blende, ISO,
/// Belichtungszeit) – anders als die übrigen Felder der Info-Ansicht
/// (Datum/Ort/Beschreibung) waren diese bisher nur automatisch aus EXIF
/// befüllt und nicht manuell korrigierbar, z.B. wenn die EXIF-Daten fehlen
/// oder falsch sind (gescannte Filmfotos, Screenshots mit nachträglich
/// bekannter Kamera, fehlerhafte Kamera-Firmware).
class MetadataEditorDialog extends StatefulWidget {
  final AssetData asset;
  final AppDatabase db;

  const MetadataEditorDialog({super.key, required this.asset, required this.db});

  @override
  State<MetadataEditorDialog> createState() => _MetadataEditorDialogState();
}

class _MetadataEditorDialogState extends State<MetadataEditorDialog> {
  late final _makeCtrl = TextEditingController(text: widget.asset.cameraMake ?? '');
  late final _modelCtrl = TextEditingController(text: widget.asset.cameraModel ?? '');
  late final _lensCtrl = TextEditingController(text: widget.asset.lensModel ?? '');
  late final _focalCtrl = TextEditingController(
    text: widget.asset.focalLengthMm != null ? widget.asset.focalLengthMm!.toStringAsFixed(1) : '',
  );
  late final _fNumberCtrl = TextEditingController(
    text: widget.asset.fNumber != null ? widget.asset.fNumber!.toStringAsFixed(1) : '',
  );
  late final _isoCtrl = TextEditingController(text: widget.asset.iso?.toString() ?? '');
  late final _exposureCtrl = TextEditingController(
    text: widget.asset.exposureTimeSeconds != null
        ? formatExposureTime(widget.asset.exposureTimeSeconds!).replaceAll(' s', '')
        : '',
  );
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_makeCtrl, _modelCtrl, _lensCtrl, _focalCtrl, _fNumberCtrl, _isoCtrl, _exposureCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final info = CameraInfo(
      make: _makeCtrl.text.trim().isEmpty ? null : _makeCtrl.text.trim(),
      model: _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
      lensModel: _lensCtrl.text.trim().isEmpty ? null : _lensCtrl.text.trim(),
      focalLengthMm: double.tryParse(_focalCtrl.text.trim().replaceAll(',', '.')),
      fNumber: double.tryParse(_fNumberCtrl.text.trim().replaceAll(',', '.')),
      iso: int.tryParse(_isoCtrl.text.trim()),
      exposureTimeSeconds: parseExposureTimeInput(_exposureCtrl.text),
    );
    await widget.db.setCameraMetadata(widget.asset.id, info);
    if (mounted) Navigator.of(context).pop(true);
  }

  Widget _field(String label, TextEditingController controller, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppTexte.of(context).auswMetadaten),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(AppTexte.of(context).metaHersteller, _makeCtrl),
              _field(AppTexte.of(context).metaModell, _modelCtrl),
              _field(AppTexte.of(context).metaObjektiv, _lensCtrl),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _field(AppTexte.of(context).metaBrennweite, _focalCtrl)),
                  const SizedBox(width: 12),
                  Expanded(child: _field(AppTexte.of(context).metaBlende, _fNumberCtrl)),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _field('ISO', _isoCtrl)),
                  const SizedBox(width: 12),
                  Expanded(child: _field(AppTexte.of(context).metaBelichtungszeit, _exposureCtrl, hint: AppTexte.of(context).metaBelichtungBeispiel)),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: Text(AppTexte.of(context).allgAbbrechen),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(AppTexte.of(context).allgSpeichern),
        ),
      ],
    );
  }
}
