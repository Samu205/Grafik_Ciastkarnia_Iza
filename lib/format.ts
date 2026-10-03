// Formatowanie dat i godzin po polsku.
// Daty z bazy przychodzą jako 'YYYY-MM-DD' – NIE przepuszczamy ich przez lokalne
// gettery Date (getDate() itp.), bo w innej strefie czasowej dałyby inny dzień.

const WEEKDAYS = ['niedziela', 'poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota'];
const WEEKDAYS_SHORT = ['nd.', 'pon.', 'wt.', 'śr.', 'czw.', 'pt.', 'sob.'];
const MONTHS = [
  'styczeń',
  'luty',
  'marzec',
  'kwiecień',
  'maj',
  'czerwiec',
  'lipiec',
  'sierpień',
  'wrzesień',
  'październik',
  'listopad',
  'grudzień',
];

function parts(isoDate: string): { year: number; month: number; day: number } {
  const [year, month, day] = isoDate.split('-').map(Number);
  if (!year || !month || !day) {
    throw new Error(`Nieprawidłowa data: ${isoDate}`);
  }
  return { year, month, day };
}

function weekdayIndex(isoDate: string): number {
  const { year, month, day } = parts(isoDate);
  return new Date(Date.UTC(year, month - 1, day)).getUTCDay();
}

/** '2026-10-14' → '14.10 (śr.)' */
export function formatShortDate(isoDate: string): string {
  const { month, day } = parts(isoDate);
  const dd = String(day).padStart(2, '0');
  const mm = String(month).padStart(2, '0');
  return `${dd}.${mm} (${WEEKDAYS_SHORT[weekdayIndex(isoDate)]})`;
}

/** '2026-10-14' → 'środa, 14.10.2026' */
export function formatLongDate(isoDate: string): string {
  const { year, month, day } = parts(isoDate);
  const dd = String(day).padStart(2, '0');
  const mm = String(month).padStart(2, '0');
  return `${WEEKDAYS[weekdayIndex(isoDate)]}, ${dd}.${mm}.${year}`;
}

/** '2026-11-01' → 'listopad 2026' */
export function formatMonth(isoDate: string): string {
  const { year, month } = parts(isoDate);
  return `${MONTHS[month - 1]} ${year}`;
}

/** '07:00:00', '14:00:00' → '07:00–14:00' */
export function formatHours(start: string, end: string): string {
  return `${start.slice(0, 5)}–${end.slice(0, 5)}`;
}

/** Znacznik czasu z bazy → '14.10.2026, 08:15' (czas polski). */
export function formatTimestamp(isoTimestamp: string): string {
  return new Intl.DateTimeFormat('pl-PL', {
    dateStyle: 'short',
    timeStyle: 'short',
    timeZone: 'Europe/Warsaw',
  }).format(new Date(isoTimestamp));
}

/** Dzisiejsza data w strefie ciastkarni jako 'YYYY-MM-DD'. */
export function todayInWarsaw(now: Date = new Date()): string {
  // Szwedzki format daty to akurat ISO 'YYYY-MM-DD'.
  return new Intl.DateTimeFormat('sv-SE', { timeZone: 'Europe/Warsaw' }).format(now);
}
