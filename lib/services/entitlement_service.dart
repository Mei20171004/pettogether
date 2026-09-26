import 'package:cloud_firestore/cloud_firestore.dart';

/// The Pro state of a household, mirrored into Firestore by the RevenueCat
/// webhook. Clients can read it but never write it.
class HouseholdPro {
  const HouseholdPro({
    required this.active,
    required this.legacy,
    required this.multiPetActive,
    required this.aiActive,
    this.expiresAt,
    this.multiPetExpiresAt,
    this.aiExpiresAt,
  });

  /// At least one member has a live `pet_together_pro` entitlement.
  final bool active;

  /// The household existed before Pro launched, so it keeps the features it
  /// already had. Set once by `scripts/backfill_legacy_pro.js`.
  final bool legacy;

  /// Independent add-ons shared across every caregiver in the household.
  final bool multiPetActive;
  final bool aiActive;

  final DateTime? expiresAt;
  final DateTime? multiPetExpiresAt;
  final DateTime? aiExpiresAt;

  bool get activeNow =>
      active && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));
  bool get multiPetActiveNow =>
      multiPetActive &&
      (multiPetExpiresAt == null || multiPetExpiresAt!.isAfter(DateTime.now()));
  bool get aiActiveNow =>
      aiActive && (aiExpiresAt == null || aiExpiresAt!.isAfter(DateTime.now()));

  bool get unlocked => activeNow || legacy;

  static const HouseholdPro none = HouseholdPro(
    active: false,
    legacy: false,
    multiPetActive: false,
    aiActive: false,
  );

  factory HouseholdPro.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> s) {
    final data = s.data();
    if (!s.exists || data == null) return none;
    return HouseholdPro(
      active: data['active'] == true,
      legacy: data['legacy'] == true,
      multiPetActive: data['multiPetActive'] == true,
      aiActive: data['aiActive'] == true,
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate(),
      multiPetExpiresAt: (data['multiPetExpiresAt'] as Timestamp?)?.toDate(),
      aiExpiresAt: (data['aiExpiresAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// How many AI parses the signed-in user has spent this calendar month.
class AiUsage {
  const AiUsage({required this.month, required this.count});

  final String month;
  final int count;

  static const AiUsage empty = AiUsage(month: '', count: 0);

  /// Usage from a previous month does not count against the current one.
  int countFor(String currentMonth) => month == currentMonth ? count : 0;
}

/// Reads the paywall state that lives in Firestore rather than on the device.
///
/// RevenueCat's own `CustomerInfo` only describes the person holding the phone.
/// Two things cannot come from it: whether somebody *else* in the household has
/// paid, and how many AI parses this account has already spent. Both live in
/// Firestore so the Security Rules can see them too.
class EntitlementService {
  EntitlementService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _proDoc(String householdId) => _db
      .collection('households')
      .doc(householdId)
      .collection('private')
      .doc('pro');

  DocumentReference<Map<String, dynamic>> _usageDoc(String uid) =>
      _db.collection('aiUsage').doc(uid);

  DocumentReference<Map<String, dynamic>> _couponDoc() =>
      _db.collection('aiUsage').doc('freecoupon');

  DocumentReference<Map<String, dynamic>> _redemptionDoc(String uid) =>
      _db.collection('freeCouponRedemptions').doc(uid);

  DocumentReference<Map<String, dynamic>> _userInfoDoc(String uid) =>
      _db.collection('userinfo').doc(uid);

  DocumentReference<Map<String, dynamic>> _entitlementDoc(String uid) =>
      _db.collection('entitlements').doc(uid);

  /// Refreshes only the signed-in user's console summary. All source reads
  /// come from the server, so an offline cache cannot extend an expired grant.
  /// Security Rules verify the resulting tier against those same sources.
  Future<UserInfoStatus> syncUserInfo(
    String uid, {
    DateTime? latestProPurchaseAt,
  }) async {
    const server = GetOptions(source: Source.server);
    final entitlement = await _entitlementDoc(uid).get(server);
    final redemption = await _redemptionDoc(uid).get(server);
    final redemptionData = redemption.data();
    Map<String, dynamic>? couponData;
    if (redemptionData?['coupon'] is String) {
      try {
        couponData = (await _couponDoc().get(server)).data();
      } on FirebaseException catch (error) {
        // Rules hide a coupon definition when this user's old code no longer
        // matches it. In that case the redemption is simply inactive.
        if (error.code != 'permission-denied') rethrow;
      }
    }

    final ref = _userInfoDoc(uid);
    final previous = (await ref.get(server)).data();
    final status = UserInfoStatus.fromSources(
      entitlement: entitlement.data(),
      redemption: redemptionData,
      coupon: couponData,
      now: DateTime.now(),
    );
    final Timestamp? paidAt = latestProPurchaseAt == null
        ? (previous?['paidAt'] as Timestamp?)
        : Timestamp.fromDate(latestProPurchaseAt);
    if (previous != null &&
        previous['userId'] == uid &&
        previous['createdAt'] is Timestamp &&
        previous['userType'] == status.userType &&
        previous['statusExpiresAt'] == status.statusExpiresAt &&
        previous['couponActivatedAt'] == status.couponActivatedAt &&
        previous['paidAt'] == paidAt) {
      return status;
    }
    await ref.set({
      'userId': uid,
      'userType': status.userType,
      'statusExpiresAt': status.statusExpiresAt,
      'couponActivatedAt': status.couponActivatedAt,
      'paidAt': paidAt,
      'createdAt': previous?['createdAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return status;
  }

  /// A server read on launch prevents an old offline cache from granting paid
  /// features after the coupon has expired or been revoked.
  Future<DateTime?> checkFreeCoupon(String uid) async {
    final redemption = await _redemptionDoc(uid)
        .get(const GetOptions(source: Source.server));
    final redeemedCode = redemption.data()?['coupon'];
    if (redeemedCode is! String) return null;

    final definition = await _couponDoc().get(
      const GetOptions(source: Source.server),
    );
    final data = definition.data();
    final enddate = data?['enddate'];
    if (data?['coupon'] != redeemedCode || enddate is! Timestamp) return null;
    final expiresAt = enddate.toDate();
    return expiresAt.isAfter(DateTime.now()) ? expiresAt : null;
  }

  /// Firestore Rules compare the submitted code and deadline on the server.
  /// No client can write a redemption merely by changing local application state.
  Future<DateTime?> redeemFreeCoupon(String uid, String code) async {
    await _redemptionDoc(
      uid,
    ).set({'coupon': code.trim(), 'redeemedAt': FieldValue.serverTimestamp()});
    return checkFreeCoupon(uid);
  }

  /// Errors (offline, permission denied) are surfaced to the listener, which
  /// falls back to "not unlocked" rather than guessing.
  Stream<HouseholdPro> watchHouseholdPro(String householdId) =>
      _proDoc(householdId).snapshots().map(HouseholdPro.fromSnapshot);

  Stream<AiUsage> watchAiUsage(String uid) =>
      _usageDoc(uid).snapshots().map((s) {
        final data = s.data();
        if (!s.exists || data == null) return AiUsage.empty;
        return AiUsage(
          month: (data['month'] as String?) ?? '',
          count: (data['count'] as num?)?.toInt() ?? 0,
        );
      });

  /// Increments this month's parse counter. The Security Rules only accept a
  /// +1 step or a reset into a new month, so a client cannot zero it out.
  Future<void> recordAiParse(String uid) async {
    final ref = _usageDoc(uid);
    final month = currentMonth();
    await _db.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      final data = snapshot.data();
      final sameMonth =
          snapshot.exists && data != null && data['month'] == month;
      final next = sameMonth ? ((data['count'] as num?)?.toInt() ?? 0) + 1 : 1;
      tx.set(ref, {
        'month': month,
        'count': next,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  static String currentMonth() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
  }
}

class UserInfoStatus {
  const UserInfoStatus({
    required this.userType,
    required this.statusExpiresAt,
    required this.couponActivatedAt,
  });

  final String userType;
  final Timestamp? statusExpiresAt;
  final Timestamp? couponActivatedAt;

  factory UserInfoStatus.fromSources({
    Map<String, dynamic>? entitlement,
    Map<String, dynamic>? redemption,
    Map<String, dynamic>? coupon,
    required DateTime now,
  }) {
    final proExpiry = entitlement?['expiresAt'] as Timestamp?;
    final proActive =
        entitlement?['active'] == true &&
        (proExpiry == null || proExpiry.toDate().isAfter(now));
    final couponExpiry = coupon?['enddate'] as Timestamp?;
    final couponActive =
        redemption?['coupon'] is String &&
        redemption?['coupon'] == coupon?['coupon'] &&
        couponExpiry != null &&
        couponExpiry.toDate().isAfter(now);
    return UserInfoStatus(
      userType: proActive
          ? 'pro user'
          : couponActive
          ? 'free coupon user'
          : 'free user',
      statusExpiresAt: proActive
          ? proExpiry
          : couponActive
          ? couponExpiry
          : null,
      couponActivatedAt: redemption?['redeemedAt'] as Timestamp?,
    );
  }
}
