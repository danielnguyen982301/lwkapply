/// Mirrors backend/app/models/document.py::DocumentType. Order matches
/// DOCUMENT_TYPES in webapp/src/types/document.ts.
enum DocumentType {
  resume,
  coverLetter,
  other;

  /// Mirrors ApplicationStatus.apiValue/InterviewType.apiValue's
  /// reasoning — Dart enum names are camelCase, the API speaks
  /// snake_case.
  String get apiValue => switch (this) {
        DocumentType.resume => 'resume',
        DocumentType.coverLetter => 'cover_letter',
        DocumentType.other => 'other',
      };

  /// Mirrors DOCUMENT_TYPE_LABELS in webapp/src/lib/document-ui.ts.
  String get label => switch (this) {
        DocumentType.resume => 'Resume',
        DocumentType.coverLetter => 'Cover Letter',
        DocumentType.other => 'Other',
      };

  static DocumentType fromApiValue(String value) {
    return DocumentType.values.firstWhere(
      (type) => type.apiValue == value,
      orElse: () => throw FormatException('Unknown document type: $value'),
    );
  }
}

/// Mirrors DocumentRead (backend/app/schemas/document.py) and
/// webapp/src/types/document.ts::Document. Deliberately no `fileUrl` —
/// the API never returns the permanent R2 object key; call
/// DocumentsApi.download to mint a short-lived presigned URL instead.
class Document {
  const Document({
    required this.id,
    required this.applicationId,
    required this.fileName,
    required this.fileType,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String applicationId;
  final String fileName;
  final DocumentType fileType;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Document.fromJson(Map<String, dynamic> json) {
    return Document(
      id: json['id'] as String,
      applicationId: json['application_id'] as String,
      fileName: json['file_name'] as String,
      fileType: DocumentType.fromApiValue(json['file_type'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Mirrors DocumentListResponse. Paginated, like Interviews (unlike
/// Contacts' nested list).
class DocumentListResponse {
  const DocumentListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<Document> items;
  final int total;
  final int page;
  final int pageSize;

  factory DocumentListResponse.fromJson(Map<String, dynamic> json) {
    return DocumentListResponse(
      items: (json['items'] as List<dynamic>)
          .map((item) => Document.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}

/// Mirrors DocumentDownloadResponse (GET .../download).
class DocumentDownloadResponse {
  const DocumentDownloadResponse({
    required this.downloadUrl,
    required this.expiresInSeconds,
  });

  final String downloadUrl;
  final int expiresInSeconds;

  factory DocumentDownloadResponse.fromJson(Map<String, dynamic> json) {
    return DocumentDownloadResponse(
      downloadUrl: json['download_url'] as String,
      expiresInSeconds: json['expires_in_seconds'] as int,
    );
  }
}
