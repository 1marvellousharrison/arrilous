import test, { describe } from 'node:test';
import assert from 'node:assert/strict';
import { api, createBusinessOwner, openBusinessEdit } from './helpers.js';

/**
 * Staff accounts (docs/staff-accounts.md).
 *
 * The owner issues a code; the staff claims it, sets a password and signs in with
 * the code. From then on the staff is a restricted member of the business: they
 * see only their own sales, cannot move a sale's status (notes only), and cannot
 * touch the catalog, customers, business details, staff management or wallet.
 */

const STAFF_PASSWORD = 'Str0ngPass!23';
const STAFF_CODE = /^[A-Z]{3}[0-9]{2}-[0-9]{2}$/;
const BUSINESS_CODE = /^[A-Z]{3}[0-9]{2}$/;

async function addStaff(owner, fullName = 'Amina Staff', phone = null) {
  const res = await api('POST', '/staff', {
    token: owner.token,
    body: { full_name: fullName, ...(phone ? { phone } : {}) },
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.staff;
}

async function activateStaff(staffCode, password = STAFF_PASSWORD) {
  const claim = await api('POST', '/staff/claim', { body: { staff_code: staffCode } });
  assert.equal(claim.status, 200, JSON.stringify(claim.body));
  const activate = await api('POST', '/staff/activate', {
    body: { staff_code: staffCode, password },
  });
  assert.equal(activate.status, 200, JSON.stringify(activate.body));
  return claim.body;
}

async function loginStaff(staffCode, password = STAFF_PASSWORD) {
  const res = await api('POST', '/auth/login', {
    body: { identifier: staffCode, password },
  });
  assert.equal(res.status, 200, JSON.stringify(res.body));
  return res.body;
}

/** A fully activated staff with its access token. */
async function staffSession(owner, name = 'Amina Staff') {
  const staff = await addStaff(owner, name);
  await activateStaff(staff.staffCode);
  const session = await loginStaff(staff.staffCode);
  return { staff, token: session.access_token, userId: session.user.id };
}

function saleBody(totalKobo = 10000) {
  return { items: [{ name: 'Walk-in item', unit_price_kobo: totalKobo, quantity: 1 }] };
}

async function recordSale(token, totalKobo = 10000) {
  const res = await api('POST', '/transactions', { token, body: saleBody(totalKobo) });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.transaction;
}

describe('staff accounts — issuing and activation', () => {
  test('the owner adds a staff and receives an unclaimed code', async () => {
    const owner = await createBusinessOwner('Staff Store');
    const staff = await addStaff(owner, 'Amina Bello');

    assert.match(staff.staffCode, STAFF_CODE);
    assert.match(staff.staffCode, new RegExp(`^${owner.business.businessCode}-`));
    assert.equal(staff.status, 'invited');
    assert.equal(staff.fullName, 'Amina Bello');
    assert.equal(staff.activatedAt, null);
  });

  test('a business is given a stable code when it is created', async () => {
    const owner = await createBusinessOwner('Code Store');
    assert.match(owner.business.businessCode, BUSINESS_CODE);

    // The code does not change on a rename — staff logins depend on it.
    const editToken = await openBusinessEdit(owner);
    await api('PATCH', '/business', {
      token: owner.token,
      headers: { 'x-business-edit-token': editToken },
      body: { business_name: 'Renamed Store' },
    });
    const after = await api('GET', '/business', { token: owner.token });
    assert.equal(after.body.business.businessCode, owner.business.businessCode);
  });

  test('claiming a code resolves the staff and the business, without logging in', async () => {
    const owner = await createBusinessOwner('Claim Store');
    const staff = await addStaff(owner, 'Ngozi Okafor');

    const claim = await api('POST', '/staff/claim', { body: { staff_code: staff.staffCode } });
    assert.equal(claim.status, 200, JSON.stringify(claim.body));
    assert.equal(claim.body.staff.fullName, 'Ngozi Okafor');
    assert.equal(claim.body.business.businessName, 'Claim Store');
    assert.equal(claim.body.access_token, undefined, 'claim must not issue a session');
  });

  test('the code is case-insensitive at claim time', async () => {
    const owner = await createBusinessOwner('Case Store');
    const staff = await addStaff(owner, 'Lower Case');
    const claim = await api('POST', '/staff/claim', {
      body: { staff_code: staff.staffCode.toLowerCase() },
    });
    assert.equal(claim.status, 200, JSON.stringify(claim.body));
  });

  test('an unknown code is refused', async () => {
    const res = await api('POST', '/staff/claim', { body: { staff_code: 'ZZZ99-99' } });
    assert.equal(res.status, 404);
  });

  test('an invited staff cannot sign in before activating', async () => {
    const owner = await createBusinessOwner('Unclaimed Store');
    const staff = await addStaff(owner, 'Not Yet');

    const res = await api('POST', '/auth/login', {
      body: { identifier: staff.staffCode, password: STAFF_PASSWORD },
    });
    assert.equal(res.status, 401);
  });

  test('activating sets a password and lets the staff sign in with the code', async () => {
    const owner = await createBusinessOwner('Activate Store');
    const staff = await addStaff(owner, 'Ready Staff');

    await activateStaff(staff.staffCode);
    const session = await loginStaff(staff.staffCode);

    assert.equal(session.user.role, 'staff');
    assert.equal(session.user.fullName, 'Ready Staff');
    assert.ok(session.access_token);
  });

  test('a code can only be claimed once', async () => {
    const owner = await createBusinessOwner('Once Store');
    const staff = await addStaff(owner, 'Single Use');
    await activateStaff(staff.staffCode);

    const again = await api('POST', '/staff/claim', { body: { staff_code: staff.staffCode } });
    assert.equal(again.status, 409);
    assert.equal(again.body.error.code, 'staff_code_claimed');

    const reactivate = await api('POST', '/staff/activate', {
      body: { staff_code: staff.staffCode, password: 'AnotherPass!23' },
    });
    assert.equal(reactivate.status, 409);
  });
});

describe('staff accounts — scoped access', () => {
  test('a staff sale is attributed and visible to the owner', async () => {
    const owner = await createBusinessOwner('Attribution Store');
    const staff = await staffSession(owner, 'Seller One');

    const sale = await recordSale(staff.token, 25000);
    assert.equal(sale.createdByUserId, staff.userId);

    const ownerList = await api('GET', '/transactions', { token: owner.token });
    assert.equal(ownerList.body.transactions.length, 1);
    assert.equal(ownerList.body.transactions[0].createdByUserId, staff.userId);
  });

  test('a staff sees only their own sales', async () => {
    const owner = await createBusinessOwner('Scope Store');
    const one = await staffSession(owner, 'Staff One');
    const two = await staffSession(owner, 'Staff Two');

    await recordSale(one.token, 5000);
    const secondSale = await recordSale(two.token, 7000);
    await recordSale(owner.token, 9000);

    const oneList = await api('GET', '/transactions', { token: one.token });
    assert.equal(oneList.body.transactions.length, 1);
    assert.equal(oneList.body.transactions[0].createdByUserId, one.userId);

    // A colleague's sale is invisible, and reading it directly is a 404.
    const read = await api('GET', `/transactions/${secondSale.id}`, { token: one.token });
    assert.equal(read.status, 404);
  });

  test('the owner can list a single staff member\'s sales', async () => {
    const owner = await createBusinessOwner('PerStaff Store');
    const staff = await staffSession(owner, 'Solo Seller');
    await recordSale(staff.token, 12000);
    await recordSale(owner.token, 3000);

    const res = await api('GET', `/staff/${staff.staff.id}/transactions`, { token: owner.token });
    assert.equal(res.status, 200, JSON.stringify(res.body));
    assert.equal(res.body.transactions.length, 1);
    assert.equal(res.body.transactions[0].createdByUserId, staff.userId);

    // The staff counts reflect that sale on the list.
    const list = await api('GET', '/staff', { token: owner.token });
    const row = list.body.staff.find((s) => s.id === staff.staff.id);
    assert.equal(row.salesCount, 1);
  });

  test('a staff may annotate a sale but not move its status', async () => {
    const owner = await createBusinessOwner('Notes Store');
    const staff = await staffSession(owner, 'Note Taker');
    const sale = await recordSale(staff.token, 4000);

    const blocked = await api('PATCH', `/transactions/${sale.id}/statuses`, {
      token: staff.token,
      body: { orderStatus: 'confirmed' },
    });
    assert.equal(blocked.status, 403);

    const noted = await api('PATCH', `/transactions/${sale.id}/statuses`, {
      token: staff.token,
      body: { note: 'Customer will pay tomorrow' },
    });
    assert.equal(noted.status, 200, JSON.stringify(noted.body));

    const detail = await api('GET', `/transactions/${sale.id}`, { token: staff.token });
    assert.equal(detail.body.transaction.orderStatus, 'pending');
    const notes = detail.body.history.filter((entry) => entry.statusType === 'note');
    assert.equal(notes.length, 1);
    assert.equal(notes[0].note, 'Customer will pay tomorrow');
  });

  test('products are readable but not writable by a staff', async () => {
    const owner = await createBusinessOwner('Catalog Store');
    const staff = await staffSession(owner, 'Catalog Staff');

    await api('POST', '/products', {
      token: owner.token,
      body: { name: 'Rice 50kg', price_kobo: 2500050, stock_quantity: 5 },
    });

    const list = await api('GET', '/products', { token: staff.token });
    assert.equal(list.status, 200);
    assert.equal(list.body.products.length, 1);

    const create = await api('POST', '/products', {
      token: staff.token,
      body: { name: 'Hidden item', price_kobo: 100 },
    });
    assert.equal(create.status, 403);
  });

  test('customers can be added but not edited by a staff', async () => {
    const owner = await createBusinessOwner('CRM Store');
    const staff = await staffSession(owner, 'CRM Staff');

    const created = await api('POST', '/customers', {
      token: staff.token,
      body: { name: 'Walk In', phone: '+2348010000011' },
    });
    assert.equal(created.status, 201, JSON.stringify(created.body));

    const edited = await api('PATCH', `/customers/${created.body.customer.id}`, {
      token: staff.token,
      body: { name: 'Renamed' },
    });
    assert.equal(edited.status, 403);
  });

  test('a staff cannot reach business details or staff management', async () => {
    const owner = await createBusinessOwner('Hidden Store');
    const staff = await staffSession(owner, 'Hidden Staff');

    const patchBusiness = await api('PATCH', '/business', {
      token: staff.token,
      body: { business_name: 'Taken Over' },
    });
    assert.equal(patchBusiness.status, 403);

    const location = await api('GET', '/business/location', { token: staff.token });
    assert.equal(location.status, 403);

    const managing = await api('GET', '/staff', { token: staff.token });
    assert.equal(managing.status, 403);
  });

  test('the wallet is not reachable by a staff', async () => {
    const owner = await createBusinessOwner('No Wallet Store');
    const staff = await staffSession(owner, 'Walletless Staff');

    const res = await api('GET', '/wallet', { token: staff.token });
    assert.equal(res.status, 404);
  });

  test('the dashboard shows a staff only their own numbers', async () => {
    const owner = await createBusinessOwner('Dash Store');
    const staff = await staffSession(owner, 'Dash Staff');

    await recordSale(staff.token, 5000);
    await recordSale(owner.token, 8000);

    const staffDash = await api('GET', '/dashboard/summary', { token: staff.token });
    assert.equal(staffDash.status, 200, JSON.stringify(staffDash.body));
    assert.equal(staffDash.body.totals.transactionCount, 1);
    assert.equal(staffDash.body.totals.grossSalesKobo, 5000);

    const ownerDash = await api('GET', '/dashboard/summary', { token: owner.token });
    assert.equal(ownerDash.body.totals.transactionCount, 2);
    assert.equal(ownerDash.body.totals.grossSalesKobo, 13000);
  });
});

describe('staff accounts — sale money lands in the owner wallet', () => {
  test('marking a sale paid credits the owner wallet with a sale ledger row', async () => {
    const owner = await createBusinessOwner('Paid Store');
    const sale = await recordSale(owner.token, 15000);

    await api('PATCH', `/transactions/${sale.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'paid' },
    });

    const wallet = await api('GET', '/wallet', { token: owner.token });
    assert.equal(wallet.body.wallet.balanceKobo, 15000);

    const ledger = await api('GET', '/wallet/transactions', { token: owner.token });
    const row = ledger.body.transactions.find((t) => t.reference === `sale:${sale.id}`);
    assert.ok(row, 'the sale appears in the ledger');
    assert.equal(row.kind, 'sale');
    assert.equal(row.direction, 'credit');
    assert.equal(row.amountKobo, 15000);
  });

  test('a staff sale credits the owner, who may mark it paid', async () => {
    const owner = await createBusinessOwner('Staff Paid Store');
    const staff = await staffSession(owner, 'Paid Staff');
    const sale = await recordSale(staff.token, 22000);

    await api('PATCH', `/transactions/${sale.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'paid' },
    });

    const wallet = await api('GET', '/wallet', { token: owner.token });
    assert.equal(wallet.body.wallet.balanceKobo, 22000);
  });

  test('a sale is credited once, even if paid is re-sent', async () => {
    const owner = await createBusinessOwner('Idempotent Store');
    const sale = await recordSale(owner.token, 10000);

    await api('PATCH', `/transactions/${sale.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'paid' },
    });
    await api('PATCH', `/transactions/${sale.id}/statuses`, {
      token: owner.token,
      body: { paymentStatus: 'paid' },
    });

    const wallet = await api('GET', '/wallet', { token: owner.token });
    assert.equal(wallet.body.wallet.balanceKobo, 10000);

    const ledger = await api('GET', '/wallet/transactions', { token: owner.token });
    const sales = ledger.body.transactions.filter((t) => t.kind === 'sale');
    assert.equal(sales.length, 1);
  });
});

describe('staff accounts — disabling', () => {
  test('a disabled staff cannot sign in and loses their session', async () => {
    const owner = await createBusinessOwner('Disable Store');
    const staff = await staffSession(owner, 'Soon Gone');

    const disabled = await api('PATCH', `/staff/${staff.staff.id}`, {
      token: owner.token,
      body: { status: 'disabled' },
    });
    assert.equal(disabled.status, 200, JSON.stringify(disabled.body));
    assert.equal(disabled.body.staff.status, 'disabled');

    const login = await api('POST', '/auth/login', {
      body: { identifier: staff.staff.staffCode, password: STAFF_PASSWORD },
    });
    assert.equal(login.status, 401);

    // The already-issued access token is refused too.
    const existing = await api('GET', '/transactions', { token: staff.token });
    assert.equal(existing.status, 403);
  });

  test('a re-enabled staff can sign in again', async () => {
    const owner = await createBusinessOwner('Reenable Store');
    const staff = await staffSession(owner, 'Back Again');

    await api('PATCH', `/staff/${staff.staff.id}`, {
      token: owner.token,
      body: { status: 'disabled' },
    });
    await api('PATCH', `/staff/${staff.staff.id}`, {
      token: owner.token,
      body: { status: 'active' },
    });

    const session = await loginStaff(staff.staff.staffCode);
    assert.equal(session.user.role, 'staff');
  });

  test('the owner cannot activate a code the staff has not activated themselves', async () => {
    const owner = await createBusinessOwner('Invite Only Store');
    const staff = await addStaff(owner, 'Never Activated');
    assert.equal(staff.status, 'invited');

    // Asking the API to make a fresh code active does not: only the staff's own
    // activation (claim + set password) can.
    const promoted = await api('PATCH', `/staff/${staff.id}`, {
      token: owner.token,
      body: { status: 'active' },
    });
    assert.equal(promoted.status, 200, JSON.stringify(promoted.body));
    assert.equal(promoted.body.staff.status, 'invited');

    // Disabling and re-enabling a never-activated code restores "invited"; it
    // still does not activate anyone.
    await api('PATCH', `/staff/${staff.id}`, { token: owner.token, body: { status: 'disabled' } });
    const restored = await api('PATCH', `/staff/${staff.id}`, {
      token: owner.token,
      body: { status: 'active' },
    });
    assert.equal(restored.body.staff.status, 'invited');

    // Still locked out until they set their own password.
    const lockedOut = await api('POST', '/auth/login', {
      body: { identifier: staff.staffCode, password: STAFF_PASSWORD },
    });
    assert.equal(lockedOut.status, 401);

    // And the code still activates normally afterwards.
    await activateStaff(staff.staffCode);
    const session = await loginStaff(staff.staffCode);
    assert.equal(session.user.role, 'staff');
  });

  test('a staff cannot sign in with a phone number, only their code', async () => {
    const owner = await createBusinessOwner('Phone Bypass Store');
    const staff = await addStaff(owner, 'Phone Staff', '+2348031234567');

    // A phone on file does not resolve a staff: the phone branch excludes the
    // staff role, so the code is the only way in. That matters most while the
    // code is still unactivated, when the account would otherwise look active.
    const viaPhone = await api('POST', '/auth/login', {
      body: { identifier: '+2348031234567', password: STAFF_PASSWORD },
    });
    assert.equal(viaPhone.status, 401);
  });

  test('one owner cannot manage another business\'s staff', async () => {
    const owner = await createBusinessOwner('Mine Store');
    const intruder = await createBusinessOwner('Theirs Store');
    const staff = await addStaff(owner, 'Private Staff');

    const list = await api('GET', '/staff', { token: intruder.token });
    assert.equal(list.status, 200);
    assert.equal(list.body.staff.length, 0);

    const patch = await api('PATCH', `/staff/${staff.id}`, {
      token: intruder.token,
      body: { status: 'disabled' },
    });
    assert.equal(patch.status, 404);
  });
});
