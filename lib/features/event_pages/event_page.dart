/// Reflète le modèle EventPage côté backend (voir
/// app/Models/EventPage.php) — page événement mariage, créée en brouillon,
/// publiée moyennant un tarif fixe.
class EventPage {
  final String id;
  final String userId;
  final String type;
  final String design;
  final String slug;
  final String? coverImageUrl;
  final String status;
  final bool sharedWithPartner;
  final String? coupleNames;
  final DateTime? eventDate;
  final String? venueName;
  final String? venueCity;
  final String? venueAddress;
  final List<Map<String, dynamic>> programme;
  final String? notreHistoire;
  final String? dressCodeText;
  final Map<String, dynamic> accentColors;
  final Map<String, bool> sectionsVisibility;
  final DateTime? rsvpDeadline;
  final String? merciMessage;
  final DateTime? publishedAt;

  const EventPage({
    required this.id,
    required this.userId,
    required this.type,
    required this.design,
    required this.slug,
    this.coverImageUrl,
    required this.status,
    required this.sharedWithPartner,
    this.coupleNames,
    this.eventDate,
    this.venueName,
    this.venueCity,
    this.venueAddress,
    this.programme = const [],
    this.notreHistoire,
    this.dressCodeText,
    this.accentColors = const {},
    this.sectionsVisibility = const {},
    this.rsvpDeadline,
    this.merciMessage,
    this.publishedAt,
  });

  bool get isPublished => status == 'published';
  String get publicUrl => 'https://binomecouple.com/e/$slug';

  factory EventPage.fromJson(Map<String, dynamic> json) {
    return EventPage(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String? ?? 'mariage',
      design: json['design'] as String,
      slug: json['slug'] as String,
      coverImageUrl: json['cover_image_url'] as String?,
      status: json['status'] as String? ?? 'draft',
      sharedWithPartner: json['shared_with_partner'] as bool? ?? false,
      coupleNames: json['couple_names'] as String?,
      eventDate: _parseDate(json['event_date']),
      venueName: json['venue_name'] as String?,
      venueCity: json['venue_city'] as String?,
      venueAddress: json['venue_address'] as String?,
      programme: (json['programme'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
      notreHistoire: json['notre_histoire'] as String?,
      dressCodeText: json['dress_code_text'] as String?,
      accentColors: json['accent_colors'] != null ? Map<String, dynamic>.from(json['accent_colors'] as Map) : const {},
      sectionsVisibility: json['sections_visibility'] != null
          ? Map<String, dynamic>.from(json['sections_visibility'] as Map).map((k, v) => MapEntry(k, v as bool))
          : const {},
      rsvpDeadline: _parseDate(json['rsvp_deadline']),
      merciMessage: json['merci_message'] as String?,
      publishedAt: _parseDate(json['published_at']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value as String);
  }
}
