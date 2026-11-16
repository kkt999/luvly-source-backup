import 'package:flutter/material.dart';
import 'design.dart';
import 'account_policy_content.dart';
export 'account_policy_content.dart';

class AccountTermsScreen extends StatefulWidget {
  const AccountTermsScreen({super.key, this.readOnly = false});
  final bool readOnly;
  @override
  State<AccountTermsScreen> createState() => _AccountTermsState();
}

class _AccountTermsState extends State<AccountTermsScreen> {
  final controller = ScrollController();
  bool reachedEnd = false, malay = false;

  void checkEnd() {
    if (!mounted || reachedEnd || !controller.hasClients) return;
    if (controller.position.extentAfter <= 2) {
      setState(() => reachedEnd = true);
    }
  }

  void language(bool next) {
    if (next == malay) return;
    setState(() {
      malay = next;
      reachedEnd = false;
    });
    if (controller.hasClients) controller.jumpTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) => checkEnd());
  }

  @override
  void initState() {
    super.initState();
    controller.addListener(checkEnd);
    WidgetsBinding.instance.addPostFrameCallback((_) => checkEnd());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: malay ? 'Terma & privasi' : 'Terms & privacy',
    bottom: widget.readOnly
        ? Primary(
            malay ? 'Tutup' : 'Close',
            () => Navigator.of(context).pop(false),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                malay
                    ? reachedEnd
                          ? 'Terima hanya jika anda bersetuju.'
                          : 'Baca hingga akhir untuk mengaktifkan “Saya setuju”.'
                    : reachedEnd
                    ? 'You have reached the end. Accept only if you agree.'
                    : 'Scroll to the end to enable “I agree”.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              gap(8),
              Primary(
                malay ? 'Saya setuju' : 'I agree',
                reachedEnd ? () => Navigator.of(context).pop(true) : null,
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(malay ? 'Bukan sekarang' : 'Not now'),
              ),
            ],
          ),
    child: NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) => checkEnd());
        return false;
      },
      child: Scrollbar(
        controller: controller,
        thumbVisibility: true,
        child: SingleChildScrollView(
          key: const Key('terms-scroll'),
          controller: controller,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                malay
                    ? 'Maklumat anda, pilihan anda.'
                    : 'Your information, your choices.',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              gap(10),
              Text(
                malay
                    ? 'Terma perkhidmatan dan notis privasi · Versi $accountTermsVersion'
                    : 'Service terms and privacy notice · Version $accountTermsVersion',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              gap(16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('English'),
                    selected: !malay,
                    onSelected: (_) => language(false),
                  ),
                  ChoiceChip(
                    label: const Text('Bahasa Melayu'),
                    selected: malay,
                    onSelected: (_) => language(true),
                  ),
                ],
              ),
              gap(20),
              Surface(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      malay ? 'Perkara utama' : 'At a glance',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    for (final item
                        in malay
                            ? const [
                                'Ukuran peribadi untuk cadangan; statistik memerlukan pilihan berasingan.',
                                'Foto AR tersimpan pada telefon. Media ulasan dimuat naik ke awan.',
                                'Ulasan yang diterbitkan dikongsi dengan pelanggan lain yang log masuk.',
                                'Permintaan privasi: Support > New message > Account.',
                              ]
                            : const [
                                'Recommendation measurements are private; statistics are a separate choice.',
                                'Saved AR photos stay on your phone. Review media is uploaded to the cloud.',
                                'Published reviews are shared with other signed-in customers.',
                                'Privacy requests: Support > New message > Account.',
                              ]) ...[
                      gap(10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            color: rose,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(fontSize: 13, height: 1.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              for (final section
                  in malay
                      ? accountTermsSectionsMalay
                      : accountTermsSections) ...[
                gap(24),
                Text(
                  section.$1,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                ),
                gap(10),
                Text(section.$2, style: const TextStyle(height: 1.6)),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
