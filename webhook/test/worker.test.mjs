// Tests for the webhook Worker's payload handling.
//
// Run with:  cd webhook && npm test
//
// These cover the two things that silently break a bank integration:
//   1. SePay using a different field name than expected → transaction dropped.
//   2. A signed amount or "in" transfer being read as an expense → income
//      polluting the expense list.
const mod = await import('../src/index.js');

const normalise = mod.normaliseForTest;
const parseDate = mod.parseDateForTest;
const constantTimeEqual = mod.constantTimeEqualForTest;

if (!normalise) {
  // Fail loudly rather than silently passing: a green run that tested nothing
  // is worse than a red one.
  throw new Error(
    'Test helpers are not exported from src/index.js. Expected ' +
      'normaliseForTest, parseDateForTest and constantTimeEqualForTest.',
  );
}

const tests = [];
const test = (name, fn) => tests.push({ name, fn });
const eq = (actual, expected, msg = '') => {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${msg}\n  expected: ${e}\n  actual:   ${a}`);
};
const assert = (cond, msg) => {
  if (!cond) throw new Error(msg);
};

// ---------------------------------------------------------------- normalise

test('reads id from `id`', () => {
  const r = normalise({
    id: 'TX1', transferAmount: 20000, transferType: 'out',
    transactionDate: '2026-10-26 09:15:00', content: 'UONG NUOC',
  });
  eq(r.key, 'sepay:TX1');
  eq(r.amount, 20000);
  eq(r.isIncome, false);
});

test('falls back to transactionId', () => {
  const r = normalise({ transactionId: 42, transferAmount: 5, transferType: 'out' });
  eq(r.key, 'sepay:42');
});

test('falls back to referenceCode', () => {
  const r = normalise({ referenceCode: 'FT123', transferAmount: 7, transferType: 'out' });
  eq(r.key, 'sepay:FT123');
});

test('treats transferType "in" as income', () => {
  const r = normalise({ id: 'A', transferAmount: 100, transferType: 'in' });
  eq(r.isIncome, true);
});

test('treats transferType "out" as expense', () => {
  const r = normalise({ id: 'B', transferAmount: 100, transferType: 'out' });
  eq(r.isIncome, false);
});

test('accepts a numeric string amount', () => {
  const r = normalise({ id: 'C', transferAmount: '15000', transferType: 'out' });
  eq(r.amount, 15000);
});

test('accepts `amount` when transferAmount is absent', () => {
  const r = normalise({ id: 'D', amount: 9000, transferType: 'out' });
  eq(r.amount, 9000);
});

test('rejects a zero amount', () => {
  eq(normalise({ id: 'E', transferAmount: 0, transferType: 'out' }), null);
});

test('rejects a negative amount but keeps the magnitude', () => {
  // Some SePay payload versions encode direction with the sign.
  const r = normalise({ id: 'F', transferAmount: -25000, transferType: 'out' });
  eq(r.amount, 25000);
});

test('rejects a payload with no id', () => {
  eq(normalise({ transferAmount: 100, transferType: 'out' }), null);
});

test('carries the bank brand through', () => {
  const r = normalise({
    id: 'G', transferAmount: 1, transferType: 'out', bankBrandName: 'MB Bank',
  });
  eq(r.bank, 'MB Bank');
});

test('trims and defaults empty content', () => {
  const r = normalise({ id: 'H', transferAmount: 1, transferType: 'out', content: '   ' });
  eq(r.content, '');
});

// ----------------------------------------------------------------- parseDate

test('parses SePay "YYYY-MM-DD HH:mm:ss" as UTC+7', () => {
  const ms = parseDate('2026-10-26 09:15:00');
  const iso = new Date(ms).toISOString();
  // 09:15 Vietnam = 02:15 UTC.
  eq(iso, '2026-10-26T02:15:00.000Z');
});

test('parses midnight Vietnam as 17:00 UTC the previous day', () => {
  const ms = parseDate('2026-10-26 00:00:00');
  eq(new Date(ms).toISOString(), '2026-10-25T17:00:00.000Z');
});

test('accepts a T separator', () => {
  const ms = parseDate('2026-10-26T09:15:00');
  eq(new Date(ms).toISOString(), '2026-10-26T02:15:00.000Z');
});

test('falls back to Date.parse for ISO strings', () => {
  const ms = parseDate('2026-10-26T02:15:00Z');
  eq(new Date(ms).toISOString(), '2026-10-26T02:15:00.000Z');
});

test('returns now for an empty date rather than NaN', () => {
  const before = Date.now();
  const ms = parseDate('');
  assert(ms >= before, 'expected a current timestamp');
});

test('returns now for an unparseable date', () => {
  const before = Date.now();
  const ms = parseDate('not a date');
  assert(ms >= before, 'expected a fallback timestamp');
});

// ------------------------------------------------------ constant-time compare

test('accepts equal secrets', () => {
  eq(constantTimeEqual('abc123', 'abc123'), true);
});

test('rejects different secrets', () => {
  eq(constantTimeEqual('abc123', 'abc124'), false);
});

test('rejects a prefix', () => {
  eq(constantTimeEqual('abc', 'abc123'), false);
});

test('rejects an empty expected secret', () => {
  eq(constantTimeEqual('anything', ''), false);
  eq(constantTimeEqual('', ''), false);
});

test('handles undefined without throwing', () => {
  eq(constantTimeEqual(undefined, 'x'), false);
});

// -------------------------------------------------------------------- runner

let passed = 0;
const failures = [];
for (const { name, fn } of tests) {
  try {
    await fn();
    passed++;
    console.log(`  ok   ${name}`);
  } catch (e) {
    failures.push({ name, message: e.message });
    console.log(`  FAIL ${name}`);
  }
}

console.log(`\n${passed}/${tests.length} passed`);
if (failures.length) {
  console.log('\nFailures:');
  for (const f of failures) console.log(` - ${f.name}\n   ${f.message}`);
  process.exitCode = 1;
}
