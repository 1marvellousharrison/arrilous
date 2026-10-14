import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// Rounded white/charcoal card used throughout the app.
class AppCard extends StatelessWidget {
  const AppCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Compact status pill, e.g. `Paid • Awaiting Delivery`.
class StatusPill extends StatelessWidget {
  const StatusPill({
    required this.label,
    required this.color,
    super.key,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline banner for form-level (non field-level) errors.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({required this.message, super.key, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}

/// Shown when a list has no content yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    super.key,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 34, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Six single-digit boxes with auto-advance, per the login spec.
class OtpCodeInput extends StatefulWidget {
  const OtpCodeInput({
    required this.length,
    required this.onCompleted,
    super.key,
    this.onChanged,
    this.hasError = false,
  });

  final int length;
  final ValueChanged<String> onCompleted;
  final ValueChanged<String>? onChanged;
  final bool hasError;

  @override
  State<OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<OtpCodeInput> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
    for (var i = 0; i < widget.length; i++) {
      _controllers[i].addListener(() => _onChanged(i));
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _value => _controllers.map((c) => c.text).join();

  void _onChanged(int index) {
    final text = _controllers[index].text.replaceAll(RegExp(r'\D'), '');
    if (text.length > 1) {
      // Pasted code: spread it across the boxes.
      _fill(text);
      return;
    }
    _controllers[index].text = text;

    setState(() {});
    widget.onChanged?.call(_value);

    if (text.isNotEmpty && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    if (_value.length == widget.length) {
      widget.onCompleted(_value);
    }
  }

  void _fill(String digits) {
    for (var i = 0; i < widget.length; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }
    setState(() {});
    widget.onChanged?.call(_value);
    if (_value.length == widget.length) {
      widget.onCompleted(_value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(widget.length, (index) {
        final filled = _controllers[index].text.isNotEmpty;
        return SizedBox(
          width: 46,
          child: TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 1,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              errorText: null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.field),
                borderSide: BorderSide(
                  color: widget.hasError
                      ? AppColors.danger
                      : filled
                          ? theme.colorScheme.primary
                          : theme.dividerColor,
                  width: filled ? 1.6 : 1,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.field),
                borderSide: BorderSide(
                  color: widget.hasError
                      ? AppColors.danger
                      : filled
                          ? theme.colorScheme.primary
                          : theme.dividerColor,
                  width: filled ? 1.6 : 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.field),
                borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.6),
              ),
            ),
            onChanged: (_) => _onChanged(index),
          ),
        );
      }),
    );
  }
}

/// The shop's logo when it has one, otherwise its first letter on a tinted
/// tile. The logo arrives as an image data URL on the profile, so it decodes
/// straight to memory; anything unreadable falls back to the letter rather than
/// throwing.
class BusinessLogoAvatar extends StatelessWidget {
  const BusinessLogoAvatar({
    required this.logoUrl,
    required this.name,
    super.key,
    this.size = 54,
    this.radius,
  });

  final String? logoUrl;
  final String name;
  final double size;
  final BorderRadius? radius;

  /// The bytes behind an image data URL, or null when there is none or it is
  /// malformed. Exposed so the setup flow can preview a saved logo too.
  static Uint8List? decode(String? dataUrl) {
    if (dataUrl == null) return null;
    final comma = dataUrl.indexOf(',');
    if (comma < 0) return null;
    try {
      return base64Decode(dataUrl.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = decode(logoUrl);
    final trimmed = name.trim();
    final letter = trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: radius ?? BorderRadius.circular(AppRadius.field),
      ),
      child: bytes != null
          ? Image.memory(bytes, width: size, height: size, fit: BoxFit.cover)
          : Text(
              letter,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.44,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

/// Shimmer-free skeleton block used while data loads.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.height = 16,
    this.width,
    this.radius = 8,
  });

  final double height;
  final double? width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
