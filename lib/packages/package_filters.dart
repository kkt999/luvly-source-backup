import '../shared/list_controls.dart';
import 'package_api.dart';
import 'rental_workspace.dart';

const packagePriceBands = [
  'All prices',
  'Under RM 1,000',
  'RM 1,000–1,999',
  'RM 2,000 and above',
];
const packageSelectionStages = [
  'All packages',
  'Not reserved',
  'Awaiting deposit',
  'Reserved',
  'Collected',
  'Returned',
  'Expired',
  'Cancelled',
  'Needs review',
];
bool matchesPackagePrice(int cents, String band) => switch (band) {
  'All prices' => true,
  'Under RM 1,000' => cents < 100000,
  'RM 1,000–1,999' => cents >= 100000 && cents < 200000,
  'RM 2,000 and above' => cents >= 200000,
  _ => false,
};
bool matchesPackageSelection(
  PackageSelection selection,
  String query,
  String stage,
) {
  final view = StaffRentalView(selection);
  return (stage == 'All packages' ||
          (stage == 'Needs review' ? view.needsReview : view.stage == stage)) &&
      matchesListSearch(query, [
        selection.name,
        ...view.dates.values,
        view.pickup,
        view.returned,
        view.event,
        ...selection.selectedGowns.map((g) => g['name']),
      ]);
}
