import '../../core/api_client.dart';

/// Symbole usuel d'une devise (ex. `$`, `€`, `£`) quand il existe et n'est
/// pas ambigu avec une autre devise déjà proposée (ex. CAD/EGP gardent un
/// préfixe pour ne pas être confondues avec USD/GBP) ; sinon on retombe sur
/// le code ISO à 3 lettres.
const Map<String, String> _currencySymbols = {
  'USD': r'$',
  'CAD': 'CA\$',
  'EUR': '€',
  'GBP': '£',
  'EGP': 'E£',
  'NGN': '₦',
  'GHS': '₵',
  'ZAR': 'R',
};

String currencySymbol(String currencyCode) => _currencySymbols[currencyCode] ?? currencyCode;

class CurrencyOption {
  final String currency;
  final String? label;
  final String? country;

  const CurrencyOption({required this.currency, this.label, this.country});

  factory CurrencyOption.fromJson(Map<String, dynamic> json) => CurrencyOption(
        currency: json['currency'] as String,
        label: json['label'] as String?,
        country: json['country'] as String?,
      );
}

/// Choix de devise pour la Boutique — voir ProfileController::setPreferredCurrency
/// côté backend : une seule fois, jamais modifiable ensuite.
class CurrencyService {
  CurrencyService._();
  static final CurrencyService instance = CurrencyService._();

  /// Devises actuellement proposables (gérées depuis l'espace admin —
  /// activer/désactiver), XOF toujours en tête.
  Future<List<CurrencyOption>> fetchAvailableCurrencies() async {
    final data = await ApiClient.instance.get('/currencies') as List;
    return data.map((e) => CurrencyOption.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String?> fetchPreferredCurrency() async {
    final data = await ApiClient.instance.get('/auth/me') as Map<String, dynamic>;
    final user = data['user'] as Map<String, dynamic>;
    return user['preferred_currency'] as String?;
  }

  Future<void> setPreferredCurrency(String currency) async {
    await ApiClient.instance.put('/auth/preferred-currency', body: {'currency': currency});
  }
}
