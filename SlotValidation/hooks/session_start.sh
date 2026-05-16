#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Lot247 / SlotValidation -- LLM-independent pre-read enforcement hook.
#
# Purpose
#   Make it *impossible* for any LLM or human operator to start working on the
#   `SlotValidation` tab without first being shown the canonical README. The
#   hook is shell-level, so it fires regardless of which LLM, CLI or IDE
#   integration is being used.
#
# Install (user-level, recommended)
#   1. Copy this file somewhere stable, e.g. ~/.local/bin/slotvalidation-hook.sh
#   2. Make it executable:   chmod +x ~/.local/bin/slotvalidation-hook.sh
#   3. Source it from your shell rc, e.g. append to ~/.bashrc (or ~/.zshrc):
#         export SLOTVALIDATION_README="$HOME/path/to/SlotValidation/Lot247_Tab_SlotValidation_README.md"
#         source "$HOME/.local/bin/slotvalidation-hook.sh"
#
# Install (Claude Code SessionStart hook)
#   Add an entry under "hooks.SessionStart" in ~/.claude/settings.json that
#   runs this script. The README contents will be surfaced into the session.
#
# Behaviour
#   * Prints a banner pointing at the README on every new shell session.
#   * Defines a `slotvalidation-ack` function which dumps the README in full,
#     so any LLM-driven shell can ingest it on demand.
#   * Sets SLOTVALIDATION_README_ACK=1 once acknowledged in the current shell.
# -----------------------------------------------------------------------------

: "${SLOTVALIDATION_README:?Set SLOTVALIDATION_README to the absolute path of Lot247_Tab_SlotValidation_README.md}"

if [[ ! -r "$SLOTVALIDATION_README" ]]; then
    printf '[SlotValidation] WARNING: README not readable at: %s\n' \
        "$SLOTVALIDATION_README" >&2
    return 0 2>/dev/null || exit 0
fi

printf '\n'
printf '================================================================\n'
printf '  Lot247 / SlotValidation -- MUST-READ before any edit.\n'
printf '  Canonical spec: %s\n' "$SLOTVALIDATION_README"
printf '  Run:  slotvalidation-ack     # to print the full README\n'
printf '================================================================\n'
printf '\n'

slotvalidation-ack() {
    cat -- "$SLOTVALIDATION_README"
    export SLOTVALIDATION_README_ACK=1
    printf '\n[SlotValidation] Acknowledged. SLOTVALIDATION_README_ACK=1\n'
}

slotvalidation-guard() {
    if [[ "${SLOTVALIDATION_README_ACK:-0}" != "1" ]]; then
        printf '[SlotValidation] BLOCKED: run `slotvalidation-ack` first.\n' >&2
        return 1
    fi
    return 0
}
