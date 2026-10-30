import sys, threading, functools
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'.qa'))
from playwright.sync_api import sync_playwright
class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self,*args): pass
server=ThreadingHTTPServer(('127.0.0.1',4173),functools.partial(QuietHandler,directory=str(root/'dist')))
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  browser=p.chromium.launch(channel='msedge',headless=True)
  page=browser.new_page(viewport={'width':1440,'height':1000},reduced_motion='reduce')
  errors=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.route('**/config.js',lambda route:route.fulfill(content_type='text/javascript',body='window.BENJAIX_CONFIG = {};'))
  page.goto('http://127.0.0.1:4173')
  page.get_by_role('heading',name='La liga se vive aquí.').wait_for()
  assert page.locator('svg.icon').count()>15
  assert '[[' not in page.locator('body').inner_text()
  assert page.locator('.home-cup-match').count()==4
  assert page.locator('.home-cup-phase h3').inner_text()=='Cuartos de final'
  page.locator('a[data-nav="copa"]').click()
  assert page.locator('.bracket-match').count()==7
  page.locator('.bracket-match').first.click()
  assert page.locator('dialog').is_visible()
  page.get_by_role('button',name='Cerrar',exact=True).click()
  page.goto('http://127.0.0.1:4173/#panel')
  page.get_by_role('button',name='Crear cuenta',exact=True).click()
  assert page.locator('input[name="password_repeat"]').is_visible()
  page.get_by_role('button',name='Demo jugador',exact=True).click()
  assert page.get_by_text('Mis equipos como jugador',exact=True).is_visible()
  assert page.locator('#edit-team').count()==0
  page.get_by_role('button',name='Cerrar sesión',exact=True).click()
  page.get_by_role('button',name='Demo capitán',exact=True).click()
  assert page.locator('#edit-team').is_visible()
  assert page.locator('#manage-match').count()==0
  page.get_by_role('button',name='Cerrar sesión',exact=True).click()
  page.get_by_role('button',name='Demo admin',exact=True).click()
  assert page.locator('#cup-form').is_visible()
  option=page.locator('#manage-match option').all()
  value=next(o.get_attribute('value') for o in option if 'Cuartos' in o.inner_text())
  page.locator('#manage-match').select_option(value)
  page.locator('#score-form input[name="home_score"]').fill('2')
  page.locator('#score-form input[name="away_score"]').fill('1')
  page.locator('#score-form select[name="status"]').select_option('finished')
  page.get_by_role('button',name='Actualizar marcador',exact=True).click()
  page.get_by_text('Cambios guardados',exact=True).wait_for()
  page.locator('#manage-match').select_option('m0')
  assert page.locator('.expert-admin').inner_text().find('La votación está abierta')>=0
  assert page.locator('#expert-poll-form').count()==0
  page.goto('http://127.0.0.1:4173/#copa')
  assert page.locator('.bracket-round').nth(1).inner_text().count('Los Cóndores')==1
  page.screenshot(path=str(root/'.qa/copa-desktop.png'),full_page=True)
  page.goto('http://127.0.0.1:4173/#panel')
  page.get_by_role('button',name='Cerrar sesión',exact=True).click()
  page.goto('http://127.0.0.1:4173/#estadisticas')
  page.locator('[data-stat-metric="assist"]').click()
  assert page.locator('.stats-table tbody tr').count()>0
  page.locator('#stat-competition').select_option('cup-demo')
  assert page.locator('.stats-table tbody tr').count()==0
  page.locator('#stat-competition').select_option('all')
  page.locator('[data-stat-metric="yellow"]').click()
  assert page.locator('.stats-table tbody tr').count()>0
  page.locator('[data-stat-metric="goal"]').click()
  page.screenshot(path=str(root/'.qa/stats-desktop.png'),full_page=True)
  page.goto('http://127.0.0.1:4173/#partidos')
  page.locator('[data-filter="live"]').click()
  page.locator('[data-match="m0"]').click()
  assert page.locator('[data-vote-player]').count()==22
  assert page.locator('.vote-status').text_content().strip()=='Vota en vivo'
  initial=int(page.locator('.vote-count strong').inner_text())
  page.locator('[data-vote-player]').first.click()
  page.locator('.candidate.chosen').wait_for()
  assert int(page.locator('.vote-count strong').inner_text())==initial+1
  page.locator('.candidate:not(.chosen)').first.click()
  assert int(page.locator('.vote-count strong').inner_text())==initial+1
  page.screenshot(path=str(root/'.qa/vote-desktop.png'),full_page=True)
  page.get_by_role('button',name='Cerrar',exact=True).click()
  page.reload()
  page.locator('[data-match="m0"]').click()
  assert page.locator('.candidate.chosen').count()==1
  assert int(page.locator('.vote-count strong').inner_text())==initial+1
  page.get_by_role('button',name='Cerrar',exact=True).click()
  page.goto('http://127.0.0.1:4173/#experto')
  assert page.locator('.showcase-card').count()==2
  assert page.locator('[data-open-match="m0"]').count()==0
  assert page.get_by_role('button',name='Votar ahora',exact=False).count()==0
  page.screenshot(path=str(root/'.qa/showcase-desktop.png'),full_page=True)
  page.goto('http://127.0.0.1:4173/#panel')
  page.get_by_role('button',name='Demo admin',exact=True).click()
  page.locator('#manage-match').select_option('m0')
  page.locator('#score-form select[name="status"]').select_option('finished')
  page.get_by_role('button',name='Actualizar marcador',exact=True).click()
  page.get_by_text('Cambios guardados',exact=True).wait_for()
  page.goto('http://127.0.0.1:4173/#experto')
  assert page.locator('.showcase-card').count()==3
  assert page.locator('.showcase-card').first.locator('[data-open-match="m0"]').count()==1
  page.locator('.showcase-card').first.locator('button').click()
  assert page.locator('.vote-status').text_content().strip()=='Votación cerrada'
  assert page.locator('[data-vote-player]:not(:disabled)').count()==0
  page.get_by_role('button',name='Cerrar',exact=True).click()
  page.goto('http://127.0.0.1:4173/#panel')
  remaining=page.evaluate("JSON.parse(localStorage.getItem('benjaix-demo-v2')).matches.filter(m=>m.competition_id==='cup-demo'&&m.round===1&&m.status!=='finished').map(m=>m.id)")
  for match_id in remaining:
   page.locator('#manage-match').select_option(match_id)
   page.locator('#score-form input[name="home_score"]').fill('1')
   page.locator('#score-form select[name="status"]').select_option('finished')
   page.get_by_role('button',name='Actualizar marcador',exact=True).click()
   page.locator('#manage-match').wait_for()
  page.goto('http://127.0.0.1:4173/#inicio')
  assert page.locator('.home-cup-phase h3').inner_text()=='Semifinales'
  assert page.locator('.home-cup-match').count()==2
  page.screenshot(path=str(root/'.qa/home-semifinals.png'),full_page=True)
  page.set_viewport_size({'width':390,'height':844})
  page.goto('http://127.0.0.1:4173')
  assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
  page.screenshot(path=str(root/'.qa/home-mobile.png'),full_page=True)
  page.goto('http://127.0.0.1:4173/#copa')
  assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
  page.screenshot(path=str(root/'.qa/copa-mobile.png'),full_page=True)
  page.goto('http://127.0.0.1:4173/#estadisticas')
  assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
  page.goto('http://127.0.0.1:4173/#experto')
  assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
  page.locator('.showcase-card').first.locator('button').click()
  assert page.evaluate('document.querySelector("dialog").scrollWidth <= document.querySelector("dialog").clientWidth')
  page.screenshot(path=str(root/'.qa/vote-mobile.png'),full_page=True)
  assert not errors,errors
  browser.close()
  print('PASS: home cup phase, roles, stats, live voting from match, participants, persistence, automatic close, showcase and mobile.')
finally:
 server.shutdown()
