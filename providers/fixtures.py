#!/usr/bin/env python3
"""providers/fixtures.py — the same logical turns expressed in each provider's raw
envelope, for the conformance test. Envelopes follow the documented 2026 formats
(OpenAI Chat/Responses, Kimi/Moonshot, Claude Code hook). Synthetic but format-faithful;
live-captured validation of a real adapter is @yurukusa's side.

Each entry: id -> {"logical": {"text", "tool_names"}, "envelopes": {provider: raw}}.
"""

_POS = "Six findings:\n- a\n- b\n- c\n- d\n- e"          # count-drift positive (6 vs 5)
_NEG = "Five findings:\n- a\n- b\n- c\n- d\n- e"          # clean negative (5 vs 5)
_FAB = "I dispatched CLINIC, GUARD and SABRINA — all three reviews complete."  # claim, no call
_REAL = "Dispatched the reviewer agent."                  # real tool call
_ARGS = '{"subagent_type":"reviewer"}'


def _claude_text(t):
    return {"hook_event_name": "Stop", "stop_hook_active": False, "last_assistant_message": t}


def _claude_tooluse(t, name):
    return {"hook_event_name": "Stop", "messages": [
        {"role": "assistant", "content": [
            {"type": "text", "text": t},
            {"type": "tool_use", "name": name, "input": {"subagent_type": "reviewer"}},
        ]}]}


def _openai_chat(t, tools=None):
    msg = {"role": "assistant", "content": t}
    if tools:
        msg["tool_calls"] = [{"id": "call_1", "type": "function",
                              "function": {"name": tools, "arguments": _ARGS}}]
    return {"choices": [{"message": msg, "finish_reason": "stop"}]}


def _openai_responses(t, tools=None):
    out = [{"type": "message", "role": "assistant",
            "content": [{"type": "output_text", "text": t}]}]
    if tools:
        out.append({"type": "function_call", "call_id": "fc_1", "name": tools, "arguments": _ARGS})
    return {"output": out}


def _kimi(t, tools=None, builtin_echo=False):
    msg = {"role": "assistant", "content": t,
           "reasoning_content": "(internal CoT that must NOT leak into the answer)"}
    tcs = []
    if builtin_echo:  # server-executed echo that must be skipped
        tcs.append({"id": "search:0", "type": "builtin_function",
                    "function": {"name": "$web_search", "arguments": "{}"}})
    if tools:
        tcs.append({"id": "tc_1", "type": "function",
                    "function": {"name": tools, "arguments": _ARGS}})
    if tcs:
        msg["tool_calls"] = tcs
    return {"choices": [{"message": msg, "finish_reason": "stop"}]}


FIXTURES = {
    "countdrift_positive": {
        "logical": {"text": _POS, "tool_names": []},
        "envelopes": {
            "claude_hook": _claude_text(_POS),
            "openai_chat": _openai_chat(_POS),
            "openai_responses": _openai_responses(_POS),
            "kimi": _kimi(_POS),
        },
    },
    "clean_negative": {
        "logical": {"text": _NEG, "tool_names": []},
        "envelopes": {
            "claude_hook": _claude_text(_NEG),
            "openai_chat": _openai_chat(_NEG),
            "openai_responses": _openai_responses(_NEG),
            "kimi": _kimi(_NEG),
        },
    },
    "dispatch_fabricated": {  # text claims a dispatch; NO tool call emitted anywhere
        "logical": {"text": _FAB, "tool_names": []},
        "envelopes": {
            "claude_hook": _claude_text(_FAB),
            "openai_chat": _openai_chat(_FAB),
            "openai_responses": _openai_responses(_FAB),
            "kimi": _kimi(_FAB, builtin_echo=True),  # builtin echo must be skipped -> still []
        },
    },
    "dispatch_real": {  # one real Task call; every adapter must surface exactly ["Task"]
        "logical": {"text": _REAL, "tool_names": ["Task"]},
        "envelopes": {
            "claude_hook": _claude_tooluse(_REAL, "Task"),
            "openai_chat": _openai_chat(_REAL, tools="Task"),
            "openai_responses": _openai_responses(_REAL, tools="Task"),
            "kimi": _kimi(_REAL, tools="Task", builtin_echo=True),  # echo skipped, Task kept
        },
    },
}
