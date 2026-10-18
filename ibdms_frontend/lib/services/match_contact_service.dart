import 'package:url_launcher/url_launcher.dart';

/// Phone dial + external map routing after ACCEPTED unlock.
class MatchContactService {
  MatchContactService._();

  static Future<bool> dialPhone(String? phone) async {
    if (phone == null || phone.trim().isEmpty) return false;
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> openMaps({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=$latitude,$longitude'
      '${label != null ? '&destination_place_id=$label' : ''}',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
