import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:luvly_app/admin/live_inventory.dart';
import 'package:luvly_app/admin/model.dart';
import 'package:luvly_app/catalogue/catalogue_repository.dart';
import 'package:luvly_app/catalogue/catalogue_widgets.dart';
import 'package:luvly_app/catalogue/dress_photo_data.dart';
import 'fake_catalogue.dart';

void main() {
  for (final role in PortalRole.values) {
    testWidgets('${role.name} sees stored thumbnail and opens details at 390px', (
      t,
    ) async {
      t.view.physicalSize = const Size(390, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repo = FakeCatalogue();
      final dress = CatalogueDress.fromFields('dress-1', {
        ...sampleDress().toFields(),
        'revision': 1,
        'photoRevision': 1,
        'imageUrl': '',
      });
      repo.records[dress.id] = dress;
      repo.photos[dress.id] = compressDressPhoto(
        img.encodePng(img.Image(width: 100, height: 150)),
      );
      final model = PortalModel.live(
        member: TeamMember('uid', 'John', 'test@example.com', role),
      );
      addTearDown(model.dispose);
      addTearDown(repo.changes.close);
      await t.pumpWidget(
        CatalogueScope(
          repository: repo,
          child: PortalScope(
            model: model,
            child: const MaterialApp(home: Scaffold(body: LiveInventoryPage())),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('1 dress'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(t.widget<Image>(find.byType(Image)).image, isA<MemoryImage>());
      expect(t.takeException(), isNull);
      // Missing data must replace the old image without overflowing the thumbnail.
      repo.photos.clear();
      repo.changes.add(null);
      await t.pumpAndSettle();
      expect(find.text('Photo unavailable'), findsOneWidget);
      expect(find.byTooltip('Retry photo'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tap(find.byType(CatalogueDressPhoto));
      await t.pumpAndSettle();
      expect(find.text('Back to inventory'), findsOneWidget);
    });
  }
}
