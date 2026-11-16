import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:luvly_app/reviews/review_api.dart';
import 'package:luvly_app/reviews/review_screen.dart';
import 'package:luvly_app/reviews/review_reports.dart';
import 'package:luvly_app/payments/payment_api.dart';
import 'package:luvly_app/src/design.dart' show luvlyTheme;
import 'checkout_redesign_test.dart' show fonts, viewport;
import 'profile_photo_test.dart' show picture, settleWork;

Map<String, dynamic> savedReview({bool owner = true, bool manager = false}) => {
  'id': 'a' * 32,
  'title': 'Bridal Essentials',
  'author': 'Alice',
  'rentalId': 'rental',
  'stars': 4,
  'text': 'Beautiful gown and a kind, helpful team.',
  'revision': 1,
  'createdAt': 1792710000000,
  'updatedAt': 1792710000000,
  'media': <Map<String, dynamic>>[],
  'owner': owner,
  'canManage': manager,
  'hidden': false,
  'withdrawn': false,
  'reply': null,
  'contentVersion': 1,
  'canReport': !owner && !manager,
  'safety': {'state': 'Allowed', 'category': 'Clear'},
};

class FakeReviews extends ReviewApi {
  final posts = <Map<String, dynamic>>[],
      uploads = <String>[],
      paths = <String>[];
  List<Map<String, dynamic>> rentals = [
    {
      'rentalId': 'rental',
      'title': 'Bridal Essentials',
      'eventDate': '2026-10-24',
      'review': null,
    },
  ];
  List<Map<String, dynamic>> reviews = [];
  List<Map<String, dynamic>> reports = [];
  String moderationState = 'Allowed';
  String failMessage = 'Save not confirmed. Retry.';
  bool failRead = false, failSave = false;
  String link =
      'https://storage.googleapis.com/luvly-44c77.firebasestorage.app/customer-reviews/${'a' * 32}/${'b' * 32}.mp4?test=fixture';
  @override
  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    paths.add(path);
    if (body != null) {
      posts.add({'path': path, ...body});
      if (failSave) throw PaymentFailure(failMessage);
      if (path.endsWith('/report')) {
        for (final r in reviews) {
          r['reported'] = true;
          r['canReport'] = false;
        }
        return {'reported': true};
      }
      if (path.endsWith('/resolve')) {
        for (final r in reports) {
          r['status'] = body['resolution'] == 'HideReview'
              ? 'Resolved'
              : 'Dismissed';
        }
        return {'resolved': true};
      }
      return {
        'review': {
          ...savedReview(),
          'revision': (body['revision'] as int) + 1,
          'safety': {'state': moderationState, 'category': 'Clear'},
        },
      };
    }
    if (failRead) throw const PaymentFailure('Reviews unavailable. Retry.');
    if (path.contains('/media/')) return {'url': link};
    if (path.endsWith('/eligible')) return {'rentals': rentals};
    if (path.startsWith('/v1/review-reports?')) {
      return {
        'reports': reports
            .where(
              (r) => path.endsWith('Open')
                  ? r['status'] == 'Open'
                  : r['status'] != 'Open',
            )
            .toList(),
      };
    }
    return {
      'reviews': reviews,
      'summary': {
        'count': reviews.length,
        'average': reviews.isEmpty ? 0 : 4.0,
      },
      'canManage': reviews.any((r) => r['canManage'] == true),
      'pendingCount': reviews
          .where((r) => r['safety']?['state'] == 'Pending')
          .length,
      'openReports': reports.where((r) => r['status'] == 'Open').length,
      'textModeration': {'configured': true},
    };
  }

  @override
  Future<Map<String, dynamic>> upload(
    String rentalId,
    String uploadId,
    Uint8List bytes,
    String mime,
  ) async {
    uploads.add(uploadId);
    return {
      'id': uploadId,
      'mime': mime,
      'width': 64,
      'height': 64,
      'bytes': bytes.length,
    };
  }
}

Future<void> host(
  WidgetTester t,
  Widget screen, {
  double width = 390,
  double scale = 1,
}) async {
  viewport(t, Size(width, 1000));
  await t.pumpWidget(
    MaterialApp(
      theme: luvlyTheme,
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (c) => TextButton(
            onPressed: () => Navigator.push(
              c,
              MaterialPageRoute<void>(builder: (_) => screen),
            ),
            child: const Text('Open reviews'),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('Open reviews'));
  await t.pumpAndSettle();
}

Future<void> reveal(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    final state = t.state<ScrollableState>(find.byType(Scrollable).first);
    state.position.jumpTo(0);
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      f,
      220,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String label) async {
  final base = find.text(label);
  if (base.evaluate().isEmpty) await reveal(t, base);
  final f = base.last;
  await reveal(t, f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Future<void> prepare(WidgetTester t) async {
  await reveal(t, find.byTooltip('5 stars'));
  await t.tap(find.byTooltip('5 stars'));
  await t.pump();
  await t.enterText(
    find.byType(TextField),
    'The fitting and service were excellent.',
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await t.pumpAndSettle();
  await reveal(t, find.byType(Checkbox));
  await t.tap(find.byType(Checkbox));
  await t.pumpAndSettle();
}

class VideoFixturePlatform extends VideoPlayerPlatform {
  final events = StreamController<VideoEvent>.broadcast();
  bool disposed = false;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) {
    scheduleMicrotask(
      () => events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 7),
          size: const Size(720, 1280),
        ),
      ),
    );
    return events.stream;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposed = true;
    await events.close();
  }

  @override
  Future<void> setLooping(int playerId, bool value) async {}
  @override
  Future<void> setVolume(int playerId, double value) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double value) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> seekTo(int playerId, Duration value) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);
}

void main() {
  testWidgets('empty eligibility explains the requirement and cannot publish', (
    t,
  ) async {
    final api = FakeReviews()..rentals = [];
    await host(t, ReviewEditor(api: api));
    expect(find.textContaining('No eligible rental yet'), findsOneWidget);
    expect(find.text('Publish review'), findsNothing);
    expect(api.posts, isEmpty);
    api.close();
  });
  testWidgets(
    'explicit missing order never falls back to another completed rental',
    (t) async {
      final api = FakeReviews();
      await host(t, ReviewEditor(api: api, rentalId: 'not-the-rental'));
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Retry rentals'), findsOneWidget);
      expect(api.posts, isEmpty);
      api.close();
    },
  );
  testWidgets(
    'stars and sharing consent are mandatory, success leaves editor',
    (t) async {
      final api = FakeReviews();
      await host(t, ReviewEditor(api: api));
      await tap(t, 'Publish review');
      expect(find.textContaining('Choose your stars'), findsOneWidget);
      expect(api.posts, isEmpty);
      await prepare(t);
      await tap(t, 'Publish review');
      expect(api.posts.single['rentalId'], isNull);
      expect(api.posts.single['path'], '/v1/reviews/rental');
      expect(api.posts.single['stars'], 5);
      expect(api.posts.single['consent'], true);
      expect(find.text('Open reviews'), findsOneWidget);
      api.close();
    },
  );
  testWidgets(
    'failed publish keeps text and reuses idempotency key on exact retry',
    (t) async {
      final api = FakeReviews()..failSave = true;
      await host(t, ReviewEditor(api: api));
      await prepare(t);
      await tap(t, 'Publish review');
      expect(find.text('Share your experience'), findsOneWidget);
      expect(find.text('Save not confirmed. Retry.'), findsOneWidget);
      final key = api.posts.single['requestId'];
      api.failSave = false;
      await tap(t, 'Publish review');
      expect(api.posts.last['requestId'], key);
      expect(api.posts.last['text'], 'The fitting and service were excellent.');
      api.close();
    },
  );
  testWidgets(
    'photo is prepared once; uncertain save retry does not duplicate upload',
    (t) async {
      final api = FakeReviews()..failSave = true;
      await host(
        t,
        ReviewEditor(
          api: api,
          pickPhotos: () async => [
            XFile.fromData(
              picture(),
              path: 'test-photo.jpg',
              mimeType: 'image/jpeg',
            ),
          ],
        ),
      );
      await t.ensureVisible(find.text('Add photos'));
      await t.tap(find.text('Add photos'));
      await settleWork(t, () => find.text('Remove').evaluate().isNotEmpty);
      await prepare(t);
      await tap(t, 'Publish review');
      expect(api.uploads, hasLength(1));
      final id = api.uploads.single;
      api.failSave = false;
      await tap(t, 'Publish review');
      expect(api.uploads, [id]);
      expect(api.posts.last['mediaIds'], [id]);
      api.close();
    },
  );
  testWidgets('oversized video is rejected before upload', (t) async {
    final api = FakeReviews();
    await host(
      t,
      ReviewEditor(
        api: api,
        pickVideo: () async => XFile.fromData(
          Uint8List(20 * 1024 * 1024 + 1),
          path: 'too-large.mp4',
        ),
      ),
    );
    await tap(t, 'Add video');
    expect(find.textContaining('no larger than 20 MB'), findsOneWidget);
    expect(api.uploads, isEmpty);
    api.close();
  });
  testWidgets('dirty editor asks before discarding; cancel does not publish', (
    t,
  ) async {
    final api = FakeReviews();
    await host(t, ReviewEditor(api: api));
    await t.tap(find.byTooltip('4 stars'));
    await t.pump();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Discard review changes?'), findsOneWidget);
    await tap(t, 'Keep editing');
    expect(find.text('Share your experience'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tap(t, 'Discard');
    expect(find.text('Open reviews'), findsOneWidget);
    expect(api.posts, isEmpty);
    api.close();
  });
  testWidgets('read errors are explicit, not false no-review states', (
    t,
  ) async {
    final api = FakeReviews()..failRead = true;
    await host(t, ReviewsScreen(api: api));
    expect(find.text('Reviews unavailable. Retry.'), findsOneWidget);
    expect(find.text('No reviews yet.'), findsNothing);
    api.close();
  });
  testWidgets(
    'owner can edit or withdraw; strangers do not receive those actions',
    (t) async {
      final api = FakeReviews()..reviews = [savedReview(owner: false)];
      await host(t, ReviewsScreen(api: api));
      expect(find.text('Edit review'), findsNothing);
      expect(find.text('Withdraw'), findsNothing);
      api.reviews = [savedReview()];
      await t.tap(find.byTooltip('Refresh reviews'));
      await t.pumpAndSettle();
      expect(find.text('Edit review'), findsOneWidget);
      await tap(t, 'Withdraw');
      await tap(t, 'Keep review');
      expect(api.posts, isEmpty);
      api.close();
    },
  );
  testWidgets(
    'manager moderation requires policy reason and cannot edit stars',
    (t) async {
      final api = FakeReviews()
        ..reviews = [savedReview(owner: false, manager: true)];
      await host(t, ReviewsScreen(api: api, manage: true), width: 1200);
      expect(find.text('Edit review'), findsNothing);
      await tap(t, 'Moderate');
      expect(
        find.textContaining('not because a customer gave'),
        findsOneWidget,
      );
      await tap(t, 'Save');
      expect(api.posts, isEmpty);
      await t.enterText(
        find.byType(TextFormField),
        'Private details without consent',
      );
      await tap(t, 'Save');
      expect(api.posts.single['hidden'], true);
      expect(api.posts.single.containsKey('stars'), false);
      api.close();
    },
  );
  testWidgets('preview never invents ratings or calls the backend', (t) async {
    final api = FakeReviews();
    await host(t, ReviewsScreen(api: api, preview: true));
    expect(
      find.text('Sign in to read and share customer reviews.'),
      findsOneWidget,
    );
    expect(api.paths, isEmpty);
    api.close();
  });
  testWidgets('media rejects untrusted link destinations', (t) async {
    final api = FakeReviews()..link = 'https://example.test/stolen';
    await host(
      t,
      ReviewMediaViewer(
        api: api,
        reviewId: 'a' * 32,
        media: {'id': 'b' * 32, 'mime': 'video/mp4'},
      ),
    );
    expect(find.text('Retry media'), findsOneWidget);
    api.close();
  });
  testWidgets('portrait video fits desktop viewport and is disposed on leave', (
    t,
  ) async {
    final original = VideoPlayerPlatform.instance,
        platform = VideoFixturePlatform();
    VideoPlayerPlatform.instance = platform;
    addTearDown(() => VideoPlayerPlatform.instance = original);
    final api = FakeReviews();
    await host(
      t,
      ReviewMediaViewer(
        api: api,
        reviewId: 'a' * 32,
        media: {'id': 'b' * 32, 'mime': 'video/mp4'},
      ),
      width: 1400,
    );
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pageBack();
    await t.pumpAndSettle();
    await settleWork(t, () => platform.disposed);
    expect(platform.disposed, true);
    api.close();
  });
  testWidgets('mobile, compact and desktop review layouts', (t) async {
    await fonts();
    final api = FakeReviews()..reviews = [savedReview(owner: false)];
    for (final size in [
      const Size(390, 1000),
      const Size(320, 800),
      const Size(1200, 900),
    ]) {
      api.reviews = [
        {
          ...savedReview(owner: false, manager: size.width > 900),
          'media': [
            {'id': 'b' * 32, 'mime': 'image/jpeg'},
            {'id': 'c' * 32, 'mime': 'video/mp4'},
          ],
        },
      ];
      viewport(t, size);
      await t.pumpWidget(
        MaterialApp(
          theme: luvlyTheme,
          home: ReviewsScreen(
            key: ValueKey(size),
            api: api,
            manage: size.width > 900,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
          'previews/customer-reviews-2079-${size.width.toInt()}.png',
        ),
      );
    }
    api.close();
  });
  testWidgets('editor mobile golden and double text scale do not overflow', (
    t,
  ) async {
    await fonts();
    final api = FakeReviews();
    await host(t, ReviewEditor(api: api));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('previews/review-editor-2080.png'),
    );
    await t.pumpWidget(const SizedBox());
    await host(t, ReviewEditor(api: api), width: 320, scale: 2);
    await t.drag(find.byType(ListView), const Offset(0, -1600));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    api.close();
  });
  testWidgets(
    'publishing includes the disclosed Google text-check policy and pending is not presented as public success',
    (t) async {
      final api = FakeReviews()..moderationState = 'Pending';
      await host(t, ReviewEditor(api: api));
      await prepare(t);
      await tap(t, 'Publish review');
      expect(api.posts.single['policyVersion'], 2);
      expect(
        find.text('Review saved for staff approval. It is not public yet.'),
        findsOneWidget,
      );
      api.close();
    },
  );
  testWidgets('blocked review keeps stars and text for correction', (t) async {
    final api = FakeReviews()
      ..failSave = true
      ..failMessage = 'Please remove abusive language before submitting.';
    await host(t, ReviewEditor(api: api));
    await prepare(t);
    await tap(t, 'Publish review');
    expect(find.text('Share your experience'), findsOneWidget);
    expect(api.posts.single['stars'], 5);
    expect(find.text(api.failMessage), findsOneWidget);
    await reveal(t, find.byType(TextField));
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      'The fitting and service were excellent.',
    );
    api.close();
  });
  testWidgets(
    'reporting another review does not remove a low rating or expose reporter identity',
    (t) async {
      final api = FakeReviews()
        ..reviews = [
          {...savedReview(owner: false), 'stars': 1},
        ];
      await host(t, ReviewsScreen(api: api));
      await tap(t, 'Report review');
      expect(
        find.textContaining('does not automatically hide'),
        findsOneWidget,
      );
      await t.enterText(
        find.byType(TextFormField),
        'Please check the words in this review.',
      );
      await tap(t, 'Send report');
      expect(api.posts.single['path'], '/v1/reviews/${'a' * 32}/report');
      expect(api.posts.single['category'], 'Harassment');
      expect(api.posts.single.containsKey('uid'), false);
      expect(api.reviews.single['stars'], 1);
      expect(find.text('You reported this version'), findsOneWidget);
      api.close();
    },
  );
  testWidgets(
    'cancel report does not call API and failed report preserves details',
    (t) async {
      final api = FakeReviews()..reviews = [savedReview(owner: false)];
      await host(t, ReviewsScreen(api: api));
      await tap(t, 'Report review');
      await tap(t, 'Cancel');
      expect(api.posts, isEmpty);
      api.failSave = true;
      await tap(t, 'Report review');
      await t.enterText(
        find.byType(TextFormField),
        'Check the video for private information.',
      );
      await tap(t, 'Send report');
      expect(find.text('You reported this version'), findsNothing);
      await tap(t, 'Report review');
      expect(
        t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
        'Check the video for private information.',
      );
      api.close();
    },
  );
  testWidgets(
    'manager sees pending state and must explain approval without changing rating',
    (t) async {
      final api = FakeReviews()
        ..reviews = [
          {
            ...savedReview(owner: false, manager: true),
            'safety': {'state': 'Pending', 'category': 'Unavailable'},
          },
        ];
      await host(t, ReviewsScreen(api: api, manage: true), width: 1200);
      expect(find.textContaining('Pending safety approval'), findsOneWidget);
      await tap(t, 'Approve safety check');
      await tap(t, 'Confirm decision');
      expect(api.posts, isEmpty);
      await t.enterText(
        find.byType(TextFormField),
        'Read the review and checked attachments.',
      );
      await tap(t, 'Confirm decision');
      expect(api.posts.single['path'], '/v1/reviews/${'a' * 32}/approve');
      expect(api.posts.single.containsKey('stars'), false);
      expect(api.posts.single.containsKey('text'), false);
      api.close();
    },
  );
  testWidgets(
    'manager reply needs explicit AI-check consent and failed reply draft is kept',
    (t) async {
      final api = FakeReviews()
        ..reviews = [savedReview(owner: false, manager: true)];
      await host(t, ReviewsScreen(api: api, manage: true), width: 1200);
      await tap(t, 'Reply');
      await t.enterText(
        find.byType(TextFormField),
        'Thank you for your honest feedback.',
      );
      await tap(t, 'Save');
      expect(api.posts, isEmpty);
      await t.tap(find.byType(Checkbox));
      await t.pumpAndSettle();
      api.failSave = true;
      await tap(t, 'Save');
      expect(api.posts.single['policyVersion'], 2);
      expect(api.posts.single['consent'], true);
      await tap(t, 'Reply');
      expect(
        t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
        'Thank you for your honest feedback.',
      );
      api.close();
    },
  );
  testWidgets(
    'report queue shows reported and edited versions and records dismissal with no rating edit',
    (t) async {
      final api = FakeReviews()..reports = [reportCase()];
      await host(t, ReviewReportsScreen(api: api), width: 1200);
      expect(
        find.text('The author changed this review after it was reported.'),
        findsOneWidget,
      );
      expect(find.text('Original reported wording'), findsOneWidget);
      expect(find.text('Current edited wording'), findsOneWidget);
      await tap(t, 'Dismiss report');
      await tap(t, 'Confirm decision');
      expect(api.posts, isEmpty);
      await t.enterText(
        find.byType(TextFormField),
        'No policy violation; honest criticism is allowed.',
      );
      await tap(t, 'Confirm decision');
      expect(api.posts.single['resolution'], 'NoViolation');
      expect(api.posts.single['reviewRevision'], 2);
      expect(api.posts.single.containsKey('stars'), false);
      expect(find.text('No reports in this view.'), findsOneWidget);
      await tap(t, 'Resolved history');
      expect(api.reports.single['status'], 'Dismissed');
      api.close();
    },
  );
  testWidgets('report queue errors do not pretend there are no reports', (
    t,
  ) async {
    final api = FakeReviews()..failRead = true;
    await host(t, ReviewReportsScreen(api: api));
    expect(find.text('Reviews unavailable. Retry.'), findsOneWidget);
    expect(find.text('No reports in this view.'), findsNothing);
    api.close();
  });
  testWidgets('report queue desktop golden and compact double-text layout', (
    t,
  ) async {
    await fonts();
    final api = FakeReviews()..reports = [reportCase()];
    await host(t, ReviewReportsScreen(api: api), width: 1200);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('previews/review-reports-2079.png'),
    );
    await t.pumpWidget(const SizedBox());
    await host(t, ReviewReportsScreen(api: api), width: 320, scale: 2);
    await t.drag(find.byType(ListView), const Offset(0, -1500));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    api.close();
  });
}

Map<String, dynamic> reportCase() => {
  'id': 'd' * 64,
  'reviewId': 'a' * 32,
  'revision': 1,
  'category': 'Harassment',
  'details': 'Please check this wording.',
  'status': 'Open',
  'createdAt': 1792710000000,
  'snapshot': {
    ...savedReview(owner: false),
    'text': 'Original reported wording',
  },
  'current': {
    ...savedReview(owner: false, manager: true),
    'text': 'Current edited wording',
    'contentVersion': 2,
    'revision': 2,
  },
};
