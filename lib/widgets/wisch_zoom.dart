import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Wieviel Zoom eine Wischstrecke von einem Punkt ergibt.
///
/// 0,01 heisst: hundert Punkte Wischweg sind eine Zoomstufe. Ein
/// bequemer Wisch auf einer Tastfläche misst rund hundert bis zweihundert
/// Punkte – eine bis zwei Stufen also, und das entspricht dem, was man
/// von Karten gewohnt ist.
const double wischZoomFaktor = 0.01;

/// Ab welcher Abweichung von 1 eine Geste als Kneifen gilt.
///
/// Ein echtes Trackpad schickt beim Zweifinger-Kneifen dieselbe Art
/// Ereignis wie beim Wischen, nur mit einem Skalenwert. Das kann
/// flutter_map bereits – dort darf nicht dazwischengefunkt werden.
const double wischKneifSchwelle = 0.01;

/// Der neue Zoom für eine Wischgeste.
///
/// Nach oben wischen vergrössert, nach unten verkleinert – so herum
/// kennt man es von Apple Maps und Google Maps auf dem Trackpad. In
/// Flutter wächst y nach unten, ein Wisch nach oben liefert also ein
/// negatives [wischWegY].
double wischZoomStufe({
  required double startZoom,
  required double wischWegY,
  double? kleinsterZoom,
  double? groesserZoom,
}) {
  final neu = startZoom - wischWegY * wischZoomFaktor;
  return neu.clamp(kleinsterZoom ?? 0.0, groesserZoom ?? double.infinity);
}

/// Ob diese Geste ein Wischen ist und kein Kneifen.
bool istWischen(double skala) =>
    (skala - 1).abs() <= wischKneifSchwelle;

/// Legt Wisch-Zoom über eine Karte.
///
/// **Warum das nötig ist – und warum es nicht in einer Zeile geht.**
/// Eine Magic Mouse hat kein Rad, sondern eine Tastfläche; macOS meldet
/// ein Wischen darauf nicht als Radschritte, sondern als fortlaufende
/// Geste, technisch wie ein Trackpad. flutter_map baut seine
/// Gestenerkennung selbst und lässt dabei `trackpadScrollCausesScale`
/// auf der Vorgabe `false` stehen – solche Eingaben **verschieben** also,
/// statt zu zoomen. Einen Schalter dafür bietet die Bibliothek nach
/// aussen nicht an.
///
/// An einer echten Karte nachgemessen, fünf Wischschritte von je zwanzig
/// Punkten nach oben:
///
/// ```
/// Zoom:  8.0 -> 8.0            (unverändert)
/// Mitte: 51,0 -> 50,72         (verschoben)
/// ```
///
/// **Die Reihenfolge ist hier der Kunstgriff – und sie liegt anders
/// herum, als man denkt.** Ein [Listener] bekommt sein Ereignis, bevor
/// die Gestenerkennung daran arbeitet: Flutter reicht das Ereignis erst
/// die getroffene Widget-Kette entlang und lässt ganz zuletzt die
/// Erkenner laufen. Wer hier sofort Mitte und Zoom setzt, dem schreibt
/// die Karte unmittelbar danach die Verschiebung darüber – gemessen:
/// der Zoom blieb bei 8,0.
///
/// Deshalb wird die Korrektur als Mikroaufgabe nachgestellt. Die läuft,
/// sobald die Ereigniszustellung fertig ist, also nach der Karte, und
/// immer noch im selben Einzelbild – sichtbar wird nur das Ergebnis.
///
/// Der Weg über eine eigene Gestenerkennung, die der Karte den Zeiger
/// streitig macht, wäre die naheliegende Alternative gewesen und
/// deutlich zerbrechlicher: Er hinge daran, wer die Kampfarena zuerst
/// für sich entscheidet.
class WischZoom extends StatefulWidget {
  const WischZoom({
    super.key,
    required this.steuerung,
    required this.child,
    this.kleinsterZoom,
    this.groesserZoom,
  });

  final MapController steuerung;
  final Widget child;
  final double? kleinsterZoom;
  final double? groesserZoom;

  @override
  State<WischZoom> createState() => _WischZoomState();
}

class _WischZoomState extends State<WischZoom> {
  /// Stand beim Beginn der Geste. Der Zoom wird daraus fortgeschrieben
  /// statt aus dem jeweils letzten Wert: `pan` ist der Gesamtweg seit
  /// dem Beginn, nicht der Weg seit dem letzten Ereignis.
  double? _startZoom;
  ll.LatLng? _startMitte;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerPanZoomStart: (_) {
          final kamera = widget.steuerung.camera;
          _startZoom = kamera.zoom;
          _startMitte = kamera.center;
        },
        onPointerPanZoomUpdate: (ereignis) {
          final startZoom = _startZoom;
          final startMitte = _startMitte;
          if (startZoom == null || startMitte == null) return;
          if (!istWischen(ereignis.scale)) return;

          final neu = wischZoomStufe(
            startZoom: startZoom,
            wischWegY: ereignis.pan.dy,
            kleinsterZoom: widget.kleinsterZoom,
            groesserZoom: widget.groesserZoom,
          );
          // Die Mitte wird ausdrücklich mitgesetzt: Sie nimmt zurück,
          // was die Karte aus derselben Geste als Verschiebung gemacht
          // hat. Und zwar NACH ihr – siehe die Erklärung oben.
          scheduleMicrotask(() {
            if (!mounted || _startZoom == null) return;
            widget.steuerung.move(startMitte, neu);
          });
        },
        onPointerPanZoomEnd: (_) {
          _startZoom = null;
          _startMitte = null;
        },
        child: widget.child,
      );
}
