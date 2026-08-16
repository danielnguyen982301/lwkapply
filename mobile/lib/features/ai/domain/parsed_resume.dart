/// Mirrors backend/app/schemas/ai.py::WorkExperienceItem /
/// webapp/src/types/ai.ts::WorkExperienceItem.
class WorkExperienceItem {
  const WorkExperienceItem({
    required this.company,
    required this.title,
    required this.startDate,
    required this.endDate,
    required this.description,
  });

  final String company;
  final String title;
  final String? startDate;

  /// "Present" (as literal text) if currently held.
  final String? endDate;
  final String? description;

  factory WorkExperienceItem.fromJson(Map<String, dynamic> json) {
    return WorkExperienceItem(
      company: json['company'] as String,
      title: json['title'] as String,
      startDate: json['start_date'] as String?,
      endDate: json['end_date'] as String?,
      description: json['description'] as String?,
    );
  }
}

/// Mirrors backend/app/schemas/ai.py::EducationItem.
class EducationItem {
  const EducationItem({
    required this.institution,
    required this.degree,
    required this.fieldOfStudy,
    required this.graduationDate,
  });

  final String institution;
  final String? degree;
  final String? fieldOfStudy;
  final String? graduationDate;

  factory EducationItem.fromJson(Map<String, dynamic> json) {
    return EducationItem(
      institution: json['institution'] as String,
      degree: json['degree'] as String?,
      fieldOfStudy: json['field_of_study'] as String?,
      graduationDate: json['graduation_date'] as String?,
    );
  }
}

/// Mirrors backend/app/schemas/ai.py::ParsedResume /
/// webapp/src/types/ai.ts::ParsedResume. Populates
/// ResumeAnalysis.parsedData once status is completed.
class ParsedResume {
  const ParsedResume({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.summary,
    required this.skills,
    required this.workExperience,
    required this.education,
    required this.totalYearsExperience,
  });

  final String? fullName;
  final String? email;
  final String? phone;
  final String? summary;
  final List<String> skills;
  final List<WorkExperienceItem> workExperience;
  final List<EducationItem> education;
  final double? totalYearsExperience;

  factory ParsedResume.fromJson(Map<String, dynamic> json) {
    return ParsedResume(
      fullName: json['full_name'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      summary: json['summary'] as String?,
      skills: (json['skills'] as List<dynamic>).cast<String>(),
      workExperience: (json['work_experience'] as List<dynamic>)
          .map(
            (item) => WorkExperienceItem.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      education: (json['education'] as List<dynamic>)
          .map((item) => EducationItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalYearsExperience:
          (json['total_years_experience'] as num?)?.toDouble(),
    );
  }
}
