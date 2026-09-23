#!/usr/bin/env python3
"""Scenario plan generator for clipboard_live.sh (D1/D4).

Emits the plan JSON consumed by the driver. Each scenario records whether it
requires candidate event-tap shortcut evidence; tap-dependent scenarios are
blocked (not silently degraded) when the probe establishes the tap is
unavailable.
"""
import argparse
import json
import sys

SCENARIOS = {
    "input_qualification": {"requiresEventTap": True},
    "successive_ab_copies": {"requiresEventTap": False},
    "cut_editable_text": {"requiresEventTap": True},
    "clipboard_screenshot_region": {"requiresEventTap": False},
    "copy_then_switch_keyboard": {"requiresEventTap": True},
    "copy_then_switch_non_keyboard": {"requiresEventTap": False},
    "restore_paste": {"requiresEventTap": False},
    "restore_paste_negative": {"requiresEventTap": False},
    "event_tap_failure_injection": {"requiresEventTap": False},
    "real_permission_denial": {"requiresEventTap": False},
}

PROFILES = {
    "qualify-input": ["input_qualification"],
    "routine": [
        "input_qualification",
        "successive_ab_copies",
        "cut_editable_text",
        "clipboard_screenshot_region",
        "copy_then_switch_keyboard",
        "copy_then_switch_non_keyboard",
        "restore_paste",
        "restore_paste_negative",
        "event_tap_failure_injection",
        "real_permission_denial",
    ],
}

# Scenarios that must pass for the profile to exit 0 (D7). real_permission_denial
# is reported separately: it requires a prepared denied-permission session and is
# never required from the routine runner (D4).
REQUIRED = {
    "qualify-input": ["input_qualification"],
    "routine": [
        "input_qualification",
        "successive_ab_copies",
        "cut_editable_text",
        "clipboard_screenshot_region",
        "copy_then_switch_keyboard",
        "copy_then_switch_non_keyboard",
        "restore_paste",
        "restore_paste_negative",
        "event_tap_failure_injection",
    ],
    "original-writer": ["original_writer_replay"],
}


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    plan = sub.add_parser("plan")
    plan.add_argument("--profile", required=True)
    plan.add_argument("--out", required=True)
    args = parser.parse_args()

    if args.profile not in PROFILES:
        print(f"unknown profile: {args.profile}", file=sys.stderr)
        return 2

    document = {
        "profile": args.profile,
        "scenarios": [
            {"name": name, "requiresEventTap": SCENARIOS[name]["requiresEventTap"]}
            for name in PROFILES[args.profile]
        ],
        "requiredScenarios": REQUIRED[args.profile],
    }
    try:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(document, handle, indent=2, sort_keys=True)
            handle.write("\n")
    except OSError as error:
        print(f"cannot write plan {args.out}: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
