import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/services/tonspur.dart';

/// Musik unter der Diashow: was ffmpeg gesagt bekommt.
///
/// Ein echter Lauf hängt am ffmpeg der Maschine und gehört nicht in die
/// Testreihe (siehe flugvideo_test.dart). Von Hand geprüft mit dem
/// ffmpeg 8 aus Homebrew: 4-s-Video, 1,5-s-Ton → 4,0 s, Bild kopiert,
/// AAC-Spur, Ton wiederholt.
void main() {
  String wert(List<String> a, String schalter) => a[a.indexOf(schalter) + 1];

  test('Bild kopiert, Musik wiederholt und auf Videolänge geschnitten', () {
    final a = ffmpegTonargumente(
      video: '/tmp/stumm.mp4',
      musik: '/tmp/lied.m4a',
      ziel: '/tmp/fertig.mp4',
      dauer: const Duration(seconds: 42, milliseconds: 500),
    );
    expect(wert(a, '-c:v'), 'copy');
    expect(wert(a, '-stream_loop'), '-1');
    // -stream_loop gilt für die Eingabe danach – die Musik, nicht das Bild.
    expect(a.indexOf('-stream_loop'), a.indexOf('/tmp/lied.m4a') - 3);
    expect(wert(a, '-t'), '42.500');
    expect(a.last, '/tmp/fertig.mp4');
    expect(
      wert(a, '-af'),
      'afade=t=in:st=0:d=1.000,afade=t=out:st=39.500:d=3.000',
    );
  });

  test('kürzer als das Ausblenden: blendet über die ganze Länge', () {
    final a = ffmpegTonargumente(
      video: 'v',
      musik: 'm',
      ziel: 'z',
      dauer: const Duration(seconds: 2),
    );
    expect(wert(a, '-af'), endsWith('afade=t=out:st=0.000:d=2.000'));
  });
}
