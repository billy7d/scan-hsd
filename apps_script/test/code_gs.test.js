// Test logic của Code.gs bằng Node, giả lập SpreadsheetApp. Chạy: node apps_script/test/code_gs.test.js
process.env.TZ = 'Asia/Ho_Chi_Minh';
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');
const assert = require('assert');

// ---------------------------------------------------------------- Mock

class MockRange {
  constructor(sheet, r, c, nr, nc) { Object.assign(this, { sheet, r, c, nr, nc }); }
  getValues() {
    const out = [];
    for (let i = 0; i < this.nr; i++) {
      const row = this.sheet.data[this.r - 1 + i] || [];
      const vals = [];
      for (let j = 0; j < this.nc; j++) {
        const v = row[this.c - 1 + j];
        vals.push(v === undefined ? '' : v);
      }
      out.push(vals);
    }
    return out;
  }
  setValues(values) {
    for (let i = 0; i < this.nr; i++) {
      while (this.sheet.data.length < this.r + i) this.sheet.data.push([]);
      const row = this.sheet.data[this.r - 1 + i];
      for (let j = 0; j < this.nc; j++) row[this.c - 1 + j] = values[i][j];
    }
    return this;
  }
  setValue(v) { return this.setValues([[v]]); }
  setNumberFormat() { return this; }
}

class MockSheet {
  constructor(data) { this.data = data; }
  getLastRow() {
    for (let i = this.data.length; i > 0; i--) {
      if ((this.data[i - 1] || []).some((v) => v !== '' && v !== undefined && v !== null)) return i;
    }
    return 0;
  }
  getLastColumn() {
    return this.data.reduce((m, row) => {
      for (let j = row.length; j > 0; j--) if (row[j - 1] !== '' && row[j - 1] !== undefined && row[j - 1] !== null) return Math.max(m, j);
      return m;
    }, 0);
  }
  getRange(r, c, nr = 1, nc = 1) { return new MockRange(this, r, c, nr, nc); }
  deleteRow(r) { this.data.splice(r - 1, 1); }
}

const pad = (n) => String(n).padStart(2, '0');

function makeContext(sheet) {
  const ss = { getSheetByName: (n) => (n === 'TonKho' ? sheet : null), getSpreadsheetTimeZone: () => 'Asia/Ho_Chi_Minh' };
  const ctx = {
    SpreadsheetApp: { getActiveSpreadsheet: () => ss, flush() {} },
    LockService: { getScriptLock: () => ({ waitLock() {}, releaseLock() {} }) },
    ContentService: { MimeType: { JSON: 'json' }, createTextOutput: (s) => ({ setMimeType: () => ({ content: s }) }) },
    Utilities: {
      getUuid: () => crypto.randomUUID(),
      formatDate: (d, tz, fmt) => fmt.replace('yyyy', d.getFullYear()).replace('MM', pad(d.getMonth() + 1)).replace('dd', pad(d.getDate())),
    },
    Date, JSON, Math, Number, String, Object, isFinite,
  };
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(path.join(__dirname, '..', 'Code.gs'), 'utf8'), ctx);
  ctx.KEY = vm.runInContext('API_KEY', ctx);
  return ctx;
}

const HEADER = ['Mã vạch', 'Tên sản phẩm', 'Date (HSD)', 'Số lượng', 'Giá bán', 'ID'];

function setup(rows = []) {
  const sheet = new MockSheet([HEADER.slice(), ...rows.map((r) => r.slice())]);
  const ctx = makeContext(sheet);
  const post = (body) => JSON.parse(ctx.doPost({ postData: { contents: JSON.stringify({ key: ctx.KEY, ...body }) } }).content);
  const get = (params) => JSON.parse(ctx.doGet({ parameter: { key: ctx.KEY, ...params } }).content);
  return { sheet, ctx, post, get };
}

const P = { barcode: '5060107330214', name: "Bánh Ella's dâu chuối", price: 140000 };

// ---------------------------------------------------------------- Tests

const tests = [];
const test = (name, fn) => tests.push({ name, fn });

test('sai key bị từ chối', () => {
  const { ctx } = setup();
  assert.strictEqual(JSON.parse(ctx.doGet({ parameter: { key: 'x', action: 'ping' } }).content).ok, false);
});

test('ghi 1 sản phẩm với nhiều date → mỗi date một dòng, 6 cột đúng thứ tự', () => {
  const { sheet, post } = setup();
  const out = post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 3 }, { hsd: '2027-06-30', qty: 5 }] });
  assert.deepStrictEqual(out.results.map((r) => r.status), ['created', 'created']);
  assert.strictEqual(sheet.getLastRow(), 3);
  const r = sheet.data[1];
  assert.strictEqual(r[0], '5060107330214');
  assert.strictEqual(r[1], P.name);
  assert.ok(r[2] instanceof Date && r[2].getDate() === 15 && r[2].getHours() === 12);
  assert.strictEqual(r[3], 3);
  assert.strictEqual(r[4], 140000);
  assert.ok(/^[0-9a-f]{8}$/.test(r[5]));
});

test('cùng mã + cùng date → duplicate (không ghi), xác nhận → cộng dồn', () => {
  const { sheet, post } = setup();
  post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 3 }] });
  const d = post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 2 }, { hsd: '2027-08-01', qty: 1 }] });
  assert.strictEqual(d.results[0].status, 'duplicate');
  assert.strictEqual(d.results[0].currentQty, 3);
  assert.strictEqual(d.results[1].status, 'created');
  assert.strictEqual(sheet.getLastRow(), 3);
  const m = post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 2 }], confirmMerge: true });
  assert.strictEqual(m.results[0].status, 'merged');
  assert.strictEqual(m.results[0].newQty, 5);
  assert.strictEqual(sheet.getLastRow(), 3);
});

test('giá bán theo sản phẩm: ghi date mới với giá mới → mọi date cùng giá', () => {
  const { sheet, post } = setup();
  post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 3 }] });
  post({ action: 'add', ...P, price: 150000, lots: [{ hsd: '2027-06-30', qty: 1 }] });
  assert.deepStrictEqual(sheet.data.slice(1).map((r) => r[4]), [150000, 150000]);
});

test('hàng không mã vạch: khoá theo tên (không phân biệt hoa thường, khoảng trắng)', () => {
  const { sheet, post } = setup();
  post({ action: 'add', barcode: '', name: 'Bánh  gạo chuối', price: 50000, lots: [{ hsd: '2027-01-31', qty: 2 }] });
  const d = post({ action: 'add', barcode: '', name: ' bánh gạo CHUỐI ', price: 50000, lots: [{ hsd: '2027-01-31', qty: 1 }] });
  assert.strictEqual(d.results[0].status, 'duplicate');
  assert.strictEqual(sheet.getLastRow(), 2);
});

test('lookup theo mã: đủ mọi date, gần hết hạn trước; UPC 12 số = EAN-13 số 0 đầu', () => {
  const { get, post } = setup();
  post({ action: 'add', barcode: '0012345678905', name: 'X', price: 1, lots: [{ hsd: '2027-09-30', qty: 1 }, { hsd: '2027-03-15', qty: 4 }] });
  const out = get({ action: 'lookup', barcode: '012345678905' });
  assert.strictEqual(out.found, true);
  assert.deepStrictEqual(out.lots.map((l) => l.hsd), ['2027-03-15', '2027-09-30']);
  assert.strictEqual(out.product.price, 1);
  assert.strictEqual(get({ action: 'lookup', barcode: '999' }).found, false);
});

test('adjust: đúng expect → cập nhật; sai → conflict; id lạ → notFound; âm → lỗi', () => {
  const { sheet, post } = setup();
  const id = post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 3 }] }).results[0].id;
  const expect = { barcode: P.barcode, hsd: '2027-03-15', qty: 3 };
  assert.strictEqual(post({ action: 'adjust', id, expect, delta: -2 }).newQty, 1);
  assert.strictEqual(sheet.data[1][3], 1);
  assert.strictEqual(post({ action: 'adjust', id, expect, delta: -1 }).status, 'conflict');
  assert.strictEqual(post({ action: 'adjust', id: 'zzzzzzzz', expect, delta: 1 }).status, 'notFound');
  assert.strictEqual(post({ action: 'adjust', id, expect: { ...expect, qty: 1 }, delta: -5 }).ok, false);
});

test('ID vẫn đúng sau khi sheet bị sắp xếp lại', () => {
  const { sheet, post } = setup();
  const id = post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 3 }, { hsd: '2027-06-15', qty: 7 }] }).results[0].id;
  sheet.data = [sheet.data[0], sheet.data[2], sheet.data[1]];
  assert.strictEqual(post({ action: 'adjust', id, expect: { barcode: P.barcode, hsd: '2027-03-15', qty: 3 }, delta: 1 }).status, 'updated');
  assert.strictEqual(sheet.data[2][3], 4);
  assert.strictEqual(sheet.data[1][3], 7);
});

test('updateLot đổi date trùng date khác → duplicate; xác nhận → gộp, xoá dòng đang sửa', () => {
  const { sheet, post } = setup();
  const r = post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 3 }, { hsd: '2027-06-15', qty: 7 }] }).results;
  const expect = { barcode: P.barcode, hsd: '2027-03-15', qty: 3 };
  assert.strictEqual(post({ action: 'updateLot', id: r[0].id, expect, hsd: '2027-06-15' }).status, 'duplicate');
  const m = post({ action: 'updateLot', id: r[0].id, expect, hsd: '2027-06-15', confirmMerge: true });
  assert.strictEqual(m.status, 'merged');
  assert.strictEqual(m.newQty, 10);
  assert.strictEqual(sheet.getLastRow(), 2);
});

test('deleteLot xoá đúng dòng', () => {
  const { sheet, post } = setup();
  const r = post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 3 }, { hsd: '2027-06-15', qty: 7 }] }).results;
  assert.strictEqual(post({ action: 'deleteLot', id: r[0].id, expect: { barcode: P.barcode, hsd: '2027-03-15', qty: 3 } }).status, 'deleted');
  assert.strictEqual(sheet.getLastRow(), 2);
  assert.strictEqual(sheet.data[1][3], 7);
});

test('updateProduct đổi tên + giá cho mọi date; hàng không mã theo tên cũ', () => {
  const { sheet, post } = setup();
  post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 3 }, { hsd: '2027-06-15', qty: 7 }] });
  assert.strictEqual(post({ action: 'updateProduct', barcode: P.barcode, name: 'Mới', price: 99000 }).rowsChanged, 2);
  assert.ok(sheet.data.slice(1).every((r) => r[1] === 'Mới' && r[4] === 99000));
  post({ action: 'add', barcode: '', name: 'Bánh gạo', price: 1, lots: [{ hsd: '2027-01-31', qty: 2 }] });
  assert.strictEqual(post({ action: 'updateProduct', barcode: '', oldName: 'bánh gạo', name: 'Bánh gạo vị táo', price: 2 }).rowsChanged, 1);
});

test('snapshot: [id, mã, tên, date, số lượng, giá]; điền ID thiếu, sinh lại ID trùng', () => {
  const rows = [['111', 'A', '31/01/2027', 1, 10, 'aaaaaaaa'], ['222', 'B', '', 2, 20, 'aaaaaaaa'], ['', 'C', '', 3, 0, '']];
  const { get } = setup(rows);
  const out = get({ action: 'snapshot' });
  assert.strictEqual(out.rows[0][3], '2027-01-31');
  assert.deepStrictEqual(out.rows[0].slice(1), ['111', 'A', '2027-01-31', 1, 10]);
  assert.strictEqual(new Set(out.rows.map((r) => r[0])).size, 3);
});

test('cột tìm theo tiêu đề: đổi thứ tự, chèn cột tự thêm → vẫn đọc/ghi đúng, không đụng cột tự thêm', () => {
  const header = ['Ghi chú', 'ID', 'Giá bán', 'Tên sản phẩm', 'Nhà cung cấp', 'Mã vạch', 'Số lượng', 'Date (HSD)'];
  const sheet = new MockSheet([header, ['giữ nguyên', 'aaaaaaaa', 10, 'A', 'NCC 1', '111', 1, '31/01/2027']]);
  const ctx = makeContext(sheet);
  const post = (body) => JSON.parse(ctx.doPost({ postData: { contents: JSON.stringify({ key: ctx.KEY, ...body }) } }).content);
  const get = (params) => JSON.parse(ctx.doGet({ parameter: { key: ctx.KEY, ...params } }).content);
  assert.deepStrictEqual(get({ action: 'snapshot' }).rows[0], ['aaaaaaaa', '111', 'A', '2027-01-31', 1, 10]);
  post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 3 }] });
  const r = sheet.data[2];
  assert.strictEqual(r[5], P.barcode);
  assert.strictEqual(r[3], P.name);
  assert.strictEqual(r[6], 3);
  assert.strictEqual(r[2], 140000);
  assert.ok(r[7] instanceof Date);
  assert.ok(/^[0-9a-f]{8}$/.test(r[1]));
  assert.ok(r[0] === undefined && r[4] === undefined);
  assert.strictEqual(sheet.data[1][0], 'giữ nguyên');
});

test('thiếu tiêu đề gốc → báo lỗi, không ghi lệch', () => {
  const sheet = new MockSheet([['Mã vạch', 'Tên', 'Date (HSD)', 'Số lượng', 'Giá bán', 'ID']]);
  const ctx = makeContext(sheet);
  const out = JSON.parse(ctx.doPost({ postData: { contents: JSON.stringify({ key: ctx.KEY, action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 1 }] }) } }).content);
  assert.strictEqual(out.ok, false);
  assert.ok(/Tên sản phẩm/.test(out.error));
  assert.strictEqual(sheet.getLastRow(), 1);
});

test('dữ liệu sai → lỗi rõ ràng', () => {
  const { post } = setup();
  assert.strictEqual(post({ action: 'add', ...P, name: '', lots: [{ hsd: '2027-01-01', qty: 1 }] }).ok, false);
  assert.strictEqual(post({ action: 'add', ...P, lots: [] }).ok, false);
  assert.strictEqual(post({ action: 'add', ...P, lots: [{ hsd: '31/02/2027', qty: 1 }] }).ok, false);
  assert.strictEqual(post({ action: 'add', ...P, lots: [{ hsd: '2027-01-01', qty: 0 }] }).ok, false);
});

let failed = 0;
for (const t of tests) {
  try { t.fn(); console.log('✓', t.name); } catch (e) { failed++; console.log('✗', t.name, '\n   ', e.message); }
}
console.log(`\n${tests.length - failed}/${tests.length} test qua`);
process.exit(failed ? 1 : 0);
