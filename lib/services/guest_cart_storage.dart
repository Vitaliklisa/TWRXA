import 'guest_cart_storage_contract.dart';
import 'guest_cart_storage_stub.dart'
    if (dart.library.html) 'guest_cart_storage_web.dart' as platform;

export 'guest_cart_storage_contract.dart';

GuestCartStorage createGuestCartStorage() => platform.createGuestCartStorage();
