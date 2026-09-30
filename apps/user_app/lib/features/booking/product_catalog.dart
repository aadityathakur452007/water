// 005-home-ux — Product catalog (user-locked prices).
//
// Exactly two SKUs (user-confirmed 2026-09-30): Refill Rs 28 (no container)
// + Jar+Container Rs 30. "Jar with tap" is detail-copy only — never a third
// priced line (hallmark honest-copy: no invented prices).
// Tap/copy facts mirror the Bisleri rulebook (ADR-007): Rs 150 refundable
// deposit per jar, Rs 3 cap-missing charge, empties-with-cap handover.

import 'package:flutter/foundation.dart';

/// Catalog SKU ids match the backend wire contract (SkuId refill|container).
enum SkuId { refill, container }

/// One sellable product: everything the buy-box needs in one place
/// (ui-checklist Cart: name + image exactly as on the item page).
@immutable
class CatalogSku {
  const CatalogSku({
    required this.id,
    required this.name,
    required this.pricePaise,
    required this.asset,
    required this.tagline,
    required this.description,
    required this.tapNote,
    required this.relatedId,
  });

  final SkuId id;
  final String name;
  final int pricePaise;
  final String asset;
  final String tagline;
  final String description;
  final String tapNote;
  final SkuId relatedId;

  String get wireId => id == SkuId.refill ? 'refill' : 'container';
}

/// The full storefront (two SKUs — search/chips filter this list).
const List<CatalogSku> kCatalog = [
  CatalogSku(
    id: SkuId.refill,
    name: 'Refill (20L)',
    pricePaise: 2800,
    asset: 'assets/20l.jpg',
    tagline: 'RO+UV • Lab-tested • khali jar dekar refill',
    description:
        '20 litre RO+UV treated paani aapke khali jar mein. Khali jar '
        '(dhakkan sahit) wapas dein — (N−E)×Rs 150 deposit sirf naye jar par.',
    tapNote:
        'Bina tap wala jar: ulta karke dispenser/stand par rakhein. '
        'Tap wala jar chahiye to Container wala option dekhein.',
    relatedId: SkuId.container,
  ),
  CatalogSku(
    id: SkuId.container,
    name: 'Jar + Container (20L)',
    pricePaise: 3000,
    asset: 'assets/20l.jpg',
    tagline: 'Naya jar + container • Rs 150 refundable deposit',
    description:
        'Naya 20L jar food-grade container ke saath. Pehli baar lene par '
        'Rs 150 refundable deposit judta hai — jar wapas par refund.',
    tapNote:
        'Tap (nal) wala jar: seedha istemal, dispenser ki zaroorat nahi. '
        'Tap ke bina wala sasta option Refill mein hai.',
    relatedId: SkuId.refill,
  ),
];

/// Lookup by id (related-SKU cross-link).
CatalogSku skuById(SkuId id) => kCatalog.firstWhere((s) => s.id == id);

/// Search scope (ui-checklist Search, honest size: 2 SKUs — name/tag match).
List<CatalogSku> searchCatalog(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return kCatalog;
  return kCatalog
      .where((s) =>
          s.name.toLowerCase().contains(q) ||
          s.tagline.toLowerCase().contains(q))
      .toList();
}
