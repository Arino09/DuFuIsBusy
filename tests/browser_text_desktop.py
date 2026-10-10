import functools,http.server,threading,time,json,os
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright
import tempfile
project=Path(__file__).resolve().parent.parent
root=project/'build'/'desktop-text-evidence';root.mkdir(parents=True,exist_ok=True)
serve_root=Path(tempfile.mkdtemp(prefix='dufu-preview-'))
(serve_root/'DuFuIsBusy').symlink_to(project/'build'/'web',target_is_directory=True)
handler=functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(serve_root))
server=http.server.ThreadingHTTPServer(('127.0.0.1',8765),handler)
threading.Thread(target=server.serve_forever,daemon=True).start()
logs=[];errors=[];failed=[];responses=[];blocked=[];checks=[]
try:
 with sync_playwright() as p:
  browser=p.chromium.launch(executable_path=os.environ.get('CHROMIUM_PATH','/usr/bin/chromium'),headless=True,chromium_sandbox=os.environ.get('DUFU_ALLOW_UNSANDBOXED_TEST')!='1')
  try:
   context=browser.new_context(viewport={'width':1440,'height':900},has_touch=False)
   def route(r):
    if urlparse(r.request.url).hostname=='127.0.0.1':r.continue_()
    else:blocked.append(r.request.url.split('?')[0]);r.abort()
   context.route('**/*',route)
   page=context.new_page()
   page.on('console',lambda m:logs.append({'type':m.type,'text':m.text}))
   page.on('pageerror',lambda e:errors.append(str(e)))
   page.on('requestfailed',lambda r:failed.append({'url':r.url.split('?')[0],'failure':r.failure}))
   page.on('response',lambda r:responses.append({'path':urlparse(r.url).path,'status':r.status,'type':r.headers.get('content-type')}))
   def wait_log(text,start=0):
    deadline=time.monotonic()+45
    while time.monotonic()<deadline:
     if any(text in e['text'] for e in logs[start:]):return
     page.wait_for_timeout(100)
    page.screenshot(path=str(root/'failure.png'))
    raise AssertionError('Missing console event '+text+'; logs='+repr(logs[-8:]))
   def click(x,y,event=None,count=1):
    i=len(logs);v=page.viewport_size;s=min(v['width']/1440,v['height']/900)
    page.mouse.click(x*s+(v['width']-1440*s)/2,y*s+(v['height']-900*s)/2,click_count=count,delay=35)
    if event:wait_log(event,i)
    page.wait_for_timeout(200)
   def shot(n):page.screenshot(path=str(root/(n+'.png')))
   def back():click(1290,128,'UI_PAGE:home')
   page.goto('http://127.0.0.1:8765/DuFuIsBusy/',wait_until='domcontentloaded')
   wait_log('UI_PAGE:home');shot('home')
   assert any('WebGL' in e['text'] for e in logs),logs
   checks.append('WebGL boot under /DuFuIsBusy/')
   def state():return [e['text'] for e in logs if 'DRAW_STATE:' in e['text']][-1]
   def objects():return [e['text'] for e in logs if 'OBJECT_STATE:' in e['text']][-1]
   def stroke(points):
    page.mouse.move(*points[0]);page.mouse.down()
    for pt in points[1:]:page.mouse.move(*pt,steps=10)
    page.mouse.up();page.wait_for_timeout(200)
   def fill(x,y,text):
    click(x,y);page.keyboard.press('Control+A')
    if all(ord(c)<128 for c in text):page.keyboard.type(text)
    else:
     page.wait_for_function("document.activeElement.matches('.ime, input, textarea')")
     session=context.new_cdp_session(page)
     session.send('Input.imeSetComposition',{'text':text,'selectionStart':len(text),'selectionEnd':len(text)})
     page.wait_for_timeout(120)
     session.send('Input.insertText',{'text':text})
     session.detach()
    page.wait_for_timeout(250)
   click(292,552,'UI_PAGE:canvas')
   click(130,520,'UI_DIALOG:添加文字')
   fill(640,420,'山川异域，风月同天。')
   fill(579,490,'36');fill(882,490,'156789')
   shot('desktop-ime');click(890,604,'TEXT_APPLIED:山川异域')
   click(1230,760,'SUBMIT_OK:-1:');shot('desktop-review')
   checks.append('Desktop non-touch IME composition, full Chinese font, editable size/color, text-only composition')
   assert not errors,errors
   assert not failed,failed
   assert not blocked,blocked
   assert not [r for r in responses if r['status']>=400],responses
   assert not [e for e in logs if 'SCRIPT ERROR' in e['text'] or 'Parse Error' in e['text']],logs
  finally:
   browser.close()
finally:
 server.shutdown();server.server_close()
 (serve_root/'DuFuIsBusy').unlink();serve_root.rmdir()
 (root/'results.json').write_text(json.dumps({'checks':checks,'console':logs,'page_errors':errors,'failed_requests':failed,'responses':responses,'blocked_external_requests':blocked,'browser_closed':True},ensure_ascii=False,indent=2))
print(json.dumps({'checks':checks,'console_count':len(logs),'errors':errors,'failed':failed,'screenshots':len(list(root.glob('*.png'))),'browser_closed':True},ensure_ascii=False))
