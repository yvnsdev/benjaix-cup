import sys, threading, functools
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'.qa'))
from playwright.sync_api import sync_playwright
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*args): pass
server=ThreadingHTTPServer(('127.0.0.1',4175),functools.partial(Quiet,directory=str(root/'dist')))
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 with sync_playwright() as p:
  browser=p.chromium.launch(channel='msedge',headless=True)
  page=browser.new_page(viewport={'width':1440,'height':1000});errors=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.route('**/config.js',lambda r:r.fulfill(content_type='text/javascript',body='window.BENJAIX_CONFIG = {};'))
  page.goto('http://127.0.0.1:4175/#partidos')
  page.locator('[data-match=m0]').click()
  assert page.locator('.match-timeline time').first.inner_text()=='61′'
  assert page.locator('.match-summary .score').inner_text().startswith('2')
  page.screenshot(path=str(root/'.qa/refined-timeline.png'))
  page.locator('[data-match-view=lineups]').click()
  assert page.locator('.pitch-player').count()==11
  page.locator('[data-lineup-side]').last.click()
  assert page.locator('.lineup-caption strong').inner_text()=='Atlético Norte'
  page.screenshot(path=str(root/'.qa/refined-lineups.png'))
  page.locator('[data-match-view=votes]').click()
  initial=int(page.locator('.vote-count strong').inner_text())
  page.locator('[data-vote-player]').first.click()
  assert page.locator('.candidate.chosen').count()==1
  assert int(page.locator('.vote-count strong').inner_text())==initial+1
  page.locator('.candidate:not(.chosen)').first.click()
  assert int(page.locator('.vote-count strong').inner_text())==initial+1
  assert page.locator('[data-match-view=votes]').get_attribute('aria-pressed')=='true'
  assert page.locator('.candidate-grid').evaluate('(e)=>getComputedStyle(e).maxHeight')=='none'
  page.locator('[data-vote-team]').last.click()
  assert page.locator('.candidate').count()==11
  page.locator('.close').click()
  page.goto('http://127.0.0.1:4175/#panel');page.locator('[data-demo=admin]').click()
  page.locator('.management-nav [data-management=matches]').click()
  page.locator('#manage-match').select_option('m0')
  assert page.locator('#score-form fieldset').count()==2
  page.locator('#score-form [name=home_score]').fill('3')
  page.locator('#score-form button').click()
  assert page.locator('#score-form [name=home_score]').input_value()=='3'
  page.locator('.management-nav [data-management=roster]').click()
  page.locator('#roster-search').fill('no-coincidencia')
  assert page.locator('#roster-no-results').is_visible()
  page.locator('#roster-search').fill('')
  assert not page.locator('#roster-no-results').is_visible()
  assert page.locator('#player-form [name=position]').input_value()=='POR'
  page.locator('#player-form [name=name]').fill('Jugador Prueba')
  page.locator('#player-form [name=number]').fill('88')
  page.locator('#player-form [name=position]').select_option('DEF')
  page.locator('#player-form button').click()
  assert 'Jugador Prueba' in page.locator('.roster-workspace').inner_text()
  page.screenshot(path=str(root/'.qa/refined-roster.png'),full_page=True)
  page.set_viewport_size({'width':390,'height':844})
  assert page.evaluate('document.documentElement.scrollWidth<=innerWidth')
  page.goto('http://127.0.0.1:4175/#partidos');page.locator('[data-match=m0]').click()
  for tab in ['timeline','lineups','votes']:
   page.locator('[data-match-view='+tab+']').click()
   assert page.locator('#modal').evaluate('(e)=>e.scrollWidth<=e.clientWidth'),tab
   page.screenshot(path=str(root/('.qa/refined-'+tab+'-mobile.png')))
  page.keyboard.press('Escape');assert not page.locator('#modal').is_visible()
  page.goto('http://127.0.0.1:4175/#equipos');page.locator('[data-team]').first.click()
  assert page.locator('.team-roster section').count()==4
  assert page.locator('#modal').evaluate('(e)=>e.scrollWidth<=e.clientWidth')
  assert not errors,errors
  browser.close()
  print('PASS: timeline order, lineup switching, voting/change/filter, single scroll, result save, roster search and registration, mobile dialogs, Escape and team roster.')
finally: server.shutdown()
