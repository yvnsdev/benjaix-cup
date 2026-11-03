"""Exercise the public website and manual registration lifecycle using demo data only."""
import functools
import sys
import threading
from pathlib import Path
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / '.qa'))
from playwright.sync_api import sync_playwright
class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, *args): pass
server = ThreadingHTTPServer(('127.0.0.1', 4184), functools.partial(Quiet, directory=str(root/'dist')))
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with sync_playwright() as p:
        browser=p.chromium.launch(channel='msedge',headless=True)
        page=browser.new_page(viewport={'width':1440,'height':1000})
        errors=[]
        page.on('pageerror',lambda e:errors.append(str(e)))
        page.on('dialog',lambda d:d.accept())
        page.route('**/config.js',lambda r:r.fulfill(content_type='text/javascript',body='window.BENJAIX_CONFIG = {};'))
        base='http://127.0.0.1:4184/'
        page.goto(base)
        page.locator('.public-hero').wait_for()
        assert page.locator('.public-hero h1').inner_text().startswith('La cancha')
        assert page.locator('#main-navigation a[href="#tabla"]').count()==0
        page.goto(base+'#panel');page.locator('[data-demo=admin]').click()
        assert not page.locator('#main-navigation').is_visible()
        assert page.locator('#panel-navigation').is_visible()
        page.locator('#panel-navigation [data-management=website]').click()
        form=page.locator('#site-settings-form')
        form.locator('[name=registration_open]').check()
        form.locator('button').click()
        assert 'Completa el monto' in page.locator('#toast').inner_text()
        form.locator('[name=registration_fee]').fill('45000')
        form.locator('[name=payment_instructions]').fill('DEMO: Banco de ejemplo. No transferir.')
        form.locator('[name=dates]').fill('Fechas de prueba')
        form.locator('[name=venue]').fill('Cancha de demostración')
        form.locator('[name=prizes]').fill('Premio de demostración')
        form.locator('button').click()
        page.locator('#panel-navigation [data-management=news]').click()
        form=page.locator('#news-form')
        form.locator('[name=title]').fill('Cambio de horario de prueba')
        form.locator('[name=body]').fill('El encuentro cambia de horario. Comunicado de demostración.')
        form.locator('[name=category]').select_option('reschedule')
        form.locator('[name=match_id]').select_option('m0')
        form.locator('[name=published]').check()
        form.locator('[name=pinned]').check()
        form.locator('button').first.click()
        page.goto(base+'#inicio')
        page.locator('.news-card').wait_for()
        assert 'Cambio de horario de prueba' in page.locator('.news-card').inner_text()
        page.screenshot(path=str(root/'.qa/portal-desktop.png'),full_page=True)
        page.locator('[data-news-open]').first.click()
        assert page.locator('.news-detail').is_visible()
        page.locator('#modal .close').click()
        page.goto(base+'#panel');page.locator('#logout').click();page.locator('[data-demo=player]').click()
        assert page.locator('#create-own-team').count()==0
        page.goto(base+'#inscripciones')
        form=page.locator('#registration-form')
        form.locator('[name=captain_name]').fill('Capitán de prueba')
        form.locator('[name=team_name]').fill('Equipo de prueba')
        form.locator('[name=contact]').fill('demo@example.test')
        form.locator('[name=payment_reference]').fill('DEMO-1234')
        form.locator('[name=accept_rules]').check();form.locator('button').click()
        assert page.locator('.status-pending').is_visible()
        assert page.locator('#registration-form').count()==0
        page.goto(base+'#panel');page.locator('#logout').click();page.locator('[data-demo=admin]').click()
        page.locator('#panel-navigation [data-management=registrations]').click()
        form=page.locator('[data-registration-review]')
        form.locator('[name=decision]').select_option('approved')
        form.locator('[name=note]').fill('Pago de prueba confirmado')
        form.locator('[name=confirmed]').check();form.locator('button').click()
        assert page.locator('[data-registration-review]').count()==0
        page.locator('#logout').click();page.locator('[data-demo=player]').click()
        page.locator('#panel-navigation [data-management=roster]').click()
        assert page.locator('#create-own-team').is_visible()
        page.set_viewport_size({'width':390,'height':844})
        assert not page.locator('.mobile-nav').is_visible()
        page.locator('#panel-more').click()
        page.locator('#panel-navigation [data-management=lineups]').click()
        assert page.locator('.management-section[data-section=lineups]').is_visible()
        assert page.locator('#panel-more').get_attribute('aria-expanded')=='false'
        page.screenshot(path=str(root/'.qa/panel-menu-mobile.png'),full_page=True)
        page.set_viewport_size({'width':1440,'height':1000})
        page.goto(base+'#inicio');page.reload()
        assert page.locator('.news-card').count()==1
        for width in [390,320]:
            page.set_viewport_size({'width':width,'height':844})
            for route in ['inicio','campeonato','noticias','inscripciones','partidos','copa']:
                page.goto(base+'#'+route)
                page.wait_for_timeout(100)
                assert page.evaluate('document.documentElement.scrollWidth <= innerWidth+1'),(route,width)
            page.goto(base+'#inicio')
            page.locator('#mobile-more').click()
            assert page.locator('#main-navigation a[href="#inscripciones"]').is_visible()
            page.locator('#main-navigation a[href="#inscripciones"]').click()
            assert page.locator('.registration-layout').is_visible()
        page.goto(base+'#inicio');page.set_viewport_size({'width':390,'height':844})
        page.screenshot(path=str(root/'.qa/portal-mobile.png'),full_page=True)
        assert not errors,errors
        browser.close()
        print('PASS: landing, settings, validation, publishing news, transfer review, captain gating, persistence and mobile layouts.')
finally:
    server.shutdown()
