export type RecordData = Record<string, any>;
export const display = (value: unknown) =>
  value === null || value === undefined || value === ""
    ? "Unavailable"
    : String(value);
export const date = (value: string | undefined) =>
  value && Number.isFinite(Date.parse(value))
    ? new Date(value).toLocaleString()
    : "Unavailable";
export function duration(attempt: RecordData) {
  if (!attempt.started_at || !attempt.ended_at) return "Unavailable";
  const seconds =
    (Date.parse(attempt.ended_at) - Date.parse(attempt.started_at)) / 1000;
  return Number.isFinite(seconds) && seconds >= 0
    ? `${seconds.toFixed(1)}s`
    : "Unavailable";
}
export function timeline(attempts: RecordData[]): RecordData[] {
  let left = 0;
  return attempts.map((attempt) => {
    const elapsed = attempt.ended_at
      ? Date.parse(attempt.ended_at) - Date.parse(attempt.started_at)
      : 0;
    const width = Math.max(
      120,
      Math.min(1200, Number.isFinite(elapsed) ? elapsed / 500 : 0),
    );
    const block = { ...attempt, left, width };
    left += width + 12;
    return block;
  });
}
