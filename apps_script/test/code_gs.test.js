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
  setFontWeight() { return this; }
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
  getMaxColumns() { return Math.max(26, this.getLastColumn()); }
  insertColumnAfter() {}
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

test('snapshot: [id, mã, tên, date, số lượng, giá, lẻ]; điền ID thiếu, sinh lại ID trùng', () => {
  const rows = [['111', 'A', '31/01/2027', 1, 10, 'aaaaaaaa'], ['222', 'B', '', 2, 20, 'aaaaaaaa'], ['', 'C', '', 3, 0, '']];
  const { get } = setup(rows);
  const out = get({ action: 'snapshot' });
  assert.strictEqual(out.rows[0][3], '2027-01-31');
  assert.deepStrictEqual(out.rows[0].slice(1), ['111', 'A', '2027-01-31', 1, 10, 0]);
  assert.strictEqual(new Set(out.rows.map((r) => r[0])).size, 3);
});

test('cột tìm theo tiêu đề: đổi thứ tự, chèn cột tự thêm → vẫn đọc/ghi đúng, không đụng cột tự thêm', () => {
  const header = ['Ghi chú', 'ID', 'Giá bán', 'Tên sản phẩm', 'Nhà cung cấp', 'Mã vạch', 'Số lượng', 'Date (HSD)'];
  const sheet = new MockSheet([header, ['giữ nguyên', 'aaaaaaaa', 10, 'A', 'NCC 1', '111', 1, '31/01/2027']]);
  const ctx = makeContext(sheet);
  const post = (body) => JSON.parse(ctx.doPost({ postData: { contents: JSON.stringify({ key: ctx.KEY, ...body }) } }).content);
  const get = (params) => JSON.parse(ctx.doGet({ parameter: { key: ctx.KEY, ...params } }).content);
  assert.deepStrictEqual(get({ action: 'snapshot' }).rows[0], ['aaaaaaaa', '111', 'A', '2027-01-31', 1, 10, 0]);
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

// Giá trị lấy từ sheet thật (Đọc ghi kho.xlsx): ID 8 ký tự cũ nằm trong cột giá.
const RAC = [
  ['1111111111111', 'Rác chữ', '9a0649ba'],
  ['2222222222222', 'Rác số', 59970494],
  ['3333333333333', 'Rác số mũ', 2.6012e58],
];

test('giá rác (ID cũ, số quá lớn) → đọc ra 0, không hiện giá sai', () => {
  const { get } = setup(RAC.map(([b, n, p], i) => [b, n, '31/01/2027', 1, p, 'abcdef0' + i]));
  RAC.forEach(([b]) => assert.strictEqual(get({ action: 'lookup', barcode: b }).product.price, 0));
});

test('tự sửa ô giá rác: lấy giá date khác cùng sản phẩm, không có thì để trống; giá chữ "140.000" → số', () => {
  const rows = [
    ['111', 'A', '31/01/2027', 1, 90000, 'aaaaaaa1'],
    ['111', 'A', '28/02/2027', 1, '9a0649ba', 'aaaaaaa2'],
    ['222', 'B', '31/01/2027', 1, 26012e50, 'aaaaaaa3'],
    ['333', 'C', '31/01/2027', 1, '140.000 ₫', 'aaaaaaa4'],
    ['444', 'D', '31/01/2027', 1, '', 'aaaaaaa5'],
    ['555', 'E', '31/01/2027', 1, 0, 'aaaaaaa6'],
  ];
  const { sheet, get } = setup(rows);
  const out = get({ action: 'snapshot' });
  assert.deepStrictEqual(sheet.data.slice(1).map((r) => r[4]), [90000, 90000, '', 140000, '', 0]);
  assert.deepStrictEqual(out.rows.map((r) => r[5]), [90000, 90000, 0, 140000, 0, 0]);
});

test('ghi date mới cho sản phẩm có ô giá rác, nhập giá → mọi date đúng giá, đúng định dạng số', () => {
  const { sheet, post, get } = setup([['111', 'A', '31/01/2027', 1, 'b2495935', 'aaaaaaa1']]);
  post({ action: 'add', barcode: '111', name: 'A', price: '85.000', lots: [{ hsd: '2027-06-30', qty: 2 }] });
  assert.deepStrictEqual(sheet.data.slice(1).map((r) => r[4]), [85000, 85000]);
  assert.ok(sheet.data.slice(1).every((r) => typeof r[4] === 'number'));
  assert.strictEqual(get({ action: 'lookup', barcode: '111' }).product.price, 85000);
});

test('ghi không nhập giá → giữ giá đang có, không ghi đè thành 0', () => {
  const { sheet, post } = setup();
  post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 3 }] });
  post({ action: 'add', ...P, price: 0, lots: [{ hsd: '2027-06-30', qty: 1 }] });
  post({ action: 'add', ...P, price: '', lots: [{ hsd: '2027-09-30', qty: 1 }] });
  assert.deepStrictEqual(sheet.data.slice(1).map((r) => r[4]), [140000, 140000, 140000]);
});

test('giá app gửi: số / "140.000" / "140,000 ₫" đều ra 140000; sai hoặc quá lớn → lỗi, không ghi', () => {
  for (const price of [140000, '140000', '140.000', '140,000 ₫', '140 000đ']) {
    const { sheet, post } = setup();
    assert.strictEqual(post({ action: 'add', ...P, price, lots: [{ hsd: '2027-03-15', qty: 1 }] }).ok, true, String(price));
    assert.strictEqual(sheet.data[1][4], 140000, String(price));
  }
  for (const price of ['9a0649ba', '26012e58', 10000001, -5, 1400.5, '14.00']) {
    const { sheet, post } = setup();
    assert.strictEqual(post({ action: 'add', ...P, price, lots: [{ hsd: '2027-03-15', qty: 1 }] }).ok, false, String(price));
    assert.strictEqual(sheet.getLastRow(), 1, String(price));
  }
  const { sheet, post } = setup();
  post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 1 }] });
  assert.strictEqual(post({ action: 'updateProduct', barcode: P.barcode, name: P.name, price: 99999999 }).ok, false);
  assert.strictEqual(sheet.data[1][4], 140000);
});

// ---------------------------------------------------------------- Hàng lẻ (tách lốc)

const LOAI = 6; // cột G — "Loại" tự thêm sau 6 cột gốc

test('cột "Loại" tự thêm vào cuối ở lần ghi đầu; hàng cũ không ghi gì = lốc', () => {
  const { sheet, post } = setup([['111', 'A', '31/01/2027', 1, 90000, 'aaaaaaa1']]);
  post({ action: 'add', barcode: '111', name: 'A', price: 0, lots: [{ hsd: '2027-02-28', qty: 1 }] });
  assert.strictEqual(sheet.data[0][LOAI], 'Loại');
  assert.ok(sheet.data.slice(1).every((r) => !r[LOAI]));
});

test('ghi hàng lẻ: dòng riêng ghi "Lẻ", cùng date với lốc không bị coi là trùng, giá lẻ riêng', () => {
  const { sheet, post, get } = setup();
  post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 2 }] });
  const r = post({ action: 'add', ...P, le: true, price: 40000, lots: [{ hsd: '2027-03-15', qty: 3 }] });
  assert.strictEqual(r.results[0].status, 'created');
  assert.strictEqual(sheet.getLastRow(), 3);
  assert.deepStrictEqual(sheet.data.slice(1).map((x) => [x[3], x[4], x[LOAI] || '']), [[2, 140000, ''], [3, 40000, 'Lẻ']]);
  const l = get({ action: 'lookup', barcode: P.barcode });
  assert.strictEqual(l.product.price, 140000);
  assert.strictEqual(l.product.priceLe, 40000);
  assert.deepStrictEqual(l.lots.map((x) => [x.qty, x.le]), [[2, false], [3, true]]);
  assert.deepStrictEqual(get({ action: 'snapshot' }).rows.map((x) => [x[4], x[5], x[6]]), [[2, 140000, 0], [3, 40000, 1]]);
});

test('hàng lẻ trùng date lẻ → hỏi cộng dồn; giá lẻ đổi không đụng giá lốc; bỏ trống giá lẻ → giữ', () => {
  const { sheet, post } = setup();
  post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 2 }] });
  post({ action: 'add', ...P, le: true, price: 40000, lots: [{ hsd: '2027-03-15', qty: 3 }] });
  const d = post({ action: 'add', ...P, le: true, price: 45000, lots: [{ hsd: '2027-03-15', qty: 1 }] });
  assert.strictEqual(d.results[0].status, 'duplicate');
  assert.strictEqual(d.results[0].currentQty, 3);
  assert.deepStrictEqual(sheet.data.slice(1).map((x) => x[4]), [140000, 45000]);
  post({ action: 'add', ...P, le: true, price: 0, lots: [{ hsd: '2027-06-30', qty: 4 }] });
  assert.deepStrictEqual(sheet.data.slice(1).map((x) => x[4]), [140000, 45000, 45000]);
  post({ action: 'add', ...P, price: 0, lots: [{ hsd: '2027-07-31', qty: 1 }] });
  assert.deepStrictEqual(sheet.data.slice(1).map((x) => x[4]), [140000, 45000, 45000, 140000]);
});

test('sản phẩm chỉ bán lẻ: tra cứu ra giá lẻ, giá lốc 0; đổi tên áp dụng cả lốc và lẻ', () => {
  const { sheet, post, get } = setup();
  post({ action: 'add', ...P, le: true, price: 40000, lots: [{ hsd: '2027-03-15', qty: 3 }] });
  const l = get({ action: 'lookup', barcode: P.barcode });
  assert.deepStrictEqual([l.product.price, l.product.priceLe], [0, 40000]);
  post({ action: 'add', ...P, name: 'Tên mới', lots: [{ hsd: '2027-03-15', qty: 1 }] });
  assert.ok(sheet.data.slice(1).every((x) => x[1] === 'Tên mới'));
});

test('updateProduct: price = giá lốc, priceLe = giá lẻ, bỏ trống thì giữ', () => {
  const { sheet, post } = setup();
  post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 2 }] });
  post({ action: 'add', ...P, le: true, price: 40000, lots: [{ hsd: '2027-03-15', qty: 3 }] });
  assert.strictEqual(post({ action: 'updateProduct', barcode: P.barcode, name: 'X', priceLe: 42000 }).rowsChanged, 2);
  assert.deepStrictEqual(sheet.data.slice(1).map((x) => [x[1], x[4]]), [['X', 140000], ['X', 42000]]);
  post({ action: 'updateProduct', barcode: P.barcode, name: 'X', price: 150000 });
  assert.deepStrictEqual(sheet.data.slice(1).map((x) => x[4]), [150000, 42000]);
});

test('updateLot hàng lẻ đổi sang date đang có ở lốc → không trùng (khác loại)', () => {
  const { post } = setup();
  post({ action: 'add', ...P, lots: [{ hsd: '2027-06-15', qty: 2 }] });
  const id = post({ action: 'add', ...P, le: true, lots: [{ hsd: '2027-03-15', qty: 3 }] }).results[0].id;
  const r = post({ action: 'updateLot', id, expect: { barcode: P.barcode, hsd: '2027-03-15', qty: 3 }, hsd: '2027-06-15' });
  assert.strictEqual(r.status, 'updated');
});

test('mở lốc: trừ lốc, cộng lẻ cùng date (tạo dòng lẻ mới, giá lẻ nhập lúc mở)', () => {
  const { sheet, post, get } = setup();
  const id = post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 3 }] }).results[0].id;
  const expect = { barcode: P.barcode, hsd: '2027-03-15', qty: 3 };
  const r = post({ action: 'openPack', id, expect, perPack: 4, priceLe: '40.000' });
  assert.deepStrictEqual([r.status, r.newQty, r.leQty, r.created], ['opened', 2, 4, true]);
  assert.deepStrictEqual(sheet.data.slice(1).map((x) => [x[2].getDate(), x[3], x[4], x[LOAI] || '']), [[15, 2, 140000, ''], [15, 4, 40000, 'Lẻ']]);
  assert.strictEqual(get({ action: 'lookup', barcode: P.barcode }).lots.find((l) => l.le).id, r.leId);
});

test('mở lốc lần nữa / mở nhiều lốc: cộng vào dòng lẻ cùng date, giữ giá lẻ', () => {
  const { sheet, post } = setup();
  const id = post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 5 }] }).results[0].id;
  post({ action: 'add', ...P, le: true, price: 40000, lots: [{ hsd: '2027-03-15', qty: 1 }] });
  const r1 = post({ action: 'openPack', id, expect: { barcode: P.barcode, hsd: '2027-03-15', qty: 5 }, perPack: 4 });
  assert.deepStrictEqual([r1.newQty, r1.leQty, r1.created], [4, 5, false]);
  const r2 = post({ action: 'openPack', id, expect: { barcode: P.barcode, hsd: '2027-03-15', qty: 4 }, perPack: 6, count: 2 });
  assert.deepStrictEqual([r2.newQty, r2.leQty], [2, 17]);
  assert.strictEqual(sheet.getLastRow(), 3);
  assert.deepStrictEqual(sheet.data.slice(1).map((x) => x[4]), [140000, 40000]);
});

test('mở lốc: thiếu lốc / số hộp sai / dòng lẻ / dữ liệu đã đổi → không ghi gì', () => {
  const { sheet, post } = setup();
  const id = post({ action: 'add', ...P, lots: [{ hsd: '2027-03-15', qty: 1 }] }).results[0].id;
  const leId = post({ action: 'add', ...P, le: true, lots: [{ hsd: '2027-03-15', qty: 1 }] }).results[0].id;
  const expect = { barcode: P.barcode, hsd: '2027-03-15', qty: 1 };
  const before = JSON.stringify(sheet.data);
  assert.strictEqual(post({ action: 'openPack', id, expect, perPack: 4, count: 2 }).ok, false);
  for (const perPack of [0, -1, 2.5, 'abc', 1001, undefined]) assert.strictEqual(post({ action: 'openPack', id, expect, perPack }).ok, false);
  assert.strictEqual(post({ action: 'openPack', id: leId, expect, perPack: 4 }).ok, false);
  assert.strictEqual(post({ action: 'openPack', id, expect: { ...expect, qty: 5 }, perPack: 4 }).status, 'conflict');
  assert.strictEqual(JSON.stringify(sheet.data), before);
});

test('tự sửa giá rác: giá lấy từ date cùng loại (lẻ lấy giá lẻ, không lấy giá lốc)', () => {
  const H = [...HEADER, 'Loại'];
  const sheet = new MockSheet([H,
    ['111', 'A', '31/01/2027', 1, 140000, 'aaaaaaa1', ''],
    ['111', 'A', '28/02/2027', 1, '9a0649ba', 'aaaaaaa2', ''],
    ['111', 'A', '31/01/2027', 4, 40000, 'aaaaaaa3', 'Lẻ'],
    ['111', 'A', '28/02/2027', 4, '5c7f1194', 'aaaaaaa4', 'lẻ'],
  ]);
  const ctx = makeContext(sheet);
  JSON.parse(ctx.doGet({ parameter: { key: ctx.KEY, action: 'snapshot' } }).content);
  assert.deepStrictEqual(sheet.data.slice(1).map((r) => r[4]), [140000, 140000, 40000, 40000]);
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
