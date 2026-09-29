# Project Overview — Shodasha Mineral Waters

## Overview

Shodasha Mineral Waters is a 20L jar water delivery platform. Core SKUs from reference: 20L Jar Refill (Rs 28) + 20L Jar + Container (Rs 30), both with −/+ quantity steppers on product cards. Home screen is a repeat-order machine: one big BOOK NOW button with last settings pre-selected. Jar exchange with Rs 150 refundable deposit per jar is asked at booking time. Status shows a 30-min arrival window (not a live dot), rider name + call button. One-tap pause/resume for auto-delivery, WhatsApp help button, UPI + Cash on Delivery. Three surfaces: Flutter Android user app + Flutter Android vendor/delivery app + Next.js React Super Admin website.

## Goals

1. Make repeat ordering one-tap — default last quantity, address, and delivery window pre-selected.
2. Stop jar-asset leakage — empty-jar exchange stepper + Rs 150 deposit note at booking time.
3. Sell reliability over price — firm confirmation (order ID, time, amount) + arrival window, no hidden charges.
4. Keep support on WhatsApp — in-app WhatsApp help, confirmations/bills shareable to WhatsApp.
5. Run operations on 3 surfaces — user orders, vendor/delivery fulfils, super-admin oversees.

## Core User Flow

1. User opens home — sees repeat-order card, big BOOK NOW button, default 2 jars / tomorrow morning pre-selected.
2. User adjusts quantity on 20L Refill (Rs 28) / Jar+Container (Rs 30) cards and sets empty-jar exchange count.
3. User confirms address + GPS location, delivery window, and UPI/COD payment chip.
4. User tracks order via 4-step status card with arrival window (e.g. 9–9:30 AM) + rider name/call, pause link available.
5. User receives delivery, hands over empties, pays, gets confirmation; feedback/complaint via sheet or WhatsApp.

## Target Audience

Households needing weekly/bi-weekly 20L refills who reorder when water runs low; later societies/RWAs and offices (bulk, standing orders). Low price sensitivity, high reliability need: clear pricing upfront, certain arrival window, easy pause during travel, WhatsApp support.

## Success Metrics

- Repeat-order rate (share of orders via one-tap repeat) and reorder time <30s.
- Empty-jar return rate per delivery; deposit disputes near zero.
- On-time arrival-window adherence + confirmation completeness (ID/time/amount shown).
- Pause/resume self-service adoption (fewer support calls for holds).
- UPI vs COD split tracked; WhatsApp help usage and complaint-resolution return rate.
