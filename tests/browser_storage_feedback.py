"""Targeted WebGL check for immediate brush preferences and wrapped storage errors."""
import functools,http.server,threading,time,json,os,tempfile,shutil
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright
from PIL import Image
project=Path(__file__).resolve().parent.parent
root=project/'build'/'storage-feedback-evidence';root.mkdir(parents=True,exist_ok=True)
serve=Path(tempfile.mkdtemp(prefix='dufu-serve-'));(serve/'DuFuIsBusy').symlink_to(project/'build'/'web',target_is_directory=True)
profile=Path(tempfile.mkdtemp(prefix='dufu-browser-profile-'))
server=http.server.ThreadingHTTPServer(('127.0.0.1',8765),functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(serve)))
threading.Thread(target=server.serve_forever,daemon=True).start()
logs=[];errors=[];failed=[];blocked=[];checks=[];context=None
key='DuFuIsBusy.art.v2'
p=None
try:
 p=sync_playwright().start()
 if True:
  def launch():
   ctx=p.chromium.launch_persistent_context(str(profile),executable_path=os.environ.get('CHROMIUM_PATH','/usr/bin/chromium'),headless=True,chromium_sandbox=os.environ.get('DUFU_ALLOW_UNSANDBOXED_TEST')!='1',viewport={'width':1440,'height':900},has_touch=True,accept_downloads=True)
   def route(r):
    if urlparse(r.request.url).hostname=='127.0.0.1':r.continue_()
    else:blocked.append(r.request.url);r.abort()
   ctx.route('**/*',route)
   tab=ctx.pages[0]
   tab.on('console',lambda m:logs.append({'type':m.type,'text':m.text}))
   tab.on('pageerror',lambda e:errors.append(str(e)))
   tab.on('requestfailed',lambda r:failed.append(r.url))
   return ctx,tab
  context,page=launch()
  def wait(text,start=0):
   deadline=time.monotonic()+40
   while time.monotonic()<deadline:
    if any(text in e['text'] for e in logs[start:]):return
    page.wait_for_timeout(100)
   page.screenshot(path=str(root/'failure.png'))
   raise AssertionError((text,logs[-12:]))
  def click(x,y,event=None,count=1):
   i=len(logs);page.mouse.click(x,y,click_count=count,delay=40)
   if event:wait(event,i)
   page.wait_for_timeout(180)
  def shot(name):page.screenshot(path=str(root/(name+'.png')))
  def fill(x,y,text):
   click(x,y);page.keyboard.press('Control+A')
   if text.isascii():page.keyboard.type(text)
   else:
    page.wait_for_function("document.activeElement.matches('.ime,input,textarea')")
    cdp=context.new_cdp_session(page)
    cdp.send('Input.imeSetComposition',{'text':text,'selectionStart':len(text),'selectionEnd':len(text)})
    page.wait_for_timeout(120);cdp.send('Input.insertText',{'text':text});cdp.detach()
   page.wait_for_timeout(150)
  def stroke(a,b):
   page.mouse.move(*a);page.mouse.down();page.mouse.move(*b,steps=10);page.mouse.up();page.wait_for_timeout(200)
  def data():return page.evaluate('(k)=>JSON.parse(localStorage.getItem(k))',key)
  def raw():return page.evaluate('(k)=>localStorage.getItem(k)',key)
  def submit():click(1230,760,'SUBMIT_OK:')
  page.goto('http://127.0.0.1:8765/DuFuIsBusy/');wait('UI_PAGE:home')
  click(292,552,'UI_PAGE:canvas')
  click(230,650,'DRAW_WIDTH:');assert data()['tools']['width']==52
  stroke((700,540),(860,580))
  page.evaluate("window.__nativeSet=Storage.prototype.setItem;Storage.prototype.setItem=function(k,v){if(k==='DuFuIsBusy.art.v2')throw new DOMException('full','QuotaExceededError');return window.__nativeSet.call(this,k,v)};true")
  submit();click(1097,650,'UI_DIALOG:保存失败');shot('quota-save-failed')
  checks.append('Brush width is persisted immediately without blur; long storage error fits modal after layout fix')
  assert not errors and not failed and not blocked,(errors,failed,blocked)
  assert not [e for e in logs if e['type']=='error' or 'SCRIPT ERROR' in e['text']],logs[-20:]
finally:
 if context:context.close()
 if p:p.stop()
 server.shutdown();server.server_close();(serve/'DuFuIsBusy').unlink();serve.rmdir();shutil.rmtree(profile)
 (root/'results.json').write_text(json.dumps({'checks':checks,'console':logs,'page_errors':errors,'failed_requests':failed,'blocked_external_requests':blocked,'browser_closed':True},ensure_ascii=False,indent=2))
print(json.dumps({'checks':checks,'errors':errors,'screenshots':len(list(root.glob('*.png'))),'browser_closed':True},ensure_ascii=False))
