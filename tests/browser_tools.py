import functools,http.server,threading,time,json,os
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright
import tempfile
project=Path(__file__).resolve().parent.parent
root=project/'build'/'tools-evidence';root.mkdir(parents=True,exist_ok=True)
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
   click(292,552,'UI_PAGE:canvas');shot('canvas-empty')
   click(1230,760,'SUBMIT_EMPTY');page.keyboard.press('Escape')
   click(130,520,'UI_DIALOG:添加文字');shot('text-editor')
   click(890,604);assert 'TEXT_APPLIED' not in str(logs)
   fill(640,420,'龘麒麟逍遥游');fill(579,490,'44');fill(882,490,'663399')
   shot('text-filled');click(890,604,'TEXT_APPLIED:龘麒麟逍遥游');assert 'OBJECT_STATE:2:' in objects()
   shot('text-added')
   stroke([(891,562),(1000,610)])
   click(360,359,'UI_DIALOG:编辑文字');fill(640,420,'临江仙，风起！');click(890,604,'TEXT_APPLIED:临江仙')
   click(788,359);click(574,359);shot('text-transformed')
   click(895,359);assert ':false:' in state(),state()
   click(1140,359);assert ':true:' in state()
   click(1280,359);assert ':false:' in state()
   click(1140,359)
   checks.append('Chinese input/edit, font size and color, text move/scale/rotate/delete, undo/redo; text-only creation')
   # Text alone qualifies and the preview must actually render it.
   click(1230,760,'SUBMIT_OK:-1:');shot('text-review');click(328,650)
   click(215,520,'UI_DIALOG:选择贴纸');click(506,242);shot('sticker-picker');click(316,503,'UI_PAGE:canvas')
   stroke([(891,562),(700,480)])
   click(788,359);click(574,359);shot('weapon-transformed')
   cdp=context.new_cdp_session(page)
   before=state()
   cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':700,'y':480}]})
   cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':780,'y':510}]})
   cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
   page.wait_for_timeout(350);assert state()!=before
   # Touch activates ordinary controls too; selecting mode prevents painting.
   before=state()
   cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':788,'y':359}]})
   cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
   page.wait_for_timeout(350);assert state()!=before,('touch button failed',state())
   for picker_x,destination in [(518,(900,455)),(720,(1060,485)),(922,(600,595)),(1124,(1210,565))]:
    click(215,520,'UI_DIALOG:选择贴纸');click(506,242);click(picker_x,503,'UI_PAGE:canvas');stroke([(891,562),destination])
   saved_objects=page.evaluate("JSON.parse(localStorage.getItem('DuFuIsBusy.art.v2')).drafts['-1'].objects")
   assert {o['kind'] for o in saved_objects}=={'avatar','text','dufu_greatsword','dufu_lightsaber','dufu_sniper_rifle','dufu_boxing_glove','dufu_ninja_mask'}
   # Move Dufu far to the right, retaining all other elements.
   stroke([(460,555),(1150,635)]);shot('objects-composed')
   checks.append('Five Dufu stickers, object selection/drag/transforms; touch drag and touch toolbar; Dufu free placement')
   click(170,577,'UI_DIALOG:颜色');shot('palette')
   fill(600,525,'ZZZZZZ');click(900,525);assert not any('COLOR_CHANGED:' in e['text'] for e in logs)
   fill(600,525,'00AABB');click(900,525,'COLOR_CHANGED:00aabb')
   click(200,650,'DRAW_WIDTH:');stroke([(610,650),(750,670),(850,630)])
   shot('canvas');click(1230,760,'SUBMIT_OK:-1:');shot('review')
   submitted=[e['text'] for e in logs if 'SUBMIT_OK:' in e['text']][-1]
   click(328,650);click(1230,760,'SUBMIT_OK:-1:');assert [e['text'] for e in logs if 'SUBMIT_OK:' in e['text']][-1]==submitted
   click(328,650);before=state();back();click(292,552,'UI_PAGE:canvas');assert before==state()
   checks.append('custom RGB color validation; pen input remains independent; actual full composition; repeat submit and navigation persistence')
   click(170,466,'UI_PAGE:canvas');click(1290,705);assert objects().endswith(':-1')
   click(360,359);assert 'UI_DIALOG:编辑文字' not in str(logs[-2:])
   # Move with a held pointer, then blur: further movement must not continue.
   page.mouse.move(900,455);page.mouse.down();page.mouse.move(930,470,steps=3);before=state()
   page.evaluate("window.dispatchEvent(new Event('blur'))");page.wait_for_timeout(250)
   assert before!=state();finished=state();page.mouse.move(990,480);page.mouse.up();assert finished==state()
   page.set_viewport_size({'width':1024,'height':768});page.wait_for_timeout(350);shot('canvas-1024x768')
   click(1230,760,'SUBMIT_OK:-1:');shot('review-1024x768');click(328,650)
   page.set_viewport_size({'width':844,'height':390});page.wait_for_timeout(350);shot('canvas-844x390')
   page.set_viewport_size({'width':390,'height':844});page.wait_for_timeout(350);shot('canvas-390x844')
   page.set_viewport_size({'width':1440,'height':900});page.wait_for_timeout(350)
   click(175,758,'UI_DIALOG:清空草稿');click(650,603);assert ':true:' in state()
   click(175,758,'UI_DIALOG:清空草稿');click(870,603,'UI_PAGE:canvas');assert ':false:0:0' in state();assert objects()=='OBJECT_STATE:1:-1'
   click(1230,760,'SUBMIT_EMPTY');page.keyboard.press('Escape')
   checks.append('cancel selection, disabled object actions, blur, responsive layout and submit, restart cancel/confirm reset all layers')
   # Only relocating Dufu is valid creative work, including touch placement.
   click(170,466,'UI_PAGE:canvas')
   cdp.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':460,'y':555}]})
   cdp.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':900,'y':560}]})
   cdp.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
   page.wait_for_timeout(300);assert ':true:1:0' in state(),state()
   click(1230,760,'SUBMIT_OK:-1:');shot('dufu-only-review');click(328,650)
   click(1140,359);assert ':false:0:1' in state(),state()
   checks.append('touch Dufu-only creation passes; undo to original is empty again')
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
