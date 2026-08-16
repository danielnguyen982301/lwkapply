import 'package:flutter/material.dart';

import '../domain/parsed_resume.dart';

/// Mirrors webapp/src/components/ai/ParsedResumeDisplay.vue field-for-
/// field. A plain widget (not a `Card`, despite the name — matches this
/// codebase's naming precedent, e.g. `AtsScoreResultCard`), meant to be
/// embedded directly in ResumeAnalysisDetailScreen's scroll body rather
/// than wrapped in its own `Card` chrome, since that screen already
/// gives it page-level framing.
class ParsedResumeCard extends StatelessWidget {
  const ParsedResumeCard({super.key, required this.parsed});

  final ParsedResume parsed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (parsed.fullName != null)
          Text(
            parsed.fullName!,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        if (parsed.email != null || parsed.phone != null) ...[
          const SizedBox(height: 2),
          Text(
            [
              if (parsed.email != null) parsed.email!,
              if (parsed.phone != null) parsed.phone!,
            ].join(' · '),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        if (parsed.summary != null) ...[
          const SizedBox(height: 12),
          Text(parsed.summary!, style: theme.textTheme.bodyMedium),
        ],
        if (parsed.totalYearsExperience != null) ...[
          const SizedBox(height: 8),
          Text(
            '${parsed.totalYearsExperience} years of experience',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (parsed.skills.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Skills', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final skill in parsed.skills)
                Chip(
                  label: Text(skill),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
        if (parsed.workExperience.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Work Experience', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final job in parsed.workExperience)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${job.title} · ${job.company}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (job.startDate != null || job.endDate != null)
                    Text(
                      '${job.startDate ?? '?'} – ${job.endDate ?? 'Present'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (job.description != null) ...[
                    const SizedBox(height: 4),
                    Text(job.description!, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
        ],
        if (parsed.education.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Education', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final school in parsed.education)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    school.institution,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (school.degree != null || school.fieldOfStudy != null)
                    Text(
                      [
                        if (school.degree != null) school.degree!,
                        if (school.fieldOfStudy != null) school.fieldOfStudy!,
                      ].join(', '),
                      style: theme.textTheme.bodySmall,
                    ),
                  if (school.graduationDate != null)
                    Text(
                      school.graduationDate!,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
