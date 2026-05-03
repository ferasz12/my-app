import 'package:flutter/material.dart';

class SafeDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hintText;
  final Widget? hint;
  final bool isExpanded;
  final InputDecoration? decoration;

  const SafeDropdown({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
    this.hintText,
    this.hint,
    this.isExpanded = true,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    // 1) احذف أي عناصر بلا قيمة
    final filtered = items.where((it) => it.value != null).toList();

    // 2) شيل التكرار بالـ value
    final seen = <T>{};
    final dedup = <DropdownMenuItem<T>>[];
    for (final it in filtered) {
      final v = it.value as T;
      if (seen.add(v)) dedup.add(it);
    }

    // 3) لو value مو ضمن القائمة، خلّها null عشان ما ينهار
    final hasValue = dedup.any((it) => it.value == value);
    final effectiveValue = hasValue ? value : null;

    return DropdownButtonFormField<T>(
      value: effectiveValue,
      isExpanded: isExpanded,
      items: dedup,
      onChanged: onChanged,
      decoration: decoration ??
          InputDecoration(
            border: const OutlineInputBorder(),
            hintText: hintText,
            isDense: true,
          ),
      hint: hint ?? (hintText != null ? Text(hintText!) : null),
    );
  }
}
