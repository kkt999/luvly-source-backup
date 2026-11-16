# Princess Wedding Dress — third-party preview asset

27 October 2026 adaptation (2093): appended LuvlyShoulderTilt, a bounded
pose-driven upper-bodice shear with matching normal deltas. It fades to zero
at/below model Y=1.10; the skirt/train, existing binary buffers, embedded
textures, colours and previous morph targets are preserved. Source:
`add_shoulder_tilt.py`. This is not cloth simulation or full sleeve rigging.
The original author/license below remain applicable. The Blender file and
catalogue thumbnails predate this post-export articulation.

26 October 2026 adaptation (2088): added the reversible LuvlyDepth morph to
correct the shallow adapted bodice, including matching torso-proxy depth and
normal deltas. Source buffers, materials and textures are preserved. See
`AR_ENHANCEMENT_2088.md` at the project root and `add_princess_depth_morph.py`.
The Blender file predates this post-export GLB adaptation.

Title: [Clothes/Dress] Princess Wedding Dress
Author: Messrs — https://sketchfab.com/vodiencongtu
Source: https://sketchfab.com/3d-models/clothesdress-princess-wedding-dress-0c06a70e6e694660aeb695df418751cb
License: Creative Commons Attribution 4.0 — https://creativecommons.org/licenses/by/4.0/

Title, creator, source and license were obtained from the downloaded GLB's embedded asset.extras metadata. No endorsement by the creator is implied. Preserve this attribution when distributing the model and app.

Source: user-supplied clothesdress_princess_wedding_dress.glb. Original file unchanged.
Adaptation: Blender import and initial uniform normalization, then a fitted-preview adaptation. The miniature source bodice is expanded horizontally (inner section 2.1x, tapering toward the shoulder drape); its vertical range 1.20–1.42 is mapped to 1.10–1.43. The lower skirt is compressed vertically and transitions smoothly to the bodice width. The torso centre is offset by 0.036, avoiding the asymmetric train's centre. Separate flower crown excluded. All five materials use metallicFactor=0 and a minimum roughness of 0.55, retaining original base-colour, lace alpha and normal textures. No user colour adjustment or white tint is applied. Preview JPEGs are renders of this adapted model, not an unchanged source model. No manufacturer/product colour accuracy is claimed.

Runtime Princess anchors: shoulder Y=1.45, virtual hip Y=0.97, shoulder width=0.40. Both pose alignment and rendering use the same per-dress anchors. Francine retains its own calibration. These are approximate model-space anchors, not body measurements or sizing predictions.

Reproducible import/render script: import_princess.py.
Editable model: princess_wedding.blend.
Runtime asset: assets/models/princess_wedding.glb.
Catalogue thumbnail: assets/images/princess_wedding.jpg.
Exact catalogue/native ID: princess-wedding.

Android test: stop the running app, run lib/main.dart again on a physical Android device, open Dresses, select Princess Wedding Dress, then open its AR try-on. Grant camera access. Stand facing the camera with shoulders and hips visible, then compare live and frozen views. No arbitrary fallback model is used.

Additional adaptation (29 September): add WaistFit and ChestFit morph targets. Runtime hip-to-shoulder joint ratio drives bounded, smoothed weights independently of skirt scaling; the algorithm is visual coverage estimation, NOT body circumference measurement. Static studio key/fill lighting was changed to show more side shading without recolouring textures. A framing check requires confident head/feet landmarks inside the image and labels cropped previews.

Correction (30 September): inspected original front/back/side views and connected components. Removed the previous upward displacement of the wrap: the long strips include rear wrap fabric leading to the back bow. Added LuvlyTorsoDepth, a camera-facing, approximate torso-depth surface with the same fit targets. Filament draws this first with colour writes OFF and depth writes ON, leaving the camera pixels unchanged while hiding fabric behind it. This is NOT a segmented body scan or an arm occlusion solution. Recomputed mesh surface normals after vertex transformations; original normal-map textures remain. There are now seven exported meshes: six garment meshes and one depth proxy.

Debug-only ArFixtureActivity renders a synthetic mannequin and the actual Android DressRenderer without camera access, writing files/ar_fixture.png in the app's private storage. Its activity exists only in debug builds. This permits deterministic GPU checks without asking a person to pose. The Flutter asset test checks the depth proxy, target ordering, opaque depth material and embedded textures.

Verification (30 September / 1 October): the connected physical Android phone rendered the dense-buffer GLB successfully; `phone_fixture.png` records this synthetic, camera-free test. Rear wrap strips are hidden behind the torso and the front bodice remains visible. This does not verify live pose stability or personal fit. The emulator's OpenGL output was corrupted and Vulkan capture was blank, so those captures are not accepted visual evidence. Dense morph buffers replace sparse accessors for importer compatibility; tests inspect actual position/delta floats for finite, bounded geometry. The original GLB and adapted GLB use the same named material alpha modes. Patchy overlapping lace, small side wrap tips and approximate lighting remain visible and are NOT considered solved. No claim of shop/product colour matching is made.

7 October adaptation: a bounded lower-skirt morph was added to the prepared GLB, preserving original rest geometry, existing morph data, textures and materials. It adjusts visual hem proportion only when both feet are confidently visible. The native renderer also has brighter neutral studio lighting and optional segmented foreground forearm/palm compositing. See `AR_REFINEMENT_2026_10_07.md` at the project root.

Limitations: frontal pose tracking and approximate visual morphing only; no cloth simulation, sleeve articulation or sizing prediction. Arm-mask accuracy is not yet validated on real people; this does not solve realistic turning or all crossed-arm cases. Use arms slightly apart for the supported preview. Lace transparency, neckline placement, fit morphs and lighting must be checked on the target phone. This is a demonstration asset, not verified shop stock.

Refinement (1 October): broaden the inner bodice from 1.9x to 2.1x without changing the lower train. Seat the upper front wrap 0–0.025 model units lower using smooth height/depth falloffs; the original wrap and neckline notch are retained, not deleted. Add independent chest/waist visual offsets to the existing automatic estimates, clamped to morph weights 0–1. They leave overall width/height transforms unchanged; lower skirt vertices outside the morph region are unaffected. Sliders appear only for the adaptive Princess asset, work while frozen, and sit in a scrollable controls panel capped at 65% of preview height. Their centre position restores the automatic estimate, not a real clothing size. The camera overlay does not remove the user's existing clothes.

Implementation reference: Filament 1.56.0 RenderableManager.setMorphWeights and getMorphTargetCount (https://github.com/google/filament/blob/v1.56.0/android/filament-android/src/main/java/com/google/android/filament/RenderableManager.java). Build/unit checks verify wiring and bounded math, not photographic realism.

Customer-flow revision (1 October): the manual dress/chest/waist/length adjustments described above are historical and no longer exposed in the customer UI. Automatic bounded estimates remain. Camera-only settings are optional; Preview starts a ten-second timer, Retake resumes tracking, and Save look records the actual camera/model composite locally. Saved looks can be viewed, compared and deleted from Profile. There is no synthetic fit score. See AR_SUBMISSION_CHECKLIST.md at the project root for evidence and outstanding real-user checks.

27 October / build 2094 material adaptation: `prepare_lace_cutout.py` changes Dress_Layer_1 and Dress_Layer_6 from BLEND to MASK with alphaCutoff=0.5 and normalTexture.scale=0.35. The GLB binary chunk is preserved byte-for-byte, including original textures, geometry and morph data. Cutout approximates lace holes and reduces overlapping transparency artifacts; it does not preserve full translucent tulle behavior. The runtime asset is updated; catalogue thumbnails have not been re-rendered. Fixed wrap geometry, photographic realism and cloth motion remain limitations. Creator attribution and CC BY 4.0 license above continue to apply.
