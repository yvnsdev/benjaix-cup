import sys, threading, functools, json
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'.qa'))
from playwright.sync_api import sync_playwright
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*args): pass
server=ThreadingHTTPServer(('127.0.0.1',4176),functools.partial(Quiet,directory=str(root/'dist')))
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  browser=p.chromium.launch(channel='msedge',headless=True)
  page=browser.new_page(viewport={'width':1440,'height':1000});errors=[]
  page.emulate_media(reduced_motion='reduce')
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.route('**/config.js',lambda r:r.fulfill(content_type='text/javascript',body='window.BENJAIX_CONFIG = {};'))
  page.goto('http://127.0.0.1:4176/#panel')
  page.locator('[data-demo=admin]').click()
  page.locator('.management-nav [data-management=matches]').click()
  assert not page.locator('#manage-match').is_visible()
  assert page.locator('[data-browser=manage-match] .match-choice').count()==6
  page.locator('[data-browser=manage-match] [data-browser-query]').fill('Cóndores')
  assert page.locator('[data-browser=manage-match] .match-choice').count()>0
  page.locator('[data-browser=manage-match] [data-pick-match=m0]').click()
  assert page.locator('#score-editor .home-event').count()==2
  assert page.locator('#score-editor .away-event').count()==1
  page.locator('[data-browser=manage-match] [data-browser-query]').fill('sin coincidencias')
  assert page.locator('[data-browser=manage-match] .match-choice').count()==0
  page.locator('[data-browser=manage-match] [data-browser-query]').fill('')
  page.locator('[data-browser=manage-match] [data-page-step="1"]').click()
  assert 'Página 2' in page.locator('[data-browser=manage-match]').inner_text()
  page.locator('.management-nav [data-management=lineups]').click()
  assert not page.locator('#lineup-match').is_visible()
  page.locator('[data-browser=lineup-match] [data-browser-status]').select_option('scheduled')
  page.locator('[data-browser=lineup-match] .match-choice').first.click()
  assert page.locator('[data-lineup-slot]').count()==7
  page.locator('#lineup-form [name=formation]').select_option('3-1-1-1')
  for i in range(7):page.locator('[data-lineup-slot="'+str(i)+'"]').select_option('p0-'+str(i))
  assert page.locator('#formation-preview .pitch-player:not(.vacant)').count()==7
  before=page.locator('#formation-preview .pitch-player').evaluate_all('(els)=>els.map(e=>e.getAttribute("style"))')
  match_id=page.locator('#lineup-form').get_attribute('data-id')
  page.locator('#lineup-form button').click()
  after=page.locator('#formation-preview .pitch-player').evaluate_all('(els)=>els.map(e=>e.getAttribute("style"))')
  assert before==after
  saved=page.evaluate('JSON.parse(localStorage.getItem("benjaix-demo-v2"))')
  lineup=next(l for l in saved['lineups'] if l['match_id']==match_id and l['team_id']=='t0')
  assert lineup['slot_player_ids']==['p0-'+str(i) for i in range(7)]
  page.screenshot(path=str(root/'.qa/fixed-formations.png'),full_page=True)
  page.locator('.management-nav [data-management=cups]').click()
  page.locator('.existing-cups summary').first.click()
  page.locator('.existing-cups [name=name]').first.fill('Copa de prueba')
  page.locator('.existing-cups [name=rules]').first.fill('Partidos de 25 minutos.\nRespeto al rival. <script>alert(1)</script>')
  page.locator('.existing-cups button').first.click()
  page.goto('http://127.0.0.1:4176/#copa')
  assert 'Copa de prueba' in page.locator('.cup-banner').inner_text()
  assert '<script>' in page.locator('.rules-text').inner_text()
  assert page.locator('.bracket-node').count()==7
  assert page.locator('.bracket-lines path').count()==6
  assert page.locator('.third-place .bracket-match').count()==1
  page.screenshot(path=str(root/'.qa/connected-bracket.png'),full_page=True)
  page.goto('http://127.0.0.1:4176/#reglamento')
  page.locator('summary').click()
  page.locator('[name=rules]').fill('Bases de la liga\nVictoria: 3 puntos.')
  page.locator('#rules-form button').click()
  assert 'Victoria: 3 puntos.' in page.locator('.rules-text').inner_text()
  page.goto('http://127.0.0.1:4176/#estadisticas')
  assert page.locator('.stats-table').count()==1 and page.locator('.stat-tabs').count()==0
  count=page.locator('.stats-table tbody tr').count()
  page.locator('#stats-sort').select_option('red')
  assert page.locator('.stats-table tbody tr').count()==count
  page.goto('http://127.0.0.1:4176/#panel')
  page.locator('[data-demo=admin]').click() if page.locator('[data-demo=admin]').count() else None
  page.locator('.management-nav [data-management=roster]').click()
  page.locator('#edit-team').locator('..').locator('summary').click()
  # PNG input becomes WebP; transparency and non-square aspect ratio are retained.
  image=page.evaluate('''()=>{const c=document.createElement('canvas');c.width=800;c.height=400;const x=c.getContext('2d');x.fillStyle='#dd2244';x.fillRect(100,50,600,300);return c.toDataURL('image/png').split(',')[1]}''')
  import base64
  page.locator('[name=crest_file]').set_input_files({'name':'crest.png','mimeType':'image/png','buffer':base64.b64decode(image)})
  page.wait_for_function('document.querySelector("#crest-feedback").textContent.includes("WebP listo")')
  page.locator('#crest-form button').click()
  page.wait_for_function('JSON.parse(localStorage.getItem("benjaix-demo-v2")).teams[0].demo_crest')
  url=page.evaluate('JSON.parse(localStorage.getItem("benjaix-demo-v2")).teams[0].demo_crest')
  assert url.startswith('data:image/webp;base64,')
  assert len(base64.b64decode(url.split(',')[1]))<=65536
  dims=page.evaluate('''async url=>{const b=await createImageBitmap(await (await fetch(url)).blob());return [b.width,b.height]}''',url)
  assert dims==[256,128]
  for width in [1440,390]:
   page.set_viewport_size({'width':width,'height':900})
   page.goto('http://127.0.0.1:4176/#partidos');page.locator('[data-match=m0]').click()
   assert page.locator('.match-timeline time').first.inner_text()=='61′'
   assert page.locator('#modal').evaluate('(e)=>e.scrollWidth<=e.clientWidth')
   page.screenshot(path=str(root/f'.qa/split-timeline-{width}.png'))
   page.locator('[data-match-view=lineups]').click()
   assert page.locator('.tactical-pitch .pitch-player').count()==7
   assert page.locator('#modal').evaluate('(e)=>e.scrollWidth<=e.clientWidth')
   page.locator('.close').click()
   page.goto('http://127.0.0.1:4176/#copa')
   assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
  assert not errors,errors
  browser.close()
  print('PASS: search/pagination, fixed lineup slots and persistence, split timelines, cup/rules editing and escaping, bracket connections, unified stats, PNG to bounded WebP, desktop/mobile overflow.')
finally:server.shutdown()
