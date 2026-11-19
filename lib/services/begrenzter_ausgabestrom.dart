import 'dart:typed_data';
import 'package:archive/archive_io.dart';

class BegrenzterDateiAusgabestrom extends OutputStream {
  BegrenzterDateiAusgabestrom(String path, this.maxBytes)
    : _delegate = OutputFileStream(path),
      super(byteOrder: ByteOrder.littleEndian);

  final OutputFileStream _delegate;
  final int maxBytes;

  void _pruefe(int bytes) {
    if (bytes < 0 || length + bytes > maxBytes) {
      throw const FormatException('Unplausible Paketgröße.');
    }
  }

  @override
  int get length => _delegate.length;

  @override
  bool get isOpen => _delegate.isOpen;

  @override
  Future<void> close() => _delegate.close();

  @override
  void closeSync() => _delegate.closeSync();

  @override
  void clear() => _delegate.clear();

  @override
  void flush() => _delegate.flush();

  @override
  Uint8List subset(int start, [int? end]) => _delegate.subset(start, end);

  @override
  void writeByte(int value) {
    _pruefe(1);
    _delegate.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _pruefe(count);
    _delegate.writeBytes(bytes, length: count);
  }

  @override
  void writeStream(InputStream stream) {
    _pruefe(stream.length);
    _delegate.writeStream(stream);
  }
}
