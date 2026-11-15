# Public writing rules

This repository is public. PR titles and bodies, issues, comments, commit messages, release notes, and website copy are read by people who know nothing about how the work was done. Write for them.

Do not include:

1. **Internal or agent links.** No `claude.ai` links of any kind: sessions, project threads, artifacts, or chats. No `Claude-Session:` commit trailers. The plain footer link to `https://claude.ai/code` is fine. Any other link must work for a stranger and add something for them.
2. **Agent chatter or process notes.** No "I", "as requested", "the user", "the thread", "the coordinator", "your Mac", "on the maintainer's desktop", or notes about how the agent worked. Describe the change and its evidence, not the conversation.
3. **Personal information.** No names of people who aren't public contributors, no private anecdotes ("a colleague couldn't..."), no email addresses, device names, or account IDs.
4. **Local paths and IDs.** No `/Users/...`, `/home/...`, `/mnt/...`, `/tmp/...`, session, message, or channel IDs.
5. **Internal status, dates, and plans.** No "CI is down until Nov 30", no quota or billing details, no unreleased plans or private deadlines. If CI did not run, say "CI did not run on this PR" and say what was run instead.
6. **Secrets.** No tokens, keys, passwords, signing identities, or private URLs, even partial or expired ones.
7. **Claims you did not check.** No "fully tested" or "fixes all". State what was run and what was not. Mark a guess as a guess.
8. **Leftovers.** No duplicate or stale screenshots, images after the footer, template hint comments, `TODO`s, or unchecked boxes without a reason.

The `public-copy-review` skill (`.claude/skills/public-copy-review/`) checks text against these rules. Its hook blocks rules 1, 4, and 6 outright, because a script can find them without judgment.
