import sys, threading, functools
from pathlib import Path
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'.qa'))
from playwright.sync_api import sync_playwright
class Quiet(SimpleHTTPRequestHandler):
 def log_message(self,*args): pass
server=ThreadingHTTPServer(('127.0.0.1',4179),functools.partial(Quiet,directory=str(root/'dist')))
threading.Thread(target=server.serve_forever,daemon=True).start()
source=(root/'dist/app.js').read_text(encoding='utf-8')
# Instrument only the served test copy, not production code. Auth network calls
# are counted; the production callback and background rendering remain intact.
source+='''
window.tabTest={
 setup(){authUserId='same-user';profile={id:'same-user',role:'admin'};window.authReads=0;
  loadProfile=async(session,isCurrent=()=>true)=>{window.authReads++;if(isCurrent())profile={id:session.user.id,role:'admin'};};
  refresh=async()=>{window.authReads++;refreshVisibleData();};},
 auth:handleAuthStateChange,
 background(){applyRealtime({table:'teams',eventType:'UPDATE',new:{id:'t1',name:'Actualizado en vivo'}});refreshVisibleData();},
 user(){return profile?.id||null;}
};'''
try:
 with sync_playwright() as p:
  browser=p.chromium.launch(channel='msedge',headless=True)
  page=browser.new_page(viewport={'width':1440,'height':1000},reduced_motion='reduce')
  errors=[];page.on('pageerror',lambda error:errors.append(str(error)))
  page.route('**/config.js',lambda r:r.fulfill(content_type='text/javascript',body='window.BENJAIX_CONFIG = {};'))
  page.route('**/app.js',lambda r:r.fulfill(content_type='text/javascript',body=source))
  page.goto('http://127.0.0.1:4179/#panel')
  page.locator('[data-demo=admin]').click()
  page.evaluate('tabTest.setup()')
  page.locator('.management-nav [data-management=schedule]').click()
  page.locator('#match-form [name=venue]').fill('Cancha sin guardar')
  page.locator('#match-form [name=kickoff]').fill('2026-11-15T18:30')
  page.evaluate('window.originalForm=document.querySelector("#match-form");document.activeElement.blur()')
  page.evaluate('''()=>{for(let i=0;i<3;i++)tabTest.auth('SIGNED_IN',{user:{id:'same-user'}});tabTest.auth('TOKEN_REFRESHED',{user:{id:'same-user'}});tabTest.background();}''')
  page.wait_for_timeout(80)
  assert page.evaluate('authReads')==0
  assert page.evaluate('originalForm===document.querySelector("#match-form")')
  assert page.locator('#match-form [name=venue]').input_value()=='Cancha sin guardar'
  assert page.locator('#match-form [name=kickoff]').input_value()=='2026-11-15T18:30'
  assert page.locator('.management-section[data-section=schedule]').is_visible()
  # Same-session reconfirmation must also leave public navigation alone.
  page.goto('http://127.0.0.1:4179/#equipos')
  page.evaluate("tabTest.auth('SIGNED_IN',{user:{id:'same-user'}})")
  page.wait_for_timeout(80)
  assert page.url.endswith('#equipos') and page.evaluate('authReads')==0
  # Rules drafts outside the admin route are protected too.
  page.goto('http://127.0.0.1:4179/#reglamento')
  page.locator('summary').click();page.locator('#rules-form textarea').fill('Bases pendientes')
  page.evaluate('document.activeElement.blur();tabTest.background()')
  assert page.locator('#rules-form textarea').input_value()=='Bases pendientes'
  # Fresh login/account change still works; repeated events are deduplicated.
  page.evaluate("tabTest.auth('SIGNED_IN',{user:{id:'new-user'}});tabTest.auth('SIGNED_IN',{user:{id:'new-user'}})")
  page.wait_for_function("tabTest.user()==='new-user'&&location.hash==='#panel'")
  assert page.evaluate('authReads')==2
  # Logout cancels a queued sign-in instead of reopening the panel afterwards.
  page.evaluate("tabTest.auth('SIGNED_IN',{user:{id:'cancelled-user'}});tabTest.auth('SIGNED_OUT',null)")
  page.wait_for_timeout(80)
  assert page.evaluate('tabTest.user()') is None
  assert page.evaluate('authReads')==2
  # Without a draft, live updates continue reaching the public view.
  page.goto('http://127.0.0.1:4179/#equipos')
  page.evaluate('tabTest.background()')
  assert 'Actualizado en vivo' in page.locator('#app').inner_text()
  assert not errors,errors
  browser.close()
  print('PASS: repeated sign-in/token refresh preserve route and drafts after blur; rules drafts survive Realtime; genuine login/logout and live updates still work.')
finally:server.shutdown()
