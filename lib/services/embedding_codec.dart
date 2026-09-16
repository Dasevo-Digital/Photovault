import 'dart:typed_data';

/// Wandelt einen als [BlobColumn] gespeicherten Embedding-Vektor (CLIP-
/// Bild-Embedding oder SFace-Gesichts-Embedding) zurück in Float32-Werte.
/// Einzige Quelle der Wahrheit für diese Konvertierung – vorher an drei
/// Stellen unabhängig voneinander inline dupliziert (database.dart,
/// library_state.dart, people_screen.dart).
Float32List floatsFromEmbeddingBlob(Uint8List bytes) =>
    Float32List.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes ~/ 4);

/// Kehrt [floatsFromEmbeddingBlob] um – für das Speichern eines Embeddings
/// als [BlobColumn].
Uint8List blobFromEmbeddingFloats(Float32List vector) =>
    Uint8List.view(vector.buffer, vector.offsetInBytes, vector.lengthInBytes);
