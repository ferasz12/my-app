import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'payments_gateway.dart';
import 'payments_tap_impl.dart';

PaymentsGateway resolveGateway() {
  if (kIsWeb) {
    return TapGateway(apiBase: 'https://api.yourapp.com/payments/tap');
  }
  if (Platform.isIOS || Platform.isAndroid) {
    // لاحقًا نستبدله بـ StoreGateway على iOS/Android
    return TapGateway(apiBase: 'https://api.yourapp.com/payments/tap');
  }
  return TapGateway(apiBase: 'https://api.yourapp.com/payments/tap');
}
