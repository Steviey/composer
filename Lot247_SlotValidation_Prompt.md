# Prompt: Document & Standardize the `Lot247 → SlotValidation` Google Sheet

> **Audience:** Any LLM (model-agnostic) that reads, writes, validates, or extends the
> `SlotValidation` tab inside the `Lot247` Google Sheet.
> **Status:** MUST-READ. This sheet is a **critical, system-of-record component**.
> Correctness is non-negotiable.

---

## 1. Context

A new tab has been created at:

```
Google Sheets → Lot247 → SlotValidation
```

This tab is an essential part of the overall Lot247 system. Every LLM that
interacts with it MUST understand its structure **before** performing any
read, write, fill, or transformation operation.

---

## 2. Objectives

The deliverables for this task are, in priority order:

1. **Universal comprehension** — Guarantee that *every* LLM (regardless of vendor
   or version) can correctly parse the structure of the `SlotValidation` tab.
2. **Authoritative documentation** — Produce a canonical reference describing
   each column, row type, and value semantics.
3. **Clear legends & descriptions** — Provide concise, unambiguous field
   descriptions (≤ 10 words per cell explanation) and a complete legend.
4. **Enforced pre-read policy** — Ensure every LLM reads
   `Lot247_Tab_SlotValidation_README.md` *before* any fill/write operation,
   ideally via an **LLM-independent mechanism** such as a user-level
   `bashrc` SessionStart hook.
5. **Suggested values** — Where cells are empty, propose sensible default or
   example values consistent with the documented semantics.

---

## 3. Row-Type Semantics

The `SlotValidation` tab contains rows of two distinct types. The
interpretation of several columns **depends on the row type**.

| Row Type   | Meaning                                                                 |
|------------|-------------------------------------------------------------------------|
| `TIPP`     | A predicted draw (model output) for a given `targetDate`.               |
| `RESULT`   | The actually drawn numbers for the same `targetDate`.                   |

### 3.1 `Hits` column

- Defined **only** for rows of type `RESULT`.
- Semantics: *Number of predicted numbers that matched the actual draw* for the
  same `targetDate`.

### 3.2 `n1`–`n7` (Number Slots)

Seven ordered number slots per drawing. Their value is the integer drawn (for
`RESULT`) or predicted (for `TIPP`) in that slot.

### 3.3 `n1_Validation_RMSE` … `n7_Validation_RMSE`

The meaning of these columns **switches based on row type**:

| Row Type   | Meaning of `nX_Validation_RMSE`                                                                                       |
|------------|-----------------------------------------------------------------------------------------------------------------------|
| `TIPP`     | `training_validation_rmse` of the best model trained for slot `nX`.                                                   |
| `RESULT`   | RMSE between the predicted number (from the matching `TIPP` row) and the actual number in slot `nX` on the same `targetDate`. |

> **Invariant:** A `RESULT` row's `nX_Validation_RMSE` is computed against the
> `TIPP` row that shares the same `targetDate`.

---

## 4. Field Description Style Guide

When filling the per-field description cells in the sheet:

- **Hard limit:** ≤ 10 words per cell.
- Use **imperative, descriptive** phrasing (e.g., *"Drawn number in slot 3"*).
- Avoid abbreviations that are not in the legend.
- Never reference internal variables, code paths, or implementation details.
- Where semantics differ by row type, write both meanings separated by `|`,
  e.g., *"TIPP: model val-RMSE | RESULT: pred-vs-actual RMSE"*.

---

## 5. Required Artifacts

1. **`Lot247_Tab_SlotValidation_README.md`**
   The canonical documentation of the tab. Must include:
   - Purpose of the tab.
   - Full column inventory (name, type, units, allowed values).
   - Row-type semantics table (see §3).
   - Worked example: one `TIPP` row + matching `RESULT` row.
   - Validation rules and invariants.
   - Change-log section.

2. **Pre-read enforcement hook**
   A user-level shell hook (e.g., appended to `~/.bashrc` or installed as a
   Claude Code SessionStart hook) that prints / surfaces the README path and
   blocks/reminds the LLM to read it before any fill operation.
   The mechanism MUST be **LLM-independent** (works for any model, any client).

---

## 6. Suggestions for Maximum LLM Comprehension

To make the structure of the tab unambiguous for *any* LLM, apply the
following techniques (in combination):

1. **Frozen header rows** — Row 1: column names. Row 2: machine-readable type
   (`int`, `float`, `enum{TIPP,RESULT}`, `date:YYYY-MM-DD`, …).
   Row 3: ≤ 10-word human description.
2. **Explicit row-type column** — A dedicated `rowType` column (`TIPP` |
   `RESULT`), never inferred from position.
3. **Stable, snake_case column names** — e.g., `target_date`, `row_type`,
   `n1`, `n1_validation_rmse`, `hits`.
4. **Legend block** — A merged cell range at the top (or a sibling `_Legend`
   tab) restating §3 in plain language.
5. **Sentinel values** — Use `N/A` (never blank) for cells that are
   semantically undefined for the current row type (e.g., `hits` on `TIPP`).
6. **Sample rows** — Include 1 worked `TIPP` + `RESULT` pair as a permanent
   reference at the top of the data range.
7. **README cross-link** — Place a cell `A1` value:
   *"See `Lot247_Tab_SlotValidation_README.md` before editing."*
8. **Schema export** — Maintain a JSON Schema (or CSV `_schema` sibling tab)
   that machines can parse to validate writes.
9. **Versioning** — Add a `schema_version` cell; bump on any structural change.
10. **Read-before-write hook** — As per §5.2, enforce README ingestion via a
    SessionStart-level mechanism so no LLM can skip it.

---

## 7. Acceptance Criteria

- [ ] `Lot247_Tab_SlotValidation_README.md` exists and covers §5.1.
- [ ] Header rows 1–3 are populated per §6.1.
- [ ] `rowType` column present and filled for every data row.
- [ ] Every field-description cell is ≤ 10 words.
- [ ] `nX_Validation_RMSE` semantics documented for both row types (§3.3).
- [ ] `Hits` column documented as `RESULT`-only (§3.1).
- [ ] Pre-read hook installed and verified on a clean shell session.
- [ ] Suggested/example values added where cells were previously empty.
- [ ] A worked `TIPP` + `RESULT` example pair is present at the top of the
      data range.
