import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Princess exports torso-depth proxy and consistent fit targets', () {
    final bytes = File('assets/models/princess_wedding.glb').readAsBytesSync();
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(0, Endian.little), 0x46546c67);
    final length = header.getUint32(12, Endian.little);
    final model =
        jsonDecode(utf8.decode(bytes.sublist(20, 20 + length))) as Map;
    final nodes = model['nodes'] as List;
    final proxies = nodes.where((n) => n['name'] == 'LuvlyTorsoDepth').toList();
    expect(proxies, hasLength(1));
    final meshes = model['meshes'] as List;
    final binaryStart = 28 + length;
    final accessors = model['accessors'] as List;
    final views = model['bufferViews'] as List;
    void checkPosition(int id, double limit) {
      final a = accessors[id];
      expect(a['sparse'], isNull); // Dense buffers for Android importers.
      expect(a['componentType'], 5126);
      expect(a['type'], 'VEC3');
      final v = views[a['bufferView']];
      final offset =
          binaryStart +
          (v['byteOffset'] as int? ?? 0) +
          (a['byteOffset'] as int? ?? 0);
      final stride = v['byteStride'] as int? ?? 12;
      for (var i = 0; i < a['count']; i++) {
        for (var j = 0; j < 3; j++) {
          final value = header.getFloat32(
            offset + i * stride + j * 4,
            Endian.little,
          );
          expect(
            value.isFinite && value.abs() <= limit,
            isTrue,
            reason: 'Invalid geometry in accessor $id at vertex $i',
          );
        }
      }
    }

    expect(meshes, hasLength(7)); // Six garment pieces plus invisible torso.
    for (final mesh in meshes) {
      expect(mesh['extras']['targetNames'], ['LuvlyWaist', 'LuvlyChest', 'LuvlyHem', 'LuvlyDepth', 'LuvlyShoulderTilt', 'LuvlyWrapRest', 'LuvlyCuffLeftX', 'LuvlyCuffLeftY', 'LuvlyCuffLeftZ', 'LuvlyCuffRightX', 'LuvlyCuffRightY', 'LuvlyCuffRightZ']);
      expect(mesh['weights'], hasLength(12));
      expect(mesh['weights'][4], 0.0);
      expect(mesh['weights'][3], 1.0); // Existing first three defaults stay authored.
      for (final primitive in mesh['primitives']) {
        expect(primitive['targets'], hasLength(12));
        expect(primitive['attributes']['NORMAL'], isNotNull);
        checkPosition(primitive['attributes']['POSITION'], 2.0);
        for (var i = 0; i < primitive['targets'].length; i++) {
          checkPosition(primitive['targets'][i]['POSITION'], (i == 2 || i >= 5) ? 0.35 : 0.15);
        }
        checkPosition(primitive['targets'][3]['NORMAL'], 2.0);
        checkPosition(primitive['targets'][4]['NORMAL'], 2.0);
        List<double> vertex(int id, int index) {
          final a = accessors[id]; final v = views[a['bufferView']];
          final offset = binaryStart + (v['byteOffset'] as int? ?? 0) +
              (a['byteOffset'] as int? ?? 0) + index * (v['byteStride'] as int? ?? 12);
          return List.generate(3, (j) => header.getFloat32(offset+j*4, Endian.little));
        }
        final position = primitive['attributes']['POSITION'] as int;
        final depth = primitive['targets'][3]['POSITION'] as int;
        expect(accessors[position]['count'], accessors[depth]['count']);
        for(var i=0; i<accessors[position]['count']; i++) {
          final p = vertex(position,i); final delta = vertex(depth,i);
          expect(delta[0], 0); expect(delta[1], 0); // No widening or lengthening.
          if(p[1] <= 0.95) expect(delta[2], 0); // Preserve lower skirt and train.
          if(p[1] >= 1.18) expect(delta[2], closeTo(0.85*(p[2]-0.53), 0.000001));
          final tilt = vertex(primitive['targets'][4]['POSITION'],i);
          expect(tilt[0], 0); expect(tilt[2], 0);
          expect(tilt[1].abs(), lessThan(0.10));
          if(p[1] <= 1.10) expect(tilt[1], 0); // Waist, skirt and train unchanged.
          if(p[1] >= 1.35) expect(tilt[1], closeTo(0.18*p[0], 0.000001));
          for (var channel=5;channel<12;channel++) {
            final cuff=vertex(primitive['targets'][channel]['POSITION'],i);
            if (p[1]<=1.20 || mesh['name']!='Object_3') {
              expect(cuff, [0.0,0.0,0.0], reason: 'Cuff shape must not move skirt, bodice or invisible torso');
            }
            if (channel>=6) {
              final axis=(channel-6)%3;
              for (var j=0;j<3;j++) { if(j!=axis) expect(cuff[j],0); }
              final isLeft=channel<9;
              if ((isLeft && p[0]>=-0.14) || (!isLeft && p[0]<=0.14)) expect(cuff,[0.0,0.0,0.0]);
            }
          }
        }
      }
    }
    final proxyMesh = meshes[proxies.single['mesh']];
    final materials = model['materials'] as List;
    for (final lace in materials.where((m) =>
        m['name'] == 'Dress_Layer_1' || m['name'] == 'Dress_Layer_6')) {
      expect(lace['alphaMode'], 'MASK');
      expect(lace['alphaCutoff'], 0.5);
      expect(lace['normalTexture']['scale'], 0.35);
      expect(lace['pbrMetallicRoughness']['baseColorTexture'], isNotNull);
    }
    final material = materials[proxyMesh['primitives'][0]['material']];
    expect(material['name'], 'LuvlyDepthOnly');
    expect(material['alphaMode'] ?? 'OPAQUE', 'OPAQUE');
    expect(model['asset']['extras']['luvlyTorsoVolume'], 1);
    expect(model['asset']['extras']['luvlyTorsoDepthAdaptation'], 1);
    expect(model['asset']['extras']['luvlyShoulderArticulation'], 1);
    expect(model['asset']['extras']['luvlyWrapArticulation'], 1);
    final proxyPosition = accessors[proxyMesh['primitives'][0]['attributes']['POSITION']];
    expect(proxyPosition['max'][2] - proxyPosition['min'][2], greaterThan(0.09));
    for (final image in model['images']) {
      expect(
        image['uri'],
        isNull,
      ); // All textures bundled, no runtime downloads.
      expect(image['bufferView'], isNotNull);
    }
  });
}

