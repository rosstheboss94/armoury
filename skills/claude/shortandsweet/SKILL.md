---
name: shortandsweet
description: Explain things concisely with short sections, bullets, and numbered steps. Use when asked for an explanation, walkthrough, or breakdown, or when explicitly invoked.
---

# Short and sweet

Make explanations easy to scan while keeping enough detail to understand and act.

## When to apply

- Apply when the user invokes `/shortandsweet` or asks for an explanation,
  walkthrough, or breakdown.
- Match the user's knowledge and requested depth. Define unfamiliar terms on
  first use.
- Follow explicit requests for a different format or more detail.

## Shape the answer

1. Lead with the answer or main takeaway in one short sentence.
2. Group longer explanations under short, descriptive, sentence-case headings.
   Aim for two to four sections when useful. A simple answer can use one list
   without headings.
3. Use bullets for ideas and numbered lists when order matters, such as steps
   in a procedure. Keep each item to one idea and one or two short sentences.
4. Add a brief example when it makes the idea clearer. Keep code in fenced
   blocks and explain only the parts the reader needs.
5. Stop when the question is answered. Cut repeated summaries and offers to
   explain more.

## Keep it readable and complete

- Use plain words, active voice, and concrete details.
- Split dense paragraphs into distinct points. Shorten dense sentences too,
  so a bullet does not become a paragraph in disguise.
- Keep lists flat where possible. Use at most one nested level when a point
  needs supporting detail.
- Use bold sparingly. Skip decorative formatting, filler introductions, and
  labels that repeat the bullet's text.
- Preserve necessary caveats, uncertainty, sources, prerequisites, and code.
  Brevity must not change the meaning or omit information needed to act.
- Treat the suggested lengths as defaults, with no hard word limit. For a
  complex topic or a request for depth, add sections and examples while
  keeping each point focused.

## Examples

### Concept explanation

User request: "Explain caching."

Example answer:

Caching saves a result so later requests can reuse it.

#### How it works

- The app checks for a saved result before doing the work again.
- If it finds one, it returns that result. Otherwise, it computes the result
  and saves a copy.

#### Example and tradeoff

- A weather app can reuse a forecast for five minutes instead of fetching it
  every time you open the screen.
- Saved data can become outdated. Expiry rules decide when to fetch a fresh copy.

### Procedural walkthrough

User request: "Walk me through making a Git commit."

Example answer:

A Git commit records the changes you stage in your local repository.

#### Review and stage

1. Run `git status` and `git diff` to inspect your changes.
2. Run `git add path/to/file` for each file you want to include.

#### Commit and check

1. Run `git diff --staged` to review exactly what the commit will contain.
2. Run `git commit -m "Describe the change"` to save it.
3. Run `git status` to see any changes still outside the commit.
