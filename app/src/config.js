// Everything a business changes lives here. The crm-customize skill edits this file.
// Keys are stored in the database; labels are only shown to people.

export const BUSINESS = {
  name: 'Northwind Cleaning',
  currency: 'USD',
  timezone: 'America/Chicago',   // used for "today" in the daily digest
};

// What a customer can ask for. Key -> label. The form <select> must use the same keys.
export const SERVICES = {
  regular: 'Regular cleaning',
  deep: 'Deep cleaning',
  move_out: 'Move-out cleaning',
  office: 'Office cleaning',
};

// Pipeline. Order matters: it is the column order on the board.
// The CHECK constraint in migrations/0001_init.sql must list the same keys.
export const STATUSES = {
  new: 'New',
  contacted: 'Contacted',
  quoted: 'Quoted',
  booked: 'Booked',
  done: 'Done',
  lost: 'Lost',
  spam: 'Spam',
};

// Statuses that count as "the lead is still open" for the digest and stale checks.
export const OPEN_STATUSES = ['new', 'contacted', 'quoted', 'booked'];

// Statuses that mean money came in (used by the weekly report).
export const WON_STATUSES = ['booked', 'done'];

// Hours (in BUSINESS.timezone) when late-lead alerts may fire. Nobody wants a 3 a.m. ping.
export const WORK_HOURS = { from: 8, to: 20 };

// Hour (in BUSINESS.timezone) for the daily digest: open leads, follow-ups due today.
export const DIGEST_HOUR = 8;

// Speed-to-lead: a 'new' lead older than this many minutes is flagged as late.
export const FIRST_CONTACT_SLA_MIN = 15;

// Public form rules (mirrored server-side, the browser checks are only a convenience).
export const FORM = {
  maxName: 100,
  maxMessage: 1000,
  maxArea: 120,
  minPhoneDigits: 7,
  maxPhoneDigits: 15,
  requireEmail: false,
  rateLimitPerIpPer10Min: 5,
  dedupWindowMin: 30,   // same phone + same service inside this window = same lead
};
