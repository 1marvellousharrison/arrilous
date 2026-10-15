import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/data/nigeria.dart';
import '../../core/services/location_service.dart';
import '../../core/services/logo_service.dart';
import '../../core/state/business_repository.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/phone.dart';
import '../../widgets/common.dart';
import '../../widgets/nigeria_fields.dart';
import '../../widgets/phone_field.dart';

/// The categories an owner picks from at setup. A dropdown rather than a free
/// text field, so the same trade is spelled the same way on every dashboard.
/// 'Other' is the escape hatch: choosing it reveals a field where the owner
/// types a trade this list does not carry, and their wording is saved as-is.
const businessCategories = <String>[
  'Fashion & Clothing',
  'Groceries & Provisions',
  'Food & Restaurant',
  'Health & Beauty',
  'Electronics & Phones',
  'Home & Furniture',
  'Farm Produce',
  'Building Materials',
  'Books & Stationery',
  'Transport & Delivery',
  'Salon & Spa',
  'Services',
  'Other',
];

/// Phase 1 + 2 — the two-step owner setup flow.
///
/// Step 1 collects the business profile; step 2 confirms the shop location.
/// The owner can only reach the rest of the app after both are done, which is
/// why this flow is a gate rather than a settings page.
///
/// Location is best-effort: the device fix fills the coordinates, but a denied
/// permission, a disabled GPS or an unsupported platform all fall back to typing
/// the address, because refusing to let someone set up a shop over a permission
/// dialog would be a worse product than one that asks for an address.
class BusinessSetupFlow extends StatefulWidget {
  const BusinessSetupFlow({
    required this.business,
    required this.onComplete,
    this.locationService,
    this.logoService,
    super.key,
  });

  final BusinessRepository business;
  final VoidCallback onComplete;
  final LocationService? locationService;
  final LogoService? logoService;

  @override
  State<BusinessSetupFlow> createState() => _BusinessSetupFlowState();
}

class _BusinessSetupFlowState extends State<BusinessSetupFlow> {
  final _formKey = GlobalKey<FormState>();
  late final LocationService _location =
      widget.locationService ?? GeolocatorLocationService();
  late final LogoService _logoService =
      widget.logoService ?? const DeviceLogoService();

  final _name = TextEditingController();
  String? _category;
  // The typed-in answer behind the 'Other' choice, kept apart from the list
  // so a custom trade never leaks into the dropdown itself.
  final _otherCategory = TextEditingController();
  // "What you sell" is a list of points, not one paragraph: the owner adds
  // each thing they sell with the plus button and the points are stored one
  // per line so they come back as points when the profile is edited.
  final List<String> _sells = [];
  final _sell = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();

  // The logo the owner picked, kept as both the image data URL that is saved
  // and the raw bytes the preview paints. Null means "no logo", which is a
  // valid choice: the profile falls back to the first letter of the name.
  String? _logo;
  Uint8List? _logoBytes;
  bool _pickingLogo = false;

  int _step = 0;
  bool _submitting = false;
  String? _formError;
  final Map<String, String> _fieldErrors = {};

  // Step 2
  final _address = TextEditingController();
  final _area = TextEditingController();
  // State and city are picked from dropdowns, so they are plain values rather
  // than controllers: the city list is rebuilt whenever the state changes.
  String? _city;
  String? _state;
  DeviceCoordinates? _coordinates;
  bool _locating = false;
  LocationUnavailable? _locationProblem;

  bool get _isEditing => widget.business.hasProfile;

  /// The dropdown choices. A profile saved before this list existed can carry
  /// any wording, so the owner's own category is kept in the list rather than
  /// showing the field as empty.
  List<String> get _categoryOptions {
    final selected = _category;
    if (selected == null ||
        selected.trim().isEmpty ||
        businessCategories.contains(selected)) {
      return businessCategories;
    }
    return [...businessCategories, selected];
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.business.business;
    if (existing != null) {
      _name.text = existing.businessName;
      _category = existing.businessCategory;
      _sells.addAll(
        (existing.businessDescription ?? '')
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty),
      );
      _phone.text = formatNationalPhone(existing.phone ?? '');
      _email.text = existing.email ?? '';
      _logo = existing.logoUrl;
      _logoBytes = BusinessLogoAvatar.decode(existing.logoUrl);
      final location = existing.location;
      if (location != null) {
        _address.text = location.address;
        _area.text = location.area ?? '';
        _city = location.city;
        _state = location.state;
        if (location.hasCoordinates) {
          _coordinates = DeviceCoordinates(
            latitude: location.latitude!,
            longitude: location.longitude!,
          );
        }
      }
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _otherCategory,
      _sell,
      _phone,
      _email,
      _address,
      _area,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Business settings' : 'Set up your business'),
        leading: _step == 1
            ? IconButton(
                tooltip: 'Back to business details',
                onPressed: _submitting ? null : () => setState(() => _step = 0),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _StepBar(current: _step),
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: _step == 0
                      ? _profileStep(theme)
                      : _locationStep(theme),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The logo tile beside the picker. It shows the picked image, or the first
  /// letter of whatever name has been typed so far, so the owner sees the exact
  /// fallback the profile will use.
  Widget _logoBox(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: InkWell(
        onTap: _pickingLogo ? null : _pickLogo,
        child: SizedBox(
          width: 64,
          height: 64,
          child: _logoBytes != null
              ? Image.memory(_logoBytes!, fit: BoxFit.cover)
              : Container(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  alignment: Alignment.center,
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _name,
                    builder: (context, value, _) {
                      final typed = value.text.trim();
                      if (typed.isEmpty) {
                        return Icon(
                          Icons.storefront_outlined,
                          color: theme.colorScheme.primary,
                        );
                      }
                      return Text(
                        typed.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          color: theme.colorScheme.primary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }

  List<Widget> _profileStep(ThemeData theme) {
    return [
      Text(
        'Tell customers who you are',
        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'This is what appears on your business page. You can change it later.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      if (_formError != null) ...[
        ErrorBanner(message: _formError!),
        const SizedBox(height: AppSpacing.lg),
      ],
      TextFormField(
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: 'Business name',
          hintText: 'Ada Provisions',
          errorText: _fieldErrors['business_name'],
        ),
        validator: (value) =>
            (value == null || value.trim().length < 2) ? 'Enter your business name.' : null,
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _logoBox(theme),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Business logo (optional)',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pick an image, or leave it empty to use the first letter '
                  'of your name.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: _pickingLogo ? null : _pickLogo,
                      icon: _pickingLogo
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: Text(_logo == null ? 'Add logo' : 'Change'),
                    ),
                    if (_logo != null)
                      TextButton.icon(
                        onPressed: _pickingLogo ? null : _removeLogo,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Remove'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      DropdownButtonFormField<String>(
        initialValue: _category,
        hint: const Text('Choose a category'),
        decoration: InputDecoration(
          labelText: 'Category',
          // While 'Other' is selected the server's message belongs on the
          // field the owner actually types into, not on the choice list.
          errorText:
              _category == 'Other' ? null : _fieldErrors['business_category'],
        ),
        items: [
          for (final option in _categoryOptions)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        validator: (value) =>
            (value == null || value.trim().isEmpty) ? 'Choose a category.' : null,
        onChanged: (value) => setState(() => _category = value),
      ),
      if (_category == 'Other') ...[
        const SizedBox(height: AppSpacing.lg),
        TextFormField(
          controller: _otherCategory,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Your own category',
            hintText: 'e.g. Baby products',
            errorText: _fieldErrors['business_category'],
          ),
          validator: (value) => (value ?? '').trim().isEmpty
              ? 'Type the category you sell under.'
              : null,
        ),
      ],
      const SizedBox(height: AppSpacing.lg),
      Text(
        'What do you sell?',
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      if (_fieldErrors['business_description'] != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          _fieldErrors['business_description']!,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        ),
      ],
      const SizedBox(height: AppSpacing.sm),
      for (final item in _sells)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(item)),
              IconButton(
                tooltip: 'Remove',
                onPressed: () => setState(() => _sells.remove(item)),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
        ),
      Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: _sell,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Add what you sell',
                hintText: 'e.g. Rice, shoes, fabrics',
                errorText: _fieldErrors['business_description'],
              ),
              validator: (value) => (_sells.isEmpty && (value ?? '').trim().isEmpty)
                  ? 'Tell us what you sell.'
                  : null,
              onFieldSubmitted: (_) => _addSell(),
            ),
          ),
          IconButton(
            tooltip: 'Add another thing you sell',
            onPressed: _addSell,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      // The field is pinned to '+234 *** *** ****': the code sits in the
      // prefix and the shared field keeps the ten national digits, spaced
      // 3-3-4, as the only thing that can ever be typed or pasted here.
      NigerianPhoneField(
        controller: _phone,
        errorText: _fieldErrors['phone'],
      ),
      const SizedBox(height: AppSpacing.lg),
      TextFormField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: 'Business email (optional)',
          errorText: _fieldErrors['email'],
        ),
      ),
      const SizedBox(height: AppSpacing.xl),
      FilledButton(
        onPressed: _submitting ? null : _saveProfile,
        child: _submitting
            ? const _ButtonSpinner()
            : Text(_isEditing ? 'Save and continue' : 'Continue'),
      ),
    ];
  }

  List<Widget> _locationStep(ThemeData theme) {
    return [
      Text(
        'Where is your shop?',
        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Customers see this address, and the delivery partner reads your city, '
        'area and state to reach you. We use your location only to fill it in.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      OutlinedButton.icon(
        onPressed: _locating || _submitting ? null : _useCurrentLocation,
        icon: _locating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.my_location),
        label: Text(_locating ? 'Finding you...' : 'Use my current location'),
      ),
      if (_locationProblem != null) ...[
        const SizedBox(height: AppSpacing.md),
        _LocationNotice(problem: _locationProblem!),
      ],
      if (_coordinates != null) ...[
        const SizedBox(height: AppSpacing.md),
        _CoordinatesChip(
          coordinates: _coordinates!,
          onRemove: () => setState(() => _coordinates = null),
        ),
      ],
      const SizedBox(height: AppSpacing.xl),
      if (_formError != null) ...[
        ErrorBanner(message: _formError!),
        const SizedBox(height: AppSpacing.lg),
      ],
      TextFormField(
        controller: _address,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: 'Street address',
          hintText: '12 Allen Avenue',
          errorText: _fieldErrors['address'],
        ),
        validator: (value) => (value == null || value.trim().length < 3)
            ? 'Enter the street address.'
            : null,
      ),
      const SizedBox(height: AppSpacing.lg),
      TextFormField(
        controller: _area,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: 'Area',
          hintText: 'Ikeja GRA, Marina, Yaba...',
          errorText: _fieldErrors['area'],
        ),
        validator: (value) => (value == null || value.trim().isEmpty)
            ? 'Enter the area your shop is in.'
            : null,
      ),
      const SizedBox(height: AppSpacing.lg),
      NigerianStateDropdown(
        value: _state,
        errorText: _fieldErrors['state'],
        onChanged: (value) => setState(() {
          _state = value;
          // A town from the previous state no longer belongs here.
          if (_city != null && !citiesForState(value).contains(_city)) {
            _city = null;
          }
        }),
      ),
      const SizedBox(height: AppSpacing.lg),
      NigerianCityDropdown(
        state: _state,
        value: _city,
        errorText: _fieldErrors['city'],
        onChanged: (value) => setState(() => _city = value),
      ),
      const SizedBox(height: AppSpacing.xl),
      FilledButton(
        onPressed: _submitting ? null : _saveLocation,
        child: _submitting
            ? const _ButtonSpinner()
            : Text(widget.business.hasLocation ? 'Update location' : 'Finish setup'),
      ),
    ];
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _locationProblem = null;
    });

    final coordinates = await _location.current();
    final failure = await _location.lastFailure();

    if (!mounted) return;
    setState(() {
      _locating = false;
      if (coordinates != null) {
        _coordinates = coordinates;
      } else {
        _locationProblem = failure;
      }
    });
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Whatever is still typed into the "add" field counts as a point: an owner
    // who types one last thing and presses continue should not lose it.
    _flushSell();

    setState(() {
      _submitting = true;
      _formError = null;
      _fieldErrors.clear();
    });

    try {
      // 'Other' means the list had no answer, so the owner's own wording is
      // what gets saved — their category works exactly like a listed one.
      final category =
          _category == 'Other' ? _otherCategory.text.trim() : (_category?.trim() ?? '');
      final phone = toNigerianE164(_phone.text);
      if (_isEditing) {
        await widget.business.updateProfile(
          businessName: _name.text.trim(),
          category: category,
          description: _sells.join('\n'),
          phone: phone,
          email: _email.text.trim(),
          // An empty string clears a removed logo; a data URL sets it.
          logo: _logo ?? '',
        );
      } else {
        await widget.business.createProfile(
          businessName: _name.text.trim(),
          category: category,
          description: _sells.join('\n'),
          phone: phone,
          email: _email.text.trim(),
          logo: _logo ?? '',
        );
      }
      if (!mounted) return;
      setState(() => _step = 1);
    } on ApiException catch (error) {
      _applyError(error);
    } on NetworkException catch (error) {
      if (!mounted) return;
      setState(() => _formError = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _saveLocation() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Everything the partner and the rider read is in the form now. The owner
    // confirms it once, and only then is it saved and handed back the main
    // page — nobody should leave setup unsure of what they just sent.
    final correct = await _confirmDetails();
    if (!mounted || !correct) return;

    setState(() {
      _submitting = true;
      _formError = null;
      _fieldErrors.clear();
    });

    try {
      await widget.business.saveLocation(
        address: _address.text.trim(),
        area: _area.text.trim(),
        city: _city?.trim() ?? '',
        state: _state?.trim() ?? '',
        latitude: _coordinates?.latitude,
        longitude: _coordinates?.longitude,
      );
      if (!mounted) return;
      widget.onComplete();
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on ApiException catch (error) {
      _applyError(error);
    } on NetworkException catch (error) {
      if (!mounted) return;
      setState(() => _formError = error.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<bool> _confirmDetails() async {
    final correct = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Are your details correct?'),
        content: const Text(
          'Check your business name, contact, what you sell and your shop '
          'location. They are saved and you go back once you confirm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No, let me review'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, take me back'),
          ),
        ],
      ),
    );
    return correct ?? false;
  }

  Future<void> _pickLogo() async {
    setState(() => _pickingLogo = true);
    try {
      final bytes = await _logoService.pick();
      if (!mounted || bytes == null) return;
      setState(() {
        _logoBytes = bytes;
        _logo = 'data:image/png;base64,${base64Encode(bytes)}';
      });
    } finally {
      if (mounted) setState(() => _pickingLogo = false);
    }
  }

  void _removeLogo() {
    setState(() {
      _logo = null;
      _logoBytes = null;
    });
  }

  void _addSell() {
    final item = _sell.text.trim();
    if (item.isEmpty) return;
    setState(() {
      if (!_sells.contains(item)) _sells.add(item);
      _sell.clear();
      _fieldErrors.remove('business_description');
    });
  }

  void _flushSell() {
    final item = _sell.text.trim();
    if (item.isNotEmpty && !_sells.contains(item)) _sells.add(item);
    _sell.clear();
  }

  void _applyError(ApiException error) {
    if (!mounted) return;
    setState(() {
      _fieldErrors
        ..clear()
        ..addEntries(
          (error.details ?? const <FieldError>[]).map(
            (detail) => MapEntry(detail.field, detail.message),
          ),
        );
      _formError = error.details == null || error.details!.isEmpty
          ? error.message
          : null;
    });
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    const labels = ['Business', 'Location'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final active = index <= current;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: index == labels.length - 1 ? 0 : AppSpacing.sm),
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              decoration: BoxDecoration(
                color: active
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '${index + 1}. ${labels[index]}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: active
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
      );
}

class _LocationNotice extends StatelessWidget {
  const _LocationNotice({required this.problem});

  final LocationUnavailable problem;

  @override
  Widget build(BuildContext context) {
    final message = switch (problem) {
      LocationUnavailable.permissionDenied =>
        'Location permission was declined. Type your address below instead.',
      LocationUnavailable.servicesDisabled =>
        'Location services are off on this device. Type your address below instead.',
      LocationUnavailable.unavailable =>
        'Could not read your location right now. Type your address below instead.',
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_off_outlined, color: AppColors.warning, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.warning, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordinatesChip extends StatelessWidget {
  const _CoordinatesChip({required this.coordinates, required this.onRemove});

  final DeviceCoordinates coordinates;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Icon(Icons.check_circle, color: AppColors.success, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Pin added: ${coordinates.latitude.toStringAsFixed(4)}, '
            '${coordinates.longitude.toStringAsFixed(4)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Remove pin',
          onPressed: onRemove,
          icon: const Icon(Icons.close, size: 18),
        ),
      ],
    );
  }
}
