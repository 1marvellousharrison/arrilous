import 'package:flutter/material.dart';

import '../core/data/nigeria.dart';

/// A dropdown of the 36 Nigerian states plus the FCT. Picking one is what makes
/// the dependent [NigerianCityDropdown] offer the right towns.
class NigerianStateDropdown extends StatelessWidget {
  const NigerianStateDropdown({
    required this.value,
    required this.onChanged,
    this.label = 'State',
    this.errorText,
    this.required = true,
    super.key,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final String? errorText;
  final bool required;

  @override
  Widget build(BuildContext context) {
    // A state saved before this list existed may not be in it; keep it as an
    // option so the field is not shown as empty.
    final states = (value != null && value!.isNotEmpty && !nigeriaStates.contains(value))
        ? [...nigeriaStates, value!]
        : nigeriaStates;
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      hint: const Text('Select a state'),
      decoration: InputDecoration(labelText: label, errorText: errorText),
      items: [
        for (final state in states)
          DropdownMenuItem(value: state, child: Text(state)),
      ],
      onChanged: onChanged,
      validator: (selected) =>
          (required && (selected == null || selected.trim().isEmpty))
              ? 'Select a state.'
              : null,
    );
  }
}

/// A dropdown of the cities and towns in [state]. Disabled until a state is
/// chosen, and rebuilt when the state changes so a town from another state can
/// never linger.
class NigerianCityDropdown extends StatelessWidget {
  const NigerianCityDropdown({
    required this.state,
    required this.value,
    required this.onChanged,
    this.label = 'City / town',
    this.errorText,
    this.required = true,
    super.key,
  });

  final String? state;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final String? errorText;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final cities = citiesForState(state);
    // A city saved before the list existed (or outside it) stays selectable.
    if (value != null && value!.isNotEmpty && !cities.contains(value)) {
      return _drop(context, [...cities, value!], enabled: true);
    }
    return _drop(context, cities, enabled: cities.isNotEmpty);
  }

  Widget _drop(BuildContext context, List<String> cities, {required bool enabled}) {
    return DropdownButtonFormField<String>(
      // Rebuild when the state changes so the field no longer holds the old town.
      key: ValueKey<String?>('city-$state'),
      initialValue: value,
      isExpanded: true,
      hint: Text(enabled ? 'Select a city or town' : 'Choose a state first'),
      decoration: InputDecoration(labelText: label, errorText: errorText),
      items: [
        for (final city in cities)
          DropdownMenuItem(value: city, child: Text(city)),
      ],
      onChanged: enabled ? onChanged : null,
      validator: (selected) {
        if (!required) return null;
        if (!enabled) return 'Choose a state first.';
        if (selected == null || selected.trim().isEmpty) {
          return 'Select a city or town.';
        }
        return null;
      },
    );
  }
}
