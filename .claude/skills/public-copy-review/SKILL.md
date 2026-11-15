---
name: public-copy-review
description: Review public text through a stranger's eyes before it is posted. Use before opening or editing a PR, issue, comment, review, or release on GitHub, and on any diff that changes public copy (README, website/, CHANGELOG, App Store text, UI strings).
---

# Public copy review

This repository is public. Anyone can read every PR, issue, comment, and release note, and the website, README, and App Store listing are the product's face. This skill gets a second reader to check that text before it goes out.

A hook in `.claude/settings.json` blocks GitHub posts (`gh pr|issue create|edit|comment`, `gh pr review`, `gh release create|edit`, `gh api` bodies, and the GitHub MCP write tools) until the exact body has passed this review.

## Steps

1. Write the exact body to a file outside the repo, with an absolute path such as `$TMPDIR/pr-body.md`. For a copy change in the diff, also save `git diff -- <copy files>` to a second file.
2. Spawn a fresh subagent (`Agent` tool, `general-purpose`) and tell it to act as the reviewer in this file's **Reviewer prompt** section. Give it only that instruction, the title (if there is one), and the file paths. Do not pass your reasoning, the conversation, or your opinion of the text. The reviewer must read it cold, like the public does.
3. If the verdict is `FIX`, apply the edits that hold up, rewrite the file, and run step 2 again with a new subagent. Stop after three rounds and show the person the open findings.
4. On `PASS`, stamp the body:

   ```bash
   python3 .claude/skills/public-copy-review/copy_review.py stamp <body-file>
   ```

5. Post with the same file: `gh pr create --title "..." --body-file <file>`, or pass the file's contents unchanged as `body` to a GitHub MCP tool. Any edit after the stamp needs a new review.

## Reviewer prompt

> You are reviewing text that will be published in the public GitHub repository and website of Nazar, an open-source macOS menu bar app that watches status pages and alerts on outages. Read the title `<title>`, the body in `<file>`, and `<diff file>` if given, as a stranger would: a developer browsing the repo, a user deciding whether to install, or an App Store reviewer. You have no other context, and neither do they.
>
> Flag anything that would embarrass the project or confuse that reader:
>
> 1. **Leaked internals.** Agent or tool chatter ("as requested", "I", "the user", "this thread", "the coordinator"), session IDs, private names, local paths like `/Users/...` or `/mnt/...`, internal tickets, secrets, or notes meant for a teammate.
> 2. **Unclear.** Jargon or abbreviations a newcomer can't decode, a title that doesn't say what changed, missing why, a reader can't tell what to do.
> 3. **Unprofessional tone.** Slang, sarcasm, blame, exclamation-heavy hype, emoji clutter, filler ("simply", "just", "robust", "seamless", "leverage"), AI-sounding padding.
> 4. **Wrong or overclaimed.** Claims the text doesn't support ("fully tested", "fixes all", "never"), numbers that look invented, promises about the future.
> 5. **Sloppy.** Typos, broken Markdown or links, leftover template comments or placeholders (`TODO`, `<!-- ... -->` hints, empty checkboxes left unexplained), inconsistent product name (it's "Nazar").
>
> Do not flag: the required `<!-- claude-projects-attribution ... -->` line and the `_Requested by ..._` line under it, the "Generated with Claude Code" footer and the `claude.ai/code/session_...` link under it, or conventional-commit prefixes like `fix(ui):` in titles. Don't rewrite for taste; flag only what a public reader would notice.
>
> Reply in exactly this form:
>
> ```
> VERDICT: PASS | FIX
> - [category] "<quoted text>" -> <replacement or what to do>
> ```
>
> `PASS` means nothing on the list above remains. Any finding means `FIX`.

## Without Claude Code

Other agents and humans don't get the hook. Before posting, run the reviewer prompt above in a fresh session or ask a second reader, and apply the same list.
