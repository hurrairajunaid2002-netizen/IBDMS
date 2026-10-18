"""
Medically accurate ABO/Rh recipient ↔ donor compatibility (Red Cross standard).

Mapping: for each recipient blood type, which DONOR blood types they may receive from.
"""

from __future__ import annotations

import re
from typing import FrozenSet, List, Optional

# Recipient → compatible donor blood types
RECIPIENT_CAN_RECEIVE_FROM: dict[str, FrozenSet[str]] = {
    "A+": frozenset({"A+", "A-", "O+", "O-"}),
    "A-": frozenset({"A-", "O-"}),
    "B+": frozenset({"B+", "B-", "O+", "O-"}),
    "B-": frozenset({"B-", "O-"}),
    "AB+": frozenset({"A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"}),
    "AB-": frozenset({"A-", "B-", "AB-", "O-"}),
    "O+": frozenset({"O+", "O-"}),
    "O-": frozenset({"O-"}),
}

_VALID = frozenset(RECIPIENT_CAN_RECEIVE_FROM.keys())
_ABO_RE = re.compile(r"^\s*([ABO]{1,2})([+-])\s*$", re.IGNORECASE)


def normalize_blood_group(value: object) -> Optional[str]:
    """
    Sanitize blood type: trim, uppercase ABO, preserve +/-.
    Examples: ' o+ ' → 'O+', 'ab-' → 'AB-'
    """
    if value is None:
        return None
    raw = str(value).strip().upper().replace(" ", "")
    if not raw:
        return None
    m = _ABO_RE.match(raw)
    if not m:
        return None
    abo = m.group(1).upper()
    rh = m.group(2)
    if abo not in ("A", "B", "O", "AB"):
        return None
    canonical = f"{abo}{rh}"
    return canonical if canonical in _VALID else None


def compatible_donor_groups(recipient_blood: object) -> List[str]:
    """
    Return sorted list of donor blood types compatible with [recipient_blood].
    Unknown types → empty list.
    """
    normalized = normalize_blood_group(recipient_blood)
    if not normalized:
        return []
    donors = RECIPIENT_CAN_RECEIVE_FROM[normalized]
    return sorted(donors)


def is_donor_compatible(donor_blood: object, recipient_blood: object) -> bool:
    """True when donor can donate to recipient per standard compatibility rules."""
    recipient = normalize_blood_group(recipient_blood)
    donor = normalize_blood_group(donor_blood)
    if not recipient or not donor:
        return False
    return donor in RECIPIENT_CAN_RECEIVE_FROM[recipient]


def compatibility_label(recipient_blood: object) -> str:
    """Human-readable label for Flutter, e.g. 'A+, A-, O+, O-'."""
    groups = compatible_donor_groups(recipient_blood)
    return ", ".join(groups) if groups else "—"
