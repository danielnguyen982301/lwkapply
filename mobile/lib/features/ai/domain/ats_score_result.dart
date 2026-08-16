/// Mirrors backend/app/schemas/ai.py::AtsScoreResult /
/// webapp/src/types/ai.ts::AtsScoreResult. Populates AtsScore.feedback
/// once status is completed.
class AtsScoreResult {
  const AtsScoreResult({
    required this.score,
    required this.summary,
    required this.matchedKeywords,
    required this.missingKeywords,
    required this.suggestions,
  });

  final int score;
  final String summary;
  final List<String> matchedKeywords;
  final List<String> missingKeywords;
  final List<String> suggestions;

  factory AtsScoreResult.fromJson(Map<String, dynamic> json) {
    return AtsScoreResult(
      score: json['score'] as int,
      summary: json['summary'] as String,
      matchedKeywords:
          (json['matched_keywords'] as List<dynamic>).cast<String>(),
      missingKeywords:
          (json['missing_keywords'] as List<dynamic>).cast<String>(),
      suggestions: (json['suggestions'] as List<dynamic>).cast<String>(),
    );
  }
}
