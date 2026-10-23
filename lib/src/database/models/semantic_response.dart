/// One filter of a semantic query: `column op value`. [op] is one of `eq`,
/// `neq`, `gt`, `gte`, `lt`, `lte`, `like`, `ilike`, `in` (a list) or `is`
/// (`null`, `true` or `false`).
class SemanticFilter {
  final String column;
  final String op;
  final Object? value;

  const SemanticFilter(this.column, this.op, [this.value]);

  static const ops = {'eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'like', 'ilike', 'in', 'is'};

  Map<String, dynamic> toJson() => {'column': column, 'op': op, 'value': value};
}

/// Result of a semantic query: rows nearest to the query by meaning.
class SemanticResponse {
  /// The table's rows (vector columns removed), each with `_similarity`
  /// (cosine, null for a keyword-only hit) and `_score` (sort key).
  final List<Map<String, dynamic>> rows;

  /// The embedding model used; null when the column has nothing embedded yet.
  final String? model;

  const SemanticResponse({required this.rows, this.model});

  factory SemanticResponse.fromJson(Map<String, dynamic> j) => SemanticResponse(
        rows: (j['rows'] is List ? j['rows'] as List : const [])
            .whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r))
            .toList(),
        model: j['model']?.toString(),
      );

  /// `_similarity` of [row], or null.
  static double? similarityOf(Map<String, dynamic> row) => (row['_similarity'] as num?)?.toDouble();

  /// `_score` of [row].
  static double scoreOf(Map<String, dynamic> row) => (row['_score'] as num?)?.toDouble() ?? 0;
}
