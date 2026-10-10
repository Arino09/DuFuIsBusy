"""Real WebGL, persistent browser restart, downloads and injected storage failures."""
import functools,http.server,threading,time,json,os,tempfile,shutil
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright
from PIL import Image
project=Path(__file__).resolve().parent.parent
root=project/'build'/'storage-evidence';root.mkdir(parents=True,exist_ok=True)
serve=Path(tempfile.mkdtemp(prefix='dufu-serve-'));(serve/'DuFuIsBusy').symlink_to(project/'build'/'web',target_is_directory=True)
profile=Path(tempfile.mkdtemp(prefix='dufu-browser-profile-'))
server=http.server.ThreadingHTTPServer(('127.0.0.1',8765),functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(serve)))
threading.Thread(target=server.serve_forever,daemon=True).start()
logs=[];errors=[];failed=[];blocked=[];checks=[];context=None
key='DuFuIsBusy.art.v1'
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
  click(260,530,'UI_PAGE:canvas')
  click(130,520,'UI_DIALOG:添加文字');fill(620,420,'麒麟献瑞，诗圣摸鱼。');fill(580,490,'40');fill(875,490,'663399');click(890,604,'TEXT_APPLIED:')
  click(215,520,'UI_DIALOG:原创贴纸');click(698,563,'UI_PAGE:canvas');stroke((891,562),(700,480));click(788,359)
  stroke((460,555),(1150,620))
  click(130,412,'UI_PAGE:canvas');stroke((600,670),(850,660))
  expected=data()['drafts']['-1'];assert len(expected['objects'])==3
  assert expected['objects'][1]['text']=='麒麟献瑞，诗圣摸鱼。'
  shot('autosaved-canvas')
  i=len(logs);page.reload();wait('UI_PAGE:canvas',i);assert data()['drafts']['-1']==expected
  shot('after-refresh');checks.append('Immediate refresh restores raster pixels, Chinese text, sticker rotation, Dufu position and prompt')
  context.close();context,page=launch();i=len(logs)
  page.goto('http://127.0.0.1:8765/DuFuIsBusy/');wait('UI_PAGE:canvas',i)
  assert data()['drafts']['-1']==expected;shot('after-browser-reopen')
  checks.append('Entire Chromium process closed and reopened with same persistent profile; full editable draft restored')
  submit();shot('review');click(325,669,'WORK_SAVED:work-1:1',count=4)
  assert len(data()['works'])==1;first=data()['works'][0];shot('saved-confirmation')
  click(650,603);submit();click(325,669,'WORK_SAVED:work-1:1')
  assert len(data()['works'])==1 and data()['works'][0]==first
  click(890,603,'UI_PAGE:gallery');shot('my-gallery')
  click(530,465,'WORK_VIEW:work-1');shot('saved-work')
  with page.expect_download() as download_info:click(1090,678,'PNG_DOWNLOAD_REQUESTED')
  download=download_info.value;assert download.suggested_filename=='dufu-artwork.png'
  download.save_as(root/'dufu-artwork.png');im=Image.open(root/'dufu-artwork.png');assert im.size==(1040,330)
  # PNG bytes are the exact stored complete preview, not a page screenshot.
  import base64
  assert (root/'dufu-artwork.png').read_bytes()==base64.b64decode(first['preview'])
  checks.append('Explicit gallery save, rapid repeat clicks create one entry; real PNG download matches complete stored artwork bytes')
  click(840,678,'UI_DIALOG:打开已存画作');click(890,603,'WORK_OPEN:work-1')
  click(891,562);click(360,359,'UI_DIALOG:编辑文字');fill(620,420,'保存后继续编辑');click(890,604,'TEXT_APPLIED:保存后')
  assert data()['works'][0]==first
  assert data()['drafts']['-1']['objects'][1]['text']=='保存后继续编辑'
  submit();click(325,669,'WORK_SAVED:work-2:2');updated=data()['works'][1];assert updated!=first and data()['works'][0]==first
  click(650,603);submit();click(850,740,'WORK_SAVED:work-3:3')
  assert data()['works'][0]==first and data()['works'][1]==updated and len(data()['works'])==3
  shot('saved-second-work');checks.append('Opening gallery loads editable layers; editing changes draft only; saving an edited draft creates a new version; original and other entries remain unchanged')
  click(650,603);click(1270,270,'UI_PAGE:levels');click(220,650,'UI_PAGE:canvas')
  click(215,520,'UI_DIALOG:原创贴纸');click(375,563,'UI_PAGE:canvas')
  before=data();assert '0' in before['drafts'] and '-1' in before['drafts']
  i=len(logs);page.reload();wait('UI_PAGE:canvas',i);assert data()['topic']==0 and data()['drafts']['0']==before['drafts']['0']
  checks.append('Multiple prompt drafts and multiple saved works coexist')
  # Fault injection affects only this temporary browser, never host security settings.
  click(130,412,'UI_PAGE:canvas')
  old_raw=raw()
  filled=page.evaluate("""(()=>{let lo=0,hi=8*1024*1024;while(hi-lo>1){let mid=Math.floor((lo+hi)/2);try{localStorage.setItem('dufu-test-fill','x'.repeat(mid));lo=mid;}catch(e){if(e.name!=='QuotaExceededError')throw e;hi=mid;}}return lo;})()""")
  assert filled>1000000

  click(130,412,'UI_PAGE:canvas');stroke((900,640),(1030,650));wait('STORAGE_ERROR:');assert raw()==old_raw
  shot('quota-warning');submit();start=len(logs);click(325,669,'UI_DIALOG:作品尚未保存')
  assert not any('WORK_SAVED:' in e['text'] for e in logs[start:]);assert raw()==old_raw;shot('quota-save-failed')
  page.keyboard.press('Escape');page.evaluate("localStorage.removeItem('dufu-test-fill');true")
  click(1270,825,'STORAGE_OK');assert raw()!=old_raw and len(data()['works'])==3
  checks.append('Actual Chromium quota exhaustion preserves original storage, never reports success; explicit retry writes pending draft')
  # An unavailable read must not cause old works to be overwritten by an empty DB.
  page.add_init_script("""window.__dufuGet=Storage.prototype.getItem;window.__denyRead=sessionStorage.getItem('dufu-test-allowRead')!=='yes';Storage.prototype.getItem=function(k){if(k==='DuFuIsBusy.art.v1'&&window.__denyRead)throw new DOMException('denied','SecurityError');return window.__dufuGet.call(this,k)}""")
  preserved=raw();i=len(logs);page.reload();wait('STORAGE_ERROR:',i);shot('storage-unavailable')
  assert page.evaluate('(k)=>window.__dufuGet.call(localStorage,k)',key)==preserved
  page.evaluate("window.__denyRead=false;sessionStorage.setItem('dufu-test-allowRead','yes');true");click(1270,825,'STORAGE_OK');assert len(data()['works'])==3
  assert data()['drafts']==json.loads(preserved)['drafts']
  click(260,530,'UI_PAGE:canvas')
  assert data()['drafts']['-1']==json.loads(preserved)['drafts']['-1']
  click(1290,128,'UI_PAGE:home')
  checks.append('Unavailable storage read is explicit and does not overwrite existing works; retry preserves gallery')
  # Existing example gallery remains independent.
  click(175,608,'UI_PAGE:gallery');wait('UI_FILTER:全部:4');shot('example-gallery')
  click(170,266,'UI_PAGE:gallery');shot('my-gallery-multiple')
  assert len(data()['works'])==3
  # An externally changed record is never silently overwritten by this tab.
  changed=data();changed['external_test_marker']='other-tab'
  page.evaluate('([k,d])=>localStorage.setItem(k,JSON.stringify(d))',[key,changed])
  other_raw=raw();click(1290,128,'UI_PAGE:home');wait('STORAGE_ERROR:其他标签页')
  assert raw()==other_raw;shot('conflict-warning')
  # Malformed data remains byte-for-byte intact, with writes disabled.
  page.evaluate('(k)=>localStorage.setItem(k,"broken-storage-test")',key)
  i=len(logs);page.reload();wait('STORAGE_ERROR:本地存档格式异常',i)
  assert raw()=='broken-storage-test';shot('corrupt-storage-protected')
  checks.append('Detected other-tab updates and malformed storage are protected from automatic overwrite')
  assert not errors and not failed and not blocked,(errors,failed,blocked)
  assert not [e for e in logs if e['type']=='error' or 'SCRIPT ERROR' in e['text']],logs[-20:]
finally:
 if context:context.close()
 if p:p.stop()
 server.shutdown();server.server_close();(serve/'DuFuIsBusy').unlink();serve.rmdir();shutil.rmtree(profile)
 (root/'results.json').write_text(json.dumps({'checks':checks,'console':logs,'page_errors':errors,'failed_requests':failed,'blocked_external_requests':blocked,'browser_closed':True},ensure_ascii=False,indent=2))
print(json.dumps({'checks':checks,'errors':errors,'screenshots':len(list(root.glob('*.png'))),'browser_closed':True},ensure_ascii=False))
