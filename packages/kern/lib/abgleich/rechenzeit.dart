/// Wann die Rechenhilfe rechnen darf (#120) – eingestellt je Rechner in
/// `verbindung.json` (siehe `Verbindungsdatei.rechenzeit`).
enum Rechenzeit {
  immer,

  /// Nicht auf Akku. Die Vorgabe: Ein Laptop, der unterwegs für den Server
  /// rechnet, ist schneller leer, als jemand ahnt.
  amNetz,

  /// Am Netzteil und nur, wenn seit [unbenutztNach] niemand Maus oder
  /// Tastatur angefasst hat.
  unbenutzt,
}

/// Ab wann ein Rechner als unbenutzt gilt (siehe [Rechenzeit.unbenutzt]).
const unbenutztNach = Duration(minutes: 5);

/// Warum die Rechenhilfe gerade nicht rechnet.
enum Rechenpause { akku, inBenutzung }

/// Ob die Rechenhilfe nach [zeit] jetzt pausiert – und warum.
///
/// [amNetz] und [ohneEingabe] sind `null`, wo der Rechner es nicht sagt
/// (ein Linux ohne Angaben unter `/sys/class/power_supply`, der Leerlauf
/// unter Linux überhaupt). Dann hält diese Bedingung nicht auf: Lieber
/// rechnen als für immer warten.
Rechenpause? rechenpause(
  Rechenzeit zeit, {
  required bool? amNetz,
  required Duration? ohneEingabe,
}) {
  if (zeit == Rechenzeit.immer) return null;
  if (amNetz == false) return Rechenpause.akku;
  if (zeit == Rechenzeit.unbenutzt &&
      ohneEingabe != null &&
      ohneEingabe < unbenutztNach) {
    return Rechenpause.inBenutzung;
  }
  return null;
}
