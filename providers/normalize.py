#!/usr/bin/env python3
"""providers/normalize.py — provider-neutral transcript normalization.

Maps a raw model-turn payload from different providers into one `NormalizedTurn`
so the llm-dark-patterns detectors (which read the assistant's closeout text and the
tool calls it actually emitted) can run cross-model. Pure standard library, no network.

See providers/CONTRACT.md for the schema and the per-provider mapping table.
"""
from dataclasses import dataclass, field


@dataclass
class NormalizedTurn:
    assistant_message: str = ""
    tool_calls: list = field(default_factory=list)  # [{"name": str, "arguments": str|dict}]

    def tool_names(self):
        return [str(tc.get("name", "")) for tc in self.tool_calls]


def _s(x):
    return x if isinstance(x, str) else ""


def from_claude_hook(payload):
    """Claude Code Stop / SubagentStop / PreToolUse hook JSON.

    assistant_message <- `.last_assistant_message` (version-gated; falls back to the last
    assistant turn in an inline `.messages`/`.transcript` if present — see CONTRACT.md).
    tool_calls <- a PreToolUse `tool_name`/`tool_input`, and/or `tool_use` blocks in an
    inline transcript. `Task`/Agent tool_input keys are treated as an opaque object.
    """
    d = payload if isinstance(payload, dict) else {}
    msg = _s(d.get("last_assistant_message"))
    tcs = []
    if d.get("tool_name"):
        tcs.append({"name": str(d.get("tool_name")), "arguments": d.get("tool_input", {})})
    msgs = d.get("messages") or d.get("transcript") or []
    if isinstance(msgs, list):
        for m in msgs:
            if not isinstance(m, dict) or m.get("role") != "assistant":
                continue
            content = m.get("content")
            if isinstance(content, str):
                if not msg:
                    msg = content
            elif isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict):
                        continue
                    if block.get("type") == "text" and not msg:
                        msg = _s(block.get("text"))
                    elif block.get("type") == "tool_use":
                        tcs.append({"name": str(block.get("name", "")),
                                    "arguments": block.get("input", {})})
    return NormalizedTurn(assistant_message=msg, tool_calls=tcs)


def from_openai_chat(payload):
    """OpenAI Chat Completions response."""
    d = payload if isinstance(payload, dict) else {}
    choices = d.get("choices") or []
    msg, tcs = "", []
    if choices and isinstance(choices[0], dict):
        m = choices[0].get("message") or {}
        msg = _s(m.get("content"))
        for tc in (m.get("tool_calls") or []):
            fn = (tc or {}).get("function") or {}
            tcs.append({"name": str(fn.get("name", "")), "arguments": fn.get("arguments", "")})
    return NormalizedTurn(assistant_message=msg, tool_calls=tcs)


def from_openai_responses(payload):
    """OpenAI Responses API response (output items; flat function_call name/arguments)."""
    d = payload if isinstance(payload, dict) else {}
    parts, tcs = [], []
    for item in (d.get("output") or []):
        if not isinstance(item, dict):
            continue
        t = item.get("type")
        if t == "function_call":
            tcs.append({"name": str(item.get("name", "")), "arguments": item.get("arguments", "")})
        elif t == "message" or item.get("role") == "assistant":
            content = item.get("content")
            if isinstance(content, str):
                parts.append(content)
            elif isinstance(content, list):
                for c in content:
                    if isinstance(c, dict) and c.get("type") in ("output_text", "text"):
                        parts.append(_s(c.get("text")))
    if not parts and isinstance(d.get("output_text"), str):
        parts.append(d["output_text"])
    return NormalizedTurn(assistant_message="".join(parts), tool_calls=tcs)


def from_kimi(payload):
    """Kimi / Moonshot — OpenAI-compatible Chat shape, with two quirks:
    `reasoning_content` is NOT part of the answer (excluded), and server-executed
    `builtin_function` tool-call echoes (type != "function") are skipped.
    """
    d = payload if isinstance(payload, dict) else {}
    choices = d.get("choices") or []
    msg, tcs = "", []
    if choices and isinstance(choices[0], dict):
        m = choices[0].get("message") or {}
        msg = _s(m.get("content"))  # deliberately NOT reasoning_content
        for tc in (m.get("tool_calls") or []):
            if (tc or {}).get("type") not in (None, "function"):
                continue  # skip builtin_function server-side echoes
            fn = (tc or {}).get("function") or {}
            tcs.append({"name": str(fn.get("name", "")), "arguments": fn.get("arguments", "")})
    return NormalizedTurn(assistant_message=msg, tool_calls=tcs)


ADAPTERS = {
    "claude_hook": from_claude_hook,
    "openai_chat": from_openai_chat,
    "openai_responses": from_openai_responses,
    "kimi": from_kimi,
}
