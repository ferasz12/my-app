// lib/gyms/gyms_map_page.dart
// صفحة "النوادي القريبة" (Google Maps + Places API v1)

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform; // ← NEW
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:my_app/services/usage_gate.dart';

class GymsMapPage extends StatefulWidget {
  const GymsMapPage({super.key});
  @override
  State<GymsMapPage> createState() => _GymsMapPageState();
}

class _GymsMapPageState extends State<GymsMapPage> {
  GoogleMapController? _mapController;

  Timer? _mapTimeout;
  bool _mapReady = false;
  bool _mapTimedOut = false;

  final _markers = <Marker>{};
  final _detailsCache = <String, Map<String, dynamic>>{};

  LatLng? _center;
  bool _loading = true;
  String? _error;

  // يقرأ المفتاح من .env (أو GOOGLE_MAPS_API_KEY كبديل)
  String get _apiKey =>
      dotenv.env['MAPS_API_KEY'] ?? dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

  // نرسل Bundle ID في رأس الطلب لتطابق قيود iOS apps في Google Cloud
  String get _iosBundleId =>
      dotenv.env['IOS_BUNDLE_ID'] ?? 'com.feras12.myapp6'; // ← غيّرها لقيمتك إن لزم

  @override
  void initState() {
    super.initState();
    final masked = _apiKey.isNotEmpty ? _apiKey.substring(0, 7) : 'EMPTY';
    debugPrint('Maps Places KEY prefix = $masked');
    debugPrint('iOS bundle (header) = ${Platform.isIOS ? _iosBundleId : '-'}');
    _initFlow();
  }

  @override
  void dispose() {
    _mapTimeout?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _armMapTimeout() {
    _mapTimeout?.cancel();
    _mapTimedOut = false;
    _mapTimeout = Timer(const Duration(seconds: 6), () {
      if (!mounted) return;
      // لو الخريطة ما صارت جاهزة خلال 6 ثواني، غالباً المشكلة إعداد مفتاح Maps SDK
      if (!_mapReady) {
        setState(() => _mapTimedOut = true);
      }
    });
  }

  Future<void> _initFlow() async {
    try {
      // ✅ حد يومي لفتح صفحة النوادي القريبة (مرتين في اليوم)
      final gate = await UsageGate.check(action: 'clubs_nearby');
      if (!gate.allowed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(gate.message ?? 'تم تجاوز الحد اليومي.'))
          );
          Navigator.of(context).maybePop();
        }
        return;
      }

      if (_apiKey.isEmpty) {
        throw 'مفتاح خرائط Google مفقود. أضِف MAPS_API_KEY في .env';
      }

      // 1) تحقق من خدمات الموقع والصلاحية
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw 'خدمة تحديد الموقع مغلقة. فعّل الـ GPS ثم أعد المحاولة.';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw 'تم رفض إذن الموقع. اسمح للتطبيق بالوصول إلى موقعك.';
      }
      if (permission == LocationPermission.deniedForever) {
        throw 'إذن الموقع مرفوض دائمًا. افتح الإعدادات لتفعيل الإذن.';
      }

      // 2) احصل على الموقع الحالي
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      final center = LatLng(pos.latitude, pos.longitude);

      if (!mounted) return;
      setState(() {
        _center = center;
        _loading = false;
        _mapReady = false;
        _mapTimedOut = false;
      });

      // شغّل مؤقت تشخيص إذا ما ظهرت الخريطة (مفيد خصوصاً على Android إذا المفتاح غير مضاف بالـ Manifest)
      _armMapTimeout();

      // 3) حمّل النوادي القريبة
      await _loadNearbyGyms(center);

      // 4) حرّك الكاميرا
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: center, zoom: 14),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _mapReady = false;
        _mapTimedOut = false;
      });
    }
  }

  Future<void> _openExternalMap() async {
    final c = _center;
    if (c == null) return;

    final url = Uri.parse(
      'https://www.google.com/maps/@?api=1&map_action=map&center=${c.latitude},${c.longitude}&zoom=14',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // ========= Helpers لطلبات Places API (New) v1 =========
  Map<String, String> _placesHeaders({String? fieldMask}) {
    final h = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'X-Goog-Api-Key': _apiKey,
    };
    if (fieldMask != null && fieldMask.isNotEmpty) {
      h['X-Goog-FieldMask'] = fieldMask;
    }
    // ← أهم إضافة: عرّف التطبيق للـ API بما يطابق قيود iOS apps
    if (Platform.isIOS) {
      h['X-Ios-Bundle-Identifier'] = _iosBundleId;
    }
    return h;
  }

  String _shorten(String s, {int max = 240}) {
    if (s.length <= max) return s;
    return s.substring(0, max) + '…';
  }

  // ============ البحث القريب (Nearby) - v1 ============
  Future<void> _loadNearbyGyms(LatLng center) async {
    final uri = Uri.https('places.googleapis.com', '/v1/places:searchNearby');

    final body = {
      "languageCode": "ar",
      "includedTypes": ["gym"],
      "maxResultCount": 20,
      "locationRestriction": {
        "circle": {
          "center": {
            "latitude": center.latitude,
            "longitude": center.longitude,
          },
          "radius": 2500.0 // متر (2.5 كم)
        }
      }
    };

    try {
      final res = await http.post(
        uri,
        headers: _placesHeaders(
          fieldMask: 'places.id,places.displayName,places.rating,places.location',
        ),
        body: jsonEncode(body),
      );

      if (res.statusCode != 200) {
        final bodyText = res.body.toString();
        debugPrint('Places Nearby error (${res.statusCode}): $bodyText');
        throw 'HTTP ${res.statusCode}: ${_shorten(bodyText)}';
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final places = (data['places'] as List?) ?? [];

      final newMarkers = <Marker>{};
      for (final p in places) {
        final id = p['id'] as String?;
        final name = (p['displayName']?['text'] as String?) ?? 'نادي رياضي';
        final rating = (p['rating'] as num?)?.toStringAsFixed(1);
        final loc = p['location'] as Map<String, dynamic>?;

        if (id == null || loc == null) continue;
        final lat = (loc['latitude'] as num?)?.toDouble() ?? center.latitude;
        final lng = (loc['longitude'] as num?)?.toDouble() ?? center.longitude;

        newMarkers.add(
          Marker(
            markerId: MarkerId(id),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(
              title: rating != null ? '$name • ⭐️ $rating' : name,
              snippet: 'اضغط للتفاصيل',
              onTap: () => _openPlace(id),
            ),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _markers
          ..clear()
          ..addAll(newMarkers);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر جلب النوادي القريبة: $e')),
      );
    }
  }

  // ============ تفاصيل المكان (Details) - v1 ============
  Future<void> _openPlace(String placeId) async {
    Map<String, dynamic>? details = _detailsCache[placeId];
    if (details == null) {
      final uri = Uri.https('places.googleapis.com', '/v1/places/$placeId', {
        'languageCode': 'ar',
      });

      try {
        final res = await http.get(
          uri,
          headers: _placesHeaders(
            fieldMask:
                'id,displayName,formattedAddress,rating,internationalPhoneNumber,websiteUri',
          ),
        );
        if (res.statusCode != 200) {
          final bodyText = res.body.toString();
          debugPrint('Places Details error (${res.statusCode}): $bodyText');
          throw 'HTTP ${res.statusCode}: ${_shorten(bodyText)}';
        }
        details = jsonDecode(res.body) as Map<String, dynamic>;
        _detailsCache[placeId] = details!;
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذّر جلب التفاصيل: $e')),
        );
        return;
      }
    }

    if (!mounted) return;

    final normalized = <String, dynamic>{
      'name': details!['displayName']?['text'] ?? 'نادي رياضي',
      'rating': details!['rating'],
      'formatted_address': details!['formattedAddress'],
      'formatted_phone_number': details!['internationalPhoneNumber'],
      'website': details!['websiteUri'],
    };

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (_) => _PlaceSheet(details: normalized),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = _center ?? const LatLng(24.7136, 46.6753); // الرياض كافتراضي

    return Scaffold(
      appBar: AppBar(
        title: const Text('النوادي القريبة'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBox(
                  message: _error!,
                  onRetry: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _initFlow();
                  },
                )
              : Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition:
                          CameraPosition(target: initial, zoom: 13),
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      compassEnabled: true,
                      zoomControlsEnabled: false,
                      onMapCreated: (c) {
                        _mapController = c;
                        if (mounted) {
                          setState(() {
                            _mapReady = true;
                            _mapTimedOut = false;
                          });
                        }
                      },
                      markers: _markers,
                    ),

                    // ✅ لو الخريطة فاضية (غالباً إعدادات Maps SDK ناقصة) نعرض تشخيص فخم بدل فراغ
                    if (_mapTimedOut)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: _MapDiagnosticsCard(
                          isAndroid: Platform.isAndroid,
                          isIOS: Platform.isIOS,
                          onRetry: () {
                            setState(() {
                              _mapTimedOut = false;
                              _mapReady = false;
                            });
                            _armMapTimeout();
                          },
                          onOpenExternal: _openExternalMap,
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _MapDiagnosticsCard extends StatelessWidget {
  final bool isAndroid;
  final bool isIOS;
  final VoidCallback onRetry;
  final VoidCallback onOpenExternal;
  const _MapDiagnosticsCard({
    required this.isAndroid,
    required this.isIOS,
    required this.onRetry,
    required this.onOpenExternal,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bullets = <String>[
      'تأكد أن "Maps SDK" مفعّل في Google Cloud لنفس المفتاح.',
      if (isAndroid)
        'Android: لازم تضيف com.google.android.geo.API_KEY في android/app/src/main/AndroidManifest.xml',
      if (isIOS)
        'iOS: تأكد من وجود GMSApiKey في ios/Runner/Info.plist وأن قيود الـ Bundle ID صحيحة.',
      'إذا قيّدت المفتاح: فعّل قيود Android Apps / iOS Apps لمفتاح الخريطة (مو HTTP فقط).',
    ];

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.map_outlined, color: cs.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'الخريطة ما ظهرت',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'الأماكن القريبة تظهر لأن Places API شغّال، لكن الخريطة تحتاج إعداد مفتاح Maps SDK على الجهاز.',
            ),
            const SizedBox(height: 10),
            ...bullets.map(
              (b) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• '),
                    Expanded(child: Text(b)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenExternal,
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('افتحها في خرائط Google'),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorBox({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, size: 40),
            const SizedBox(height: 8),
            Text(message, style: t.bodyMedium?.copyWith(color: Colors.red)),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('حاول مرة أخرى'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceSheet extends StatelessWidget {
  final Map<String, dynamic> details;
  const _PlaceSheet({required this.details});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final name = (details['name'] as String?) ?? 'نادي رياضي';
    final rating = (details['rating'] as num?)?.toStringAsFixed(1);
    final phone = details['formatted_phone_number'] as String?;
    final site = details['website'] as String?;
    final addr = (details['formatted_address'] as String?) ?? 'بدون عنوان';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          if (rating != null) Text('التقييم: $rating/5', style: t.bodyMedium),
          const SizedBox(height: 8),
          Text(addr, style: t.bodyMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              if (phone != null)
                ActionChip(
                  label: const Text('اتصال'),
                  avatar: const Icon(Icons.call),
                  onPressed: () async {
                    final uri = Uri.parse('tel:$phone');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                ),
              if (site != null)
                ActionChip(
                  label: const Text('الموقع'),
                  avatar: const Icon(Icons.language),
                  onPressed: () async {
                    final uri = Uri.parse(site);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
