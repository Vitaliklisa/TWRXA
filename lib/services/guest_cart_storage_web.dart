import 'package:web/web.dart' as web;
import 'guest_cart_storage_contract.dart';

GuestCartStorage createGuestCartStorage() => const _CookieGuestCartStorage();

class _CookieGuestCartStorage implements GuestCartStorage {
  const _CookieGuestCartStorage();

  static const _maxValueLength = 3800;

  @override
  bool get isSupported => true;

  @override
  String? read(String key) {
    for (final cookie in web.document.cookie.split(';')) {
      final separator = cookie.indexOf('=');
      if (separator < 0 || cookie.substring(0, separator).trim() != key) {
        continue;
      }
      try {
        return Uri.decodeComponent(cookie.substring(separator + 1).trim());
      } on FormatException {
        throw const FormatException('The saved cart cookie is malformed.');
      }
    }
    return null;
  }

  @override
  Future<void> write(String key, String value) async {
    final encoded = Uri.encodeComponent(value);
    if (encoded.length > _maxValueLength) {
      throw StateError(
        'The guest cart is too large to fit in a browser cookie. '
        'Please sign in to save this cart.',
      );
    }
    web.document.cookie =
        '$key=$encoded; Path=/; Max-Age=2592000; SameSite=Lax$_secureAttribute';
    if (read(key) != value) {
      throw StateError(
        'The browser did not save the guest cart cookie. '
        'Check your browser cookie settings and retry.',
      );
    }
  }

  @override
  Future<void> remove(String key) async {
    web.document.cookie = '$key=; Path=/; Max-Age=0; SameSite=Lax'
        '$_secureAttribute';
    if (read(key) != null) {
      throw StateError('Could not clear the guest cart cookie.');
    }
  }

  String get _secureAttribute =>
      web.window.location.protocol == 'https:' ? '; Secure' : '';
}
