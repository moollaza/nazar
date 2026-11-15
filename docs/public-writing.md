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
8. **Meta-commentary.** Don't talk about the repo being public, who reads it, or how the text or code was produced. Don't explain that an AI or agent did or reviewed something. Write like a senior engineer: what changed, why, how it was tested. Cut anything a reviewer would skim past.

   Bad: "This repository is public, so every PR, issue, comment, and release note is read by strangers. This PR adds a Claude Code skill and hook. The skill has an AI agent review that text before it is posted, and the hook blocks GitHub posts that skip the review."

   Good: "Adds a pre-post review for PR, issue, and release text, and a hook that blocks posts that skip it."
9. **Leftovers.** No duplicate or stale screenshots, images after the footer, template hint comments, `TODO`s, or unchecked boxes without a reason.

In Claude Code, a hook in `.claude/settings.json` checks every PR, issue, comment, review, and release post against this guide and blocks the post until the text follows it.
