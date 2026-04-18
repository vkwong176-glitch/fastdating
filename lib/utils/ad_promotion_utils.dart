int stablePromotionSeed(String raw) {
  var hash = 0;
  for (final unit in raw.codeUnits) {
    hash = ((hash * 31) + unit) & 0x7fffffff;
  }
  return hash;
}

List<T> mergePromotionItems<T, P>({
  required List<T> items,
  required List<P> promotions,
  required String pageSalt,
  required String Function(P promotion) promotionId,
  required T Function(P promotion) buildPromotionItem,
  int? maxPromotions,
}) {
  final merged = List<T>.from(items);
  if (promotions.isEmpty) {
    return merged;
  }

  if (maxPromotions != null && maxPromotions <= 0) {
    return merged;
  }

  final limited =
      (maxPromotions == null ? promotions : promotions.take(maxPromotions))
          .toList();
  final usedSlots = <int>{};
  for (var i = 0; i < limited.length; i++) {
    final promotion = limited[i];
    final slotCount = merged.length + 1;
    if (slotCount <= 0) {
      merged.add(buildPromotionItem(promotion));
      continue;
    }
    var insertAt = stablePromotionSeed(
          '$pageSalt|${promotionId(promotion)}|$i|$slotCount',
        ) %
        slotCount;
    while (usedSlots.contains(insertAt) && usedSlots.length < slotCount) {
      insertAt = (insertAt + 1) % slotCount;
    }
    usedSlots.add(insertAt);
    merged.insert(insertAt, buildPromotionItem(promotion));
  }
  return merged;
}
