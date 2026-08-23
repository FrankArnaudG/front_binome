import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/app_router.dart';
import '../../l10n/locale_scope.dart';
import '../../models/app_user.dart';
import '../../models/box.dart';
import '../../theme/theme_scope.dart';
import '../../theme/themed_background.dart';
import '../../widgets/primary_button.dart';
import '../box/box_service.dart';
import 'auth_service.dart';

final List<String> _kCountries = [
  'Afghanistan', 'Afrique du Sud', 'Albanie', 'Algérie', 'Allemagne', 'Andorre',
  'Angola', 'Antigua-et-Barbuda', 'Arabie saoudite', 'Argentine', 'Arménie',
  'Australie', 'Autriche', 'Azerbaïdjan', 'Bahamas', 'Bahreïn', 'Bangladesh',
  'Barbade',
  'Belgique',
  'Belize',
  'Bénin',
  'Bhoutan',
  'Biélorussie',
  'Birmanie',
  'Bolivie', 'Bosnie-Herzégovine', 'Botswana', 'Brésil', 'Brunei', 'Bulgarie',
  'Burkina Faso', 'Burundi', 'Cambodge', 'Cameroun', 'Canada', 'Cap-Vert',
  'République centrafricaine',
  'Chili',
  'Chine',
  'Chypre',
  'Colombie',
  'Comores',
  'Congo', 'Congo (RDC)', 'Corée du Nord', 'Corée du Sud', 'Costa Rica',
  'Côte d\'Ivoire', 'Croatie', 'Cuba', 'Danemark', 'Djibouti', 'Dominique',
  'Égypte', 'Émirats arabes unis', 'Équateur', 'Érythrée', 'Espagne', 'Estonie',
  'Eswatini', 'États-Unis', 'Éthiopie', 'Fidji', 'Finlande', 'France', 'Gabon',
  'Gambie', 'Géorgie', 'Ghana', 'Grèce', 'Grenade', 'Guatemala', 'Guinée',
  'Guinée-Bissau',
  'Guinée équatoriale',
  'Guyana',
  'Haïti',
  'Honduras',
  'Hongrie',
  'Îles Marshall',
  'Îles Salomon',
  'Inde',
  'Indonésie',
  'Irak',
  'Iran',
  'Irlande',
  'Islande', 'Israël', 'Italie', 'Jamaïque', 'Japon', 'Jordanie', 'Kazakhstan',
  'Kenya', 'Kirghizistan', 'Kiribati', 'Koweït', 'Laos', 'Lesotho', 'Lettonie',
  'Liban', 'Libéria', 'Libye', 'Liechtenstein', 'Lituanie', 'Luxembourg',
  'Macédoine du Nord', 'Madagascar', 'Malaisie', 'Malawi', 'Maldives', 'Mali',
  'Malte',
  'Maroc',
  'Maurice',
  'Mauritanie',
  'Mexique',
  'Micronésie',
  'Moldavie',
  'Monaco', 'Mongolie', 'Monténégro', 'Mozambique', 'Namibie', 'Nauru', 'Népal',
  'Nicaragua', 'Niger', 'Nigéria', 'Norvège', 'Nouvelle-Zélande', 'Oman',
  'Ouganda', 'Ouzbékistan', 'Pakistan', 'Palaos', 'Palestine', 'Panama',
  'Papouasie-Nouvelle-Guinée', 'Paraguay', 'Pays-Bas', 'Pérou', 'Philippines',
  'Pologne',
  'Portugal',
  'Qatar',
  'République dominicaine',
  'République tchèque',
  'Roumanie', 'Royaume-Uni', 'Russie', 'Rwanda', 'Saint-Christophe-et-Niévès',
  'Saint-Marin', 'Saint-Vincent-et-les-Grenadines', 'Sainte-Lucie', 'Salvador',
  'Samoa', 'São Tomé-et-Principe', 'Sénégal', 'Serbie', 'Seychelles',
  'Sierra Leone', 'Singapour', 'Slovaquie', 'Slovénie', 'Somalie', 'Soudan',
  'Soudan du Sud', 'Sri Lanka', 'Suède', 'Suisse', 'Suriname', 'Syrie',
  'Tadjikistan', 'Tanzanie', 'Tchad', 'Thaïlande', 'Timor oriental', 'Togo',
  'Tonga', 'Trinité-et-Tobago', 'Tunisie', 'Turkménistan', 'Turquie', 'Tuvalu',
  'Ukraine', 'Uruguay', 'Vanuatu', 'Vatican', 'Venezuela', 'Vietnam', 'Yémen',
  'Zambie', 'Zimbabwe',
  // Tri insensible aux accents : un tri Unicode brut classerait "Éthiopie"
  // après "Zimbabwe" (É a un point de code supérieur à Z) au lieu de
  // l'ordre alphabétique attendu entre "Estonie" et "Fidji".
]..sort((a, b) => _normalizeForSearch(a).compareTo(_normalizeForSearch(b)));

// "Autre" reste épinglé en dernier plutôt que trié alphabétiquement (dans
// les A) — c'est une échappatoire, pas un vrai pays.
final List<String> _kCountriesWithFallback = [..._kCountries, 'Autre'];

/// Compare insensible aux accents/casse, pour que "cote d ivoire" trouve
/// "Côte d'Ivoire" en tapant sans accent (clavier standard).
String _normalizeForSearch(String value) {
  const accented = 'àâäáãåèéêëìíîïòóôöõùúûüçñÀÂÄÁÃÅÈÉÊËÌÍÎÏÒÓÔÖÕÙÚÛÜÇÑ';
  const plain = 'aaaaaaeeeeiiiioooooouuuucnAAAAAAEEEEIIIIOOOOOOUUUUCN';
  final buffer = StringBuffer();
  for (final char in value.toLowerCase().split('')) {
    final index = accented.indexOf(char);
    buffer.write(index == -1 ? char : plain[index].toLowerCase());
  }
  return buffer.toString();
}

/// Étape bloquante juste après authentification tant que
/// [AppUser.needsProfileCompletion] est vrai (voir AppRouter.routeAfterAuth)
/// — ni Google ni l'inscription classique ne collectent genre/pays, et un
/// compte Google peut arriver avec un nom d'affichage fantaisiste (voir
/// AuthenticationController::loginWithGoogle côté backend).
class ProfileCompletionScreen extends StatefulWidget {
  final AppUser user;

  const ProfileCompletionScreen({super.key, required this.user});

  @override
  State<ProfileCompletionScreen> createState() =>
      _ProfileCompletionScreenState();
}

enum _Gender { homme, femme, personnalise }

class _ProfileCompletionScreenState extends State<ProfileCompletionScreen> {
  // Vides volontairement : un compte Google peut arriver avec un nom
  // fantaisiste (voir AuthenticationController::loginWithGoogle côté
  // backend), pré-remplir inviterait à ne pas les corriger.
  final _prenomController = TextEditingController();
  final _nameController = TextEditingController();
  late final _customGenderController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  _Gender? _gender;
  String? _country;
  bool _saving = false;
  String? _error;
  // Affichés uniquement après une tentative de soumission (pas dès la
  // frappe) : le genre/pays n'ont pas de TextFormField natif à valider via
  // le Form, donc leur erreur est gérée à la main ici.
  bool _showGenderError = false;
  bool _showCountryError = false;

  @override
  void dispose() {
    _prenomController.dispose();
    _nameController.dispose();
    _customGenderController.dispose();
    super.dispose();
  }

  String? get _genderValue {
    switch (_gender) {
      case _Gender.homme:
        return 'Homme';
      case _Gender.femme:
        return 'Femme';
      case _Gender.personnalise:
        final custom = _customGenderController.text.trim();
        return custom.isEmpty ? null : custom;
      case null:
        return null;
    }
  }

  Future<void> _submit() async {
    if (_saving) return;

    final formValid = _formKey.currentState?.validate() ?? true;
    final genderValid = _genderValue != null;
    final countryValid = _country != null;

    setState(() {
      _showGenderError = !genderValid;
      _showCountryError = !countryValid;
    });

    if (!formValid || !genderValid || !countryValid) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await AuthService.instance.completeProfile(
        prenom: _prenomController.text.trim(),
        name: _nameController.text.trim(),
        gender: _genderValue!,
        country: _country!,
      );
      if (!mounted) return;

      final Box? box = await BoxService.instance.fetchCurrent();
      if (!mounted) return;
      AppRouter.routeAfterAuth(context, updated, box);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Une erreur est survenue, réessaie.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.paletteOf(context);
    final t = LocaleScope.of(context).t;

    return PopScope(
      // Étape obligatoire : impossible de revenir en arrière ou de fermer
      // tant qu'elle n'est pas complétée (même motif que
      // MilestoneReminderDialog).
      canPop: false,
      child: Scaffold(
        body: ThemedBackground(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('profile_completion_title'),
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: theme.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t('profile_completion_subtitle'),
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        color: theme.textOnBackgroundMuted,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _prenomController,
                      style: TextStyle(color: theme.textOnBackground),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? t('profile_completion_required')
                          : null,
                      decoration: InputDecoration(
                        labelText: t('profile_firstname'),
                        labelStyle: TextStyle(
                          color: theme.textOnBackgroundMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      style: TextStyle(color: theme.textOnBackground),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? t('profile_completion_required')
                          : null,
                      decoration: InputDecoration(
                        labelText: t('profile_lastname'),
                        labelStyle: TextStyle(
                          color: theme.textOnBackgroundMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      t('profile_gender_label'),
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.textOnBackgroundMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _GenderChip(
                          label: t('profile_gender_male'),
                          selected: _gender == _Gender.homme,
                          theme: theme,
                          onTap: () => setState(() {
                            _gender = _Gender.homme;
                            _showGenderError = false;
                          }),
                        ),
                        _GenderChip(
                          label: t('profile_gender_female'),
                          selected: _gender == _Gender.femme,
                          theme: theme,
                          onTap: () => setState(() {
                            _gender = _Gender.femme;
                            _showGenderError = false;
                          }),
                        ),
                        _GenderChip(
                          label: t('profile_gender_custom'),
                          selected: _gender == _Gender.personnalise,
                          theme: theme,
                          onTap: () => setState(() {
                            _gender = _Gender.personnalise;
                            _showGenderError = false;
                          }),
                        ),
                      ],
                    ),
                    if (_gender == _Gender.personnalise) ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: _customGenderController,
                        autofocus: true,
                        maxLength: 30,
                        style: TextStyle(color: theme.textOnBackground),
                        onChanged: (_) =>
                            setState(() => _showGenderError = false),
                        decoration: InputDecoration(
                          hintText: t('profile_gender_custom_hint'),
                          hintStyle: TextStyle(
                            color: theme.textOnBackgroundMuted,
                          ),
                          counterText: '',
                        ),
                      ),
                    ],
                    if (_showGenderError) ...[
                      const SizedBox(height: 6),
                      Text(
                        t('profile_completion_required'),
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      t('profile_country_label'),
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.textOnBackgroundMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _CountrySearchField(
                      theme: theme,
                      hint: t('profile_country_hint'),
                      initialValue: _country,
                      onSelected: (value) => setState(() {
                        _country = value;
                        if (value != null) _showCountryError = false;
                      }),
                    ),
                    if (_showCountryError) ...[
                      const SizedBox(height: 6),
                      Text(
                        t('profile_completion_required'),
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: PrimaryButton(
                        label: t('common_continue'),
                        loading: _saving,
                        onPressed: _submit,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Champ pays avec filtrage en tapant (voir [_kCountries], ~195 pays) — sans
/// ça, faire défiler une liste aussi longue à la main pour trouver son pays
/// est pénible. Tant que le champ est vide, [optionsBuilder] renvoie la
/// liste complète : on peut aussi bien taper que défiler.
class _CountrySearchField extends StatelessWidget {
  final dynamic theme;
  final String hint;
  final String? initialValue;
  final ValueChanged<String?> onSelected;

  const _CountrySearchField({
    required this.theme,
    required this.hint,
    required this.initialValue,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: initialValue ?? ''),
      optionsBuilder: (textEditingValue) {
        final query = _normalizeForSearch(textEditingValue.text.trim());
        if (query.isEmpty) return _kCountriesWithFallback;
        return _kCountriesWithFallback.where(
          (c) => _normalizeForSearch(c).contains(query),
        );
      },
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: TextStyle(color: theme.textOnBackground, fontSize: 15),
          // Une saisie qui ne correspond plus à un pays sélectionné doit
          // redevenir "rien de choisi" — sinon _canSubmit resterait vrai
          // avec un texte libre jamais validé par onSelected.
          onChanged: (value) {
            if (value.trim() != (initialValue ?? '')) onSelected(null);
          },
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: theme.textOnBackgroundMuted),
            suffixIcon: Icon(
              Icons.search_rounded,
              color: theme.textOnBackgroundMuted,
            ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final list = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: theme.surface,
            elevation: 6,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, minWidth: 260),
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        hint,
                        style: TextStyle(color: theme.textOnBackgroundMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shrinkWrap: true,
                      itemCount: list.length,
                      itemBuilder: (context, index) {
                        final country = list[index];
                        return InkWell(
                          onTap: () => onSelected(country),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Text(
                              country,
                              style: TextStyle(color: theme.textOnBackground),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final dynamic theme;

  const _GenderChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? theme.primary : theme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? theme.primary
                : theme.textOnBackgroundMuted.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : theme.textOnBackground,
          ),
        ),
      ),
    );
  }
}
