import 'guest_cart_storage_contract.dart';

GuestCartStorage createGuestCartStorage() =>
    const _UnsupportedGuestCartStorage();

class _UnsupportedGuestCartStorage implements GuestCartStorage {
  const _UnsupportedGuestCartStorage();

  @override
  bool get isSupported => false;

  @override
  String? read(String key) => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> remove(String key) async {}
}
