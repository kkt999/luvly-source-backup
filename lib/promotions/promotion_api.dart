import '../payments/payment_api.dart';

String offerMoney(int value) => 'RM ${(value / 100).toStringAsFixed(2)}';
String offerDay(DateTime value) => value.toIso8601String().substring(0, 10);
String todayInMalaysia() =>
    offerDay(DateTime.now().toUtc().add(const Duration(hours: 8)));
int? promotionCents(String value) {
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(value.trim())) return null;
  final parts = value.trim().split('.');
  return int.parse(parts[0]) * 100 +
      int.parse(parts.length == 1 ? '00' : parts[1].padRight(2, '0'));
}

class Campaign {
  Campaign(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'];
  String get title => data['title'];
  String get description => data['description'];
  bool get offer => data['kind'] == 'Offer';
  bool get newCustomerOnly => data['newCustomerOnly'] == true;
  String get code => data['code'];
  String get packageId => data['packageId'];
  int get revision => data['revision'];
  String get status => data['active'] != true
      ? 'Inactive'
      : todayInMalaysia().compareTo(data['startDate']) < 0
      ? 'Scheduled'
      : todayInMalaysia().compareTo(data['endDate']) > 0
      ? 'Ended'
      : 'Active';
  String get saving => !offer
      ? 'Boutique news'
      : data['discountType'] == 'Percent'
      ? '${data['value']}% off · up to ${offerMoney(data['maxDiscountCents'])}'
      : '${offerMoney(data['value'])} off';
  String get terms {
    final package = packageId.isEmpty
        ? 'All gown packages'
        : 'Selected package';
    final period =
        '${data['startDate']} – ${data['endDate']} · Malaysia time\n$package';
    if (!offer) return period;
    final eligibility = newCustomerOnly
        ? 'Available during your first 30 days after registration. '
        : '';
    return '$period · minimum ${offerMoney(data['minimumCents'])}\n'
        '${eligibility}One use per customer. One code per package; no stacking. '
        'Apply before the deposit invoice. Rechecked at rental confirmation. '
        'Unpaid holds expire after 15 minutes. Paid cancellations require review; '
        'vouchers are not automatically restored. Fitting fees and refundable security are excluded.';
  }
}

abstract class PromotionApi {
  Future<List<Campaign>> list();
  Future<void> save(Map<String, dynamic> data);
  Future<void> remove(Campaign campaign);
  Future<void> apply(String selectionId, String code, int revision);
  void close();
}

class HttpPromotionApi implements PromotionApi {
  HttpPromotionApi({HttpPaymentApi? transport})
    : transport = transport ?? HttpPaymentApi();
  final HttpPaymentApi transport;
  @override
  Future<List<Campaign>> list() async {
    final result = await transport.businessRequest('/v1/promotions');
    return (result['campaigns'] as List)
        .map((p) => Campaign(Map<String, dynamic>.from(p)))
        .toList();
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    await transport.businessRequest('/v1/promotions', body: data);
  }

  @override
  Future<void> remove(Campaign campaign) async {
    await transport.businessRequest(
      '/v1/promotions/${campaign.id}/delete',
      body: {'revision': campaign.revision},
    );
  }

  @override
  Future<void> apply(String selectionId, String code, int revision) async {
    await transport.businessRequest(
      '/v1/package-selections/$selectionId/promotion',
      body: {'code': code, 'revision': revision},
    );
  }

  @override
  void close() => transport.close();
}
