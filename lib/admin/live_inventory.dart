import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../catalogue/dress_photo_data.dart';
import '../catalogue/ar_models.dart';
import '../catalogue/catalogue_repository.dart';
import '../catalogue/catalogue_widgets.dart';
import '../catalogue/dress_ar_api.dart';
import '../catalogue/variant_stock_screen.dart';
import '../payments/payment_api.dart';
import 'design.dart';
import 'model.dart';
import 'inventory_workspace.dart';
import 'dress_ar_dialog.dart';

class LiveInventoryPage extends StatefulWidget {
  const LiveInventoryPage({super.key});
  @override
  State<LiveInventoryPage> createState() => _LiveInventoryPageState();
}

class _LiveInventoryPageState extends State<LiveInventoryPage> {
  final listState = InventoryListState();
  String? selectedId;
  bool unpublishing = false;
  bool deleting = false;
  bool get changingDress => unpublishing || deleting;

  Future<void> edit(CatalogueDress? dress) async {
    final model = PortalScope.of(context);
    if (!model.isManager || changingDress) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DressEditor(
        repository: CatalogueScope.of(context),
        actorUid: model.current!.id,
        dress: dress,
      ),
    );
    if (mounted && saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dress saved.')));
    }
  }

  void stock(CatalogueDress dress) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => VariantStockScreen(dress: dress)),
  );

  Future<void> unpublish(CatalogueDress dress) async {
    final model = PortalScope.of(context);
    if (!model.isManager || !dress.published || changingDress) return;
    final repository = CatalogueScope.of(context);
    final actorUid = model.current!.id;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Unpublish dress?'),
        content: Text(
          'Hide ${dress.name} from the customer catalogue. You can publish it again from Edit Dress.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Unpublish'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || changingDress) return;
    setState(() => unpublishing = true);
    var message = 'Dress unpublished.';
    try {
      await repository.save(
        CatalogueDress.fromFields(dress.id, {
          ...dress.toFields(),
          'revision': dress.revision,
          'published': false,
        }),
        actorUid: actorUid,
      );
    } catch (error) {
      message = error is StateError
          ? error.message
          : 'Could not unpublish the dress. Check your connection and try again.';
    }
    if (!mounted) return;
    setState(() => unpublishing = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> delete(CatalogueDress dress) async {
    if (!PortalScope.of(context).isManager || changingDress) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Permanently delete dress?'),
        content: Text(
          'Delete ${dress.name} and its stock records? This action is permanent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialog).colorScheme.error,
              foregroundColor: Theme.of(dialog).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || changingDress) return;
    setState(() => deleting = true);
    final api = HttpPaymentApi();
    var deleted = false;
    var message = 'Dress deleted.';
    try {
      final result = await api.businessRequest(
        '/v1/dresses/${Uri.encodeComponent(dress.id)}/delete',
        body: {'revision': dress.revision},
      );
      deleted = result is Map && result['deleted'] == true;
      if (!deleted) {
        message = 'Could not confirm deletion. Refresh the inventory.';
      }
    } on PaymentFailure catch (error) {
      message = error.code == 'NOT_FOUND'
          ? 'Dress deletion needs the updated inventory service.'
          : error.message;
    } catch (_) {
      message =
          'Could not delete the dress. Check your connection and try again.';
    } finally {
      api.close();
    }
    if (!mounted) return;
    setState(() {
      deleting = false;
      if (deleted && selectedId == dress.id) selectedId = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final manager = PortalScope.of(context).isManager;
    return CatalogueFeed(
      inventory: true,
      builder: (context, snapshot) {
        CatalogueDress? selected;
        for (final dress in snapshot.dresses) {
          if (dress.id == selectedId) selected = dress;
        }
        final g = selected;
        return PageBody(
          key: PageStorageKey(
            selectedId == null
                ? 'inventory-list'
                : 'inventory-detail-$selectedId',
          ),
          children: [
            Heading(
              'Dress inventory',
              manager
                  ? 'Manage catalogue details and open size-level stock records.'
                  : 'Browse catalogue details and check size-level stock. Catalogue editing is manager-only.',
              action: manager && selectedId == null
                  ? FilledButton.icon(
                      onPressed: snapshot.fromCache ? null : () => edit(null),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Dress'),
                    )
                  : null,
            ),
            if (snapshot.fromCache) ...[
              const Text(
                'Offline or reconnecting · Showing cached dresses. Saving requires a connection.',
                style: TextStyle(color: muted),
              ),
              gap(16),
            ],
            if (selectedId == null)
              InventoryWorkspace(
                records: snapshot.dresses,
                state: listState,
                cached: snapshot.fromCache,
                onView: (d) => setState(() => selectedId = d.id),
                onStock: stock,
                onEdit: manager ? (d) => edit(d) : null,
              )
            else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => selectedId = null),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to inventory'),
                ),
              ),
              gap(16),
              if (g == null)
                const Panel(
                  child: Text(
                    'This dress is no longer in the current catalogue. Return to the inventory to choose another record.',
                  ),
                )
              else
                ResponsiveGrid(
                  minWidth: 340,
                  children: [
                    Panel(child: CatalogueDressPhoto(dress: g, height: 350)),
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.name,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          gap(12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              Pill(g.published ? 'Published' : 'Unpublished'),
                              Pill(g.availability),
                            ],
                          ),
                          gap(20),
                          Info('Style', g.category),
                          Info('Colour', g.colour),
                          Info('Sizes', g.sizes),
                          Info('Price', g.priceLabel),
                          Info(
                            'Visibility',
                            g.published ? 'Published' : 'Visible to staff only',
                          ),
                          gap(12),
                          Text(g.description),
                          gap(16),
                          Text(
                            resolveCatalogueArDress(g.arModelId) == null
                                ? 'No prepared AR model linked.'
                                : 'AR model: ${resolveCatalogueArDress(g.arModelId)!.name}',
                          ),
                          gap(20),
                          const Text(
                            'Catalogue status is not a stock reservation. Check physical stock by size; rental availability also depends on dates and cleaning.',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          gap(16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => stock(g),
                                icon: const Icon(Icons.inventory_2_outlined),
                                label: const Text('Stock by size'),
                              ),
                              if (manager)
                                FilledButton(
                                  onPressed: snapshot.fromCache || changingDress
                                      ? null
                                      : () => edit(g),
                                  child: const Text('Edit Dress'),
                                ),
                              if (manager && g.published)
                                OutlinedButton.icon(
                                  onPressed: snapshot.fromCache || changingDress
                                      ? null
                                      : () => unpublish(g),
                                  icon: const Icon(
                                    Icons.visibility_off_outlined,
                                  ),
                                  label: const Text('Unpublish dress'),
                                ),
                              if (manager)
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    foregroundColor: Theme.of(
                                      context,
                                    ).colorScheme.error,
                                  ),
                                  onPressed: snapshot.fromCache || changingDress
                                      ? null
                                      : () => delete(g),
                                  icon: const Icon(Icons.delete_outline),
                                  label: const Text('Delete dress'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ],
        );
      },
    );
  }
}

class DressEditor extends StatefulWidget {
  const DressEditor({
    super.key,
    required this.repository,
    required this.actorUid,
    this.dress,
    this.pickPhoto = selectDressPhoto,
  });
  final CatalogueRepository repository;
  final String actorUid;
  final CatalogueDress? dress;
  final Future<XFile?> Function() pickPhoto;
  @override
  State<DressEditor> createState() => _DressEditorState();
}

class _DressEditorState extends State<DressEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, description, price;
  final photoField = GlobalKey<FormFieldState<bool>>();
  DressPhotoData? selectedPhoto;
  bool removePhoto = false, preparingPhoto = false;
  String? photoError;
  bool get hasPhoto =>
      selectedPhoto != null ||
      (!removePhoto &&
          ((widget.dress?.photoRevision ?? 0) > 0 ||
              (widget.dress?.imageUrl.isNotEmpty ?? false)));
  String? colour;
  final selectedSizes = <String>{};
  bool confirmedHighPrice = false;
  String arModelId = '';
  bool confirmedArModel = false;
  bool generateTryOn = false;
  late final String id;
  late String category, availability;
  late bool published;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final d = widget.dress;
    id = d?.id ?? widget.repository.newId();
    name = TextEditingController(text: d?.name ?? '');
    description = TextEditingController(text: d?.description ?? '');
    colour = dressColours.contains(d?.colour) ? d!.colour : null;
    if (d != null && validDressSizes(d.sizes)) {
      selectedSizes.addAll(d.sizes.split(', '));
    }
    price = TextEditingController(
      text: d == null ? '' : (d.priceCents / 100).toStringAsFixed(2),
    );
    category = d?.category ?? dressCategories.first;
    availability = d?.availability ?? 'Available';
    published = d?.published ?? false;
    arModelId = d?.arModelId ?? '';
    confirmedArModel =
        arModelId.isNotEmpty && resolveCatalogueArDress(arModelId) != null;
  }

  @override
  void dispose() {
    for (final c in [name, description, price]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> choosePhoto() async {
    if (busy) return;
    setState(() {
      busy = true;
      preparingPhoto = true;
      photoError = null;
    });
    try {
      final file = await widget.pickPhoto();
      if (file == null || !mounted) return;
      // Let the preparation state paint before decoding on web.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final photo = await prepareDressPhoto(file);
      if (!mounted) return;
      setState(() {
        selectedPhoto = photo;
        removePhoto = false;
        confirmedArModel = false;
      });
      photoField.currentState?.validate();
    } catch (e) {
      if (mounted) {
        setState(
          () => photoError = e is FormatException
              ? e.message
              : 'Could not open this photo. Please choose it again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          preparingPhoto = false;
        });
      }
    }
  }

  Future<void> save({bool manageTryOn = false}) async {
    if (busy || !form.currentState!.validate()) return;
    if (generateTryOn) {
      final confirmed = await confirmDressArGeneration(
        context,
        credits: dressArEstimatedCredits,
        saveFirst: true,
      );
      if (!mounted || !confirmed || busy) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    final photoRevision = selectedPhoto != null
        ? (widget.dress?.revision ?? 0) + 1
        : removePhoto
        ? 0
        : (widget.dress?.photoRevision ?? 0);
    try {
      await widget.repository.save(
        CatalogueDress(
          id: id,
          name: name.text.trim(),
          category: category,
          description: description.text.trim(),
          productDetails: widget.dress?.productDetails ?? const {},
          colour: colour!,
          sizes: dressSizes.where(selectedSizes.contains).join(', '),
          priceCents: parsePriceCents(price.text)!,
          imageUrl: selectedPhoto != null || removePhoto
              ? ''
              : (widget.dress?.imageUrl ?? ''),
          photoRevision: photoRevision,
          availability: availability,
          published: published,
          revision: widget.dress?.revision ?? 0,
          arModelId: arModelId,
        ),
        actorUid: widget.actorUid,
        photo: selectedPhoto,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = e is StateError
              ? e.message
              : 'Could not save. Check your connection and manager access, then retry. Your entries are still here.';
        });
      }
      return;
    }
    if (!mounted) return;
    if ((generateTryOn || manageTryOn) && photoRevision > 0) {
      await showDialog<void>(
        context: context,
        builder: (_) => DressArDialog(
          uid: widget.actorUid,
          dressId: id,
          photoRevision: photoRevision,
          generateOnOpen: generateTryOn,
        ),
      );
    }
    if (mounted) Navigator.pop(context, true);
  }

  Widget field(
    String label,
    TextEditingController controller,
    int max, {
    int lines = 1,
    int min = 3,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      enabled: !busy,
      maxLength: max,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        alignLabelWithHint: lines > 1,
      ),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) =>
          validateDressText(v ?? '', label.toLowerCase(), min, max),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.dress == null ? 'Add Dress' : 'Edit Dress'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                field('Dress name', name, 100),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Style'),
                  items: dressCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: busy ? null : (v) => setState(() => category = v!),
                ),
                gap(16),
                if (widget.dress != null &&
                    (!dressColours.contains(widget.dress!.colour) ||
                        !validDressSizes(widget.dress!.sizes)))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Previous colour: ${widget.dress!.colour}. Previous sizes: ${widget.dress!.sizes}. Select the matching options below; use the description for exact sizing or colour details.',
                    ),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: colour,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Colour'),
                  items: dressColours
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: busy ? null : (v) => setState(() => colour = v),
                  validator: (v) => dressColours.contains(v)
                      ? null
                      : 'Select the actual dress colour',
                ),
                gap(16),
                FormField<bool>(
                  validator: (_) => selectedSizes.isEmpty
                      ? 'Select at least one available size'
                      : null,
                  builder: (state) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Available sizes'),
                      const Text(
                        'Choose stock sizes, or Made to measure. Add exact measurements in the description.',
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final size in dressSizes)
                            FilterChip(
                              label: Text(size),
                              selected: selectedSizes.contains(size),
                              onSelected: busy
                                  ? null
                                  : (selected) {
                                      setState(() {
                                        if (selected) {
                                          if (size == 'Made to measure') {
                                            selectedSizes.clear();
                                          } else {
                                            selectedSizes.remove(
                                              'Made to measure',
                                            );
                                          }
                                          selectedSizes.add(size);
                                        } else {
                                          selectedSizes.remove(size);
                                        }
                                      });
                                      state.didChange(selectedSizes.isNotEmpty);
                                      state.validate();
                                    },
                            ),
                        ],
                      ),
                      if (state.hasError)
                        Text(
                          state.errorText!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
                gap(16),
                TextFormField(
                  controller: price,
                  enabled: !busy,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Price (RM)',
                    counterText: '',
                  ),
                  maxLength: 10,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  onChanged: (_) => setState(() => confirmedHighPrice = false),
                  validator: (v) => parsePriceCents(v ?? '') == null
                      ? 'Enter RM 0.01–1,000,000, with up to two decimal places'
                      : null,
                ),
                if ((parsePriceCents(price.text) ?? 0) > 1000000)
                  FormField<bool>(
                    validator: (_) => confirmedHighPrice
                        ? null
                        : 'Confirm this unusually high price before saving',
                    builder: (state) => Column(
                      children: [
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'I checked the price: RM ${((parsePriceCents(price.text) ?? 0) / 100).toStringAsFixed(2)}',
                          ),
                          subtitle: const Text(
                            'Prices above RM 10,000 require a second check.',
                          ),
                          value: confirmedHighPrice,
                          onChanged: busy
                              ? null
                              : (v) {
                                  setState(
                                    () => confirmedHighPrice = v ?? false,
                                  );
                                  state.didChange(confirmedHighPrice);
                                  state.validate();
                                },
                        ),
                        if (state.hasError)
                          Text(
                            state.errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                gap(16),
                field('Description', description, 3000, lines: 4, min: 20),
                FormField<bool>(
                  key: photoField,
                  validator: (_) {
                    if (generateTryOn && selectedPhoto == null) {
                      return 'Upload a photo to generate AR try-on';
                    }
                    return published && !hasPhoto
                        ? 'Add a photo before publishing'
                        : null;
                  },
                  builder: (state) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Dress photo'),
                      const Text(
                        'JPG or PNG · up to 5 MB. Choose a photo you have permission to use.',
                      ),
                      gap(8),
                      if (selectedPhoto != null) ...[
                        Image.memory(
                          selectedPhoto!.imageBytes,
                          height: 220,
                          width: double.infinity,
                          fit: BoxFit.contain,
                          semanticLabel: 'Selected dress photo preview',
                        ),
                        const Text('New photo · saved with the dress'),
                      ] else if (hasPhoto)
                        CatalogueDressPhoto(
                          dress: widget.dress!,
                          repository: widget.repository,
                          height: 220,
                        )
                      else
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('No photo selected'),
                        ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: busy ? null : choosePhoto,
                            icon: const Icon(Icons.upload_outlined),
                            label: Text(
                              preparingPhoto
                                  ? 'Preparing photo…'
                                  : hasPhoto
                                  ? 'Replace photo'
                                  : 'Upload photo',
                            ),
                          ),
                          if (hasPhoto)
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      setState(() {
                                        selectedPhoto = null;
                                        removePhoto = true;
                                        photoError = null;
                                      });
                                      state.validate();
                                    },
                              child: const Text('Remove photo'),
                            ),
                          if ((selectedPhoto != null || removePhoto) &&
                              widget.dress != null)
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      setState(() {
                                        selectedPhoto = null;
                                        removePhoto = false;
                                        photoError = null;
                                      });
                                      state.validate();
                                    },
                              child: const Text('Undo photo change'),
                            ),
                        ],
                      ),
                      if (photoError != null || state.hasError)
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            photoError ?? state.errorText!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                gap(12),
                if (widget.dress == null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('AR try-on'),
                    subtitle: Text(
                      generateTryOn
                          ? 'Tripo generates a 3D model from the dress photo. About $dressArEstimatedCredits API credits.'
                          : 'Add a 3D try-on for this dress.',
                    ),
                    value: generateTryOn,
                    onChanged: busy
                        ? null
                        : (value) {
                            setState(() => generateTryOn = value);
                            if (!value) photoField.currentState?.validate();
                          },
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    initialValue: availability,
                    decoration: const InputDecoration(
                      labelText: 'Availability',
                    ),
                    items: dressAvailability
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (v) => setState(() => availability = v!),
                  ),
                  gap(12),
                  DropdownButtonFormField<String>(
                    initialValue: resolveCatalogueArDress(arModelId) == null
                        ? ''
                        : arModelId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'AR model (optional)',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('No AR model'),
                      ),
                      for (final model in catalogueArModels)
                        DropdownMenuItem(
                          value: model.id!,
                          child: Text(
                            model.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (value) => setState(() {
                            arModelId = value ?? '';
                            confirmedArModel = false;
                          }),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Link an existing model or save an uploaded photo to generate one with Tripo.',
                    ),
                  ),
                  if (resolveCatalogueArDress(arModelId) != null) ...[
                    gap(12),
                    Image.asset(
                      'assets/images/${resolveCatalogueArDress(arModelId)!.asset}.jpg',
                      height: 140,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      semanticLabel: 'Selected AR model render',
                    ),
                    FormField<bool>(
                      validator: (_) => confirmedArModel
                          ? null
                          : 'Check that the selected model represents this dress',
                      builder: (state) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: confirmedArModel,
                            title: const Text(
                              'I checked this model against the dress and photo.',
                            ),
                            onChanged: busy
                                ? null
                                : (value) {
                                    setState(
                                      () => confirmedArModel = value ?? false,
                                    );
                                    state.validate();
                                  },
                          ),
                          if (state.hasError)
                            Text(
                              state.errorText!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
                gap(12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Publish to bride catalogue'),
                  subtitle: Text(
                    published
                        ? 'Brides will see this dress after saving.'
                        : 'Only staff can see this gown.',
                  ),
                  value: published,
                  onChanged: busy ? null : (v) => setState(() => published = v),
                ),
                const Text(
                  'To remove a dress from the bride catalogue, turn publishing off and save. Its record is kept.',
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (widget.dress != null &&
            arModelId.isEmpty &&
            (selectedPhoto != null ||
                (!removePhoto && (widget.dress?.photoRevision ?? 0) > 0)))
          OutlinedButton(
            onPressed: busy ? null : () => save(manageTryOn: true),
            child: const Text('Save & manage 3D try-on'),
          ),
        FilledButton(
          onPressed: busy ? null : () => save(),
          child: Text(
            preparingPhoto
                ? 'Preparing photo…'
                : busy
                ? 'Saving…'
                : generateTryOn
                ? 'Save & generate AR'
                : 'Save Dress',
          ),
        ),
      ],
    ),
  );
}
