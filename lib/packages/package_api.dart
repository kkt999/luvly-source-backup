import 'dart:math';
import '../payments/payment_api.dart';
import '../catalogue/catalogue_repository.dart';
import '../bookings/booking_outcome.dart';
import 'rental_availability.dart';
export '../bookings/booking_outcome.dart';

String packageRequestId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
String packageMoney(int cents) => formatRinggit(cents);

const packageGownSecurityCents = 30000;

enum PackageServiceType {
  custom('custom', 'Custom service'),
  makeupHair('makeup-hair', 'Wedding-day makeup & hair'),
  makeupTrial('makeup-trial', 'Pre-wedding makeup & hair trial'),
  secondBeautyLook('second-beauty-look', 'Second beauty look'),
  portraits('portrait-session', 'Portrait session'),
  extraFitting('extra-fitting', 'Additional fitting'),
  extraRentalDay('extra-rental-day', 'Additional rental day'),
  packageVeil('package-veil', 'Veil Rental'),
  itemAccessories('item-priced-accessories', 'Bridal Accessories'),
  veil('veil-rental', 'Veil rental'),
  jewellery('accessory-rental', 'Jewellery & accessories'),
  veilAndJewellery('veil-accessories', 'Veil & jewellery');

  const PackageServiceType(this.code, this.label);
  final String code, label;

  bool get needsTiming => switch (this) {
    makeupHair ||
    makeupTrial ||
    secondBeautyLook ||
    portraits ||
    extraFitting => true,
    _ => false,
  };
  bool get includesVeils =>
      this == veil || this == packageVeil || this == veilAndJewellery;
  bool get includesJewellery =>
      this == jewellery || this == itemAccessories || this == veilAndJewellery;
  bool get isAccessory => includesVeils || includesJewellery;
  bool get needsGownRental =>
      isAccessory || needsTiming || this == extraRentalDay;

  static PackageServiceType? fromCode(Object? code) =>
      values.where((type) => type.code == code).firstOrNull;
}

class PackageServiceItem {
  const PackageServiceItem({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    required this.priceCents,
    this.serviceType,
    this.accessoryAllowanceCents,
    this.standardVeilId,
  });
  final String id, name, description, kind;
  final int priceCents;
  final PackageServiceType? serviceType;
  final int? accessoryAllowanceCents;
  final String? standardVeilId;

  PackageServiceType? get schedulingType =>
      serviceType ?? PackageServiceType.fromCode(id);

  bool get requiresTeamScheduling => schedulingType?.needsTiming ?? false;

  bool get requiresStockSelection =>
      (serviceType ?? PackageServiceType.fromCode(id))?.isAccessory ?? false;

  bool get includesVeils =>
      serviceType?.includesVeils ?? name.toLowerCase().contains('veil');
  bool get includesJewellery =>
      serviceType?.includesJewellery ??
      RegExp(r'accessor|jewel|tiara', caseSensitive: false).hasMatch(name);
  bool get isAccessory => includesVeils || includesJewellery;
  bool get itemPriced => serviceType == PackageServiceType.itemAccessories;
  bool get packageVeil => serviceType == PackageServiceType.packageVeil;
  bool get usesAccessoryAllowance => isAccessory && !itemPriced && !packageVeil;
  int get allowanceCents => accessoryAllowanceCents ?? priceCents;
  bool get addsRentalDay => serviceType == null
      ? RegExp(
          r'extra.*rental.*day|additional.*rental.*day',
          caseSensitive: false,
        ).hasMatch(name)
      : serviceType == PackageServiceType.extraRentalDay;

  String get customerDescription => switch (serviceType?.code ?? id) {
    'makeup-trial' =>
      'Luvly confirms your artist and trial time before the deposit. Select it here to include it in your package quote.',
    'makeup-hair' || 'second-beauty-look' =>
      'Luvly confirms your artist and timing before the deposit.',
    'portrait-session' when serviceType == null =>
      'A 60-minute boutique portrait session with 10 edited images. Luvly confirms the time before the deposit.',
    'portrait-session' =>
      '${description.isEmpty ? '' : '$description '}Luvly confirms the session time before the deposit.',
    'extra-fitting' =>
      'One additional in-boutique fitting. Luvly confirms the time before the deposit.',
    'extra-rental-day' =>
      'Adds one calendar day to the standard rental period.',
    _ => description,
  };

  factory PackageServiceItem.fromJson(Map<String, dynamic> d) =>
      PackageServiceItem(
        id: d['id'],
        name: d['name'],
        description: d['description'],
        kind: d['kind'],
        priceCents: d['priceCents'],
        serviceType: PackageServiceType.fromCode(d['serviceType']),
        accessoryAllowanceCents: d['accessoryAllowanceCents'] as int?,
        standardVeilId: d['standardVeilId'] as String?,
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'kind': kind,
    'priceCents': priceCents,
    if (serviceType != null) 'serviceType': serviceType!.code,
    if (accessoryAllowanceCents != null)
      'accessoryAllowanceCents': accessoryAllowanceCents,
    if (standardVeilId != null) 'standardVeilId': standardVeilId,
  };
}

class BridalPackage {
  const BridalPackage({
    required this.id,
    required this.name,
    required this.description,
    required this.basePriceCents,
    required this.revision,
    required this.active,
    required this.services,
    this.includedGownCount = 0,
    this.eligibleDressIds = const [],
    this.allCatalogueGowns = false,
    this.draft = false,
    this.accessoryPricingApproved = false,
  });
  final String id, name, description;
  final int basePriceCents, revision;
  final bool active, draft, accessoryPricingApproved;
  String get statusLabel => active
      ? 'Active'
      : draft
      ? 'Unpublished'
      : 'Inactive';
  final List<PackageServiceItem> services;
  final int includedGownCount;
  final List<String> eligibleDressIds;
  final bool allCatalogueGowns;
  factory BridalPackage.fromJson(Map<String, dynamic> d) => BridalPackage(
    id: d['id'],
    name: d['name'],
    description: d['description'],
    basePriceCents: d['basePriceCents'],
    revision: d['revision'],
    active: d['active'],
    draft: d['draft'] == true,
    includedGownCount: d['includedGownCount'] ?? 0,
    eligibleDressIds: List<String>.from(d['eligibleDressIds'] ?? []),
    allCatalogueGowns: d['allCatalogueGowns'] == true,
    services: (d['services'] as List)
        .map((s) => PackageServiceItem.fromJson(Map<String, dynamic>.from(s)))
        .toList(),
  );
  int total(Set<String> removed, Set<String> addons) =>
      basePriceCents -
      services
          .where((s) => s.kind == 'Optional' && removed.contains(s.id))
          .fold<int>(0, (n, s) => n + s.priceCents) +
      services
          .where((s) => s.kind == 'Add-on' && addons.contains(s.id))
          .fold<int>(0, (n, s) => n + s.priceCents);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'basePriceCents': basePriceCents,
    'revision': revision,
    'active': active,
    if (accessoryPricingApproved) 'accessoryPricingApproved': true,
    'includedGownCount': includedGownCount,
    'eligibleDressIds': allCatalogueGowns ? const <String>[] : eligibleDressIds,
    if (allCatalogueGowns) 'allCatalogueGowns': true,
    'services': services.map((s) => s.toJson()).toList(),
  };
}

class PackageSelection {
  PackageSelection(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'];
  String get name => data['name'];
  String get customer => data['customerName'];
  int get totalCents => data['agreedTotalCents'] as int? ?? data['totalCents'];
  List<Map<String, dynamic>> get selectedGowns =>
      ((data['selectedGowns'] ?? []) as List)
          .map((g) => Map<String, dynamic>.from(g))
          .toList();
  List<PackageServiceItem> get services => (data['services'] as List)
      .map((s) => PackageServiceItem.fromJson(Map<String, dynamic>.from(s)))
      .toList();
  List<Map<String, dynamic>> get appointments =>
      ((data['appointments'] ?? []) as List)
          .map((s) => Map<String, dynamic>.from(s))
          .toList();
  SandboxInvoice? get invoice => data['invoice'] == null
      ? null
      : SandboxInvoice.fromJson(Map<String, dynamic>.from(data['invoice']));
}

abstract class PackageApi {
  bool get configured;
  Future<List<BridalPackage>> catalogue();
  Future<List<CatalogueDress>> gowns();
  Future<BridalPackage> save(BridalPackage package);
  Future<List<PackageSelection>> selections();
  Future<void> select(
    BridalPackage package,
    Set<String> removed,
    Set<String> addons,
    String requestId, {
    List<Map<String, dynamic>> gowns = const [],
    List<Map<String, dynamic>> accessories = const [],
    int? accessoryCatalogueVersion,
  });
  Future<BookingOutcome?> book(
    String selectionId,
    String type,
    DateTime start,
    String notes,
    String requestId,
  );
  Future<void> invoice(String selectionId, String appointmentId);
  void close();
}

abstract interface class PackageDeletionApi {
  Future<void> remove(BridalPackage package);
}

abstract interface class PackageGownLimitApi {
  Future<int> gownLimit();
}

class HttpPackageApi
    implements
        PackageApi,
        PackageDeletionApi,
        PackageAvailabilityApi,
        PackageGownLimitApi {
  HttpPackageApi({HttpPaymentApi? transport})
    : transport = transport ?? HttpPaymentApi();
  final HttpPaymentApi transport;
  @override
  Future<RentalAvailability> availability(
    String packageId,
    int revision,
    Set<String> removed,
    Set<String> addons,
    Map<String, String> dates,
  ) async => RentalAvailability(
    await transport.businessRequest(
      '/v1/package-availability',
      body: {
        'packageId': packageId,
        'revision': revision,
        'removedIds': removed.toList(),
        'addonIds': addons.toList(),
        'rentalPlan': dates,
      },
    ),
  );
  @override
  bool get configured => transport.configured;
  @override
  Future<int> gownLimit() async {
    final result = await transport.businessRequest('/v1/package-gown-limit');
    final limit = result['maxGowns'];
    if (limit is! int || limit < 0 || limit > 100) {
      throw const PaymentFailure(
        'Could not check how many gowns are rentable.',
      );
    }
    return limit;
  }

  @override
  Future<List<CatalogueDress>> gowns() async {
    final data = await transport.businessRequest('/v1/package-gowns');
    return (data['dresses'] as List)
        .map(
          (d) =>
              CatalogueDress.fromFields(d['id'], Map<String, dynamic>.from(d)),
        )
        .toList();
  }

  @override
  Future<List<BridalPackage>> catalogue() async {
    final data = await transport.businessRequest(
      '/v1/packages?serviceTypes=1&itemPricing=1&veilUpgrades=1',
    );
    return (data['packages'] as List)
        .map((d) => BridalPackage.fromJson(Map<String, dynamic>.from(d)))
        .toList();
  }

  Future<BridalPackage> approvedPricing(String id) async =>
      BridalPackage.fromJson(
        Map<String, dynamic>.from(
          await transport.businessRequest(
            '/v1/packages/${Uri.encodeComponent(id)}/approved-pricing',
          ),
        ),
      );

  @override
  Future<BridalPackage> save(BridalPackage package) async =>
      BridalPackage.fromJson(
        Map<String, dynamic>.from(
          await transport.businessRequest(
            '/v1/packages',
            body: package.toJson(),
          ),
        ),
      );
  @override
  Future<void> remove(BridalPackage package) async {
    await transport.businessRequest(
      '/v1/packages/${package.id}/delete',
      body: {'revision': package.revision},
    );
  }

  @override
  Future<List<PackageSelection>> selections() async {
    final data = await transport.businessRequest('/v1/package-selections');
    return (data['selections'] as List)
        .map((d) => PackageSelection(Map<String, dynamic>.from(d)))
        .toList();
  }

  @override
  Future<void> select(
    BridalPackage package,
    Set<String> removed,
    Set<String> addons,
    String requestId, {
    List<Map<String, dynamic>> gowns = const [],
    List<Map<String, dynamic>> accessories = const [],
    int? accessoryCatalogueVersion,
    Map<String, String>? rentalPlan,
  }) async {
    await saveSelection(
      package,
      removed,
      addons,
      requestId,
      gowns: gowns,
      accessories: accessories,
      accessoryCatalogueVersion: accessoryCatalogueVersion,
      rentalPlan: rentalPlan,
    );
  }

  /// Keep the server-issued selection identity and dates for the next screen.
  Future<PackageSelection> saveSelection(
    BridalPackage package,
    Set<String> removed,
    Set<String> addons,
    String requestId, {
    List<Map<String, dynamic>> gowns = const [],
    List<Map<String, dynamic>> accessories = const [],
    int? accessoryCatalogueVersion,
    Map<String, String>? rentalPlan,
    int? expectedTotalCents,
  }) async {
    final saved = await transport.businessRequest(
      '/v1/package-selections',
      body: {
        'requestId': requestId,
        'packageId': package.id,
        'revision': package.revision,
        'removedIds': removed.toList(),
        'addonIds': addons.toList(),
        'gowns': gowns,
        'rentalPlan': ?rentalPlan,
        if (package.services.any((s) => s.serviceType != null))
          'expectedTotalCents':
              expectedTotalCents ?? package.total(removed, addons),
        if (accessories.isNotEmpty) 'accessories': accessories,
        if (accessories.isNotEmpty)
          'accessoryCatalogueVersion': accessoryCatalogueVersion,
      },
    );
    return PackageSelection(saved);
  }

  @override
  Future<BookingOutcome?> book(
    String selectionId,
    String type,
    DateTime start,
    String notes,
    String requestId,
  ) async {
    return BookingOutcome.fromJson(
      await transport.businessRequest(
        '/v1/package-selections/$selectionId/book',
        body: {
          'requestId': requestId,
          'type': type,
          'startAt': start.toUtc().millisecondsSinceEpoch,
          'notes': notes.trim(),
          'feePolicyVersion': 1,
        },
      ),
    );
  }

  @override
  Future<void> invoice(String selectionId, String appointmentId) async {
    await transport.businessRequest(
      '/v1/package-selections/$selectionId/invoice',
      body: {'appointmentId': appointmentId},
    );
  }

  @override
  void close() => transport.close();
}
