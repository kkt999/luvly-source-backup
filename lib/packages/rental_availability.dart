/// Only public, per-size statuses; never contains another customer's booking.
class RentalAvailability {
  RentalAvailability(Map<String, dynamic> json)
    : gowns = {
        for (final gown in json['gowns'] as List)
          gown['dressId'] as String: {
            for (final entry in gown['sizes'] as List)
              entry['size'] as String: entry['status'] as String,
          },
      },
      accessories = {
        for (final item in json['accessories'] as List? ?? const [])
          item['itemId'] as String: item['status'] as String,
      };
  final Map<String, Map<String, String>> gowns;
  final Map<String, String> accessories;
  String status(String dressId, String size) =>
      gowns[dressId]?[size] ?? 'Unconfirmed';
  bool available(String dressId, String size) =>
      status(dressId, size) == 'Available';
  Set<String> availableSizes(String dressId) => {
    for (final entry in (gowns[dressId] ?? <String, String>{}).entries)
      if (entry.value == 'Available') entry.key,
  };
}

abstract interface class PackageAvailabilityApi {
  Future<RentalAvailability> availability(
    String packageId,
    int revision,
    Set<String> removed,
    Set<String> addons,
    Map<String, String> dates,
  );
}
