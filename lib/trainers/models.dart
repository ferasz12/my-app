class Trainer {
  final String id;
  final String name;
  final String bio;
  final String? photoUrl;
  final int priceMonthlyCents; // مثال: 29900 = 299.00
  final double rating; // 0..5
  final List<String> specialties;
  final bool isActive;

  Trainer({
    required this.id,
    required this.name,
    required this.bio,
    this.photoUrl,
    required this.priceMonthlyCents,
    required this.rating,
    required this.specialties,
    this.isActive = true,
  });

  factory Trainer.fromJson(Map<String, dynamic> j) => Trainer(
        id: j['id'],
        name: j['name'],
        bio: j['bio'] ?? '',
        photoUrl: j['photoUrl'],
        priceMonthlyCents: j['priceMonthlyCents'] ?? 0,
        rating: (j['rating'] ?? 0).toDouble(),
        specialties:
            (j['specialties'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        isActive: j['isActive'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'bio': bio,
        'photoUrl': photoUrl,
        'priceMonthlyCents': priceMonthlyCents,
        'rating': rating,
        'specialties': specialties,
        'isActive': isActive,
      };
}

class Subscription {
  final String id;
  final String userId;
  final String trainerId;
  final String status; // 'active' | 'canceled' | 'pending'
  final String period; // 'monthly'
  final int priceCents;
  final String currency; // 'SAR' مثلاً
  final DateTime startAt;
  final DateTime renewAt;

  Subscription({
    required this.id,
    required this.userId,
    required this.trainerId,
    required this.status,
    required this.period,
    required this.priceCents,
    required this.currency,
    required this.startAt,
    required this.renewAt,
  });

  factory Subscription.fromJson(Map<String, dynamic> j) => Subscription(
        id: j['id'],
        userId: j['userId'],
        trainerId: j['trainerId'],
        status: j['status'],
        period: j['period'],
        priceCents: j['priceCents'],
        currency: j['currency'] ?? 'SAR',
        startAt: DateTime.fromMillisecondsSinceEpoch(j['startAt']),
        renewAt: DateTime.fromMillisecondsSinceEpoch(j['renewAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'trainerId': trainerId,
        'status': status,
        'period': period,
        'priceCents': priceCents,
        'currency': currency,
        'startAt': startAt.millisecondsSinceEpoch,
        'renewAt': renewAt.millisecondsSinceEpoch,
      };
}

class TrainerApplication {
  final String id;
  final String userId; // صاحب الطلب
  final String name; // الاسم المعروض
  final String bio; // نبذة
  final int priceMonthlyCents;
  final List<String> specialties;
  final String status; // 'pending' | 'approved' | 'rejected'
  final DateTime createdAt;

  // جديد — مطلوبين
  final String personalImagePath; // صورة شخصية
  final String idImagePath; // صورة الهوية

  TrainerApplication({
    required this.id,
    required this.userId,
    required this.name,
    required this.bio,
    required this.priceMonthlyCents,
    required this.specialties,
    required this.status,
    required this.createdAt,
    required this.personalImagePath,
    required this.idImagePath,
  });

  factory TrainerApplication.fromJson(Map<String, dynamic> j) =>
      TrainerApplication(
        id: j['id'],
        userId: j['userId'],
        name: j['name'],
        bio: j['bio'],
        priceMonthlyCents: j['priceMonthlyCents'],
        specialties:
            (j['specialties'] as List).map((e) => e.toString()).toList(),
        status: j['status'],
        createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt']),
        personalImagePath: j['personalImagePath'] ?? '',
        idImagePath: j['idImagePath'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'name': name,
        'bio': bio,
        'priceMonthlyCents': priceMonthlyCents,
        'specialties': specialties,
        'status': status,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'personalImagePath': personalImagePath,
        'idImagePath': idImagePath,
      };
}
