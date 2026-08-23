import '../../core/api_client.dart';

/// "Nous contacter" (voir AboutCard) — crée un ticket visible côté admin,
/// la réponse se fait par email en dehors de l'app (pas de messagerie
/// intégrée, voir SupportTicketController côté backend).
class SupportService {
  SupportService._();
  static final SupportService instance = SupportService._();

  Future<void> submitTicket({required String subject, required String message}) async {
    await ApiClient.instance.post('/support/tickets', body: {
      'subject': subject,
      'message': message,
    });
  }
}
