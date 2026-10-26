import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import '../data/models/category.dart';
import '../data/stores/category_store.dart';

/// One choosable category, whether it comes from the built-in enum or from the
/// user's own list.
///
/// Before this existed the UI quietly resolved every category id through
/// [Category.byId], which only knows the built-ins. A user-created id therefore
/// fell through to "Khác" in the ledger and to the generic icon — the exact bug
/// where custom categories "cứ báo ở mục khác".
@immutable
class CategoryRef {
  const CategoryRef({
    required this.id,
    required this.label,
    required this.icon,
    required this.tint,
    this.isCustom = false,
  });

  /// Builds a ref from a stored custom category.
  factory CategoryRef.fromItem(CategoryItem item) => CategoryRef(
        id: item.id,
        label: item.label,
        icon: item.icon,
        tint: item.tint,
        isCustom: item.isCustom,
      );

  /// Builds a ref from a built-in enum value.
  factory CategoryRef.fromEnum(Category c) => CategoryRef(
        id: c.id,
        label: c.label,
        icon: c.icon,
        tint: c.tint,
      );

  /// The "Khác" bucket shown for rows with no usable category.
  static final CategoryRef fallback = CategoryRef.fromEnum(Category.other);

  final String id;
  final String label;
  final IconData icon;
  final Color tint;
  final bool isCustom;

  /// Ids are stable and compared verbatim; custom ids look like `cat_<millis>`.
  @override
  bool operator ==(Object other) => other is CategoryRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Resolves category ids to display data, falling back to the built-in table.
///
/// Keeping the lookup in one place is what makes custom categories show up
/// correctly *everywhere* — ledger rows, reports, the review queue and the
/// edit sheet all go through here instead of guessing.
class CategoryResolver {
  const CategoryResolver._(this._store);

  final CategoryStore? _store;

  static const CategoryResolver _builtInsOnly = CategoryResolver._(null);

  /// Reads the store from [context]. Only valid during a build.
  static CategoryResolver of(BuildContext context) {
    final CategoryStore? store =
        Provider.of<CategoryStore?>(context, listen: false);
    return store == null ? _builtInsOnly : CategoryResolver._(store);
  }

  /// Delegates to [CategoryResolver.of]; tolerates a missing provider so widgets
  /// can still be used in isolation (tests, previews).
  static CategoryResolver maybeOf(BuildContext? context) {
    if (context == null) return _builtInsOnly;
    try {
      return of(context);
    } on ProviderNotFoundException {
      return _builtInsOnly;
    }
  }

  /// Resolves [id] to a full category, or `null` when nothing matches.
  CategoryRef? resolve(String? id) {
    if (id == null || id.isEmpty) return null;
    final CategoryItem? custom = _store?.resolve(id);
    if (custom != null) return CategoryRef.fromItem(custom);
    final Category? builtIn = Category.byId(id);
    return builtIn == null ? null : CategoryRef.fromEnum(builtIn);
  }

  /// Like [resolve], but never returns null — unknown ids read as "Khác".
  CategoryRef findById(String? id) => resolve(id) ?? CategoryRef.fallback;

  /// Everything the user can pick for a new or edited transaction.
  ///
  /// The store is the source of truth when present, because it also honours
  /// deleted defaults and the user's renames. Income keeps the built-in short
  /// list (Lương / Chuyển khoản / Khác) plus any custom bucket, since a custom
  /// bucket may well be an income source.
  List<CategoryRef> choicesFor({required bool isIncome}) {
    final CategoryStore? store = _store;
    if (store != null) {
      final List<CategoryRef> all = <CategoryRef>[
        for (final CategoryItem item in store.all) CategoryRef.fromItem(item),
      ];
      if (!isIncome) {
        return all.where((CategoryRef c) => c.id != 'other').toList(growable: false);
      }
      final Set<String> builtInIncomeIds = <String>{
        for (final Category c in Category.incomeChoices) c.id,
      };
      return all
          .where((CategoryRef c) =>
              c.isCustom || builtInIncomeIds.contains(c.id) || c.id == 'other')
          .toList(growable: false);
    }
    final Iterable<Category> source =
        isIncome ? Category.incomeChoices : Category.expenseChoices;
    return <CategoryRef>[
      for (final Category c in source) CategoryRef.fromEnum(c),
    ];
  }
}

/// Extension so any `BuildContext` can ask for a resolver.
extension CategoryResolverX on BuildContext {
  /// Prefer this over [Category.byId] for anything user-facing.
  CategoryResolver get categories => CategoryResolver.of(this);
}
