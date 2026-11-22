import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/l10n/app_localizations.dart';
import 'package:photo_vault/widgets/live_photo_view.dart';
import 'package:photo_vault/widgets/video_playback.dart';

/// Ein Spieler, dessen Öffnen erst endet, wenn die Prüfung es sagt.
class _Spieler implements VideoPlaybackController {
  final offen = Completer<bool>();
  var abgespielt = 0;
  var angehalten = 0;
  var entsorgt = false;
  bool? schleife;

  @override
  bool get isReady => false;

  @override
  Future<bool> open(File file, {bool loop = false}) => offen.future;

  @override
  Future<void> setLooping(bool loop) async => schleife = loop;

  @override
  Future<void> seekToStart() async {}

  @override
  Future<void> play() async => abgespielt++;

  @override
  Future<void> pause() async => angehalten++;

  @override
  Future<void> dispose() async => entsorgt = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// #433: Loslassen während des Öffnens spielte das Video trotzdem ab, und
/// ein zweiter Aufruf in dieser Zeit öffnete einen zweiten Spieler.
void main() {
  final de = lookupAppTexte(const Locale('de'));
  late List<_Spieler> spieler;

  Future<void> zeige(WidgetTester tester) async {
    spieler = [];
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: AppTexte.localizationsDelegates,
        supportedLocales: AppTexte.supportedLocales,
        home: Scaffold(
          body: LivePhotoView(
            imageFile: File('gibt-es-nicht.jpg'),
            videoFile: File('gibt-es-nicht.mov'),
            neuerSpieler: () {
              final neu = _Spieler();
              spieler.add(neu);
              return neu;
            },
          ),
        ),
      ),
    );
  }

  /// Hält über die halbe Sekunde und lässt dann los.
  Future<void> halteUndLasseLos(WidgetTester tester) async {
    final geste = await tester.startGesture(
      tester.getCenter(find.byType(LivePhotoView)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await geste.up();
    await tester.pump();
  }

  testWidgets('losgelassen, bevor das Video offen ist: nichts spielt', (
    tester,
  ) async {
    await zeige(tester);
    await halteUndLasseLos(tester);
    expect(spieler, hasLength(1));

    spieler.single.offen.complete(true);
    await tester.pump();
    await tester.pump();
    expect(spieler.single.abgespielt, 0);
    expect(find.text(de.livePhotoHalten), findsOneWidget);
  });

  testWidgets('loslassen und gleich Play: ein Spieler, in Dauerschleife', (
    tester,
  ) async {
    await zeige(tester);
    await halteUndLasseLos(tester);
    await tester.tap(find.byTooltip(de.liveDauerschleife));
    await tester.pump();
    expect(spieler, hasLength(1), reason: 'kein zweiter Spieler');

    spieler.single.offen.complete(true);
    await tester.pump();
    await tester.pump();
    expect(spieler.single.abgespielt, 1);
    expect(spieler.single.schleife, isTrue);
    expect(find.byTooltip(de.liveWiedergabeStoppen), findsOneWidget);
  });
}
