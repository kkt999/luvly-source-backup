# Francine reference study

Reference dress: Rebecca Ingram Francine, style 23RB645.
This is an independently generated approximate visual reconstruction, not an official
manufacturer asset, garment pattern, product stock listing, or size/fit prediction.

## Sources inspected on 26 September 2026

- Designer description: https://www.maggiesottero.com/rebecca-ingram/francine/18883
- Front, back and train photographs visually inspected in the gallery:
  https://www.mybridalcloset.com/products/francine-by-rebecca-ingram-23rb645
- Additional indexed view descriptions:
  https://www.christianlanebridal.com/rebecca-ingram/fall-2023/23rb645

Observed design: strapless straight cuff, lower back neckline, smooth fitted
waist/hip silhouette, lower-skirt flare, swept train and covered rear buttons.
The model does not reuse the former sweetheart/A-line geometry.
No vendor photographs or textures are copied into the app. The catalogue image is
a locally rendered view of the actual GLB geometry. Reference links are attribution,
not evidence of manufacturer endorsement or publication rights clearance.

## Assumptions and limitations

All model dimensions are artistic estimates in metres. Hidden lining, exact seams,
train pattern, fabric response and physical fit cannot be recovered from these photos.
The cuff/back shape, skirt folds and button spacing are approximations. No rig,
cloth simulation, body occlusion or per-size assets are included. Reference study is
labelled not for sale; no actual product price or availability is claimed.

## Files and routing

- `build_francine.py`: reproducible Blender generator (creates a separate scene).
- `francine_reference.blend`: editable local source with studio preview setup.
- `../../assets/models/francine_reference.glb`: mobile asset, two mesh objects (continuous dress/cuff and rear buttons).
- `../../assets/images/francine_reference.jpg`: our front catalogue render.
- `francine_back.jpg`: our rear review render.
- Catalogue ID: `francine-reference`.

Flutter sends selected ID and asset path. Android resolves both against its explicit
allowlist and loads that asset. Unknown IDs, mismatched paths and absent models are
rejected; the original A-line asset is retained on disk but is no longer a fallback.
Other existing demo catalogue entries remain intact without AR models.

## Manual verification

Latest geometry refinement: shape-preserving cubic profile interpolation removes the artificial flat tangent at each profile ring while retaining the same artistic silhouette control points. An integrated rounded lower cuff fold makes the neckline band visible without reinstating a detached shell. Material colour/roughness and renderer lighting are unchanged. Model shoulder (1.49 m) and hip (0.97 m) anchors now define the torso scale consistently (0.52 m rather than the previous 0.50 m). These are model coordinates, not body measurements. Waist adaptation, fabric weave, body segmentation and occlusion are still not implemented; this does not eliminate all visible torso gaps.

26 September shading refinement: cuff integrated into the main surface instead of a floating overlapping shell; slightly cooler ivory base. Android uses a neutral directional key plus constant diffuse environment fill to reduce black side edges. This is fixed artistic lighting, not camera-derived illumination. Shoulder/hip anchor scaling is unchanged: a cropped frozen screenshot is insufficient to calibrate physical fit. Confirm brightness and neckline on the real phone, including freeze/resume and background/resume.

After a full Android rebuild: Dresses → Francine — reference study → AR try-on →
Start live try-on. Confirm the native tracking label names Francine, and the gown is
straight-necked and fitted instead of sweetheart/A-line. Test freeze, controls,
camera switching and resume. Select a different catalogue entry and confirm that
no camera/model opens from its unavailable-preview screen.
