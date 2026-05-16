# `Lot247 → SlotValidation` — Canonical Tab Reference

> **STATUS: MUST-READ before any read/write operation on the tab.**
> This document is the single source of truth for the structure, semantics
> and invariants of the `SlotValidation` tab in the `Lot247` Google Sheet.

---

## 1. Purpose

The `SlotValidation` tab records, per drawing `targetDate`:

1. The **predicted** numbers produced by the best-trained per-slot models
   (`rowType = TIPP`), together with each model's training-time validation
   RMSE.
2. The **actual** drawn numbers (`rowType = RESULT`), together with
   per-slot RMSE between prediction and result, and the number of hits.

The tab is the authoritative ground truth used by downstream evaluation,
reporting and retraining pipelines. **Correctness is mandatory.**

---

## 2. Column Inventory

| Column                  | Type                       | Unit / Format    | Required | Description (≤ 10 words)                              |
|-------------------------|----------------------------|------------------|----------|-------------------------------------------------------|
| `target_date`           | `date`                     | `YYYY-MM-DD`     | yes      | Date of the drawing.                                  |
| `row_type`              | `enum{TIPP,RESULT}`        | —                | yes      | Distinguishes prediction row from result row.         |
| `n1` … `n7`             | `int`                      | drawing range    | yes      | Number in slot 1…7 (predicted or drawn).              |
| `hits`                  | `int` \| `N/A`             | count            | RESULT   | Count of predicted numbers matching actual draw.      |
| `n1_validation_rmse`    | `float` \| `N/A`           | RMSE             | yes      | See §3.3 — meaning depends on `row_type`.             |
| `n2_validation_rmse`    | `float` \| `N/A`           | RMSE             | yes      | See §3.3.                                             |
| `n3_validation_rmse`    | `float` \| `N/A`           | RMSE             | yes      | See §3.3.                                             |
| `n4_validation_rmse`    | `float` \| `N/A`           | RMSE             | yes      | See §3.3.                                             |
| `n5_validation_rmse`    | `float` \| `N/A`           | RMSE             | yes      | See §3.3.                                             |
| `n6_validation_rmse`    | `float` \| `N/A`           | RMSE             | yes      | See §3.3.                                             |
| `n7_validation_rmse`    | `float` \| `N/A`           | RMSE             | yes      | See §3.3.                                             |
| `schema_version`        | `string`                   | semver           | yes      | Schema version this row adheres to.                   |

> **Sentinel:** Use literal `N/A` (never blank) where a column is
> semantically undefined for the current `row_type`.

---

## 3. Row-Type Semantics

### 3.1 `row_type = TIPP`

- A predicted draw produced by the per-slot best models for `target_date`.
- `n1`…`n7` = predicted integers.
- `hits` = `N/A` (undefined for predictions).
- `nX_validation_rmse` = the **training-time validation RMSE**
  (`training_validation_rmse`) of the *best model* trained for slot `nX`.

### 3.2 `row_type = RESULT`

- The actually drawn numbers for `target_date`.
- `n1`…`n7` = drawn integers.
- `hits` = count of predicted numbers (from the matching `TIPP` row with the
  same `target_date`) that match the actual draw.
- `nX_validation_rmse` = RMSE between the **predicted** number in slot `nX`
  (from the matching `TIPP` row) and the **actual** number in slot `nX`,
  for the same `target_date`.

### 3.3 Conditional-meaning summary

| Column                  | `TIPP` meaning                                | `RESULT` meaning                                                |
|-------------------------|-----------------------------------------------|-----------------------------------------------------------------|
| `nX_validation_rmse`    | Best model's training validation RMSE.        | RMSE between predicted `nX` and actual `nX` (same `target_date`).|
| `hits`                  | `N/A`                                         | Number of matching predicted numbers.                           |
| `nX`                    | Predicted integer.                            | Drawn integer.                                                  |

---

## 4. Invariants

1. **Pairing:** Every `RESULT` row MUST have a matching `TIPP` row sharing
   the same `target_date`. A `RESULT` without a `TIPP` is invalid.
2. **Uniqueness:** For each `target_date`, at most one `TIPP` row and at
   most one `RESULT` row may exist.
3. **Sentinels:** Cells undefined for the row type (e.g. `hits` on `TIPP`)
   are written as `N/A`, never left blank.
4. **Computed values:** `hits` and `RESULT.nX_validation_rmse` are derived;
   never edit them by hand — recompute from the paired `TIPP` row.
5. **Schema version:** Any row written must carry the current
   `schema_version`. Increment on any structural change.

---

## 5. Worked Example

| target_date | row_type | n1 | n2 | n3 | n4 | n5 | n6 | n7 | hits | n1_validation_rmse | n2_validation_rmse | n3_validation_rmse | n4_validation_rmse | n5_validation_rmse | n6_validation_rmse | n7_validation_rmse | schema_version |
|-------------|----------|----|----|----|----|----|----|----|------|--------------------|--------------------|--------------------|--------------------|--------------------|--------------------|--------------------|----------------|
| 2026-05-14  | TIPP     |  4 | 11 | 17 | 23 | 31 | 42 |  6 | N/A  | 9.81               | 10.22              | 11.04              |  9.65              | 10.88              | 12.10              |  3.42              | 1.0.0          |
| 2026-05-14  | RESULT   |  4 | 12 | 17 | 25 | 31 | 40 |  6 | 4    | 0.00               | 1.00               | 0.00               | 2.00               | 0.00               | 2.00               | 0.00               | 1.0.0          |

Reading:

- Slot `n1`: predicted `4`, drawn `4` → RESULT RMSE `0.00`, contributes to `hits`.
- Slot `n2`: predicted `11`, drawn `12` → RESULT RMSE `1.00`, no hit.
- TIPP `nX_validation_rmse` values (9.81…3.42) describe the *models*, not
  this draw.

---

## 6. Field-Description Style Guide

When populating the per-field description row in the sheet:

- ≤ 10 words per cell.
- Imperative, descriptive phrasing.
- For row-type-conditional columns, split with `|`, e.g.
  *"TIPP: model val-RMSE | RESULT: pred-vs-actual RMSE"*.
- No abbreviations outside the legend; no implementation references.

---

## 7. Suggested Sheet-Level Conventions

To maximise comprehension by every LLM:

1. **Header rows**
   - Row 1: column names (snake_case).
   - Row 2: machine-readable type (`int`, `float`, `enum{...}`, `date:YYYY-MM-DD`).
   - Row 3: ≤ 10-word human description.
   - Freeze rows 1–3.
2. **Explicit `row_type` column** — never inferred from position or styling.
3. **Legend block** in a sibling `_Legend` tab restating §3.
4. **Sentinel `N/A`** for undefined cells.
5. **Permanent example pair** at the top of the data range.
6. **`A1` cross-link cell:**
   *"See `Lot247_Tab_SlotValidation_README.md` before editing."*
7. **JSON schema** in `SlotValidation/schema/slot_validation.schema.json`.
8. **Read-before-write hook** (see `SlotValidation/hooks/`).
9. **`schema_version`** column; bump on structural change.

---

## 8. Change Log

| Version | Date       | Change                          |
|---------|------------|---------------------------------|
| 1.0.0   | 2026-05-16 | Initial canonical specification.|
