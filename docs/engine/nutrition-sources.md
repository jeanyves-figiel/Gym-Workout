# Nutrition sources (#1017)

Where Fuel's numbers come from, and the checks that keep them honest.

## Foods (`WorkoutEngine/Resources/Foods.json`)

Every catalog food has `source`:

| `source.kind` | Meaning | Shown as |
|---|---|---|
| `usda` | Matched to the USDA FoodData Central entry in `source.ref` (SR Legacy, Foundation or FNDDS); `per100` within ±12% kcal, ±15% protein, ±20% fat, carbs within 15% of total or net (fibre removed) carbs | **USDA** chip, counts as checked |
| `label` | Typical European label values for this kind of product (no close USDA entry, or EU products differ: EU labels leave fibre out of carbs) | **LABEL** chip |

Foods made on the device have no `source`: a barcode food is **Open Food Facts** (`OFF`), anything else (own food, AI guess) is an **estimate** (`≈`). `Food.nutritionSource` returns the shown source.

Carbs are **available (net) carbs**, as on EU labels. Dry goods (rice, pasta, grains, lentils) are per 100 g **dry**.

The 2026-10-31 match used the USDA FoodData Central data packaged in the `pyfooda` PyPI wheel (the USDA API and the Swiss Food Composition Database site weren't reachable from the build environment). To recheck or add a food, look the food up on fdc.nal.usda.gov (or naehrwertdaten.ch), set `per100`, and set `source` to `{"kind":"usda","ref":"<FDC description>"}` or `{"kind":"label"}`.

## Recipes (`Resources/Recipes.json`)

Each recipe's `protein`, `carbs`, `fat`, `kcal` per serving are **computed** from `amounts` (grams of catalog foods) × `per100` ÷ `servings`, not typed. `RecipeTrust.of(recipe)` recomputes them and gives:

- **checked**: every ingredient is `usda` and the stated numbers add up (kcal within 5% or 10 kcal; protein, carbs, fat within 5% or 1 g);
- **mostlyChecked**: adds up, some ingredients are `label`;
- **estimate**: own recipes, products, or numbers that don't add up.

Ingredient lines for dry goods say *dry* so members weigh the right thing.

## Tests

`RecipeCatalogTests.nutritionSourcesAndTotals` fails CI when a food has no source, a USDA food has no ref, a food's kcal is far from 4·protein + 4·carbs + 9·fat (alcohol exempt), a recipe doesn't add up from its grams, or a recipe with a dry food never says *dry*. After editing a food, recompute the recipes that use it.

## Member reviews

Members review catalog recipes (stars, *Numbers* and *Cooking* chips; no free text). `GET /v1/recipe-reviews` returns anonymous counts; `node src/admin.ts recipe-flags` lists recipes whose numbers members flagged, most flags first: check those against the sources and fix the JSON (or ship a `recipes` / `foods` content pack, see `backend/content/README.md`).
