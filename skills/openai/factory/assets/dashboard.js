const board = document.querySelector('#jobs');
const status = document.querySelector('#status');
const dialog = document.querySelector('#artifact');
let reportButton;
document.querySelector('#close').addEventListener('click', () => dialog.close());
dialog.addEventListener('close', () => reportButton?.focus({ preventScroll: true }));
function element(tag, text, className) {
  const node = document.createElement(tag);
  node.textContent = text;
  if (className) node.className = className;
  return node;
}
try {
  const rows = JSON.parse(document.querySelector('#factory-data').textContent);
  for (const job of rows) {
    const card = element('article', '', job.stage);
    card.append(element('h2', job.id), element('span', job.stage, 'stage'));
    card.append(element('p', `Round ${job.round} of ${job.limit}. Default runner: ${job.runner}.`));
    if (job.blocker) card.append(element('p', job.blocker, 'blocker'));
    if (job.pr_url && /^https:\/\/github\.com\//.test(job.pr_url)) {
      const link = element('a', 'Open pull request');
      link.href = job.pr_url; link.rel = 'noreferrer'; card.append(link);
    }
    for (const [name, report] of Object.entries(job.artifacts || {})) {
      const button = element('button', name);
      button.type = 'button';
      button.addEventListener('click', () => {
        reportButton = button;
        document.querySelector('#report-heading').textContent = `${job.id}: ${name}`;
        document.querySelector('#report').textContent = report;
        dialog.showModal();
      });
      card.append(button);
    }
    board.append(card);
  }
  status.textContent = rows.length ? `${rows.length} jobs. Use Refresh jobs to load the latest saved snapshot.` : 'No jobs yet. Use Refresh jobs to load the latest saved snapshot.';
} catch (error) { status.textContent = `Could not read the job snapshot: ${error.message}`; }
const refresh = document.querySelector('#refresh');
const positionKey = 'factory-refresh-position';
refresh.addEventListener('click', () => {
  if (dialog.open) return;
  try { sessionStorage.setItem(positionKey, JSON.stringify({ x: scrollX, y: scrollY })); } catch { }
  location.reload();
});
try {
  const position = JSON.parse(sessionStorage.getItem(positionKey));
  sessionStorage.removeItem(positionKey);
  if (position) requestAnimationFrame(() => {
    refresh.focus({ preventScroll: true });
    scrollTo(position.x, position.y);
  });
} catch { }
