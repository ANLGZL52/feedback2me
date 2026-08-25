// error-watch birim testleri — log satırı sınıflandırma + yeni-hata deduplama (saf).
import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { classify, errorKeysOf, newErrorKeys } from './error-watch.mjs';

const ev = (o) => JSON.stringify(o);

describe('classify — hangi log satırı HATA sayılır', () => {
  test('IAP rejected (yapısal event) -> ERROR', () => {
    const c = classify('W', 'iapverify', ev({ eventType: 'iap.verify.android.rejected', errorCode: 'play_http_401', service: 'iapVerify' }));
    assert.equal(c.severity, 'ERROR');
    assert.equal(c.service, 'iapVerify');
    assert.equal(c.code, 'play_http_401');
  });
  test('IAP transient_failure -> WARNING (kalıcı değil)', () => {
    const c = classify('W', 'iapverify', ev({ eventType: 'iap.verify.android.transient_failure', errorCode: 'play_http_503', service: 'iapVerify' }));
    assert.equal(c.severity, 'WARNING');
  });
  test('iap.verify.error -> ERROR', () => {
    const c = classify('E', 'iapverify', ev({ eventType: 'iap.verify.error', service: 'iapVerify' }));
    assert.equal(c.severity, 'ERROR');
  });
  test('success / started / replay -> HATA DEĞİL (null)', () => {
    assert.equal(classify('I', 'iapverify', ev({ eventType: 'iap.verify.android.success' })), null);
    assert.equal(classify('I', 'iapverify', ev({ eventType: 'iap.verify.started' })), null);
    assert.equal(classify('I', 'iapverify', ev({ eventType: 'iap.credit.granted', creditDelta: 1 })), null);
  });
  test('ham severity E satırı -> function-error ERROR + kod çıkarımı', () => {
    const c = classify('E', 'aiSummary', 'Error: FUNCTION_RUNTIME_ERROR unhandled');
    assert.equal(c.severity, 'ERROR');
    assert.equal(c.kind, 'function-error');
    assert.ok(c.code); // bir hata kodu yakalanmış olmalı
  });
  test('severity W + "timeout" (ham) -> WARNING', () => {
    const c = classify('W', 'iapverify', 'request timeout while calling upstream');
    assert.equal(c.severity, 'WARNING');
    assert.equal(c.kind, 'function-warning');
  });
  test('normal info/debug -> null', () => {
    assert.equal(classify('I', 'iapverify', 'Default STARTUP TCP probe succeeded'), null);
    assert.equal(classify('D', 'iapverify', 'Callable request verification passed'), null);
  });
});

describe('deduplama — yeni-vs-bilinen hata anahtarları', () => {
  const report = {
    items: [
      { severity: 'ERROR', service: 'iapVerify', event: 'iap.verify.android.rejected', code: 'play_http_401', count: 2 },
      { severity: 'ERROR', service: 'aiSummary', event: 'log.error', code: 'X', count: 1 },
      { severity: 'WARNING', service: 'iapVerify', event: 'iap.verify.android.transient_failure', code: 'play_http_503', count: 1 },
    ],
  };
  test('errorKeysOf yalnız ERROR öğelerini alır (uyarıları değil)', () => {
    const keys = errorKeysOf(report);
    assert.equal(keys.length, 2);
    assert.ok(keys.includes('iapVerify|iap.verify.android.rejected|play_http_401'));
    assert.ok(!keys.some((k) => k.includes('transient')));
  });
  test('newErrorKeys: alarm verilmemiş olanları döndürür', () => {
    const current = errorKeysOf(report);
    const alerted = ['iapVerify|iap.verify.android.rejected|play_http_401'];
    const fresh = newErrorKeys(current, alerted);
    assert.deepEqual(fresh, ['aiSummary|log.error|X']);
  });
  test('hepsi biliniyorsa yeni yok', () => {
    const current = errorKeysOf(report);
    assert.equal(newErrorKeys(current, current).length, 0);
  });
});
