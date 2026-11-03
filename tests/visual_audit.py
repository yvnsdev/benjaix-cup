"""Read-only browser audit of all presentations using isolated demonstration data."""
import functools
import sys
import threading
from pathlib import Path
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
root=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(root/'.qa'))
from playwright.sync_api import sync_playwright
class Quiet(SimpleHTTPRequestHandler):
    def log_message(self,*args): pass
server=ThreadingHTTPServer(('127.0.0.1',4186),functools.partial(Quiet,directory=str(root/'dist')))
threading.Thread(target=server.serve_forever,daemon=True).start()
shots=root/'.qa'/'polish'
shots.mkdir(exist_ok=True)
try:
 with sync_playwright() as p:
    browser=p.chromium.launch(channel='msedge',headless=True)
    page=browser.new_page(viewport={'width':1440,'height':1000},reduced_motion='reduce')
    errors=[]
    page.on('pageerror',lambda error:errors.append(str(error)))
    page.on('dialog',lambda dialog:dialog.accept())
    page.route('**/config.js',lambda r:r.fulfill(content_type='text/javascript',body='window.BENJAIX_CONFIG = {};'))
    source=(root/'dist/app.js').read_text(encoding='utf-8')+'''\nwindow.seedVisualAudit=()=>{
      data.site_settings=[{...portalDefaults,dates:'Noviembre de 2026 · DEMO',venue:'Cancha de demostración',prizes:'Premios de demostración: copa para el equipo campeón y reconocimiento al jugador destacado.',registration_fee:45000,registration_open:true,payment_instructions:'Datos de demostración. No realizar transferencias.'}];
      data.championship_news=[
       {id:'qa-news-1',title:'Una nueva fecha para encontrarnos en la cancha',body:'Comunicado de demostración. Consulta los horarios actualizados del campeonato y prepara a tu equipo para la próxima jornada.',category:'reschedule',published:true,pinned:true,created_at:'2026-11-03T14:00:00Z',match_id:'m0'},
       {id:'qa-news-2',title:'El camino a la copa ya tiene protagonistas',body:'Noticia de demostración. Revisa los equipos que forman parte del cuadro y conoce a sus jugadores.',category:'general',published:true,pinned:false,created_at:'2026-11-02T14:00:00Z'},
       {id:'qa-news-3',title:'Tu equipo puede ser parte de esta historia',body:'Aviso de demostración. Revisa los requisitos de inscripción, las bases y el proceso de aprobación.',category:'registration',published:true,pinned:false,created_at:'2026-11-01T14:00:00Z'}
      ];
      const c=data.competitions.find(c=>c.format==='cup');
      c.rules='BASES DE DEMOSTRACIÓN\\n\\n01. Formato de competencia\\nFútbol 7 y eliminación directa. Cada equipo deberá presentarse en el horario informado por la organización.\\n\\n02. Planteles y alineaciones\\nLos capitanes deben registrar sus jugadores y preparar la alineación antes del comienzo del encuentro.\\n\\n03. Resultados y desempates\\nEl resultado oficial será confirmado por la organización. Los empates se resolverán mediante penales.\\n\\n04. Cambios de programación\\nConsulta las noticias y el calendario para conocer las actualizaciones.';
      data.captain_registrations=[{id:'qa-registration',user_id:'qa-user',captain_name:'Capitán de demostración',team_name:'Equipo de demostración',contact:'demo@example.test',payment_reference:'DEMO-123',amount:45000,status:'pending',created_at:'2026-11-03T14:00:00Z'}];
      render();
    };'''
    page.route('**/app.js',lambda r:r.fulfill(content_type='text/javascript',body=source))
    base='http://127.0.0.1:4186/'
    page.goto(base);page.locator('.public-hero').wait_for();page.evaluate('seedVisualAudit()')
    def check(label,width,screenshot=False):
        page.wait_for_timeout(80)
        overflow=page.evaluate('document.documentElement.scrollWidth > innerWidth+1')
        if overflow:
            details=page.evaluate("[...document.querySelectorAll('body *')].filter(e=>e.getBoundingClientRect().right>innerWidth+2 && getComputedStyle(e).position!=='fixed').slice(0,15).map(e=>[e.tagName,e.className,Math.round(e.getBoundingClientRect().right)])")
            raise AssertionError((label,width,details))
        assert page.locator('main').inner_text().strip(),label
        if screenshot:page.screenshot(path=str(shots/f'{label}-{width}.png'),full_page=True)
    for width in [1440,768,390,320]:
        page.set_viewport_size({'width':width,'height':1000 if width>700 else 844})
        for route in ['inicio','campeonato','noticias','inscripciones','partidos','copa','equipos','estadisticas','experto','reglamento','panel']:
            page.goto(base+'#'+route)
            check(route,width,width in [1440,390])
        if width<=700:
            page.goto(base+'#inicio');page.locator('#mobile-more').click()
            assert page.locator('#main-navigation a[href="#estadisticas"]').is_visible()
            page.locator('#main-navigation a[href="#estadisticas"]').click()
            assert page.locator('.stats-table').is_visible()
    page.set_viewport_size({'width':1440,'height':1000})
    page.goto(base+'#panel');page.locator('[data-demo=admin]').click()
    for width in [1440,390,320]:
        page.set_viewport_size({'width':width,'height':1000 if width>700 else 844})
        for section in ['summary','matches','roster','lineups','cups','website','news','registrations']:
            if width<=700:page.locator('#panel-more').click()
            page.locator(f'#panel-navigation [data-management="{section}"]').click()
            check('admin-'+section,width,width in [1440,390])
            assert page.locator(f'.management-section[data-section="{section}"]').is_visible()
    page.set_viewport_size({'width':1440,'height':1000})
    page.locator('#panel-navigation [data-management=matches]').click()
    page.locator('[data-pick-match="m0"]').first.click()
    for tab in page.locator('[data-editor-tab]').all():
        tab.click();check('editor-'+tab.get_attribute('data-editor-tab'),1440,True)
    page.goto(base+'#partidos');page.locator('[data-match="m0"]').click()
    for width in [1440,390,320]:
        page.set_viewport_size({'width':width,'height':1000 if width>700 else 844})
        for tab in ['timeline','lineups','votes']:
            page.locator(f'[data-match-view="{tab}"]').click()
            assert page.locator('#modal').evaluate('(e)=>e.scrollWidth<=e.clientWidth+1'),('dialog',tab,width)
            if width in [1440,390]:page.screenshot(path=str(shots/f'detail-{tab}-{width}.png'),full_page=True)
    page.locator('#modal .close').click()
    page.goto(base+'#equipos');page.locator('.team-directory-row').first.click()
    assert page.locator('#modal').is_visible()
    assert page.locator('#modal').evaluate('(e)=>e.scrollWidth<=e.clientWidth+1'),'team dialog'
    page.locator('#modal .close').click()
    assert not errors,errors
    browser.close()
    print('PASS: 11 public/auth views at 4 widths; 8 admin sections at 3 widths; match tabs, team detail and mobile navigation.')
finally:
 server.shutdown()
