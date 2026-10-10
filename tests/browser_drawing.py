import functools,http.server,threading,time,json,os
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright
import tempfile
project=Path(__file__).resolve().parent.parent
root=project/'build'/'browser-evidence';root.mkdir(parents=True,exist_ok=True)
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
   context=browser.new_context(viewport={'width':1440,'height':900},has_touch=True)
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
   def stroke(points):
    page.mouse.move(*points[0]);page.mouse.down()
    for pt in points[1:]:page.mouse.move(*pt,steps=8)
    page.mouse.up();page.wait_for_timeout(200)
   def state():
    return [e['text'] for e in logs if 'DRAW_STATE:' in e['text']][-1]
   click(265,450,'UI_PAGE:levels');shot('levels')
   click(220,650,'UI_PAGE:canvas');shot('canvas-empty')
   click(1230,760,'SUBMIT_EMPTY');shot('empty-rejected');page.keyboard.press('Escape')
   stroke([(700,540),(850,540)])
   assert ':true:1:0' in state(),state()
   shot('canvas-stroke')
   click(215,412,'UI_PAGE:canvas')
   # Same 12-pixel eraser traverses exactly the same raster pixels.
   stroke([(700,540),(850,540)])
   assert ':false:2:0' in state(),state()
   click(1230,760,'SUBMIT_EMPTY');shot('erased-rejected');page.keyboard.press('Escape')
   click(1140,359);assert ':true:1:1' in state(),state()
   shot('undo-restored')
   click(1280,359);assert ':false:2:0' in state(),state()
   click(1140,359);click(130,412,'UI_PAGE:canvas')
   click(170,577,'UI_DIALOG:调色盘');click(474,295,'COLOR_CHANGED:aa4937')
   # Adjust pen width through the real slider.
   click(230,650,'DRAW_WIDTH:');assert [e['text'] for e in logs if 'DRAW_WIDTH:' in e['text']][-1]!='DRAW_WIDTH:12'
   stroke([(680,600),(760,650),(870,580),(980,650)])
   shot('canvas')
   click(1230,760,'SUBMIT_OK:0:');shot('review')
   submit=[e['text'] for e in logs if 'SUBMIT_OK' in e['text']][-1]
   click(830,670);click(1230,760,'SUBMIT_OK:0:')
   assert [e['text'] for e in logs if 'SUBMIT_OK' in e['text']][-1]==submit
   click(830,670)
   before=state();back();click(265,450,'UI_PAGE:levels');click(220,650,'UI_PAGE:canvas')
   assert state()==before,(before,state())
   click(1270,270,'UI_PAGE:levels');click(547,650,'UI_PAGE:canvas')
   assert ':false:0:0' in state(),state()
   click(1270,270,'UI_PAGE:levels');click(220,650,'UI_PAGE:canvas')
   assert state()==before
   checks.append('blank and erased rejection; raster undo/redo; color/width; actual artwork review; repeat submission; per-topic navigation persistence')
   # Boundary exits terminate the stroke, returning while held does not bridge.
   stroke([(1290,690),(1400,740),(1000,500)])
   assert ':true:' in state()
   shot('boundary')
   page.mouse.move(900,510);page.mouse.down();page.mouse.move(930,510)
   before_blur=state()
   page.evaluate("window.dispatchEvent(new Event('blur'))")
   page.wait_for_timeout(250)
   after_blur=state()
   assert after_blur!=before_blur,('blur must finish',before_blur,after_blur)
   page.mouse.move(1000,520);page.mouse.up();page.wait_for_timeout(200)
   assert state()==after_blur,('blur must not bridge',state(),after_blur)
   checks.append('pointer exit/re-entry and window blur exercised')
   # Native browser touch events via CDP, not synthesized mouse drawing.
   before_touch=state()
   cdp=context.new_cdp_session(page)
   cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':950,'y':450}]})
   cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':1100,'y':480}]})
   cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
   page.wait_for_timeout(300);assert state()!=before_touch;shot('touch')
   checks.append('CDP touchscreen stroke')
   page.mouse.move(780,460);page.mouse.down();page.mouse.move(810,460);before_resize=state()
   page.set_viewport_size({'width':1024,'height':768});page.wait_for_timeout(500);shot('canvas-1024x768')
   assert state()!=before_resize
   after_resize=state();page.mouse.up();assert state()==after_resize
   # resized viewport maps original canvas coordinates via uniform letterboxing
   v=page.viewport_size;s=min(v['width']/1440,v['height']/900)
   def mapped(x,y):return (x*s+(v['width']-1440*s)/2,y*s+(v['height']-900*s)/2)
   stroke([mapped(700,450),mapped(800,480)])
   click(1230,760,'SUBMIT_OK:0:');shot('review-1024x768');page.keyboard.press('Escape')
   page.set_viewport_size({'width':844,'height':390});page.wait_for_timeout(400);shot('canvas-844x390')
   page.set_viewport_size({'width':390,'height':844});page.wait_for_timeout(400);shot('canvas-390x844')
   page.set_viewport_size({'width':1440,'height':900});page.wait_for_timeout(400)
   click(175,758,'UI_DIALOG:重新创作');click(650,603);assert ':true:' in state()
   click(175,758,'UI_DIALOG:重新创作');click(870,603,'UI_PAGE:canvas');assert ':false:0:0' in state()
   checks.append('scaled drawing/submission at 1024; landscape/portrait; restart cancel/confirm')
   back();click(175,608,'UI_PAGE:gallery');shot('gallery');back()
   click(365,606,'UI_PAGE:settings');shot('settings');back();shot('home')
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
