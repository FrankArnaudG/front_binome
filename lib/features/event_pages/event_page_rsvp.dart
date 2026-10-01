class EventPageRsvp {
  final String id;
  final String guestName;
  final bool? attending;
  final String? message;
  final DateTime? createdAt;

  const EventPageRsvp({
    required this.id,
    required this.guestName,
    this.attending,
    this.message,
    this.createdAt,
  });

  factory EventPageRsvp.fromJson(Map<String, dynamic> json) {
    return EventPageRsvp(
      id: json['id'] as String,
      guestName: json['guest_name'] as String,
      attending: json['attending'] as bool?,
      message: json['message'] as String?,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
    );
  }
}
