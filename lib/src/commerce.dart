import 'package:flutter/material.dart';
import 'design.dart';
import 'model.dart';
import 'appointments.dart';
import '../payments/payment_screen.dart';
import '../packages/package_screen.dart';

const packageOptions = [
  (
    'Premium Bridal',
    4800.0,
    'Your complete bridal experience, thoughtfully curated.',
    'bridal_hero',
  ),
  (
    'Essential Elegance',
    2500.0,
    'The beautiful essentials for an intimate celebration.',
    'eden',
  ),
  (
    'Luxury Bespoke',
    6500.0,
    'Extraordinary details for a day that is uniquely yours.',
    'golden',
  ),
];
const extras = {
  'Pre-wedding photography': 1200.0,
  'Makeup trial': 350.0,
  'Extra photography hour': 500.0,
  'Accessories styling': 150.0,
};

class PackagesScreen extends StatelessWidget {
  const PackagesScreen({super.key});
  @override
  Widget build(BuildContext c) {
    final m = AppScope.of(c);
    if (m.accountId != null) return const LivePackageScreen();
    return PageFrame(
      title: 'Service packages',
      child: PageList(
        children: [
          Text(
            'Your day.\nYour kind of beautiful.',
            style: Theme.of(c).textTheme.headlineMedium,
          ),
          gap(10),
          const Text(
            'Thoughtful packages for every bridal journey.',
            style: TextStyle(color: muted),
          ),
          gap(20),
          if (m.selectedPackage != null)
            MenuTile(
              Icons.check_circle_outline,
              'My selected package',
              m.selectedPackage!,
              () => go(c, const SelectedPackageScreen()),
            ),
          for (int i = 0; i < packageOptions.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Surface(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(18),
                      ),
                      child: photo(
                        packageOptions[i].$4,
                        height: 190,
                        width: double.infinity,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            packageOptions[i].$1,
                            style: Theme.of(c).textTheme.titleLarge,
                          ),
                          gap(6),
                          Text(
                            packageOptions[i].$3,
                            style: const TextStyle(color: muted),
                          ),
                          gap(14),
                          Text(
                            'From ${money(packageOptions[i].$2)}',
                            style: const TextStyle(
                              color: rose,
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                            ),
                          ),
                          gap(14),
                          Primary(
                            'Explore package',
                            () => go(c, PackageDetailScreen(index: i)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PackageDetailScreen extends StatelessWidget {
  const PackageDetailScreen({super.key, required this.index});
  final int index;
  @override
  Widget build(BuildContext c) {
    final p = packageOptions[index];
    return PageFrame(
      title: p.$1,
      bottom: Primary(
        'Customize this package',
        () => go(c, CustomizePackageScreen(index: index)),
      ),
      child: PageList(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: photo(p.$4, height: 250, width: double.infinity),
          ),
          gap(20),
          Text(p.$1, style: Theme.of(c).textTheme.headlineMedium),
          gap(8),
          Text(
            money(p.$2),
            style: const TextStyle(
              color: rose,
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          gap(12),
          Text(p.$3),
          const Section('Beautifully included'),
          for (final s in [
            'Wedding dress rental',
            'Bridal consultation',
            'Stylist guidance',
            'Fitting coordination',
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline, color: rose),
              title: Text(s),
            ),
          const DemoNote(
            text:
                'Package pricing and inclusions are demonstration content. Final catalogue rules will be connected later.',
          ),
        ],
      ),
    );
  }
}

class CustomizePackageScreen extends StatefulWidget {
  const CustomizePackageScreen({super.key, required this.index});
  final int index;
  @override
  State<CustomizePackageScreen> createState() => _CustomizeState();
}

class _CustomizeState extends State<CustomizePackageScreen> {
  final selected = <String>{};
  bool review = false;
  double get total =>
      packageOptions[widget.index].$2 +
      selected.fold(0.0, (s, n) => s + extras[n]!);
  @override
  Widget build(BuildContext c) => PageFrame(
    title: review ? 'Review your package' : 'Make it yours',
    bottom: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InfoRow('Package total', money(total)),
        Primary(review ? 'Confirm package' : 'Review selection', () async {
          if (!review) {
            setState(() => review = true);
            return;
          }
          if (await confirm(
                c,
                'Confirm your package?',
                'Save ${packageOptions[widget.index].$1} at ${money(total)} in this demo?',
                action: 'Confirm package',
              ) &&
              c.mounted) {
            AppScope.of(
              c,
            ).savePackage(packageOptions[widget.index].$1, total, selected);
            Navigator.of(c).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => const SelectedPackageScreen(),
              ),
            );
          }
        }),
        if (review)
          TextButton(
            onPressed: () => setState(() => review = false),
            child: const Text('Edit my selection'),
          ),
      ],
    ),
    child: PageList(
      children: [
        Text(
          review
              ? 'A package as unique\nas your love story.'
              : 'A few personal touches.',
          style: Theme.of(c).textTheme.headlineMedium,
        ),
        const Section('Your essentials'),
        Surface(
          child: Column(
            children: [
              InfoRow(
                packageOptions[widget.index].$1,
                money(packageOptions[widget.index].$2),
              ),
              const Divider(),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.lock_outline, color: rose),
                title: Text('Dress rental & bridal consultation'),
                subtitle: Text(
                  'Required services · Included',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        Section(review ? 'Your selected extras' : 'Something extra'),
        for (final e in extras.entries)
          if (!review || selected.contains(e.key))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Surface(
                padding: EdgeInsets.zero,
                child: review
                    ? ListTile(
                        title: Text(e.key),
                        trailing: Text(money(e.value)),
                      )
                    : CheckboxListTile(
                        value: selected.contains(e.key),
                        onChanged: (v) => setState(
                          () =>
                              v! ? selected.add(e.key) : selected.remove(e.key),
                        ),
                        title: Text(e.key),
                        subtitle: Text('+ ${money(e.value)}'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
              ),
            ),
        if (review && selected.isEmpty)
          const Text(
            'No optional extras selected.',
            style: TextStyle(color: muted),
          ),
        const DemoNote(
          text:
              'Selecting a package saves it in this UI session only. It does not place an order or charge you.',
        ),
      ],
    ),
  );
}

class SelectedPackageScreen extends StatelessWidget {
  const SelectedPackageScreen({super.key});
  @override
  Widget build(BuildContext c) {
    final m = AppScope.of(c);
    return PageFrame(
      title: 'My selected package',
      child: PageList(
        children: [
          const EmptyState(
            Icons.check_circle_outline,
            'Beautiful choice.',
            'Your package is saved in this demo.',
          ),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.selectedPackage ?? 'Premium Bridal (sample)',
                  style: Theme.of(c).textTheme.titleLarge,
                ),
                gap(),
                const InfoRow('Required', 'Dress rental & consultation'),
                for (final extra in m.addons)
                  InfoRow(extra, money(extras[extra]!)),
                const Divider(),
                InfoRow('Total', money(m.packageTotal)),
              ],
            ),
          ),
          gap(24),
          Primary(
            'Book an appointment',
            () => go(c, const BookAppointmentScreen()),
          ),
          gap(10),
          OutlinedButton(
            onPressed: () => go(c, const PaymentsScreen()),
            child: const Text('View payments'),
          ),
          const DemoNote(),
        ],
      ),
    );
  }
}

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});
  @override
  Widget build(BuildContext c) {
    final m = AppScope.of(c);
    if (m.accountId != null) {
      return const LivePaymentsScreen();
    }
    return PageFrame(
      title: 'Payments & receipts',
      child: PageList(
        children: [
          Text(
            'All the little details,\nin one place.',
            style: Theme.of(c).textTheme.headlineMedium,
          ),
          gap(20),
          Surface(
            color: blush,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'REMAINING BALANCE',
                  style: TextStyle(
                    letterSpacing: 1.5,
                    fontSize: 10,
                    color: rose,
                  ),
                ),
                gap(8),
                Text(
                  money(m.balance),
                  style: Theme.of(c).textTheme.headlineLarge,
                ),
                gap(16),
                InfoRow('Package total', money(m.packageTotal)),
                InfoRow('Payments received', money(m.paid)),
                gap(10),
                LinearProgressIndicator(
                  value: (m.paid / m.packageTotal).clamp(0, 1),
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(8),
                ),
                gap(20),
                Primary(
                  m.balance == 0 ? 'Fully paid' : 'Preview payment',
                  m.balance == 0
                      ? null
                      : () => go(c, const PaymentFormScreen()),
                ),
              ],
            ),
          ),
          const DemoNote(
            text:
                'No real money is charged. All payment balances, references and receipts are demo records.',
          ),
          const Section('Payment history'),
          for (final p in m.payments.reversed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Surface(
                padding: EdgeInsets.zero,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: blush,
                    child: Icon(Icons.receipt_long, color: rose),
                  ),
                  title: Text(
                    money(p.amount),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${dateLabel(p.date)} · ${p.method}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => go(c, ReceiptScreen(payment: p)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PaymentFormScreen extends StatefulWidget {
  const PaymentFormScreen({super.key});
  @override
  State<PaymentFormScreen> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<PaymentFormScreen> {
  final amount = TextEditingController(),
      promo = TextEditingController(),
      form = GlobalKey<FormState>();
  String method = 'Online banking';
  bool review = false, busy = false, loaded = false;
  String? promoMessage;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!loaded) {
      amount.text = AppScope.of(context).balance.toStringAsFixed(2);
      loaded = true;
    }
  }

  @override
  void dispose() {
    amount.dispose();
    promo.dispose();
    super.dispose();
  }

  Future<void> pay() async {
    setState(() => busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() => busy = false);
    final m = AppScope.of(context);
    final value = double.parse(amount.text);
    if (value > m.balance) {
      toast(context, 'The balance changed. Review your amount.');
      setState(() => review = false);
      return;
    }
    final p = DemoPayment(
      value,
      method,
      DateTime.now(),
      'LV-DEMO-${m.payments.length + 1}',
    );
    m.payments.add(p);
    m.changed();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ReceiptScreen(payment: p, success: true),
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final m = AppScope.of(c);
    return PageFrame(
      title: review ? 'Review demo payment' : 'Make a payment',
      bottom: Primary(
        busy
            ? 'Processing demo…'
            : review
            ? 'Simulate successful payment'
            : 'Review payment',
        busy
            ? null
            : () {
                if (review) {
                  pay();
                } else if (form.currentState!.validate()) {
                  setState(() => review = true);
                }
              },
      ),
      child: PageList(
        children: [
          const DemoNote(
            text:
                'Payment UI preview only. Do not enter real card or banking details. No payment gateway is connected.',
          ),
          if (!review) ...[
            Form(
              key: form,
              child: TextFormField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Amount to pay (RM)',
                  helperText: 'Outstanding: ${money(m.balance)}',
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  return n == null || !n.isFinite || n <= 0 || n > m.balance
                      ? 'Enter an amount between RM 0.01 and ${money(m.balance)}'
                      : null;
                },
              ),
            ),
            const Section('Payment method'),
            for (final v in [
              'Online banking',
              'Credit / debit card',
              'E-wallet',
            ])
              ListTile(
                contentPadding: EdgeInsets.zero,
                selected: method == v,
                leading: Icon(
                  method == v
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: rose,
                ),
                onTap: () => setState(() => method = v),
                title: Text(v),
                trailing: Icon(
                  v == 'Online banking'
                      ? Icons.account_balance_outlined
                      : v == 'E-wallet'
                      ? Icons.account_balance_wallet_outlined
                      : Icons.credit_card,
                  color: rose,
                ),
              ),
            const Section('Promotional code preview'),
            TextField(
              controller: promo,
              decoration: const InputDecoration(
                hintText: 'Try BRIDE100 or EXPIRED20',
              ),
            ),
            TextButton(
              onPressed: () => setState(
                () =>
                    promoMessage = promo.text.trim().toUpperCase() == 'BRIDE100'
                    ? 'Valid demo code. Discount preview: RM 100. Not applied to this sample invoice.'
                    : promo.text.trim().toUpperCase() == 'EXPIRED20'
                    ? 'This promotional code has expired.'
                    : 'This code is not recognised.',
              ),
              child: const Text('Check code'),
            ),
            if (promoMessage != null)
              Text(promoMessage!, style: const TextStyle(color: rose)),
          ] else ...[
            const EmptyState(
              Icons.lock_outline,
              'Review your payment',
              'Check the details before simulating a result.',
            ),
            Surface(
              child: Column(
                children: [
                  InfoRow('Amount', money(double.parse(amount.text))),
                  InfoRow('Method', method),
                  InfoRow(
                    'Remaining after payment',
                    money(m.balance - double.parse(amount.text)),
                  ),
                ],
              ),
            ),
            gap(20),
            TextButton(
              onPressed: busy ? null : () => setState(() => review = false),
              child: const Text('Edit payment details'),
            ),
          ],
        ],
      ),
    );
  }
}

class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.payment, this.success = false});
  final DemoPayment payment;
  final bool success;
  @override
  Widget build(BuildContext c) => PageFrame(
    title: 'Demo receipt',
    child: PageList(
      children: [
        if (success)
          const EmptyState(
            Icons.check_circle_outline,
            'Payment preview complete',
            'Your demo balance has been updated.',
          ),
        Surface(
          child: Column(
            children: [
              const Text(
                'Luvly',
                style: TextStyle(
                  fontFamily: 'LuvlySerif',
                  fontSize: 32,
                  fontStyle: FontStyle.italic,
                  color: rose,
                ),
              ),
              gap(),
              const StatusPill('Paid'),
              gap(20),
              Text(
                money(payment.amount),
                style: Theme.of(c).textTheme.headlineLarge,
              ),
              gap(),
              InfoRow('Reference', payment.reference),
              InfoRow('Date', dateLabel(payment.date)),
              InfoRow('Payment method', payment.method),
              const Divider(),
              const Text(
                'DEMO • NOT A VALID PAYMENT RECEIPT',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: rose,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        gap(20),
        Primary('Back to payment overview', () => Navigator.pop(c)),
        const DemoNote(
          text:
              'PDF download and sharing will be added with real receipt generation. This is an in-app receipt preview.',
        ),
      ],
    ),
  );
}
