import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/ats_score_result.dart';
import 'ai_job_status_style.dart';

/// Mirrors webapp/src/components/ai/AtsScoreDisplay.vue field-for-field
/// — same plain-widget-not-`Card` convention as `ParsedResumeCard`.
class AtsScoreResultCard extends StatelessWidget {
  const AtsScoreResultCard({
    super.key,
    required this.score,
    required this.jobDescription,
    required this.jobDescriptionSource,
    this.jobUrl,
  });

  final AtsScoreResult score;

  /// The actual job description text used (pasted or scraped from
  /// job_url) — always populated once a score is completed, regardless
  /// of source. Mirrors AtsScoreDisplay.vue's `jobDescription` prop.
  final String? jobDescription;

  /// "pasted" | "url" | null.
  final String? jobDescriptionSource;

  /// The pasted URL when `jobDescriptionSource == "url"` — null for a
  /// pasted score, since `AtsScore` has no application link any more to
  /// identify the job by any other means. The one remaining way to show
  /// "which job" for a URL-sourced score. Mirrors
  /// AtsScoreDisplay.vue's `jobUrl` prop.
  final String? jobUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            RichText(
              text: TextSpan(
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: atsScoreColor(context, score.score),
                ),
                children: [
                  TextSpan(text: '${score.score}'),
                  TextSpan(
                    text: '/100',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            if (jobDescriptionSource != null)
              Chip(
                label: Text(
                  jobDescriptionSource == 'url'
                      ? 'Sourced from job URL'
                      : 'Pasted job description',
                ),
                visualDensity: VisualDensity.compact,
              ),
            if (jobUrl != null && jobUrl!.isNotEmpty)
              InkWell(
                onTap: () => launchUrl(
                  Uri.parse(jobUrl!),
                  mode: LaunchMode.externalApplication,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View job posting',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(score.summary, style: theme.textTheme.bodyMedium),
        if (score.matchedKeywords.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Matched keywords', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in score.matchedKeywords)
                Chip(
                  label: Text(keyword),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.green.shade50,
                  labelStyle: TextStyle(color: Colors.green.shade800),
                ),
            ],
          ),
        ],
        if (score.missingKeywords.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Missing keywords', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final keyword in score.missingKeywords)
                Chip(
                  label: Text(keyword),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: theme.colorScheme.errorContainer,
                  labelStyle:
                      TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
            ],
          ),
        ],
        if (score.suggestions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Suggestions', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final suggestion in score.suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(
                    child: Text(suggestion, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
        if (jobDescription != null && jobDescription!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Job description used', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: Text(jobDescription!, style: theme.textTheme.bodySmall),
            ),
          ),
        ],
      ],
    );
  }
}
