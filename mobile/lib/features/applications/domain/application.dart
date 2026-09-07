/// Mirrors backend/app/models/application.py::ApplicationStatus.
///
/// Order matches APPLICATION_STATUSES in webapp/src/types/application.ts —
/// used for filter-list order and, later, any Kanban-style grouping.
enum ApplicationStatus {
  saved,
  applied,
  phoneScreen,
  interviewing,
  offer,
  accepted,
  rejected,
  withdrawn;

  /// The exact string the backend sends/expects. Not `name`, since Dart
  /// enum member names are camelCase (`phoneScreen`) but the API speaks
  /// snake_case (`phone_screen`).
  String get apiValue => switch (this) {
        ApplicationStatus.saved => 'saved',
        ApplicationStatus.applied => 'applied',
        ApplicationStatus.phoneScreen => 'phone_screen',
        ApplicationStatus.interviewing => 'interviewing',
        ApplicationStatus.offer => 'offer',
        ApplicationStatus.accepted => 'accepted',
        ApplicationStatus.rejected => 'rejected',
        ApplicationStatus.withdrawn => 'withdrawn',
      };

  /// Mirrors APPLICATION_STATUS_LABELS in webapp/src/types/application.ts.
  String get label => switch (this) {
        ApplicationStatus.saved => 'Saved',
        ApplicationStatus.applied => 'Applied',
        ApplicationStatus.phoneScreen => 'Phone Screen',
        ApplicationStatus.interviewing => 'Interviewing',
        ApplicationStatus.offer => 'Offer',
        ApplicationStatus.accepted => 'Accepted',
        ApplicationStatus.rejected => 'Rejected',
        ApplicationStatus.withdrawn => 'Withdrawn',
      };

  static ApplicationStatus fromApiValue(String value) {
    return ApplicationStatus.values.firstWhere(
      (status) => status.apiValue == value,
      orElse: () => throw FormatException('Unknown application status: $value'),
    );
  }
}

/// Mirrors backend/app/models/application.py::SalaryCurrency and
/// webapp/src/types/application.ts::SalaryCurrency — a curated set of
/// major job-market currencies, not the full ISO 4217 list. Extend here
/// (and in the backend enum + migration, and the webapp mirror) if a
/// currency outside this set shows up on a job.
enum SalaryCurrency {
  usd,
  eur,
  gbp,
  cad,
  aud,
  nzd,
  chf,
  sek,
  nok,
  dkk,
  isk,
  pln,
  czk,
  huf,
  ron,
  uah,
  rub,
  // `try` is a reserved Dart keyword, so the ISO code TRY can't be the
  // member name directly.
  tryLira,
  ils,
  aed,
  sar,
  egp,
  ngn,
  kes,
  zar,
  inr,
  pkr,
  bdt,
  cny,
  jpy,
  krw,
  twd,
  hkd,
  sgd,
  myr,
  thb,
  vnd,
  idr,
  php,
  brl,
  mxn,
  ars,
  clp,
  cop;

  /// The exact string the backend sends/expects.
  String get apiValue => switch (this) {
        SalaryCurrency.usd => 'USD',
        SalaryCurrency.eur => 'EUR',
        SalaryCurrency.gbp => 'GBP',
        SalaryCurrency.cad => 'CAD',
        SalaryCurrency.aud => 'AUD',
        SalaryCurrency.nzd => 'NZD',
        SalaryCurrency.chf => 'CHF',
        SalaryCurrency.sek => 'SEK',
        SalaryCurrency.nok => 'NOK',
        SalaryCurrency.dkk => 'DKK',
        SalaryCurrency.isk => 'ISK',
        SalaryCurrency.pln => 'PLN',
        SalaryCurrency.czk => 'CZK',
        SalaryCurrency.huf => 'HUF',
        SalaryCurrency.ron => 'RON',
        SalaryCurrency.uah => 'UAH',
        SalaryCurrency.rub => 'RUB',
        SalaryCurrency.tryLira => 'TRY',
        SalaryCurrency.ils => 'ILS',
        SalaryCurrency.aed => 'AED',
        SalaryCurrency.sar => 'SAR',
        SalaryCurrency.egp => 'EGP',
        SalaryCurrency.ngn => 'NGN',
        SalaryCurrency.kes => 'KES',
        SalaryCurrency.zar => 'ZAR',
        SalaryCurrency.inr => 'INR',
        SalaryCurrency.pkr => 'PKR',
        SalaryCurrency.bdt => 'BDT',
        SalaryCurrency.cny => 'CNY',
        SalaryCurrency.jpy => 'JPY',
        SalaryCurrency.krw => 'KRW',
        SalaryCurrency.twd => 'TWD',
        SalaryCurrency.hkd => 'HKD',
        SalaryCurrency.sgd => 'SGD',
        SalaryCurrency.myr => 'MYR',
        SalaryCurrency.thb => 'THB',
        SalaryCurrency.vnd => 'VND',
        SalaryCurrency.idr => 'IDR',
        SalaryCurrency.php => 'PHP',
        SalaryCurrency.brl => 'BRL',
        SalaryCurrency.mxn => 'MXN',
        SalaryCurrency.ars => 'ARS',
        SalaryCurrency.clp => 'CLP',
        SalaryCurrency.cop => 'COP',
      };

  /// Mirrors SALARY_CURRENCY_LABELS in webapp/src/types/application.ts.
  String get label => switch (this) {
        SalaryCurrency.usd => 'US Dollar',
        SalaryCurrency.eur => 'Euro',
        SalaryCurrency.gbp => 'British Pound',
        SalaryCurrency.cad => 'Canadian Dollar',
        SalaryCurrency.aud => 'Australian Dollar',
        SalaryCurrency.nzd => 'New Zealand Dollar',
        SalaryCurrency.chf => 'Swiss Franc',
        SalaryCurrency.sek => 'Swedish Krona',
        SalaryCurrency.nok => 'Norwegian Krone',
        SalaryCurrency.dkk => 'Danish Krone',
        SalaryCurrency.isk => 'Icelandic Krona',
        SalaryCurrency.pln => 'Polish Zloty',
        SalaryCurrency.czk => 'Czech Koruna',
        SalaryCurrency.huf => 'Hungarian Forint',
        SalaryCurrency.ron => 'Romanian Leu',
        SalaryCurrency.uah => 'Ukrainian Hryvnia',
        SalaryCurrency.rub => 'Russian Ruble',
        SalaryCurrency.tryLira => 'Turkish Lira',
        SalaryCurrency.ils => 'Israeli Shekel',
        SalaryCurrency.aed => 'UAE Dirham',
        SalaryCurrency.sar => 'Saudi Riyal',
        SalaryCurrency.egp => 'Egyptian Pound',
        SalaryCurrency.ngn => 'Nigerian Naira',
        SalaryCurrency.kes => 'Kenyan Shilling',
        SalaryCurrency.zar => 'South African Rand',
        SalaryCurrency.inr => 'Indian Rupee',
        SalaryCurrency.pkr => 'Pakistani Rupee',
        SalaryCurrency.bdt => 'Bangladeshi Taka',
        SalaryCurrency.cny => 'Chinese Yuan',
        SalaryCurrency.jpy => 'Japanese Yen',
        SalaryCurrency.krw => 'South Korean Won',
        SalaryCurrency.twd => 'Taiwan Dollar',
        SalaryCurrency.hkd => 'Hong Kong Dollar',
        SalaryCurrency.sgd => 'Singapore Dollar',
        SalaryCurrency.myr => 'Malaysian Ringgit',
        SalaryCurrency.thb => 'Thai Baht',
        SalaryCurrency.vnd => 'Vietnamese Dong',
        SalaryCurrency.idr => 'Indonesian Rupiah',
        SalaryCurrency.php => 'Philippine Peso',
        SalaryCurrency.brl => 'Brazilian Real',
        SalaryCurrency.mxn => 'Mexican Peso',
        SalaryCurrency.ars => 'Argentine Peso',
        SalaryCurrency.clp => 'Chilean Peso',
        SalaryCurrency.cop => 'Colombian Peso',
      };

  /// Mirrors SALARY_CURRENCY_SYMBOLS in webapp/src/types/application.ts —
  /// not necessarily the symbol used in-country, but the one job seekers
  /// scanning a salary figure will recognize fastest.
  String get symbol => switch (this) {
        SalaryCurrency.usd => '\$',
        SalaryCurrency.eur => '€',
        SalaryCurrency.gbp => '£',
        SalaryCurrency.cad => 'C\$',
        SalaryCurrency.aud => 'A\$',
        SalaryCurrency.nzd => 'NZ\$',
        SalaryCurrency.chf => 'CHF',
        SalaryCurrency.sek => 'kr',
        SalaryCurrency.nok => 'kr',
        SalaryCurrency.dkk => 'kr',
        SalaryCurrency.isk => 'kr',
        SalaryCurrency.pln => 'zł',
        SalaryCurrency.czk => 'Kč',
        SalaryCurrency.huf => 'Ft',
        SalaryCurrency.ron => 'lei',
        SalaryCurrency.uah => '₴',
        SalaryCurrency.rub => '₽',
        SalaryCurrency.tryLira => '₺',
        SalaryCurrency.ils => '₪',
        SalaryCurrency.aed => 'AED',
        SalaryCurrency.sar => 'SAR',
        SalaryCurrency.egp => 'E£',
        SalaryCurrency.ngn => '₦',
        SalaryCurrency.kes => 'KSh',
        SalaryCurrency.zar => 'R',
        SalaryCurrency.inr => '₹',
        SalaryCurrency.pkr => '₨',
        SalaryCurrency.bdt => '৳',
        SalaryCurrency.cny => 'CN¥',
        SalaryCurrency.jpy => '¥',
        SalaryCurrency.krw => '₩',
        SalaryCurrency.twd => 'NT\$',
        SalaryCurrency.hkd => 'HK\$',
        SalaryCurrency.sgd => 'S\$',
        SalaryCurrency.myr => 'RM',
        SalaryCurrency.thb => '฿',
        SalaryCurrency.vnd => '₫',
        SalaryCurrency.idr => 'Rp',
        SalaryCurrency.php => '₱',
        SalaryCurrency.brl => 'R\$',
        SalaryCurrency.mxn => 'MX\$',
        SalaryCurrency.ars => 'AR\$',
        SalaryCurrency.clp => 'CL\$',
        SalaryCurrency.cop => 'CO\$',
      };

  static SalaryCurrency fromApiValue(String value) {
    return SalaryCurrency.values.firstWhere(
      (currency) => currency.apiValue == value,
      orElse: () => throw FormatException('Unknown salary currency: $value'),
    );
  }
}

/// Mirrors ApplicationRead (backend/app/schemas/application.py) and
/// webapp/src/types/application.ts::Application.
class Application {
  const Application({
    required this.id,
    required this.userId,
    required this.company,
    required this.position,
    required this.applicationName,
    required this.location,
    required this.status,
    required this.salaryMin,
    required this.salaryMax,
    required this.salaryCurrency,
    required this.appliedDate,
    required this.jobUrl,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String company;
  final String position;

  /// Optional, user-chosen label distinguishing applications that share
  /// the same company/position (e.g. a re-apply after rejection) —
  /// mirrors backend/app/models/application.py's application_name.
  final String? applicationName;
  final String? location;
  final ApplicationStatus status;
  final int? salaryMin;
  final int? salaryMax;
  final SalaryCurrency salaryCurrency;

  /// Backend sends a plain `date` (e.g. "2026-07-16"), not a `datetime` —
  /// parsed here but should only ever be used for its date components.
  final DateTime? appliedDate;
  final String? jobUrl;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory Application.fromJson(Map<String, dynamic> json) {
    return Application(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      company: json['company'] as String,
      position: json['position'] as String,
      applicationName: json['application_name'] as String?,
      location: json['location'] as String?,
      status: ApplicationStatus.fromApiValue(json['status'] as String),
      salaryMin: json['salary_min'] as int?,
      salaryMax: json['salary_max'] as int?,
      salaryCurrency:
          SalaryCurrency.fromApiValue(json['salary_currency'] as String),
      appliedDate: json['applied_date'] == null
          ? null
          : DateTime.parse(json['applied_date'] as String),
      jobUrl: json['job_url'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// Mirrors ApplicationListResponse (backend/app/schemas/application.py).
class ApplicationListResponse {
  const ApplicationListResponse({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<Application> items;
  final int total;
  final int page;
  final int pageSize;

  factory ApplicationListResponse.fromJson(Map<String, dynamic> json) {
    return ApplicationListResponse(
      items: (json['items'] as List<dynamic>)
          .map((item) => Application.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      pageSize: json['page_size'] as int,
    );
  }
}
