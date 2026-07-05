"""
Guidance source for the voice coach — the single seam for "everything flows from
dad's rules, nothing from the AI's own opinions."

CONTRACT: all coaching content (suggestions + answers about training, nutrition,
recovery, effort, technique) goes through `GuidanceSource.consult()`. The agent
treats whatever this returns as the source of truth.

Today it's an AI placeholder (returns None → the agent falls back to general
knowledge, clearly marked as temporary). To flip the coach to dad's-rules-only,
change ONE line in `make_guidance_source()` from AIGuidanceSource to
DadRulesGuidanceSource. Nothing else in the agent changes.
"""

from __future__ import annotations

import os
from typing import Optional


class GuidanceSource:
    async def consult(self, topic: str) -> Optional[str]:
        """Return dad's rule text relevant to `topic`, or None if no rule applies."""
        raise NotImplementedError


class AIGuidanceSource(GuidanceSource):
    """PLACEHOLDER until the dad-rules Supabase table is wired.

    Returns None for everything → tells the agent "no specific rule, use your own
    general knowledge FOR NOW." Swap this out to make the coach dad's-rules-only.
    """

    async def consult(self, topic: str) -> Optional[str]:
        return None


class DadRulesGuidanceSource(GuidanceSource):
    """FUTURE: dad's rules from Supabase (the dad-OS rules table).

    When ready: init a Supabase client and query the rules table (keyword or
    semantic match on `topic`). Return the best-matching rule text, or None if
    nothing applies — the agent will then say it has no rule rather than guess.
    """

    def __init__(self, url: str, key: str, table: str = "dad_rules") -> None:
        self._url = url
        self._key = key
        self._table = table
        # TODO: from supabase import create_client; self._db = create_client(url, key)

    async def consult(self, topic: str) -> Optional[str]:
        # TODO: query self._table for the rule(s) matching `topic`; return text or None.
        return None


def make_guidance_source() -> GuidanceSource:
    """THE ONE SWITCH.

    Today → AIGuidanceSource() (placeholder).
    Dad's-rules-only → return DadRulesGuidanceSource(
        os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"]).
    """
    return AIGuidanceSource()
