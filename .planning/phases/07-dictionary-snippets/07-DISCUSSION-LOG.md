# Phase 7: Dictionary & Snippets - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-30
**Phase:** 07-dictionary-snippets
**Areas discussed:** Snippet matching, Dictionary prompt strategy, Dictionary tab layout, Snippets tab layout

---

## Snippet Matching

### Q1: Whole-word vs substring matching

| Option | Description | Selected |
|--------|-------------|----------|
| Whole-word only | Trigger "addr" only matches standalone "addr", not "address". Safer | ✓ |
| Substring matching | Trigger "addr" also matches inside "address". More aggressive | |

**User's choice:** Whole-word only
**Notes:** Recommended to avoid unintended expansions in natural speech

### Q2: Case sensitivity

| Option | Description | Selected |
|--------|-------------|----------|
| Case-insensitive | Whisper output casing varies — more reliable for speech-to-text | |
| Case-sensitive | Exact case match required | |
| You decide | Claude picks based on Whisper output behavior | ✓ |

**User's choice:** You decide
**Notes:** Deferred to Claude's discretion

### Q3: Punctuation handling

| Option | Description | Selected |
|--------|-------------|----------|
| Strip punctuation before matching | "sig." and "sig," both match trigger "sig" | ✓ |
| Exact match including punctuation | "sig." does NOT match "sig" | |

**User's choice:** Strip punctuation before matching
**Notes:** Accounts for Whisper/GPT adding punctuation around short words

### Q4: Multiple triggers in one transcription

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, expand all matches | Both "sig" and "addr" get expanded in one pass | ✓ |
| Only first match | Only the first trigger found gets expanded | |

**User's choice:** Yes, expand all matches
**Notes:** None

---

## Dictionary Prompt Strategy

### Q1: Whisper prompt format

| Option | Description | Selected |
|--------|-------------|----------|
| Comma-separated list | "Kubernetes, kubectl, Tailscale" — maximizes token budget | |
| Context sentences | "The user often says Kubernetes, kubectl" — more tokens but better context | |
| You decide | Claude picks the most effective format | ✓ |

**User's choice:** You decide
**Notes:** Deferred to Claude's discretion

### Q2: Token cap prioritization

| Option | Description | Selected |
|--------|-------------|----------|
| Most recently added first | Newer entries get priority — users add terms they're actively using | |
| Alphabetical with truncation | Fill prompt alphabetically, cut off when full | |
| You decide | Claude picks the prioritization strategy | ✓ |

**User's choice:** You decide
**Notes:** Deferred to Claude's discretion

### Q3: Abbreviation replacement approach

| Option | Description | Selected |
|--------|-------------|----------|
| Same engine as snippets | Abbreviation expansion uses same whole-word replacement as snippets | ✓ |
| Whisper prompt only | Only feed abbreviations into Whisper prompt | |

**User's choice:** Same engine as snippets
**Notes:** Consistent behavior, one code path for both abbreviations and snippets

---

## Dictionary Tab Layout

### Q1: Layout style

| Option | Description | Selected |
|--------|-------------|----------|
| Simple list with + button | Toolbar + button, search bar, scrollable list, bottom token counter | ✓ |
| Two-section list | Split into "Vocabulary" and "Abbreviations" sections | |

**User's choice:** Simple list with + button
**Notes:** Selected with preview mockup. Matches Apple Notes/Reminders pattern

### Q2: Add/edit flow

| Option | Description | Selected |
|--------|-------------|----------|
| Inline sheet | Sheet slides up with term field, optional replacement, isAbbreviation toggle | ✓ |
| Inline editing in list | New row appears in-place with editable text fields | |

**User's choice:** Inline sheet
**Notes:** Same sheet pattern for consistency

### Q3: Token indicator placement

| Option | Description | Selected |
|--------|-------------|----------|
| Bottom bar, always visible | Persistent footer with color change as limit approaches | ✓ |
| Only in add/edit sheet | Show token impact only when adding/editing | |

**User's choice:** Bottom bar, always visible
**Notes:** None

### Q4: Delete pattern

| Option | Description | Selected |
|--------|-------------|----------|
| Swipe-to-delete | Standard macOS/iOS swipe gesture | |
| Hover delete icon | Trash icon appears on hover, matching Phase 6 history | ✓ |

**User's choice:** Hover delete icon
**Notes:** Consistency with Phase 6 history pattern was the deciding factor

---

## Snippets Tab Layout

### Q1: Layout style

| Option | Description | Selected |
|--------|-------------|----------|
| Same pattern as Dictionary | Toolbar + button, search, list with "trigger → expansion" | ✓ |
| Card-based grid | Each snippet as a card with trigger prominent | |

**User's choice:** Same pattern as Dictionary
**Notes:** Selected with preview mockup. Consistent companion app feel

### Q2: Add/edit flow

| Option | Description | Selected |
|--------|-------------|----------|
| Sheet with trigger + expansion fields | Sheet with "Trigger phrase" and "Expands to" multi-line area | ✓ |
| Full-width editor | Navigation push to dedicated edit view | |

**User's choice:** Sheet with trigger + expansion fields
**Notes:** Same sheet pattern as dictionary for consistency

### Q3: Text display in list

| Option | Description | Selected |
|--------|-------------|----------|
| Truncate with ellipsis | Show first ~60 chars with … — compact and scannable | ✓ |
| Wrap to 2-3 lines max | Show more context per entry | |

**User's choice:** Truncate with ellipsis
**Notes:** None

---

## Claude's Discretion

- Case-insensitive vs case-sensitive snippet matching
- Whisper prompt format (comma-separated vs context sentences)
- Token cap prioritization strategy
- SF Symbol choices, sheet styling, search implementation details

## Deferred Ideas

None — discussion stayed within phase scope
