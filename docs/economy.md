# Economy model

This document is the model for pricing items and sizing GP rewards. Follow it when you add an item or a reward, so the economy stays consistent as the game grows.

GP is the only currency, and nothing is cheaper than 1 GP. Most of the rules below exist because of that: with whole coins only, cheap goods need room to be priced differently from each other.

Some numbers here were fitted from the small set of items the game has today. They are marked as provisional. Revise them when enough new content shows they no longer fit, and update this document with them.

## 1. Unit anchors

Every price should be explainable as a number of meals or days of work.

| GP | Roughly worth |
| --- | --- |
| 1–3 | Scraps, a piece of fruit |
| 6–15 | A pinch of salt, a snack |
| **25** | **A full meal, or one plain garment: the reference unit** |
| ~100 | A day's wage |
| ~500 | A week's wages: the size of a major reward |

The meal is 25 GP rather than something smaller so that the most frequent monster drops, which can't sell for less than 1 GP, stay a small fraction of a meal. See section 8.

If a price reads oddly against this table, for example a weapon cheaper than a meal, it is probably wrong.

## 2. Hard constraints

These are enforced by the code or by the whole-GP currency. Breaking one either stops the game from loading or makes an item unsellable.

- **Prices are whole GP.** A sellable item sells for at least 1 GP, so its buy price is at least 2.
- **Buy must be higher than sell**, unless the item has no price at all (0/0). `sources/db/DB.gd` asserts this when items load. `MerchantScript.HasValidPrices()` in `sources/scripts/generic/MerchantScript.gd` checks it again for each merchant, after any price overrides.
- **A sell price of 0 means merchants won't buy the item.** `GetShopSellPrice` returns 0 for it, so it never appears in a shop's sell list. Use this for unique items you don't want sold back.
- **Quest items are always 0/0.** The trade window already excludes the quest slot.

## 3. Sell price

The sell price is derived from the buy price, by category:

| Category | Sell price |
| --- | --- |
| Equipment (anything that goes in an equipment slot) | 10% of buy, rounded, minimum 1 |
| Consumables and materials | 50% of buy, rounded down, minimum 1 |
| Unique items | 0 (merchants won't buy it) |
| Quest items | 0, and buy price 0 |

There are two ratios because of the whole-GP floor. At 10%, everything that buys for under 15 GP would sell for exactly 1 GP, so a fruit, a snack and a scrap would all be worth the same to a merchant. At 50%, cheap goods keep distinct sell prices.

Equipment stays at 10% so that used gear loses most of its value. Buying gear is then a real gold sink, not something you can undo at a shop.

## 4. Buy price

### Clothes (no stats, or Defense 1 or less)

- A plain garment costs 25–30.
- Finer cloth, or a garment that takes more fabric, costs up to about 3× that (40–70).
- A smaller piece of an outfit, such as a hood that goes with a robe, costs less than the main piece.

### Armour (Defense 2 or more)

```latex
\text{buy} = 25 \cdot 2^{\,\text{def}/4} \cdot \text{premium}
```

The price doubles every 4 Defense, so armour quickly outpaces clothes. At Defense 30, a piece costs about 4500 GP, or 180 meals.

Premiums multiply together:

| Modifier | Premium |
| --- | --- |
| +20 walk speed | ×2.6 |
| −10 walk speed | ×0.71 |
| −20 walk speed | ×0.42 |
| Made of silver | ×1.4 |
| Made of gold | ×3 relative to silver |
| Unique item | Set the price by hand; sell price 0 |

### Weapons (provisional)

```latex
\text{buy} = 125 \cdot 2^{\,(\text{atk} - 20)/20} \cdot \text{premium}
```

A 20-Attack weapon is the baseline, at 125 GP (5 meals), and the price doubles every 20 Attack. Weapons carry a premium over clothes because they take metal and skilled work.

| Modifier | Premium |
| --- | --- |
| Slightly faster cast (around −0.1 cast delay) | ×1.5 |
| Shorter cooldown (around −0.2) | ×1.8 |
| Extra attack range | ×1.3 |
| Bonus Max HP | ×1.7 |
| Much slower cast (around +0.5 cast delay) | ×0.6 |

These premiums were fitted from only a handful of weapons. Expect to adjust them.

### Consumables

Healing gets more expensive per HP as potency rises. A stronger item pays for its convenience.

| Tier | Effect | Buy | HP per GP |
| --- | --- | --- | --- |
| Fruit | 15–20 HP | 3 | ~5–7 |
| Snack, such as a croissant | Small heal or mana, plus stamina | 15 | — |
| Full meal | — | ~25 | — |
| Drink | ~75 HP | 40 | ~1.9 |
| Potion | ~100 HP, magical, crafted | 200 | ~0.5 |

If you add a new healing item, place it on this curve. An item that heals more per GP than the tier below it is underpriced.

Fruit is cheaper than the scale alone would suggest because Apple and Pitaya are frequent monster drops. They follow the drop rule in the next section, not the food scale.

### Containers

A filled container costs more than the empty container plus its contents. A crafted consumable costs more than the sum of its ingredients' buy prices.

For example, a Bottle (140) costs more than its 4 Salt, 4 Bone and 4 Sulphur Powder (132). A Water Bottle (150) costs more than a Bottle. A Cactus Potion (200) costs more than its 6 Maggot Slime, Water Bottle and Pitaya (165).

### Materials and other monster drops

Price a drop from the gold it should earn per kill, not from the meal scale. The more often it drops, the less each one is worth.

```latex
\text{target GP per kill} = 0.5 + 0.1 \cdot \text{monster level}
```

1. Divide the monster's target by the item's drop rate to get its sell price.
2. Double the sell price and round it to the ladder to get the buy price.
3. Recompute the sell price from the rounded buy price.
4. If several monsters drop the item, use the most common source.

For example, a Skeleton (level 20) has a target of 2.5 GP per kill and drops Bone 33% of the time. That gives a sell price of about 7.5, so Bone costs 15 to buy and sells for 7.

The floor is 2/1. A drop that would land below it, like Maggot Slime, stays at 2/1.

A drop that is also a crafting ingredient must still leave the crafted item above the cost of its inputs (see Containers).

## 5. Rounding

Round every buy price to the nearest value on this ladder:

2, 3, 4, 5, 6, 8, 10, 12, 15, 20, 25, 30, 35, 40, 50, 60, 70, 80, 90, 100, 125, 140, 150, 175, 200, then steps of 50 up to 500, steps of 100 up to 1000, then steps of 250.

Then derive the sell price from the rounded buy price, not from the unrounded formula result.

## 6. Crafting

- **Crafting saves money compared with buying.** A crafted item's buy price is higher than the total buy price of its ingredients.
- **Crafting gear is not a way to make money from shops.** Materials sell at 50% and equipment at 10%, so crafted gear sells for less than its ingredients would. This is intended: players craft to use the result.
- **Crafted materials and consumables may sell for slightly more than their ingredients**, because both sides sell at 50%. Keep that margin small. A Bottle sells for 70, against 64 for its ingredients.

## 7. GP rewards

Size rewards in units of meals and wages:

| Reward type | GP |
| --- | --- |
| Small find, or a trivial errand | ~10 |
| Daily repeatable quest | ~25 (one meal) |
| One-off quest | 50–100 (half a day's wage to a full day's) |
| Long or dangerous one-off quest | 100 or more |
| Major or group mission | ~500 (a week's wages) |

- **When a reward pays back an item** the player handed in, set it to that item's current buy price plus a small margin. Recalculate it if that item's price changes.
- **Keep the quest log in sync.** The `reward = "..."` text in the quest's file under `presets/quests/` must match the amount the script passes to `AddGP`.

## 8. Drop income

GP per kill is the sum of sell price × drop rate over a monster's drops. It should rise with monster level, so that fighting stronger monsters pays more.

The target is `0.5 + 0.1 × level` GP per kill: about 40 kills per meal at level 1, and about 10 at level 20. Drop rates are designed around quests, so they are left alone and the target is reached through prices (section 4, Materials and other monster drops).

| Monster | Level | Drop | GP per kill | Target |
| --- | --- | --- | --- | --- |
| Maggot | 1 | Maggot Slime 60% | 0.6 | 0.6 |
| Salt Slime | 1 | Apple 70% | 0.7 | 0.6 |
| Peyote | 2 | Pitaya 33% | 0.33 | 0.7 |
| Sea Slime | 6 | Salt 33% | 1.0 | 1.1 |
| Fire Goblin | 8 | Sulphur Powder 20% | 1.2 | 1.3 |
| Giant Maggot | 15 | Maggot Slime 60% | 0.6 | 2.0 |
| Snake | 17 | Snake Skin 10% | 2.0 | 2.2 |
| Sand Snake | 19 | Snake Skin 5% | 1.0 | 2.4 |
| Skeleton | 20 | Bone 33% | 2.3 | 2.5 |

Price alone can't fix two monsters. Giant Maggot shares the level-1 Maggot's drop, and Sand Snake drops Snake Skin at half the Snake's rate. They need a new or different drop when their content is next revised.

The Combat Simulator in the Game Data addon (`addons/game_data_manager/CombatSimulatorView.gd`) already reports GP per kill. Use it when you set drop rates.

## 9. Merchants

A merchant script extends `MerchantScript` and lists its stock in `GetStock()`. By default it uses each item's own buy and sell prices.

A merchant can override `GetBuyPrice` or `GetSellPrice`, for example for a local markup. Its prices must still pass `HasValidPrices()`, which means it can't sell an item at or below either its own sell price or the item's default sell price.

## 10. Checklists

### Adding an item

1. Decide its category: clothes, armour, weapon, consumable, material, unique or quest item.
2. Work out the buy price from that category's rule, applying any premiums.
3. Round it to the ladder.
4. Work out the sell price from the category's ratio.
5. Check the result against the unit anchors.
6. Set both prices in the Game Data addon's item table, or in the item's `.tres` file under `presets/cells/items/`.

### Adding a GP reward

1. Pick the reward type from the table in section 7.
2. If the reward pays back an item, use that item's price plus a small margin instead.
3. Update the quest's `reward = "..."` text to match.
