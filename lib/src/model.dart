import 'package:flutter/material.dart';

class Dress {
  const Dress(
    this.name,
    this.price,
    this.shape,
    this.asset,
    this.description, {
    this.id,
    this.arAsset,
    this.referenceUrl,
    this.credits,
    this.previewNote,
  });
  final String name, shape, asset, description;
  final String? id, arAsset, referenceUrl;
  final String? credits, previewNote;
  final int price;
  String get priceLabel =>
      referenceUrl != null ? 'Reference study • Not for sale' : money(price);
}

const dresses = [
  Dress(
    'The Golden Gown',
    4500,
    'A-Line',
    'golden',
    'An elegant sweetheart neckline and flowing tulle skirt. A timeless silhouette for your forever moment.',
  ),
  Dress(
    'Eden Lace',
    3100,
    'A-Line',
    'eden',
    'Delicate lace meets effortless romance, finished with a softly sweeping train.',
  ),
  Dress(
    'Blush Romance',
    3900,
    'Ball Gown',
    'blush',
    'A dreamy full skirt with delicate details, made for an unforgettable entrance.',
  ),
  Dress(
    'Luxe Satin',
    4200,
    'Mermaid',
    'satin',
    'Clean lines and luminous satin for a beautifully modern bridal look.',
  ),
  Dress(
    'Pearl Dreams',
    3600,
    'Ball Gown',
    'pearl',
    'Soft layers and pearl-inspired details with a graceful, romantic finish.',
  ),
  Dress(
    'Ivory Bliss',
    3800,
    'Mermaid',
    'ivory',
    'A sculpted silhouette and airy train in a delicate shade of ivory.',
  ),
  Dress(
    'Francine Gown',
    0,
    'Sheath',
    'francine_reference',
    'An ivory gown with a folded neckline, fitted silhouette and flared hem. The 3D preview shows an independent interpretation of the Francine gown by Rebecca Ingram.',
    id: 'francine-reference',
    arAsset: 'assets/models/francine_reference.glb',
    referenceUrl: 'https://www.maggiesottero.com/rebecca-ingram/francine/18883',
  ),
  Dress(
    'Princess Wedding Dress',
    0,
    'Ball Gown',
    'princess_wedding',
    'A full-skirted wedding gown with layered lace, floral details and a bow at the back. The image shows the 3D gown used in the virtual try-on.',
    id: 'princess-wedding',
    arAsset: 'assets/models/princess_wedding.glb',
    referenceUrl:
        'https://sketchfab.com/3d-models/clothesdress-princess-wedding-dress-0c06a70e6e694660aeb695df418751cb',
    credits:
        '[Clothes/Dress] Princess Wedding Dress by Messrs (https://sketchfab.com/vodiencongtu). CC BY 4.0: https://creativecommons.org/licenses/by/4.0/. Adapted for preview: fitted bodice, chest/waist morphs, torso-depth masking, recalculated surface normals, cloth shading and crown removal. Original base-colour, lace and normal textures retained.',
    previewNote:
        'Adapted model preview, not a fit or colour guarantee. Chest and waist adjust approximately to body landmarks. Face forward with arms slightly apart; arm occlusion and physical cloth movement are not supported. Lighting and your display affect appearance.',
  ),
];

class Booking {
  Booking({
    required this.type,
    required this.date,
    required this.time,
    this.notes = '',
    this.status = 'Confirmed',
  });
  final String type;
  DateTime date;
  String time, notes, status;
  bool calendarRequested = false;
}

class ChatMessage {
  const ChatMessage(this.text, this.mine);
  final String text;
  final bool mine;
}

class Ticket {
  Ticket(
    this.id,
    this.subject,
    this.category,
    this.messages, {
    this.status = 'Open',
  });
  final String id, subject, category;
  String status;
  final List<ChatMessage> messages;
}

class DemoPayment {
  DemoPayment(this.amount, this.method, this.date, this.reference);
  final double amount;
  final String method, reference;
  final DateTime date;
}

class AppModel extends ChangeNotifier {
  AppModel();
  AppModel.live() {
    clearAccount();
  }
  String? accountId;
  String membership = 'Silver';
  // Sample fixtures are only for isolated UI previews, never for a real account.
  void clearAccount() {
    accountId = null;
    name = '';
    email = '';
    phone = '';
    contact = 'Email';
    notes = '';
    for (final key in measurements.keys.toList()) {
      measurements[key] = 0;
    }
    shortlist.clear();
    points = 0;
    membership = 'Standard';
    rewards.clear();
    selectedPackage = null;
    packageTotal = 0;
    addons.clear();
    bookings.clear();
    payments.clear();
    tickets.clear();
  }

  String name = 'Sophia Loren',
      email = 'sophia@example.com',
      phone = '012 345 6789',
      contact = 'Email',
      notes = '';
  final measurements = <String, double>{
    'Height': 165,
    'Weight': 52,
    'Bust': 88,
    'Waist': 68,
    'Hips': 92,
    'Shoulder': 40,
    'Arm length': 56,
  };
  final Set<int> shortlist = {0, 1};
  int points = 1250;
  final List<String> rewards = [];
  String? selectedPackage;
  double packageTotal = 4800;
  final Set<String> addons = {};
  final List<Booking> bookings = [
    Booking(
      type: 'Dress Trial',
      date: DateTime.now().add(const Duration(days: 7)),
      time: '2:00 PM',
      notes: 'First fitting with Jane Lee.',
    ),
  ];
  final List<DemoPayment> payments = [
    DemoPayment(
      1000,
      'Online banking',
      DateTime.now().subtract(const Duration(days: 3)),
      'LV-2026-001',
    ),
  ];
  final List<Ticket> tickets = [
    Ticket(
      'LV-1001',
      'Help with my fitting appointment',
      'Appointments',
      [
        const ChatMessage('Can I bring my mother to the fitting?', true),
        const ChatMessage(
          'Of course, Sophia! You are welcome to bring up to two guests to your appointment.',
          false,
        ),
      ],
      status: 'In Progress',
    ),
    Ticket('LV-1000', 'Package inclusions', 'Packages', [
      const ChatMessage('Does my package include accessories?', true),
      const ChatMessage(
        'Yes, the Premium Bridal package includes an accessories set.',
        false,
      ),
    ], status: 'Closed'),
  ];
  double get paid => payments.fold(0.0, (sum, p) => sum + p.amount);
  double get balance => (packageTotal - paid).clamp(0, double.infinity);
  void changed() => notifyListeners();
  void toggleShortlist(int i) {
    shortlist.contains(i) ? shortlist.remove(i) : shortlist.add(i);
    changed();
  }

  void savePackage(String name, double total, Set<String> extras) {
    selectedPackage = name;
    packageTotal = total;
    addons
      ..clear()
      ..addAll(extras);
    changed();
  }
}

class AppScope extends InheritedNotifier<AppModel> {
  static AppModel? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()?.notifier;
  const AppScope({super.key, required AppModel model, required super.child})
    : super(notifier: model);
  static AppModel of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

String money(num v) => 'RM ${v.toStringAsFixed(2)}';
const months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String dateLabel(DateTime d) => '${d.day} ${months[d.month - 1]} ${d.year}';
