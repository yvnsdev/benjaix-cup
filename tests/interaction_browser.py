"""Exercise discovery, admin editing and mobile navigation with local demo data."""
import functools
import json
import sys
import threading
from pathlib import Path
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / '.qa'))
from playwright.sync_api import sync_playwright

class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 4182), functools.partial(Quiet, directory=str(root / 'dist')))
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    with sync_playwright() as p:
        browser = p.chromium.launch(channel='msedge', headless=True)
        context = browser.new_context(viewport={'width': 1440, 'height': 1000})
        page = context.new_page()
        errors = []
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.route('**/config.js', lambda route: route.fulfill(content_type='text/javascript', body='window.BENJAIX_CONFIG = {};'))
        page.goto('http://127.0.0.1:4182/#partidos')
        page.wait_for_selector('.match-card')
        assert page.locator('.match-card').first.get_attribute('data-match') == 'm0'
        page.locator('[data-discovery-status=scheduled]').click()
        assert page.locator('[data-discovery-status=scheduled]').get_attribute('aria-pressed') == 'true'
        dates = page.locator('.match-date-group h2').all_text_contents()
        assert dates and all('Próximos' in text for text in dates)
        page.locator('#search').fill('condores')
        assert 'Cóndores' in page.locator('#match-list').inner_text()
        page.locator('#search').fill('no-existe-equipo')
        assert page.locator('#match-list .empty').is_visible()
        page.locator('#match-list [data-reset-matches]').click()
        assert page.locator('#search').input_value() == ''
        page.locator('#discovery-competition').select_option('cup-demo')
        assert 'Copa Benjaix' in page.locator('.match-card').first.inner_text()
        page.locator('#discovery-day').fill('2020-01-01')
        assert page.locator('#match-list .empty').is_visible()
        page.locator('#match-list [data-reset-matches]').click()
        page.locator('[data-discovery-page="1"]').click()
        assert 'Página 2' in page.locator('.match-list-pagination').inner_text()
        page.locator('[data-discovery-page="-1"]').click()
        page.locator('.match-card').first.focus()
        page.keyboard.press('Space')
        assert page.locator('#modal').is_visible()
        page.locator('[data-match-view=lineups]').click()
        assert page.locator('.lineup-switch').is_visible()
        page.keyboard.press('Escape')
        assert not page.locator('#modal').is_visible()
        assert page.locator('.match-card').first.evaluate('(el)=>el===document.activeElement')
        page.locator('.header-right a[href="#panel"]').click()
        page.locator('[data-demo=admin]').click()
        assert not page.locator('.admin-team-control').is_visible()
        page.locator('.management-nav [data-management=matches]').click()
        page.locator('[data-picker=manage-match][data-pick-match=m0]').click()
        assert page.locator('[data-editor-pane=match]').is_visible()
        assert not page.locator('#event-form').is_visible()
        page.locator('[data-editor-view=events]').click()
        page.locator('[data-event-type=injury]').click()
        assert page.locator('#event-form [name=type]').input_value() == 'injury'
        page.locator('#event-form [name=player_id]').select_option('p0-1')
        page.locator('#event-form [name=minute]').fill('72')
        page.locator('#event-form button').click()
        assert page.locator('[data-editor-pane=events]').is_visible()
        assert 'Lesión' in page.locator('#score-editor .match-timeline').inner_text()
        page.locator('[data-editor-view=substitutions]').click()
        assert page.locator('.substitution-editor').is_visible()
        page.locator('[data-editor-view=votes]').click()
        assert page.locator('.expert-admin').is_visible()
        page.locator('.admin-editor-heading [data-open-match]').click()
        page.locator('[data-manage-encounter]').click()
        assert not page.locator('#modal').is_visible()
        page.locator('.management-nav [data-management=schedule]').click()
        page.locator('#match-form [name=home_id]').select_option('t1')
        assert page.locator('#match-form [name=away_id]').input_value() != 't1'
        page.locator('.management-nav [data-management=roster]').click()
        assert page.locator('.admin-team-control').is_visible()
        page.locator('.management-nav [data-management=lineups]').click()
        assert page.locator('.admin-team-control').is_visible()

        for width in (390, 320):
            page.set_viewport_size({'width': width, 'height': 844})
            page.locator('.mobile-nav [data-nav=partidos]').click()
            assert page.locator('.mobile-nav').is_visible()
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), f'Overflow at {width}'
            page.locator('#mobile-more').click()
            assert page.locator('.sidebar nav').is_visible()
            page.locator('.sidebar [data-nav=tabla]').click()
            assert not page.locator('.sidebar nav').is_visible()
            assert 'Tabla de posiciones' in page.title()
            page.locator('.mobile-nav [data-nav=partidos]').click()
            page.locator('.match-card').first.click()
            assert page.locator('#modal').is_visible()
            assert page.locator('#modal').evaluate('(el)=>el.scrollWidth<=el.clientWidth'), f'Dialog overflow at {width}'
            page.locator('[data-dialog-back]').click()
            assert not page.locator('#modal').is_visible()
        page.set_viewport_size({'width': 390, 'height': 844})
        assert page.locator('.skip-link').evaluate('(el)=>getComputedStyle(el).clipPath') != 'none'
        page.screenshot(path=str(root / '.qa/interaction-mobile.png'), full_page=True)
        page.locator('.mobile-nav [data-nav=panel]').click()
        page.locator('.management-nav [data-management=matches]').click()
        page.locator('[data-change-encounter]').click()
        page.locator('[data-picker=manage-match][data-pick-match=m0]').click()
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'), 'Admin mobile overflow'
        page.screenshot(path=str(root / '.qa/interaction-admin-mobile.png'), full_page=True)
        assert not errors, errors
        print(json.dumps({'result': 'PASS', 'browser_errors': errors, 'checks': 'discovery, filters, pagination, keyboard, dialog return, event save, admin tasks, 320/390px navigation'}, ensure_ascii=False))
        browser.close()
finally:
    server.shutdown()
