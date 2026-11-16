import 'package:flutter/material.dart';
import '../catalogue/rental_screen.dart';
import '../packages/package_api.dart';
import '../packages/package_screen.dart';
import '../payments/payment_api.dart';

/// A single profile destination, retaining both existing record types without
/// showing package-linked gown records for a second time in the gown-only tab.
class MyRentalsScreen extends StatelessWidget {
  const MyRentalsScreen({super.key, this.packageApi, this.rentalApi});
  final PackageApi? packageApi;
  final HttpPaymentApi? rentalApi;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        toolbarHeight:
            56 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
        title: const Text(
          'My rentals & packages',
          style: TextStyle(fontSize: 18),
        ),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Packages'),
            Tab(text: 'Gown-only rentals'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          children: [
            LivePackageScreen(
              initialSelections: true,
              profileWorkspace: true,
              api: packageApi,
            ),
            RentalScreen(
              profileWorkspace: true,
              gownOnly: true,
              api: rentalApi,
            ),
          ],
        ),
      ),
    ),
  );
}
