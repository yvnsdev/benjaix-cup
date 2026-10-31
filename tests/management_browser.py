import sys,threading,functools
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
root=Path.cwd();sys.path.insert(0,str(root/'.qa'))
from playwright.sync_api import sync_playwright
server=ThreadingHTTPServer(('127.0.0.1',4174),functools.partial(SimpleHTTPRequestHandler,directory=str(root/'dist')))
threading.Thread(target=server.serve_forever,daemon=True).start()
with sync_playwright() as p:
 browser=p.chromium.launch(channel='msedge',headless=True)
 page=browser.new_page(viewport={'width':1440,'height':1000});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
 page.route('**/config.js',lambda r:r.fulfill(content_type='text/javascript',body='window.BENJAIX_CONFIG = {};'))
 page.goto('http://127.0.0.1:4174/#panel');page.locator('[data-demo=admin]').click()
 page.locator('.management-section[data-section=summary]').wait_for(state='visible')
 page.screenshot(path=str(root/'.qa/management-admin.png'),full_page=True)
 page.locator('.management-nav [data-management=matches]').click();page.locator('#manage-match').select_option('m0');page.locator('#score-form').wait_for(state='visible')
 page.locator('.management-nav [data-management=cups]').click()
 assert page.locator('#cup-form button').is_disabled()
 for i in range(4):page.locator('#cup-form input[type=checkbox]').nth(i).check()
 assert page.locator('#cup-form button').is_enabled()
 assert 'vs' in page.locator('#cup-progress').inner_text()
 page.locator('#logout').click();page.locator('[data-demo=captain]').click();page.locator('.management-nav [data-management=roster]').click()
 assert page.locator('#player-form').is_visible()
 assert page.locator('#score-form').count()==0
 page.locator('.management-nav [data-management=lineups]').click();page.locator('#lineup-match').select_option(index=2)
 if page.locator('#lineup-form').count():
  page.locator('#lineup-form input[type=checkbox]').first.check();assert '1 de 11' in page.locator('#lineup-form .selection-progress').inner_text()
  selected=page.locator('#lineup-match').input_value()
  page.locator('#lineup-form button').click()
  assert page.locator('#lineup-match').input_value()==selected
  assert page.locator('#lineup-form input[type=checkbox]').first.is_checked()
 page.locator('.management-nav [data-management=summary]').click()
 assert page.locator('.next-task').is_visible()
 page.locator('#logout').click();page.locator('[data-demo=player]').click()
 page.locator('.next-task button').click()
 assert page.locator('#create-own-team').is_visible()
 page.locator('.management-nav [data-management=lineups]').click()
 assert 'Primero necesitas un equipo' in page.locator('.management-section[data-section=lineups]').inner_text()
 page.set_viewport_size({'width':390,'height':844});page.locator('.management-nav [data-management=summary]').click()
 assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
 page.screenshot(path=str(root/'.qa/management-mobile.png'),full_page=True)
 assert not errors,errors
 print('PASS management: admin/captain navigation, result editor, cup validation and pairs, lineup counter, mobile overflow, no JS errors')
 browser.close()
server.shutdown()
