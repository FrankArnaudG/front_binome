import 'package:flutter/material.dart';

/// Les 6 designs mariage déjà maquettés (voir demande utilisateur) — clé
/// envoyée telle quelle au backend (`EventPage.design`), couleur utilisée
/// pour la carte de sélection dans l'éditeur.
class EventPageDesign {
  final String key;
  final String label;
  final Color color;
  final Color textColor;
  final Color? borderColor;

  const EventPageDesign({
    required this.key,
    required this.label,
    required this.color,
    this.textColor = Colors.white,
    this.borderColor,
  });
}

const List<EventPageDesign> kEventPageDesigns = [
  EventPageDesign(key: 'botanique', label: 'Botanique (sauge & or)', color: Color(0xFF7C8B6F)),
  EventPageDesign(key: 'romantique', label: 'Romantique (terracotta)', color: Color(0xFFB5654A)),
  EventPageDesign(key: 'elegance', label: 'Élégance noire (or sur noir)', color: Color(0xFF17140F)),
  EventPageDesign(key: 'traditionnel', label: 'Traditionnel (couleurs vives)', color: Color(0xFFD4A72C), textColor: Color(0xFF123524)),
  // Fond blanc : invisible sur un panneau blanc sans bordure (voir
  // demande utilisateur, bouton "Minimaliste" qui ne se voyait pas).
  EventPageDesign(key: 'minimaliste', label: 'Minimaliste moderne', color: Color(0xFFFFFFFF), textColor: Color(0xFF1A1A17), borderColor: Color(0xFFD5D5CF)),
  EventPageDesign(key: 'enveloppe', label: 'Enveloppe', color: Color(0xFFB08D57)),
];

class EventPageSection {
  final String key;
  final String label;
  const EventPageSection(this.key, this.label);
}

const List<EventPageSection> kEventPageSections = [
  EventPageSection('histoire', 'Notre histoire'),
  EventPageSection('programme', 'Programme'),
  EventPageSection('lieu', 'Lieu'),
  EventPageSection('dress_code', 'Dress code'),
  EventPageSection('merci', 'Merci'),
  EventPageSection('rsvp', 'RSVP'),
];

/// Contenu d'exemple par thème — voir demande utilisateur : "pour chaque
/// theme creer des example". Pré-remplit le formulaire d'une NOUVELLE page
/// au choix du design (voir EventPageEditorScreen), pour montrer tout de
/// suite à quoi ressemble la page plutôt qu'un formulaire vide. Effacé dès
/// que l'utilisateur tape son propre contenu.
class EventPageExample {
  final String coupleNames;
  final String venueName;
  final String venueCity;
  final String venueAddress;
  final String notreHistoire;
  final String dressCodeText;
  final String merciMessage;
  final List<Map<String, String>> programme;

  const EventPageExample({
    required this.coupleNames,
    required this.venueName,
    required this.venueCity,
    required this.venueAddress,
    required this.notreHistoire,
    required this.dressCodeText,
    required this.merciMessage,
    required this.programme,
  });
}

const Map<String, EventPageExample> kEventPageExamples = {
  'botanique': EventPageExample(
    coupleNames: 'Aïcha & Karim',
    venueName: 'Jardin des Cascades',
    venueCity: 'Abidjan',
    venueAddress: 'Cocody, Riviera Golf',
    notreHistoire:
        'Nous nous sommes rencontrés un dimanche de pluie, sous le même abri de fortune. Depuis, plus rien ne nous a séparés.',
    dressCodeText: 'Tenue élégante — tons sauge, ivoire et touches dorées bienvenus.',
    merciMessage: 'Votre présence à nos côtés en ce jour si spécial est le plus beau des cadeaux.',
    programme: [
      {'time': '10h00', 'title': 'Cérémonie traditionnelle'},
      {'time': '14h30', 'title': 'Mairie'},
      {'time': '17h00', 'title': 'Réception'},
    ],
  ),
  'romantique': EventPageExample(
    coupleNames: 'Léa & Thomas',
    venueName: 'Villa Les Hibiscus',
    venueCity: 'Grand-Bassam',
    venueAddress: 'Boulevard de la Plage',
    notreHistoire: 'Une rencontre improbable, un coup de foudre certain. Aujourd\'hui nous disons oui, pour la vie.',
    dressCodeText: 'Tenue de soirée — camaïeu de terracotta et corail apprécié.',
    merciMessage: 'Merci d\'illuminer cette journée avec nous, simplement par votre présence.',
    programme: [
      {'time': '11h00', 'title': 'Cérémonie religieuse'},
      {'time': '15h00', 'title': 'Séance photo'},
      {'time': '19h00', 'title': 'Dîner & bal'},
    ],
  ),
  'elegance': EventPageExample(
    coupleNames: 'Sarah & Olivier',
    venueName: 'Le Grand Salon',
    venueCity: 'Dakar',
    venueAddress: 'Almadies, en bord de mer',
    notreHistoire: 'Deux parcours, une seule destination. Nous sommes heureux de vous compter parmi nos témoins.',
    dressCodeText: 'Tenue de soirée stricte — noir et or de rigueur.',
    merciMessage: 'Avec toute notre gratitude pour votre présence à nos côtés.',
    programme: [
      {'time': '18h00', 'title': 'Cocktail de bienvenue'},
      {'time': '19h30', 'title': 'Cérémonie'},
      {'time': '21h00', 'title': 'Dîner de gala'},
    ],
  ),
  'traditionnel': EventPageExample(
    coupleNames: 'Awa & Ismaël',
    venueName: 'Salle des Fêtes Baobab',
    venueCity: 'Ouagadougou',
    venueAddress: 'Quartier Ouaga 2000',
    notreHistoire: 'Nos familles se connaissaient déjà — nous, il nous restait juste à nous trouver.',
    dressCodeText: 'Couleurs vives et tissus traditionnels à l\'honneur — pagnes bienvenus.',
    merciMessage: 'Que la joie de ce jour rejaillisse sur chacun de vous, merci d\'être présents.',
    programme: [
      {'time': '09h00', 'title': 'Dot & cérémonie coutumière'},
      {'time': '13h00', 'title': 'Mairie'},
      {'time': '16h00', 'title': 'Réception & fête'},
    ],
  ),
  'minimaliste': EventPageExample(
    coupleNames: 'Julie & Antoine',
    venueName: 'Loft Saint-Martin',
    venueCity: 'Lyon',
    venueAddress: '12 rue des Tisserands',
    notreHistoire: 'Simple, évident, sans détour. Comme nous.',
    dressCodeText: 'Tenue élégante et sobre — blanc, noir et beige.',
    merciMessage: 'Merci de partager ce moment avec nous.',
    programme: [
      {'time': '15h00', 'title': 'Cérémonie'},
      {'time': '17h00', 'title': 'Vin d\'honneur'},
      {'time': '20h00', 'title': 'Dîner'},
    ],
  ),
  'enveloppe': EventPageExample(
    coupleNames: 'Fatou & Moussa',
    venueName: 'Résidence Le Palmier',
    venueCity: 'Bamako',
    venueAddress: 'Hippodrome, Rue 234',
    notreHistoire: 'Une lettre jamais envoyée, un message jamais oublié — et puis, enfin, une réponse.',
    dressCodeText: 'Tenue chic — tons beiges et or appréciés.',
    merciMessage: 'Merci pour votre présence, le plus précieux des cadeaux.',
    programme: [
      {'time': '10h30', 'title': 'Cérémonie religieuse'},
      {'time': '15h00', 'title': 'Mairie'},
      {'time': '18h00', 'title': 'Réception'},
    ],
  ),
};
