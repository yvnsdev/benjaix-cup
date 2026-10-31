import sys,threading,functools
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'.qa'))
from playwright.sync_api import sync_playwright
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',4182),functools.partial(Quiet,directory=str(root/'dist')))
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  browser=p.chromium.launch(channel='msedge',headless=True)
  page=browser.new_page(viewport={'width':1440,'height':1000},reduced_motion='reduce')
  errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
  page.route('**/config.js',lambda r:r.fulfill(content_type='text/javascript',body='window.BENJAIX_CONFIG = {};'))
  page.goto('http://127.0.0.1:4182/#experto')
  assert page.locator('[data-nav=experto]').inner_text()=='Experto Tanzy'
  image=page.locator('.expert-tanzy-media img');image.wait_for()
  assert image.evaluate('(e)=>e.complete&&e.naturalWidth===768&&e.naturalHeight===512')
  assert 'Jugador Experto Tanzy' in page.locator('.page-heading').inner_text()
  assert 'BCUP' not in page.locator('#app').inner_text().upper()
  page.goto('http://127.0.0.1:4182/#partidos');page.locator('[data-match=m0]').click();page.locator('[data-match-view=votes]').click()
  assert 'Jugador Experto Tanzy' in page.locator('.vote-panel').inner_text()
  assert 'BCUP' not in page.locator('.vote-panel').inner_text().upper()
  page.locator('.close').click();page.goto('http://127.0.0.1:4182/#inicio')
  assert 'Jugador Experto Tanzy' in page.locator('.expert-promo').inner_text()
  for width in [1440,390]:
   page.set_viewport_size({'width':width,'height':900});page.goto('http://127.0.0.1:4182/#experto')
   assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
   assert page.locator('.expert-tanzy-media').is_visible()
   page.screenshot(path=str(root/f'.qa/expert-tanzy-{width}.png'),full_page=True)
  assert not errors,errors
  browser.close();print('PASS: Tanzy branding, optimized card image, voting/promo labels, desktop/mobile layout.')
finally:server.shutdown()
