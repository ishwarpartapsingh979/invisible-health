"""The RULES LAYER — decoupled from the LLM (Phase 1).

Rules live as DATA in the Supabase `rules` table (trigger_conditions -> forces /
vetoes + rationale + tier + source + domain). This engine MATCHES rules against a
fused context and RESOLVES them into a deterministic decision. The LLM only
DELIVERS the decision; it never makes it.

Layering:
  match   -> every rule whose trigger conditions ⊆ context fires
  resolve -> tiers (0 safety > 1 arc > 2 sizing > 3 preference);
             VETOES ARE ABSOLUTE (any veto wins, blocks the matching force);
             on conflict, higher tier and dad(coach) > sports_science.
  output  -> {vetoes, forces (tiered), because[rationales], fired[ids+source]}

Reads Supabase via REST (SUPABASE_URL + SUPABASE_SERVICE_KEY). No-ops if absent.
"""

import logging
import os
import re

logger = logging.getLogger("voice-agent")

TIER_NAMES = {0: "safety", 1: "arc", 2: "sizing", 3: "preference"}


class RulesEngine:
    def __init__(self) -> None:
        self.url = (os.environ.get("SUPABASE_URL") or "").rstrip("/")
        self.key = os.environ.get("SUPABASE_SERVICE_KEY") or ""
        self.enabled = bool(self.url and self.key)
        if self.enabled:
            logger.info("RulesEngine enabled")

    def _headers(self):
        return {"apikey": self.key, "Authorization": f"Bearer {self.key}"}

    async def _fetch(self, domains) -> list:
        if not self.enabled:
            return []
        try:
            import aiohttp
            params = {"status": "eq.active", "select": "*"}
            if domains:
                params["domain"] = f"in.({','.join(domains)})"
            async with aiohttp.ClientSession() as s:
                async with s.get(f"{self.url}/rest/v1/rules", params=params,
                                 headers=self._headers(),
                                 timeout=aiohttp.ClientTimeout(total=15)) as r:
                    if r.status < 300:
                        return await r.json()
                    logger.warning("rules fetch %s", r.status)
        except Exception as e:
            logger.warning("rules fetch error: %s", e)
        return []

    @staticmethod
    def matches(trigger: dict, context: dict) -> bool:
        """ALL trigger conditions must match the context (ported from DadOSEngine).
        list -> context value must be in it; str -> case-insensitive partial;
        number -> exact; else equality. Missing context key -> no match."""
        for key, expected in (trigger or {}).items():
            cv = context.get(key)
            if isinstance(expected, list):
                # trigger value is a list of acceptable values OR the context is a list
                if isinstance(cv, list):
                    if not any(e in cv for e in expected):
                        return False
                elif cv not in expected:
                    return False
            elif isinstance(expected, str):
                if cv is None or cv == "":
                    return False
                # Numeric comparison triggers (">=2", "<=5", ">10") vs a numeric
                # context value.
                cmp = re.match(r"^\s*(>=|<=|==|>|<)\s*(-?\d+(?:\.\d+)?)\s*$", expected)
                if cmp:
                    try:
                        n = float(str(cv).strip())
                    except (TypeError, ValueError):
                        return False
                    op, val = cmp.group(1), float(cmp.group(2))
                    ok = {">=": n >= val, "<=": n <= val, "==": n == val,
                          ">": n > val, "<": n < val}[op]
                    if not ok:
                        return False
                    continue
                cvl = str(cv).lower()
                # "/" and "," in a trigger value mean OR (e.g. "knee/upper
                # hamstring"). Match if ANY alternative is a substring of the
                # context OR the context is a substring of it (both directions,
                # so canonical<->free-text both work).
                alts = [a.strip().lower() for part in expected.split("/")
                        for a in part.split(",") if a.strip()]
                if not any(a in cvl or cvl in a for a in alts):
                    return False
            elif isinstance(expected, (int, float)):
                if cv != expected:
                    return False
            else:
                if cv != expected:
                    return False
        return True

    async def resolve(self, context: dict, domains=None) -> dict:
        """Match + resolve rules for the given context. Returns a structured,
        deterministic decision the LLM must deliver within."""
        rules = await self._fetch(domains)
        fired = [r for r in rules if self.matches(r.get("trigger_conditions") or {}, context)]
        if not fired:
            return {"fired": [], "vetoes": [], "forces_by_tier": {}, "because": [], "empty": True}

        fired.sort(key=lambda r: (r.get("tier", 1), 0 if r.get("domain") == "coach" else 1))

        vetoes, forces_by_tier, because, fired_meta = [], {}, [], []
        for r in fired:
            tier = r.get("tier", 1)
            for v in (r.get("action_vetoes") or []):
                if v not in vetoes:
                    vetoes.append(v)
            for f in (r.get("action_forces") or []):
                # A force that is also vetoed is dropped (veto absolute).
                if any(f.lower() in v.lower() or v.lower() in f.lower() for v in vetoes):
                    continue
                forces_by_tier.setdefault(tier, [])
                if f not in forces_by_tier[tier]:
                    forces_by_tier[tier].append(f)
            if r.get("rationale"):
                because.append(r["rationale"])
            fired_meta.append({"id": r.get("id"), "domain": r.get("domain"),
                               "tier": tier, "source": r.get("source")})
        return {"fired": fired_meta, "vetoes": vetoes,
                "forces_by_tier": forces_by_tier, "because": because, "empty": False}

    async def log_firing(self, context: dict, decision: dict,
                         user_id: str = "ishwar") -> None:
        """Log the firing for audit + as future ML training data (context->decision)."""
        if not self.enabled or decision.get("empty"):
            return
        try:
            import aiohttp
            rows = [{"user_id": user_id, "rule_id": f.get("id"), "domain": f.get("domain"),
                     "decision": decision, "context": context}
                    for f in decision.get("fired", [])]
            headers = {**self._headers(), "Content-Type": "application/json",
                       "Prefer": "return=minimal"}
            async with aiohttp.ClientSession() as s:
                await s.post(f"{self.url}/rest/v1/rule_firings", json=rows,
                             headers=headers, timeout=aiohttp.ClientTimeout(total=10))
        except Exception as e:
            logger.warning("rule firing log failed: %s", e)

    @staticmethod
    def to_prompt(decision: dict) -> str:
        """Render the resolved decision as hard constraints for the LLM."""
        if decision.get("empty"):
            return ("No specific rules fired for this situation — coach off the "
                    "general method + what they're telling you, and stay safe.")
        lines = []
        if decision["vetoes"]:
            lines.append("MUST NOT (absolute): " + "; ".join(decision["vetoes"]))
        for tier in sorted(decision["forces_by_tier"]):
            fs = decision["forces_by_tier"][tier]
            if fs:
                lines.append(f"DO ({TIER_NAMES.get(tier, tier)}): " + "; ".join(fs))
        if decision["because"]:
            lines.append("Because: " + " ".join(decision["because"][:3]))
        lines.append("Follow these EXACTLY. Vetoes are absolute; on any conflict, "
                     "higher tier and dad's rules win. Deliver in your own warm voice.")
        return "\n".join(lines)
