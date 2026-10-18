import 'lebensbaum.dart';
import 'stammbaum.dart';
import 'verwandtschaftsgrad.dart';

/// Verwandtschaftsbezeichnungen auf Deutsch und Englisch – für die
/// Handy-App, die keine Textbausteine des Rechners hat. Dieselben Wörter
/// wie dort (lib/l10n, grad*) und im Browser (web/lebensbaum.js, LB_GRAD).
///
/// Je Stufe ein eigenes Wort und ab der fünften eine ausgeschriebene
/// Auskunft – zusammengesetzte Vorsilben wären in einer der beiden
/// Sprachen falsch (siehe lib/widgets/verwandtschaft_text.dart).
class Verwandtschaftstexte {
  const Verwandtschaftstexte._(this._de);

  final bool _de;

  static const deutsch = Verwandtschaftstexte._(true);
  static const englisch = Verwandtschaftstexte._(false);

  /// Deutsch für `de…`, sonst Englisch.
  static Verwandtschaftstexte fuer(String sprache) =>
      sprache.startsWith('de') ? deutsch : englisch;

  String _w(
    String g,
    (String, String, String) de,
    (String, String, String) en,
  ) {
    final (w, m, other) = _de ? de : en;
    return g == 'w'
        ? w
        : g == 'm'
        ? m
        : other;
  }

  /// Wie [person] mit der Person am Stamm verwandt ist.
  String grad(Grad grad, String? geschlecht) {
    final g = auswahlwert(geschlechtAusText(geschlecht));
    final auf = grad.aufwaerts, ab = grad.abwaerts;
    switch (grad.art) {
      case Gradart.selbst:
        return _de ? 'diese Person' : 'this person';
      case Gradart.vorfahre:
        if (grad.elternArt == Verwandtschaft.adoptivelternteil) {
          return _w(
            g,
            ('Adoptivmutter', 'Adoptivvater', 'Adoptivelternteil'),
            ('Adoptive mother', 'Adoptive father', 'Adoptive parent'),
          );
        }
        if (grad.elternArt == Verwandtschaft.pflegeelternteil) {
          return _w(
            g,
            ('Pflegemutter', 'Pflegevater', 'Pflegeelternteil'),
            ('Foster mother', 'Foster father', 'Foster parent'),
          );
        }
        return switch (auf) {
          1 => _w(
            g,
            ('Mutter', 'Vater', 'Elternteil'),
            ('Mother', 'Father', 'Parent'),
          ),
          2 => _w(
            g,
            ('Großmutter', 'Großvater', 'Großelternteil'),
            ('Grandmother', 'Grandfather', 'Grandparent'),
          ),
          3 => _w(
            g,
            ('Urgroßmutter', 'Urgroßvater', 'Urgroßelternteil'),
            ('Great-grandmother', 'Great-grandfather', 'Great-grandparent'),
          ),
          4 => _w(
            g,
            ('Ururgroßmutter', 'Ururgroßvater', 'Ururgroßelternteil'),
            (
              'Great-great-grandmother',
              'Great-great-grandfather',
              'Great-great-grandparent',
            ),
          ),
          _ =>
            _de
                ? 'Vorfahre der $auf. Generation'
                : 'Ancestor, $auf generations up',
        };
      case Gradart.nachkomme:
        if (grad.elternArt == Verwandtschaft.adoptivelternteil) {
          return _w(
            g,
            ('Adoptivtochter', 'Adoptivsohn', 'Adoptivkind'),
            ('Adopted daughter', 'Adopted son', 'Adopted child'),
          );
        }
        if (grad.elternArt == Verwandtschaft.pflegeelternteil) {
          return _w(
            g,
            ('Pflegetochter', 'Pflegesohn', 'Pflegekind'),
            ('Foster daughter', 'Foster son', 'Foster child'),
          );
        }
        return switch (ab) {
          1 => _w(g, ('Tochter', 'Sohn', 'Kind'), ('Daughter', 'Son', 'Child')),
          2 => _w(
            g,
            ('Enkelin', 'Enkel', 'Enkelkind'),
            ('Granddaughter', 'Grandson', 'Grandchild'),
          ),
          3 => _w(
            g,
            ('Urenkelin', 'Urenkel', 'Urenkelkind'),
            ('Great-granddaughter', 'Great-grandson', 'Great-grandchild'),
          ),
          4 => _w(
            g,
            ('Ururenkelin', 'Ururenkel', 'Ururenkelkind'),
            (
              'Great-great-granddaughter',
              'Great-great-grandson',
              'Great-great-grandchild',
            ),
          ),
          _ =>
            _de
                ? 'Nachkomme der $ab. Generation'
                : 'Descendant, $ab generations down',
        };
      case Gradart.geschwister:
        return grad.halb
            ? _w(
                g,
                ('Halbschwester', 'Halbbruder', 'Halbgeschwister'),
                ('Half-sister', 'Half-brother', 'Half-sibling'),
              )
            : _w(
                g,
                ('Schwester', 'Bruder', 'Geschwister'),
                ('Sister', 'Brother', 'Sibling'),
              );
      case Gradart.geschwisterkind:
        return switch (ab) {
          2 => _w(
            g,
            ('Nichte', 'Neffe', 'Geschwisterkind'),
            ('Niece', 'Nephew', 'Sibling’s child'),
          ),
          3 => _w(
            g,
            ('Großnichte', 'Großneffe', 'Großgeschwisterkind'),
            ('Great-niece', 'Great-nephew', 'Sibling’s grandchild'),
          ),
          _ =>
            _de
                ? 'Nachkomme eines Geschwisters, $ab Stufen entfernt'
                : 'Descendant of a sibling, $ab steps down',
        };
      case Gradart.vorfahrengeschwister:
        return switch (auf) {
          2 => _w(
            g,
            ('Tante', 'Onkel', 'Elterngeschwister'),
            ('Aunt', 'Uncle', 'Parent’s sibling'),
          ),
          3 => _w(
            g,
            ('Großtante', 'Großonkel', 'Großelterngeschwister'),
            ('Great-aunt', 'Great-uncle', 'Grandparent’s sibling'),
          ),
          _ =>
            _de
                ? 'Geschwister eines Vorfahren der $auf. Generation'
                : 'Sibling of an ancestor, $auf generations up',
        };
      case Gradart.cousin:
        final n = grad.cousinGrad;
        final grund = _de
            ? '${_w(g, ('Cousine', 'Cousin', 'Cousin/Cousine'), ('', '', ''))} $n. Grades'
            : '${n == 1
                  ? 'First'
                  : n == 2
                  ? 'Second'
                  : 'Degree-$n'} cousin';
        final entfernung = (auf - ab).abs();
        if (entfernung == 0) return grund;
        return _de
            ? '$grund, $entfernung-fach entfernt'
            : '$grund, $entfernung times removed';
      case Gradart.partner:
        return _w(
          g,
          ('Partnerin', 'Partner', 'Partner'),
          ('Partner', 'Partner', 'Partner'),
        );
      case Gradart.schwager:
        return _w(
          g,
          ('Schwägerin', 'Schwager', 'Schwager/Schwägerin'),
          ('Sister-in-law', 'Brother-in-law', 'Sibling-in-law'),
        );
      case Gradart.schwiegerelternteil:
        return _w(
          g,
          ('Schwiegermutter', 'Schwiegervater', 'Schwiegerelternteil'),
          ('Mother-in-law', 'Father-in-law', 'Parent-in-law'),
        );
      case Gradart.schwiegerkind:
        return _w(
          g,
          ('Schwiegertochter', 'Schwiegersohn', 'Schwiegerkind'),
          ('Daughter-in-law', 'Son-in-law', 'Child-in-law'),
        );
      case Gradart.stiefelternteil:
        return _w(
          g,
          ('Stiefmutter', 'Stiefvater', 'Stiefelternteil'),
          ('Stepmother', 'Stepfather', 'Stepparent'),
        );
      case Gradart.stiefkind:
        return _w(
          g,
          ('Stieftochter', 'Stiefsohn', 'Stiefkind'),
          ('Stepdaughter', 'Stepson', 'Stepchild'),
        );
      case Gradart.stiefgeschwister:
        return _w(
          g,
          ('Stiefschwester', 'Stiefbruder', 'Stiefgeschwister'),
          ('Stepsister', 'Stepbrother', 'Stepsibling'),
        );
      case Gradart.angeheiratet:
        return _de ? 'angeheiratet' : 'related by marriage';
      case Gradart.keine:
        return _de ? 'nicht verwandt' : 'not related';
    }
  }

  /// „Schwager von Tante Erika“ – für Angeheiratete der Weg über die
  /// Person, durch die sie zur Familie gehören.
  String ueberWeg(String schritt, String bezug, String name) =>
      _de ? '$schritt von $bezug $name' : '$schritt of $bezug $name';

  /// Der Titel über dem Lebensbaum.
  String titel(String? nachname, {required bool kurz}) => nachname == null
      ? (_de ? 'Stammbaum' : 'Family tree')
      : kurz
      ? (_de ? 'Familie $nachname' : 'The $nachname family')
      : (_de ? 'Stammbaum der Familie $nachname' : 'The $nachname family tree');

  /// Die Zeile darunter.
  String untertitel(Lebensbaumrichtung richtung, String name) =>
      switch (richtung) {
        Lebensbaumrichtung.vorfahren || Lebensbaumrichtung.paar =>
          _de ? 'Die Vorfahren von $name' : 'The ancestors of $name',
        Lebensbaumrichtung.nachkommen =>
          _de ? 'Die Nachkommen von $name' : 'The descendants of $name',
        Lebensbaumrichtung.familie =>
          _de ? 'Die Familie von $name' : 'The family of $name',
      };
}
