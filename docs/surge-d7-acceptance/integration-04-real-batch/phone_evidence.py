#!/usr/bin/env python3
"""Phone-failure evidence classification (integration-04, Review
6034204978 point 3).

The gap: both importers READ trial_generation (v2 receiver column)
but filtered only on the old cv/mode/sha fields. A trial-pool failure
row -- control_verified=1, probe_mode='external_policy_id',
bearer='cellular', and an identity that also happens to be a formal
pool member (the trial Canada node shares its identity with the formal
Canada node) -- passed every old gate and was imported as FORMAL
deletion evidence. Trial evidence must never become formal prune
evidence through the importer.

Classification (one function, used by BOTH importers so they cannot
drift apart):

  * trial_generation is an integer (not None) -> "trial_bound".
    The row belongs to a trial generation: it is trial-path evidence
    (verify_promotion), never formal prune evidence. It is skipped
    with its own reason and NEVER imported, whatever its cv/mode/
    bearer say.
  * trial_generation is None -> "formal_historical". This is the old
    formal receiver's historical trusted evidence, kept compatible in
    its own single column: it may still be imported when it passes all
    the old gates, and it is reported separately from any new-mode
    evidence so the two are never confused. A pre-v2 trial legacy row
    is ALSO None -- but such a row is bound to the trial pool SHA, not
    the formal pool SHA, so the existing sha/key gates (v2 importer:
    sha == current formal pool SHA; v1 importer: key in current formal
    pool keys) already exclude it before this classifier is consulted.
    The classifier never invents a distinction the data cannot support.

The imported detail carries the class explicitly so a later reader can
tell it apart without re-reading staging:
  * v2 importer (JSON detail): "evidence_class": "formal_historical".
  * v1 importer (key=value detail): " evidence_class=formal_historical".
Rows written by the pre-v2 importers carry no marker; they are formal
by provenance (the old importer only ever read the formal staging DB)
and classify as "formal_historical" here too.

Consumer side (defense in depth): classify_failure_detail(detail)
parses a phone_failures detail (JSON or legacy key=value string) and
returns the evidence class. A prune consumer MUST only consume
"formal_historical" rows. A row whose detail says
trial_generation=<int> (i.e. a trial-bound row that somehow reached
phone_failures, e.g. written by a pre-fix importer or by hand) is
"trial_bound" and must be skipped even if it is present -- rollback
to the old importer can never resurrect it as consumable evidence,
because the old importer never wrote trial rows in the first place
and the consumer refuses trial-bound rows wherever they came from.

No credentials, no pool bytes, no URIs are read or written here: the
classifier sees only (trial_generation, dual_target_ok) and the detail
string, both of which are audit metadata.
"""

FORMAL_HISTORICAL = "formal_historical"
TRIAL_BOUND = "trial_bound"


def classify_row(trial_generation):
    """Evidence class of one staging observation row.

    trial_generation is an integer -> TRIAL_BOUND (trial-path evidence,
    never formal prune evidence). None -> FORMAL_HISTORICAL (old formal
    receiver evidence, compatible in its own column).
    """
    if trial_generation is None:
        return FORMAL_HISTORICAL
    return TRIAL_BOUND


def _detail_value(detail, key):
    """Extract one value from a phone_failures detail string.

    Tries JSON first (v2 importer detail), then legacy key=value pairs
    (v1 importer detail). Returns the raw value (str/int/None) or None
    when the key is absent or the detail is unparseable. Never raises.
    """
    if not isinstance(detail, str) or not detail:
        return None
    import json
    try:
        obj = json.loads(detail)
        if isinstance(obj, dict) and key in obj:
            return obj[key]
    except (ValueError, TypeError):
        pass
    for part in detail.split():
        if "=" in part:
            k, _, v = part.partition("=")
            if k == key:
                return v
    return None


def classify_failure_detail(detail):
    """Evidence class of one phone_failures row, from its detail.

    Returns FORMAL_HISTORICAL or TRIAL_BOUND:
      * detail carries evidence_class=formal_historical -> formal.
      * detail carries trial_generation=<int> -> trial_bound (a
        trial-bound row must never be consumed as formal evidence,
        wherever it came from).
      * detail carries trial_generation=None/null (or no marker at
        all, i.e. a pre-v2 row) -> formal_historical (formal by
        provenance: the old importer only read the formal staging DB).
    """
    cls = _detail_value(detail, "evidence_class")
    if cls == TRIAL_BOUND:
        return TRIAL_BOUND
    if cls == FORMAL_HISTORICAL:
        return FORMAL_HISTORICAL
    gen = _detail_value(detail, "trial_generation")
    if gen is None:
        return FORMAL_HISTORICAL
    if isinstance(gen, bool):
        return FORMAL_HISTORICAL
    if isinstance(gen, int):
        return TRIAL_BOUND
    if isinstance(gen, str):
        if gen in ("None", "null", ""):
            return FORMAL_HISTORICAL
        try:
            int(gen)
            return TRIAL_BOUND
        except ValueError:
            return FORMAL_HISTORICAL
    return FORMAL_HISTORICAL
