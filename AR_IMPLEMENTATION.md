# Android live try-on prototype

> Current behavior and verification: [9 October safe dress switching and visual picker](AR_DRESS_SWITCH_2026_10_09.md), [8 October body-registered perspective AR](AR_BODY_REGISTRATION_2026_10_08.md), [tracking stability](AR_TRACKING_STABILITY_2026_10_08.md), and [7 October AR refinement](AR_REFINEMENT_2026_10_07.md). The sections below are historical implementation notes. In particular, screen-space-only alignment/no-yaw, the single-model mapping, manual-width slider, demo capture/history and original 10 FPS statements are no longer current. Live-person acceptance of the new 3D registration is still pending.

## Run

Open this same `luvly_unified` project in Android Studio. Fully stop the old app and run again on Android (native changes cannot be loaded by hot reload). Open a dress, choose **Preview try-on**, then **Start live try-on**. Grant camera permission yourself. A physical Android phone is recommended. Chrome still opens the staff/manager portal.

The Android debug review build has three explicitly allowlisted dress models. The visual picker shows the matching local reference image, style and current selection. No model is inferred from a catalogue name or external URL.

## Implemented

- Android method-channel launch, private native activity and runtime camera permission.
- CameraX image analysis with dropped stale frames and a maximum input rate of approximately 10 fps; actual speed depends on the device.
- Google MediaPipe Pose Landmarker Lite running on-device in VIDEO mode on a single worker. Frames are not uploaded or saved.
- Rotated/mirrored camera bitmap used consistently for both detection and display. FIT_CENTER mapping accounts for letterboxing.
- Visibility/presence checks for both shoulders and hips. Implausible and missing poses hide the garment; a 700 ms watchdog hides stale tracking.
- Filament rendering of the actual GLB on a transparent texture. Camera, 3D renderer and tracker lifecycle cleanup.
- Shoulder-width scaling, torso-height scaling, in-plane body lean and exponential smoothing. A manual width slider is visual calibration, not a clothing-size measurement.

## Alignment design

Let S be the midpoint of shoulders 11/12 and H the midpoint of hips 23/24, in display pixels with Y upward. Let W be shoulder distance and T = |S-H|.

| Quantity | Formula / design constant |
| --- | --- |
| Horizontal scale | W / 0.40 metres |
| Vertical scale | T / 0.50 metres |
| In-plane angle | atan2(-(Sx-Hx), Sy-Hy) |
| Shoulder model anchor | (0, 1.49, 0) in glTF coordinates |
| Smoothed value | previous + 0.35 × (new - previous) |
| Model transform | Translate(S) × RotateZ(angle) × Scale × Translate(0,-1.49,0) |

These are prototype calibration assumptions. They are not measured body dimensions. The model is front-facing; no world-space depth/yaw estimation, rigging or cloth deformation is implemented.

## Still required before claiming a completed AR feature

Build verification (21 September 2026): Android debug APK and web build succeeded; Flutter analysis reported no issues; 26 Flutter tests and the native alignment unit-test suite passed. APK contents were checked for both the GLB and pose model. No Android device was connected, so camera/renderer runtime behavior is not yet device-verified. The web build emitted a font-family warning for CupertinoIcons; this did not fail compilation.

1. Real-device validation: permission denial, front/back cameras, skin/clothing/background variations, portrait alignment, camera interruption, background/resume, back navigation and sustained performance.
2. Visual calibration of neckline/waist/hem on people; improve lighting/materials and dress detail.
3. Arm/person occlusion, sideways-body handling and 3D pose/deformation work if required by the project specification.
4. Genuine screenshot capture and saved history. Existing demo capture/history screens remain demo-only and are not connected to the live route.
5. Separate GLB assets and explicit catalogue-to-model mappings for additional dresses.

## Dependencies and provenance

### Selected-dress mapping (26 September 2026)

Latest geometry/anchor revision: neckline has a continuous rounded 4 mm artistic fold instead of a detached shell; shape-preserving cubic interpolation smooths the silhouette between the existing control points. The material base colour and lighting are unchanged. The actual model shoulder-to-hip anchor span (1.49 minus 0.97 = 0.52 metres) now drives vertical alignment, with a regression assertion that the model hip lands on the tracked hip midpoint. Waist deformation and fabric textures are not implemented, so visible gaps can remain. Generated GLB and catalogue render changed in this revision; hashes below describe the earlier colour-only revision, not these new files.

Latest colour-pipeline correction (supersedes the lighting values below): post-processing is enabled for proper display gamma/colour processing, with Filament PBRNeutralToneMapper for highlight compression. Neutral key is 50,000 lux and diffuse fill intensity 10,000, retaining the existing camera exposure. No colour grading tint, saturation adjustment or material recolouring is applied. Transparent clear/TextureView compositing remains enabled. These fixed studio settings are not colour calibration against a physical dress or the phone camera. Real-device transparency, highlights and fabric appearance must be checked after a full restart.

Dress GLB unchanged SHA-256: `4C99879F4F0F9CB95128A182E8FBE5AEB2D1E7121ED27E1861D8C8119489E284`; catalogue JPEG unchanged SHA-256: `85655F9C4EA250D3F7C65913EDD5A67C83BD7D90E0F58A1F8B3C79210E1FD742`. The material remains a reference approximation, not a manufacturer-approved colour measurement.

Phone-feedback refinement: neutral 80,000-lux directional light and 25,000-intensity constant diffuse IndirectLight replace the warm key-only setup. The fill is released during renderer cleanup. These are artistic settings, not measured room lighting. Francine now has one continuous shell/cuff plus rear buttons, with a less yellow ivory base; the former floating cuff mesh was removed. Studio render inspected, native unit tests and Android build passed. Final phone shading still needs user validation. Existing body anchor mapping remains unchanged pending full-body evidence.

The live route now requires an explicit catalogue dress ID and GLB path. Flutter passes both and Android validates them against ArDressCatalogue. Francine — reference study maps to assets/models/francine_reference.glb; unsupported dresses show an unavailable message rather than opening the old generic A-line model. The home try-on shortcut opens the catalogue. These changes supersede the original single-model routing described above.

The Francine model is an independent approximate study based on public front/back photographs, not an official asset, stocked product or fit prediction. The catalogue photograph is our own Blender render. See design/dresses/FRANCINE_REFERENCE.md for sources, assumptions, editable model and reproducible build script. No third-party product photography is embedded. Native model routing requires a full stop/rebuild; hot reload is insufficient. New model alignment still needs a physical-phone test.

Verification: 27 Flutter tests passed, analysis was clean, native unit tests and Android debug build succeeded. Web compilation succeeded with the existing CupertinoIcons font warning. Front/back Blender renders and the full-garment detail preview were visually inspected. No live phone validation of the Francine model was performed in this update.

### Camera controls (25 September 2026)

26 September refinement: the transparent dress TextureView is clipped to the FIT_CENTER camera-image bounds, retaining the existing full-view alignment coordinates. Unit tests cover top/bottom and side letterboxing. Frozen/live controls now include visual length (80–120%) and vertical offset calibration, in addition to width; these are not sizing predictions. The active GLB uses non-metallic ivory with roughness 0.8 to reduce harsh highlights. `design/dresses/soften_material.py` reapplies this material-only change after Blender export; the editable Blender source is unchanged. Real-device clipping, fabric appearance and calibration still require visual testing. No cloth simulation, body occlusion or measurement-based fitting is implied.

The preview now uses a compact header and bottom action row. Show controls opens an overlay, so toggling controls does not resize the image or pose coordinate system. Freeze in 10s hides controls and displays a cancellable countdown. At expiry, only a current tracked pose (last displayed within 700 ms) can be frozen. The displayed camera frame and aligned dress stay together in memory; inference frames are discarded while frozen. Dress width remains adjustable. Camera switching and zoom are disabled until Resume live. No snapshot is written or uploaded. Backgrounding the app cancels the timer and clears the frozen preview.

Manual acceptance checks: freeze a valid pose, approach the phone, open controls and adjust width; verify the background and pose do not move. Resume and verify tracking restarts. Try the timer without a visible body (must not freeze), cancel a countdown, and background the app during both countdown and frozen modes. These new interactions still require physical-device verification.

Live try-on now has front/rear switching, a camera zoom slider and a Widest view button. CameraX linear zoom 0 selects the minimum supported zoom on each newly opened camera; the label reports the actual zoom ratio and minimum. A minimum of 1x means that lens cannot zoom out further. The app does not simulate a wider field of view by shrinking the preview, or explicitly select a separate physical ultrawide lens. Dress width adjustment remains independent of camera zoom. Stale frames from a previous camera are ignored when switching.

Device checks: try both lenses, move the zoom slider and return to Widest view; verify dress alignment and front-camera mirroring; switch repeatedly, then background/resume the app. Use Android Studio mirroring to operate the controls while standing back. New native controls require a full stop and rebuild, not hot reload. Hardware zoom range and full-body alignment still require real-device verification.

- MediaPipe tasks-vision 0.10.21, model `pose_landmarker_lite/float16/1`.
- Model source: https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task
- Model SHA-256: `59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a`.
- Tracking API reference: https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/android
- Filament / gltfio 1.56.0, CameraX 1.4.2. Filament reference: https://github.com/google/filament/tree/v1.56.0/android
- Dress asset: original AI-assisted Blender procedural prototype; see `design/dresses/README.md`.

The pre-trained pose model is Google's model, not a model trained by this project. The project's custom logic is the validation, coordinate mapping, scaling, smoothing and integration. Retain dependency licence notices for distribution.
