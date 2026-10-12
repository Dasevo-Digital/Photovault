/// Was die Oberfläche zu einem Modell des Katalogs anzeigt – getrennt vom
/// Katalog selbst, der ohne Flutter auskommt (`package:kern`).
library;

import '../l10n/app_localizations.dart';

/// Titel, Beschreibung und Lizenz eines Katalogeintrags in der
/// Oberflächensprache.
///
/// Sie stehen nicht in [ModelCatalogEntry] selbst: Die Einträge sind `const`,
/// ein übersetzter Text braucht aber den Kontext. Stünden sie doppelt – hier
/// deutsch und in den Sprachdateien nochmal – liefen beide Fassungen früher
/// oder später auseinander. Die Zuordnung läuft über die
/// [ModelCatalogEntry.id], dieselbe Kennung, unter der die Dateien im
/// Modellordner liegen.
String modellTitel(AppTexte t, String id) => switch (id) {
  'face_detection_yunet' => t.modellYunetTitel,
  'face_recognition_sface' => t.modellSfaceTitel,
  'clip_vit_b32' => t.modellClipTitel,
  'segmentation_sam_vit_base' => t.modellSamTitel,
  'captioning_florence2_base_ft' => t.modellCaptionTitel,
  'speech_whisper_small' => t.modellWhisperTitel,
  'eye_state_ocec' => t.modellOcecTitel,
  'neural_restore_real_esrgan_x4' => t.modellEsrganTitel,
  'inpainting_lama' => t.modellLamaTitel,
  'colorize_ddcolor' => t.modellDdcolorTitel,
  'scratch_detection_bopbtl' => t.modellKratzerTitel,
  'translation_en_de' => t.modellEnDeTitel,
  'translation_de_en' => t.modellDeEnTitel,
  'ocr_ppocr_latin' => t.modellOcrTitel,
  // Lieber die Kennung als eine leere Karte: Ein neu aufgenommenes
  // Modell fällt so sofort auf, statt still ohne Namen dazustehen.
  _ => id,
};

String modellBeschreibung(AppTexte t, String id) => switch (id) {
  'face_detection_yunet' => t.modellYunetText,
  'face_recognition_sface' => t.modellSfaceText,
  'clip_vit_b32' => t.modellClipText,
  'segmentation_sam_vit_base' => t.modellSamText,
  'captioning_florence2_base_ft' => t.modellCaptionText,
  'speech_whisper_small' => t.modellWhisperText,
  'eye_state_ocec' => t.modellOcecText,
  'neural_restore_real_esrgan_x4' => t.modellEsrganText,
  'inpainting_lama' => t.modellLamaText,
  'colorize_ddcolor' => t.modellDdcolorText,
  'scratch_detection_bopbtl' => t.modellKratzerText,
  'translation_en_de' => t.modellEnDeText,
  'translation_de_en' => t.modellDeEnText,
  'ocr_ppocr_latin' => t.modellOcrText,
  _ => '',
};

String modellLizenz(AppTexte t, String id) => switch (id) {
  'face_detection_yunet' => t.modellYunetLizenz,
  'face_recognition_sface' => t.modellSfaceLizenz,
  'clip_vit_b32' => t.modellClipLizenz,
  'segmentation_sam_vit_base' => t.modellSamLizenz,
  'captioning_florence2_base_ft' => t.modellCaptionLizenz,
  'speech_whisper_small' => t.modellWhisperLizenz,
  'eye_state_ocec' => t.modellOcecLizenz,
  'neural_restore_real_esrgan_x4' => t.modellEsrganLizenz,
  'inpainting_lama' => t.modellLamaLizenz,
  'colorize_ddcolor' => t.modellDdcolorLizenz,
  'scratch_detection_bopbtl' => t.modellKratzerLizenz,
  'translation_en_de' => t.modellEnDeLizenz,
  'translation_de_en' => t.modellDeEnLizenz,
  'ocr_ppocr_latin' => t.modellOcrLizenz,
  _ => '',
};
