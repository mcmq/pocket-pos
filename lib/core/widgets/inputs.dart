import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Pill-shaped search field with a leading search icon and an optional
/// trailing action (scan).
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.controller,
    this.trailingIcon,
    this.trailingTooltip,
    this.onTrailing,
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final IconData? trailingIcon;
  final String? trailingTooltip;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(Icons.search, color: c.textSecondary),
        suffixIcon: trailingIcon == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  tooltip: trailingTooltip,
                  icon: Icon(trailingIcon, color: c.textPrimary),
                  onPressed: onTrailing,
                ),
              ),
      ),
    );
  }
}

/// Label above a pill-shaped outlined input ("Quantity", "Rate").
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.onChanged,
    this.validator,
    this.prefix,
    this.suffix,
    this.maxLines = 1,
    this.textInputAction,
    this.autofocus = false,
    this.enabled = true,
    this.textCapitalization = TextCapitalization.none,
    this.focusNode,
    this.obscureText = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;
  final Widget? prefix;
  final Widget? suffix;
  final int maxLines;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool enabled;
  final TextCapitalization textCapitalization;
  final FocusNode? focusNode;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final multiline = maxLines > 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          validator: validator,
          maxLines: maxLines,
          autofocus: autofocus,
          enabled: enabled,
          textInputAction: textInputAction,
          textCapitalization: textCapitalization,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: prefix,
            suffixIcon: suffix,
            border: multiline ? _roundedBorder(context) : null,
            enabledBorder: multiline ? _roundedBorder(context) : null,
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _roundedBorder(BuildContext context) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: context.colors.outline),
      );
}

/// Allows digits and one decimal separator with up to [decimals] places.
class DecimalInputFormatter extends TextInputFormatter {
  DecimalInputFormatter({this.decimals = 2});

  final int decimals;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final pattern = decimals == 0 ? RegExp(r'^\d*$') : RegExp('^\\d*\\.?\\d{0,$decimals}\$');
    return pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}

/// Dropdown styled like the other pill inputs.
class LabeledDropdown<T> extends StatelessWidget {
  const LabeledDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          borderRadius: BorderRadius.circular(16),
          style: Theme.of(context).textTheme.bodyLarge,
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
      ],
    );
  }
}
