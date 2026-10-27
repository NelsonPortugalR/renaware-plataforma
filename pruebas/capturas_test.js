// Capturas de la página del test en un celular (Chromium + Supabase simulado).
// Correr: node pruebas/capturas_test.js <carpeta>   (necesita playwright)
const {chromium} = require('playwright');
const fs = require('fs');
const path = require('path');
const {servidor} = require('./simulador_test');
const HTML = fs.readFileSync(path.join(__dirname, '..', 'public', 'test', 'index.html'), 'utf8');
const URL = 'https://renaware-plataforma.nelson1614.workers.dev/test/';
const SB = 'https://kiexpdaaoegbtesqmaff.supabase.co';
const out = process.argv[2] || 'capturas';
fs.mkdirSync(out, {recursive: true});
const foto = color => `<svg xmlns="http://www.w3.org/2000/svg" width="600" height="420" viewBox="0 0 600 420">
  <rect width="600" height="420" fill="#fff"/><ellipse cx="300" cy="150" rx="190" ry="34" fill="${color}" opacity=".85"/>
  <rect x="110" y="150" width="380" height="200" rx="26" fill="${color}"/><ellipse cx="300" cy="350" rx="190" ry="30" fill="${color}"/>
  <rect x="40" y="185" width="80" height="22" rx="11" fill="#555"/><rect x="480" y="185" width="80" height="22" rx="11" fill="#555"/></svg>`;

async function abrir(browser, {oscuro = false, preparar} = {}){
  const srv = servidor();
  const ctx = await browser.newContext({viewport: {width: 390, height: 844}, deviceScaleFactor: 2, colorScheme: oscuro ? 'dark' : 'light'});
  const page = await ctx.newPage();
  await page.route('**/*', async route => {
    const u = route.request().url();
    if (u.startsWith(URL)) return route.fulfill({contentType: 'text/html; charset=utf-8', body: HTML});
    if (u.startsWith('https://x/')) return route.fulfill({contentType: 'image/svg+xml', body: foto(u.includes('a.') ? '#9aa6b2' : u.includes('b.') ? '#b88a5a' : '#7f8c99')});
    if (u.startsWith(SB)) {
      const req = route.request();
      const b = req.postData() ? JSON.parse(req.postData()) : {};
      const {st = 200, d} = await srv.manejar(u.replace(SB, ''), b, req.headers());
      return route.fulfill({status: st, contentType: 'application/json', body: d === undefined ? '' : JSON.stringify(d)});
    }
    return route.abort();
  });
  await page.goto(URL);
  if (preparar) { await page.evaluate(preparar); await page.goto(URL); }
  await page.waitForTimeout(250);
  return {page, srv, ctx};
}
const foto_ = async (page, n) => { await page.waitForTimeout(200); await page.screenshot({path: path.join(out, n + '.png'), fullPage: true}); };

(async () => {
  const browser = await chromium.launch();
  // Asesor
  let {page, srv} = await abrir(browser, {preparar: () => localStorage.setItem('rw_test_token', JSON.stringify('tok-test'))});
  await foto_(page, '01-estado-habilitado');
  await page.getByRole('button', {name: 'Empezar el test'}).click();
  await foto_(page, '02-emparejar');
  await page.selectOption('#par-i1', 'n2'); await page.selectOption('#par-i2', 'n1');
  await page.getByRole('button', {name: 'Responder'}).click();
  await foto_(page, '03-correcto');
  await page.getByRole('button', {name: 'Siguiente'}).click();
  await page.locator('.opcion').first().click();
  await foto_(page, '04-pregunta-con-foto');
  await page.getByRole('button', {name: 'Responder'}).click();
  await foto_(page, '05-fallo-con-logica');
  await page.getByRole('button', {name: 'Otra pregunta'}).click();
  await page.locator('.opcion').nth(1).click(); await page.getByRole('button', {name: 'Responder'}).click();
  await page.getByRole('button', {name: 'Siguiente'}).click();
  await page.locator('.opcion').nth(0).click(); await page.locator('.opcion').nth(2).click();
  await foto_(page, '06-multi');
  await page.getByRole('button', {name: 'Responder'}).click(); await page.getByRole('button', {name: 'Siguiente'}).click();
  await page.fill('input[inputmode="numeric"]', '1941234567890');
  await page.getByRole('button', {name: 'Responder'}).click();
  await page.getByRole('button', {name: 'Ver mi nota'}).click();
  await foto_(page, '07-final-no-aprueba');
  // Oficina
  ({page} = await abrir(browser, {preparar: () => localStorage.setItem('rw_test_admin', JSON.stringify('adm-1'))}));
  await foto_(page, '10-oficina-resultados');
  await page.locator('.persona > button').first().click();
  await foto_(page, '11-oficina-persona');
  await page.getByRole('tab', {name: 'Preguntas'}).click();
  await foto_(page, '12-oficina-preguntas');
  await page.getByRole('tab', {name: 'Ajustes'}).click();
  await foto_(page, '13-oficina-ajustes');
  // Oscuro
  ({page} = await abrir(browser, {oscuro: true, preparar: () => localStorage.setItem('rw_test_token', JSON.stringify('tok-test'))}));
  await page.getByRole('button', {name: 'Empezar el test'}).click();
  await page.selectOption('#par-i1', 'n1'); await page.selectOption('#par-i2', 'n2');
  await page.getByRole('button', {name: 'Responder'}).click();
  await foto_(page, '20-oscuro-fallo');
  // Entrada
  ({page} = await abrir(browser));
  await foto_(page, '30-entrar');
  await browser.close();
  console.log('capturas en', out);
})().catch(e => { console.error(e); process.exit(1); });
