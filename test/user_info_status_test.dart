import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pettogether/services/entitlement_service.dart';

void main() {
  final now = DateTime.utc(2026, 9, 26);
  final couponEnd = Timestamp.fromDate(now.add(const Duration(days: 30)));
  final redeemedAt = Timestamp.fromDate(now.subtract(const Duration(days: 1)));
  final redemption = {'coupon': 'example', 'redeemedAt': redeemedAt};
  final coupon = {'coupon': 'example', 'enddate': couponEnd};

  test('existing valid redemption resolves to free coupon user', () {
    final status = UserInfoStatus.fromSources(
      redemption: redemption,
      coupon: coupon,
      now: now,
    );
    expect(status.userType, 'free coupon user');
    expect(status.statusExpiresAt, couponEnd);
    expect(status.couponActivatedAt, redeemedAt);
  });

  test('expired or replaced coupon resolves to free user', () {
    final expired = UserInfoStatus.fromSources(
      redemption: redemption,
      coupon: {'coupon': 'example', 'enddate': Timestamp.fromDate(now)},
      now: now,
    );
    final replaced = UserInfoStatus.fromSources(
      redemption: redemption,
      coupon: {'coupon': 'different', 'enddate': couponEnd},
      now: now,
    );
    expect(expired.userType, 'free user');
    expect(replaced.userType, 'free user');
    expect(expired.couponActivatedAt, redeemedAt);
  });

  test('active Pro wins; after Pro expires, valid coupon takes over', () {
    final proEnd = Timestamp.fromDate(now.add(const Duration(days: 3)));
    final pro = UserInfoStatus.fromSources(
      entitlement: {'active': true, 'expiresAt': proEnd},
      redemption: redemption,
      coupon: coupon,
      now: now,
    );
    final afterPro = UserInfoStatus.fromSources(
      entitlement: {'active': true, 'expiresAt': proEnd},
      redemption: redemption,
      coupon: coupon,
      now: now.add(const Duration(days: 4)),
    );
    expect(pro.userType, 'pro user');
    expect(pro.statusExpiresAt, proEnd);
    expect(afterPro.userType, 'free coupon user');
    expect(afterPro.statusExpiresAt, couponEnd);
  });
}
