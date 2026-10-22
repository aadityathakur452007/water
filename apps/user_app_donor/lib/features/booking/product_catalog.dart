// Product catalog — presentation facts only; prices come from GET /catalog.
//
// Exactly two SKUs (owner-confirmed): Refill (Rs 28) + Jar + Container
// (Rs 30). No price is written in this file: [catalogFor] stamps the
// latest server snapshot onto the two product cards.
//
// Rs 150 refundable deposit per new container, Rs 3 cap-missing charge and
// empties-with-cap handover mirror the Bisleri rulebook (ADR-007).

import 'package:flutter/foundation.dart';

import 'booking_controller.dart';

/// Catalog SKU ids match the backend wire contract (refill|container).
enum SkuId { refill, container }

/// One sellable product: everything the buy-box needs in one place.
@immutable
class CatalogSku {
  const CatalogSku({
    required this.id,
    required this.name,
    required this.pricePaise,
    required this.depositPaise,
    required this.capPaise,
    required this.asset,
    required this.tagline,
    required this.description,
    required this.tapNote,
    required this.relatedId,
  });

  final SkuId id;
  final String name;
  final int pricePaise;

  /// Server deposit + cap values, carried for the honest fact rows.
  final int depositPaise;
  final int capPaise;
  final String asset;
  final String tagline;
  final String description;
  final String tapNote;
  final SkuId relatedId;

  String get wireId => id == SkuId.refill ? 'refill' : 'container';
}

/// Builds the two storefront cards from the latest server snapshot.
List<CatalogSku> catalogFor(CatalogRates rates) => [
  CatalogSku(
    id: SkuId.refill,
    name: 'Refill (20L)',
    pricePaise: rates.refillPaise,
    depositPaise: rates.depositPaise,
    capPaise: rates.capPaise,
    asset: 'assets/20l.jpg',
    tagline: 'RO+UV • Lab-tested • refill your empty jar',
    description:
        '20 litres of RO+UV treated water, filled into your empty 20L '
        'jar. Return the empty jar with its cap. A refundable safety '
        'deposit applies only to new containers.',
    tapNote:
        'No tap on this jar: place it upside down on a dispenser or '
        'stand. Need a tap? Choose the Jar + Container option.',
    relatedId: SkuId.container,
  ),
  CatalogSku(
    id: SkuId.container,
    name: 'Jar + Container (20L)',
    pricePaise: rates.containerPaise,
    depositPaise: rates.depositPaise,
    capPaise: rates.capPaise,
    asset: 'assets/20l.jpg',
    tagline: 'New jar + container • refundable safety deposit',
    description:
        'A new 20L food-grade jar with a container. The first container '
        'carries a refundable safety deposit; it comes back when you '
        'return the jar.',
    tapNote:
        'Tap (nozzle) jar: ready to use, no dispenser needed. The '
        'cheaper no-tap option is Refill.',
    relatedId: SkuId.refill,
  ),
];

/// Lookup by id from the current server-priced list.
CatalogSku skuById(SkuId id, CatalogRates rates) =>
    catalogFor(rates).firstWhere((s) => s.id == id);
