# Dashboard capture evidence

The host completed `capture.mjs` using Edge 157.0.4341.60. This directory contains
18 PNGs and `keyboard-log.json`, with separate runs at 1280x900 and 500x900 CSS
pixels. `capture.log` records the earlier failed sandbox attempt, not the
successful host capture.

The capture generated `populated.html` and `empty.html` from the worktree's
dashboard template, CSS, and JavaScript. Both generated pages were compared with
the current assets after sample-data substitution and match exactly. The sample
has long identifiers, a long blocker, resolved blocker history, and a report with
180 lines and a final marker. It is separate from real job records. Node is used
only for this optional capture. Product helpers and required checks do not depend
on it.

At both widths, the log records Tab navigation, Enter opening, visible focus on
Close and report text, and PageDown events. Report scrollTop increases from 0 to
3327, with scrollHeight 3822 and clientHeight 495. The later-content captures
show `LATER-CONTENT-MARKER`. Tab reaches Close after scrolling. Separate Escape
and Close dismissals return visible focus to `builder.md`. Literal script text,
refresh suppression while open, and explicit refresh with restored focus pass.
The narrow explicit refresh also preserves scrollY 100.

| Evidence | Files at each width |
| --- | --- |
| Empty and populated boards | `*-empty.png`, `*-populated.png` |
| Initiating button and dialog focus | `*-focus-report.png`, `*-dialog.png` |
| Report focus before and after scrolling | `*-report-start.png`, `*-later-content.png` |
| Reachable Close after scrolling | `*-close-after-scroll.png` |
| Focus return after both dismissal paths | `*-escape-focus-return.png`, `*-close-focus-return.png` |

Prefixes are `desktop` and `narrow`. The builder inspected eight captures,
including narrow long content and empty state, desktop and narrow report states,
and focus return. No layout defect was observed. Independent UI and UX review
remain controller work.

The capture identifies working tree assets rather than a builder commit. The host
will record the delivered commit and hashes of the identical captured assets
after committing. No implementation or dashboard asset changed during this
handoff update.

Round 2 changed only issue test decoding, fixture launchers, and evidence.
The production helpers and all dashboard assets still match
`bfb41aac844edd7382a1133068bc811506391c32`. The dashboard hashes in
`../successor-validation.txt` were rechecked and match. The builder re-inspected
`narrow-later-content.png` and `desktop-close-after-scroll.png`. Both show the
later-content marker and reachable Close. Existing captures remain applicable.

The ignored `edge-profile/` remains untouched. Automatic approval review rejected
its earlier cleanup as "blocked by policy". Cleanup is unnecessary, and no retry
or alternate deletion method was used.
