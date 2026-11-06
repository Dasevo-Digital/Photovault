part of 'database.dart';

/// [spalte] ist eine der [kennungen] – als ein einziger Wert, wie viele es
/// auch sind. Für Mengen, die SQLite einzeln nicht nähme (siehe [inStuecken])
/// und die sich auch nicht portionieren lassen, weil die Abfrage drumherum
/// sortiert oder zählt.
Expression<bool> kennungIn(
  Expression<String> spalte,
  Iterable<String> kennungen,
) => _InJson(spalte, jsonEncode(kennungen.toList()));

class _InJson extends Expression<bool> {
  const _InJson(this.spalte, this.werte);

  final Expression<String> spalte;
  final String werte;

  @override
  Precedence get precedence => Precedence.comparisonEq;

  @override
  void writeInto(GenerationContext context) {
    writeInner(context, spalte);
    context.buffer.write(' IN (SELECT value FROM json_each(');
    Variable<String>(werte).writeInto(context);
    context.buffer.write('))');
  }
}
