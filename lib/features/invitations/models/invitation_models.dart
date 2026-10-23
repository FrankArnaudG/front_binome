/// Une catégorie de la bibliothèque de messages romantiques prédéfinis
/// (voir RomanticMessageController côté serveur) — pas liée à un modèle en
/// particulier, disponible pour toutes les collections.
class RomanticCategory {
  final String key;
  final String label;

  const RomanticCategory({required this.key, required this.label});

  factory RomanticCategory.fromJson(Map<String, dynamic> json) =>
      RomanticCategory(key: json['key'] as String, label: json['label'] as String);
}

class RomanticMessage {
  final int id;
  final String category;
  final String title;
  final String message;

  const RomanticMessage({required this.id, required this.category, required this.title, required this.message});

  factory RomanticMessage.fromJson(Map<String, dynamic> json) => RomanticMessage(
        id: json['id'] as int,
        category: json['category'] as String,
        title: json['title'] as String,
        message: json['message'] as String,
      );
}

/// Modèles du module "Invitations numériques" (voir cahier des charges) —
/// miroir des tables `invitation_templates`/`invitations`/
/// `invitation_ceremonies`/`invitation_media` côté binome_back. Les champs
/// `*Url` viennent d'accessors Eloquent déjà calculés côté serveur (jamais
/// reconstruits ici, voir InvitationCeremony::photoUrl etc.).
class InvitationTemplate {
  final String id;
  final String key;
  final String collectionKey;
  final String name;
  final String? description;
  final Map<String, dynamic> defaultTheme;
  final List<String> availableBlocks;
  final String? previewImageUrl;

  /// URLs résolues des ornements du thème (`ornament_frame`,
  /// `ornament_frame_alt`...) — voir InvitationTemplate::themeAssetUrls
  /// côté serveur. Source de la liste prédéfinie de couvertures (voir
  /// demande utilisateur : jamais un upload libre pour la couverture).
  final Map<String, String> themeAssetUrls;
  final bool isActive;
  final int sortOrder;

  const InvitationTemplate({
    required this.id,
    required this.key,
    required this.collectionKey,
    required this.name,
    this.description,
    required this.defaultTheme,
    required this.availableBlocks,
    this.previewImageUrl,
    required this.themeAssetUrls,
    required this.isActive,
    required this.sortOrder,
  });

  factory InvitationTemplate.fromJson(Map<String, dynamic> json) => InvitationTemplate(
        id: json['id'] as String,
        key: json['key'] as String,
        collectionKey: json['collection_key'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        defaultTheme: (json['default_theme'] as Map?)?.cast<String, dynamic>() ?? const {},
        availableBlocks: (json['available_blocks'] as List?)?.cast<String>() ?? const [],
        previewImageUrl: json['preview_image_url'] as String?,
        themeAssetUrls: (json['theme_asset_urls'] as Map?)?.cast<String, String>() ?? const {},
        isActive: json['is_active'] as bool? ?? true,
        sortOrder: json['sort_order'] as int? ?? 0,
      );
}

class InvitationCeremony {
  final String id;
  final String title;
  final String? description;
  final String? date;
  final String? time;
  final String timezone;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? photoUrl;
  final String? dressCode;
  final String? instructions;
  final String? icon;
  final int sortOrder;

  const InvitationCeremony({
    required this.id,
    required this.title,
    this.description,
    this.date,
    this.time,
    required this.timezone,
    this.address,
    this.latitude,
    this.longitude,
    this.photoUrl,
    this.dressCode,
    this.instructions,
    this.icon,
    required this.sortOrder,
  });

  factory InvitationCeremony.fromJson(Map<String, dynamic> json) => InvitationCeremony(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        date: json['date'] as String?,
        time: json['time'] as String?,
        timezone: json['timezone'] as String? ?? 'Africa/Ouagadougou',
        address: json['address'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        photoUrl: json['photo_url'] as String?,
        dressCode: json['dress_code'] as String?,
        instructions: json['instructions'] as String?,
        icon: json['icon'] as String?,
        sortOrder: json['sort_order'] as int? ?? 0,
      );
}

class InvitationMedia {
  final String id;
  final String blockKey;
  final String url;
  final String? caption;
  final int sortOrder;

  const InvitationMedia({
    required this.id,
    required this.blockKey,
    required this.url,
    this.caption,
    required this.sortOrder,
  });

  factory InvitationMedia.fromJson(Map<String, dynamic> json) => InvitationMedia(
        id: json['id'] as String,
        blockKey: json['block_key'] as String,
        url: json['url'] as String,
        caption: json['caption'] as String?,
        sortOrder: json['sort_order'] as int? ?? 0,
      );
}

class Invitation {
  final String id;
  final String? slug;
  final String status;
  final InvitationTemplate? template;
  final Map<String, dynamic> theme;
  final Map<String, dynamic> coverSettings;
  final String? partnerOneName;
  final String? partnerTwoName;
  final String? eventDate;
  final String? eventCity;
  final String? introText;
  final Map<String, dynamic> families;
  final Map<String, dynamic> story;
  final Map<String, dynamic> countdown;
  final Map<String, dynamic> dressCode;
  final Map<String, dynamic> gratitude;
  final Map<String, dynamic> rsvpSettings;
  final List<String> visibleBlocks;
  final List<InvitationCeremony> ceremonies;
  final List<InvitationMedia> media;

  const Invitation({
    required this.id,
    this.slug,
    required this.status,
    this.template,
    required this.theme,
    required this.coverSettings,
    this.partnerOneName,
    this.partnerTwoName,
    this.eventDate,
    this.eventCity,
    this.introText,
    required this.families,
    required this.story,
    required this.countdown,
    required this.dressCode,
    required this.gratitude,
    required this.rsvpSettings,
    required this.visibleBlocks,
    required this.ceremonies,
    required this.media,
  });

  bool get isPublished => status == 'published';
  bool get isDraft => status == 'draft';

  factory Invitation.fromJson(Map<String, dynamic> json) => Invitation(
        id: json['id'] as String,
        slug: json['slug'] as String?,
        status: json['status'] as String? ?? 'draft',
        template: json['template'] != null ? InvitationTemplate.fromJson((json['template'] as Map).cast<String, dynamic>()) : null,
        theme: (json['theme'] as Map?)?.cast<String, dynamic>() ?? const {},
        coverSettings: (json['cover_settings'] as Map?)?.cast<String, dynamic>() ?? const {},
        partnerOneName: json['partner_one_name'] as String?,
        partnerTwoName: json['partner_two_name'] as String?,
        eventDate: json['event_date'] as String?,
        eventCity: json['event_city'] as String?,
        introText: json['intro_text'] as String?,
        families: (json['families'] as Map?)?.cast<String, dynamic>() ?? const {},
        story: (json['story'] as Map?)?.cast<String, dynamic>() ?? const {},
        countdown: (json['countdown'] as Map?)?.cast<String, dynamic>() ?? const {},
        dressCode: (json['dress_code'] as Map?)?.cast<String, dynamic>() ?? const {},
        gratitude: (json['gratitude'] as Map?)?.cast<String, dynamic>() ?? const {},
        rsvpSettings: (json['rsvp_settings'] as Map?)?.cast<String, dynamic>() ?? const {},
        visibleBlocks: (json['visible_blocks'] as List?)?.cast<String>() ?? const [],
        ceremonies: (json['ceremonies'] as List?)
                ?.map((e) => InvitationCeremony.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
        media: (json['media'] as List?)?.map((e) => InvitationMedia.fromJson((e as Map).cast<String, dynamic>())).toList() ?? const [],
      );
}
