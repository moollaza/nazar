#!/usr/bin/env python3
"""Gate public GitHub posts on a passed copy review.

  copy_review.py stamp FILE   record that FILE's text passed review
  copy_review.py hook         PreToolUse hook: read the tool call on stdin,
                              deny a post whose body has no stamp

A stamp is the SHA-256 of the normalized text, kept under the git common dir,
so the text that was reviewed is the text that gets posted.
"""
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

SKILL = ".claude/skills/public-copy-review/SKILL.md"

MCP_BODY_TOOLS = {
    "mcp__github__create_pull_request",
    "mcp__github__update_pull_request",
    "mcp__github__issue_write",
    "mcp__github__add_issue_comment",
    "mcp__github__update_issue_comment",
    "mcp__github__add_reply_to_pull_request_comment",
    "mcp__github__add_comment_to_pending_review",
    "mcp__github__pull_request_review_write",
}

GH_POST = re.compile(
    r"\bgh\s+(?:(?:pr|issue)\s+(?:create|edit|comment|review)|release\s+(?:create|edit))\b"
)
GH_API = re.compile(r"\bgh\s+api\b")
INLINE_BODY_FLAGS = {"--body", "-b", "--notes", "-n", "--fill", "--fill-first", "--fill-verbose"}
BODY_FILE_FLAGS = {"--body-file", "-F", "--notes-file"}


def normalize(text: str) -> str:
    lines = text.replace("\r\n", "\n").split("\n")
    return "\n".join(line.rstrip() for line in lines).strip()


def digest(text: str) -> str:
    return hashlib.sha256(normalize(text).encode()).hexdigest()


def stamp_dir() -> Path:
    root = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    common = subprocess.run(
        ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"],
        cwd=root, capture_output=True, text=True, check=True,
    ).stdout.strip()
    return Path(common) / "copy-review"


def is_stamped(text: str) -> bool:
    return (stamp_dir() / digest(text)).exists()


def deny(reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))


def unreviewed(what: str) -> str:
    return (
        f"Blocked: {what} is public and has not passed the copy review. "
        f"Follow {SKILL}: write the exact text to a file, get a PASS from a "
        "fresh reviewer, run `copy_review.py stamp <file>`, then post that "
        "file unchanged."
    )


def bash_bodies(command: str, cwd: str):
    """Yield ('file', path) or ('inline', None) for each body a gh post carries."""
    try:
        argv = shlex.split(command)
    except ValueError:
        argv = command.split()
    for i, arg in enumerate(argv):
        flag, _, value = arg.partition("=")
        if flag in BODY_FILE_FLAGS:
            path = value or (argv[i + 1] if i + 1 < len(argv) else "")
            yield "file", Path(cwd, path)
        elif flag in INLINE_BODY_FLAGS:
            yield "inline", None


def check_bash(command: str, cwd: str) -> None:
    if GH_API.search(command) and re.search(r"(?:-f|-F|--field|--raw-field)\s+(?:body|title)=", command):
        if not re.search(r"body=@", command):
            deny(unreviewed("a `gh api` body") + " Use `-F body=@<file>` so the reviewed file is what gets sent.")
            return
        for path in re.findall(r"body=@(\S+)", command):
            if not is_stamped(Path(cwd, path).read_text()):
                deny(unreviewed(f"`{path}`"))
                return
        return
    if not GH_POST.search(command):
        return
    for kind, path in bash_bodies(command, cwd):
        if kind == "inline":
            deny(unreviewed("an inline or auto-filled body") + " Pass the text with --body-file instead.")
            return
        if str(path).endswith("/-"):
            deny("Blocked: body from stdin can't be checked. Write it to a file and use --body-file.")
            return
        if not path.exists() or not is_stamped(path.read_text()):
            deny(unreviewed(f"`{path}`"))
            return


def hook() -> None:
    call = json.load(sys.stdin)
    tool = call.get("tool_name", "")
    args = call.get("tool_input") or {}
    if tool == "Bash":
        check_bash(args.get("command", ""), call.get("cwd") or os.getcwd())
    elif tool in MCP_BODY_TOOLS:
        body = args.get("body")
        if isinstance(body, str) and body.strip() and not is_stamped(body):
            deny(unreviewed(f"the body for {tool}"))


def stamp(path: str) -> None:
    d = stamp_dir()
    d.mkdir(parents=True, exist_ok=True)
    h = digest(Path(path).read_text())
    (d / h).touch()
    print(f"stamped {path} ({h[:12]})")


if __name__ == "__main__":
    if sys.argv[1:2] == ["hook"]:
        hook()
    elif sys.argv[1:2] == ["stamp"] and len(sys.argv) == 3:
        stamp(sys.argv[2])
    else:
        sys.exit(__doc__)
