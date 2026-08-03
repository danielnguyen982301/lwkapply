/// Request payload for POST/PATCH .../contacts, mirroring
/// ContactCreate/ContactUpdate (backend/app/schemas/contact.py).
///
/// Unlike ApplicationDraft, the backend's update schema is genuinely
/// used with `exclude_unset=True` server-side (see
/// update_contact in contacts.py) — but same as the Applications form,
/// the mobile dialog always has every field in hand (prefilled when
/// editing), so sending the full object on both create and update is
/// simplest and matches ApplicationDraft's precedent. Only `name` is
/// required; the rest send `null` explicitly to clear a value, which
/// `exclude_unset=True` still honors since the key IS present in the
/// request body.
class ContactDraft {
  const ContactDraft({
    required this.name,
    required this.title,
    required this.email,
    required this.linkedinUrl,
  });

  final String name;
  final String? title;
  final String? email;
  final String? linkedinUrl;

  Map<String, dynamic> toJson() => {
        'name': name,
        'title': title,
        'email': email,
        'linkedin_url': linkedinUrl,
      };
}
