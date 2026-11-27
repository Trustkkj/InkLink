#!/usr/bin/env bash
set -euo pipefail
ROOT="$HOME/.local/share/inklink"
echo "InkLink v0.3.1"
if [[ $EUID == 0 ]]; then echo "Execute como usuário normal, não root."; exit 1; fi
PIN=12a2bac0389c0b69287c949abb6ca8e89133ba0a
mkdir -p "$ROOT"
for c in adb git python3 node npm; do
 if ! command -v "$c" >/dev/null; then
  sudo apt-get update
  sudo apt-get install -y adb git python3 nodejs npm
  break
 fi
done
if ! node -e 'process.exit(Number(process.versions.node.split(".")[0])>=22?0:1)'; then
 echo 'Instale Node.js 22 ou superior antes de continuar.'; exit 1
fi
ADB=(adb)
if ! adb start-server || ! adb devices | awk '$2=="device"{ok=1} END{exit !ok}'; then
 ADB=(sudo adb)
 sudo adb start-server
fi
"${ADB[@]}" devices
SERIAL=$("${ADB[@]}" devices | awk '$2=="device"{print $1}')
if [[ $(printf '%s\n' "$SERIAL" | grep -c . || true) != 1 ]]; then echo 'Conecte apenas um Android, compartilhe USB com Linux e autorize a depuração USB.'; exit 1; fi
if [[ ! -d "$ROOT/wosu/.git" ]]; then
 git clone --no-checkout https://github.com/Mostlime12195/wosu.git "$ROOT/wosu"
 git -C "$ROOT/wosu" checkout --detach "$PIN"
fi
cd "$ROOT/wosu"
if [[ $(git rev-parse HEAD) != "$PIN" ]]; then
 echo 'Versão do wosu! diferente da testada. Nenhum arquivo será sobrescrito.'; exit 1
fi
python3 - <<'PY'
from pathlib import Path
p=Path('src/gameplay/input/GameplayInput.ts'); s=p.read_text()
if 'inkLinkEvents' not in s:
 def patch(a,b):
  global s
  if s.count(a)!=1: raise SystemExit('Versão do wosu incompatível: '+a)
  s=s.replace(a,b,1)
 patch('    private readonly touches','    private inkLinkEvents: EventSource | null = null;\n    private inkLinkActive = false;\n    private readonly touches')
 patch('        this.y = start.y;', '''        this.y = start.y;
        this.inkLinkEvents = new EventSource('http://' + window.location.hostname + ':8765/events');
        this.inkLinkEvents.onmessage = event => {
            const d = JSON.parse(event.data);
            this.inkLinkActive = d.active === true;
            if (!this.inkLinkActive || !document.hasFocus()) return;
            const p = this.app.toLogical(d.x * window.innerWidth, d.y * window.innerHeight);
            this.x = p.x; this.y = p.y;
        };
        this.inkLinkEvents.onerror = () => { this.inkLinkActive = false; };''')
 patch('    private track(e: PointerEvent): boolean {','    private track(e: PointerEvent): boolean {\n        if (this.inkLinkActive) return false;')
 patch('    private onDown(e: PointerEvent): void {','    private onDown(e: PointerEvent): void {\n        if (this.inkLinkActive) return;')
 patch('    dispose(): void {','    dispose(): void {\n        this.inkLinkEvents?.close();')
 p.with_suffix('.ts.inklink-backup').write_text(p.read_text()); p.write_text(s)
else:
 s=s.replace("new EventSource('http://localhost:8765/events')", "new EventSource('http://' + window.location.hostname + ':8765/events')")
 p.write_text(s)
# Harden both existing and fresh integrations.
s=p.read_text()
old="            const d = JSON.parse(event.data);\n            this.inkLinkActive = d.active === true;"
new="            let d;\n            try { d = JSON.parse(event.data); } catch { this.inkLinkActive = false; return; }\n            this.inkLinkActive = d?.active === true && Number.isFinite(d.x) && Number.isFinite(d.y) && d.x >= 0 && d.x <= 1 && d.y >= 0 && d.y <= 1;"
if old in s: p.write_text(s.replace(old,new,1))
PY
python3 - <<'PY2'
from pathlib import Path
p=Path('index.html'); s=p.read_text()
if 'inklink-canonical' not in s:
 s=s.replace('<head>', '<head>\n<script id="inklink-canonical">if(location.hostname === "127.0.0.1" && location.port === "5173") location.replace("http://localhost:5173" + location.pathname + location.search + location.hash);</script>',1)
 p.write_text(s)
PY2
if [[ ! -d node_modules || ! -f "$ROOT/npm-lock.sha" ]] || ! sha256sum -c "$ROOT/npm-lock.sha" >/dev/null 2>&1; then
 npm ci
 sha256sum package-lock.json > "$ROOT/npm-lock.sha"
fi
if [[ -f "$ROOT/bridge.py" && ! -f "$ROOT/bridge.pre-v0.3.py" ]]; then cp "$ROOT/bridge.py" "$ROOT/bridge.pre-v0.3.py"; fi
cat > "$ROOT/bridge.py" <<'PY'
import subprocess,re,json,threading,time,sys,os,signal,socket,atexit,urllib.request
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from urllib.parse import urlparse,parse_qs
root=Path(__file__).parent
process_lock=threading.Lock()
game=None
log=None
stopping=False
capture_process=None

def stop_game():
 global game,log
 with process_lock:
  if game is not None:
   try:
    os.killpg(game.pid,signal.SIGTERM)
    game.wait(timeout=5)
   except ProcessLookupError: pass
   except subprocess.TimeoutExpired:
    os.killpg(game.pid,signal.SIGKILL); game.wait()
   game=None
  if log is not None: log.close(); log=None

def start_game():
 global game,log
 with process_lock:
  if stopping: raise RuntimeError('InkLink encerrando')
  if game is None or game.poll() is not None:
   with socket.socket() as sock:
    if sock.connect_ex(('127.0.0.1',5173))==0: raise RuntimeError('Porta 5173 ocupada. Feche o wosu! antigo.')
   if log: log.close()
   log=open(root/'wosu.log','w')
   game=subprocess.Popen(['npm','run','dev','--','--host','127.0.0.1','--port','5173','--strictPort'],cwd=root/'wosu',stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
  for _ in range(120):
   if game.poll() is not None: raise RuntimeError('Falha ao iniciar. Consulte wosu.log.')
   try:
    with urllib.request.urlopen('http://127.0.0.1:5173',timeout=1) as r:
     if r.status==200: return
   except OSError: pass
   time.sleep(.25)
  raise RuntimeError('Jogo demorou a iniciar. Tente novamente.')
atexit.register(stop_game)
adb=sys.argv[2:]+['-s',sys.argv[1],'shell']
info=subprocess.check_output(adb+['getevent','-lp'],text=True)
candidates=[]
for block in re.split(r'(?=add device \d+:)',info):
 path=re.search(r'/dev/input/event\d+',block)
 axes=[re.search(r'ABS_MT_POSITION_'+a+r'\s*:.*?min\s+(-?\d+),\s*max\s+(-?\d+)',block) for a in 'XY']
 if path and all(axes): candidates.append((path.group(),axes,block))
if not candidates: sys.exit('Touchscreen não encontrado.')
path,axes,_=next((c for c in candidates if 'INPUT_PROP_DIRECT' in c[2]),candidates[0]); bounds=[tuple(map(int,a.groups())) for a in axes]
print('Touchscreen:',path,bounds,flush=True)
state={'x':.5,'y':.5,'active':False,'connected':False,'hz':0,'last':0}; config={'mode':'reverse','width':1.,'height':1.,'enabled':True}; lock=threading.Lock()
settings=Path(__file__).with_name('settings.json')
try:
 saved=json.loads(settings.read_text())
 if saved['mode'] in ('reverse','horizontal','vertical'):
  config.update(mode=saved['mode'],width=max(.2,min(1,float(saved['width']))),height=max(.2,min(1,float(saved['height']))),enabled=bool(saved['enabled']))
except (OSError,ValueError,KeyError,TypeError): pass
model=subprocess.run(adb+['getprop','ro.product.model'],capture_output=True,text=True).stdout.strip() or 'Android'

def capture():
 global capture_process
 p=subprocess.Popen(adb+['getevent','-lt',path],stdout=subprocess.PIPE,text=True,bufsize=1)
 capture_process=p
 slot=0; xy=[None,None]; changed=False; count=0; start=time.monotonic()
 with lock: state['connected']=True
 try:
  for line in p.stdout:
   parts=line.split()
   if not parts: continue
   if 'ABS_MT_SLOT' in line: slot=int(parts[-1],16)
   for i,a in enumerate('XY'):
    if 'ABS_MT_POSITION_'+a in line and slot==0: xy[i]=int(parts[-1],16); changed=True
   if 'SYN_REPORT' in line and changed and None not in xy:
    changed=False
    with lock:
     for i,a in enumerate('xy'): state[a]=max(0,min(1,(xy[i]-bounds[i][0])/(bounds[i][1]-bounds[i][0])))
     state['active']=True; state['last']=time.monotonic()
     count+=1
     if time.monotonic()-start>=1:
      state['hz']=round(count/(time.monotonic()-start)); count=0; start=time.monotonic()
 finally:
  with lock: state.update(active=False,connected=False,hz=0)
threading.Thread(target=capture,daemon=True).start()
HTML='''<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>InkLink 0.3.1</title><style>
*{box-sizing:border-box}body{margin:0;background:#101018;color:#eee;font:15px system-ui}main{max-width:860px;margin:auto;padding:28px}header{display:flex;align-items:center;gap:14px;margin-bottom:24px}h1{margin:0;font-size:28px}small,p{color:#aaa9bd}small{font-size:12px}.logo{background:#b6a0ff;color:#181327;padding:12px;border-radius:14px;font-weight:900;font-size:24px}.cards{display:grid;grid-template-columns:repeat(3,1fr);gap:10px}.card,section{background:#1b1b29;border:1px solid #343345;border-radius:16px;padding:18px}.card strong{display:block;font-size:20px;margin-top:8px;overflow-wrap:anywhere}section{margin-top:14px}label{display:block;margin:18px 0}select,input{accent-color:#b6a0ff}select{background:#292839;color:white;padding:8px;border:1px solid #555;border-radius:8px;width:100%}input[type=range]{width:100%}output{float:right;color:#b6a0ff}#pad{position:relative;height:240px;background:#11111b;border:1px solid #46405d;border-radius:12px;overflow:hidden;background-image:linear-gradient(#ffffff08 1px,transparent 1px),linear-gradient(90deg,#ffffff08 1px,transparent 1px);background-size:24px 24px}#dot{position:absolute;width:14px;height:14px;background:#b6a0ff;box-shadow:0 0 16px #b6a0ff;border-radius:50%;transform:translate(-50%,-50%)}a,button{display:inline-block;background:#b6a0ff;color:#181327;padding:12px 18px;border:0;border-radius:9px;font-weight:700;text-decoration:none;cursor:pointer}button{background:#303044;color:white}footer{margin-top:18px;color:#aaa9bd;font-size:12px}@media(max-width:560px){main{padding:14px}.cards{grid-template-columns:1fr}}
</style><main><header><div class="logo">IL</div><div><h1>InkLink <small>v0.3.1</small></h1><small>Your phone. Your tablet.</small></div></header><div class="cards"><div class="card"><small>Dispositivo</small><strong id="model">—</strong></div><div class="card"><small>Captura USB</small><strong id="status">Conectando</strong></div><div class="card"><small>Amostras de movimento/s</small><strong id="hz">0</strong></div></div><section><h2>Área ativa</h2><label><input id="en" type="checkbox" checked> Ativar InkLink</label><label>Orientação<select id="mode"><option value="reverse">Horizontal invertido</option><option value="horizontal">Horizontal</option><option value="vertical">Vertical</option></select></label><label>Largura <output id="wo">100%</output><input id="w" type="range" min="20" max="100" value="100"></label><label>Altura <output id="ho">100%</output><input id="h" type="range" min="20" max="100" value="100"></label><div id="pad"><div id="dot"></div></div><p id="save">Carregando configurações...</p><button id="reset">Restaurar padrão</button></section><section><h2>Jogar</h2><p>Use o celular para mirar e Z/X para acertar. O mouse continua disponível quando o InkLink está desativado.</p><button id="game" disabled>Iniciar osu!</button> <button id="stop">Encerrar InkLink</button><p id="launch"></p><p id="diag"></p></section><footer>InkLink • Experimental • Linux / Chromebook • Sem hover</footer></main><script>
const $=id=>document.getElementById(id);let ready=false,timer; $('game').onclick=async()=>{if(!ready)return;clearTimeout(timer);$('game').disabled=true;$('launch').textContent='Iniciando jogo...';try{await save();const r=await fetch('/launch',{method:'POST'});if(!r.ok)throw Error(await r.text());location.href='http://localhost:5173'}catch(e){$('launch').textContent=e.message;$('game').disabled=false}};$('stop').onclick=async()=>{if(!confirm('Encerrar InkLink e o jogo?'))return;try{await fetch('/shutdown',{method:'POST'});$('launch').textContent='InkLink encerrado';$('game').disabled=true}catch{ $('launch').textContent='Não foi possível encerrar'}};function labels(){$('wo').value=$('w').value+'%';$('ho').value=$('h').value+'%'}function apply(c){$('mode').value=c.mode;$('w').value=Math.round(c.width*100);$('h').value=Math.round(c.height*100);$('en').checked=c.enabled;labels()}async function save(){try{const r=await fetch('/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({mode:$('mode').value,width:$('w').value/100,height:$('h').value/100,enabled:$('en').checked})});if(!r.ok)throw Error();$('save').textContent='Configurações salvas automaticamente'}catch{$('save').textContent='Falha ao salvar; tente novamente';throw Error('Falha ao salvar configurações')}}function update(){labels();if(!ready)return;clearTimeout(timer);timer=setTimeout(()=>save().catch(()=>{}),100)}for(const id of ['mode','w','h','en'])$(id).oninput=update;$('reset').onclick=()=>{apply({mode:'reverse',width:1,height:1,enabled:true});update()};fetch('/config').then(r=>r.json()).then(c=>{apply(c);ready=true;$('game').disabled=false;$('save').textContent='Configurações carregadas'}).catch(()=>{$('save').textContent='Falha ao carregar configurações'});const es=new EventSource('/events');es.onmessage=e=>{const d=JSON.parse(e.data);$('dot').style.left=d.x*100+'%';$('dot').style.top=d.y*100+'%';$('status').textContent=!d.connected?'Desconectado':d.active?'Ativo':$('en').checked?'Aguardando toque':'Desativado';$('hz').textContent=d.hz;$('model').textContent=d.model;$('diag').textContent=d.device+' · '+d.bounds+' · frequência de movimento, não latência';};es.onerror=()=>{$('status').textContent='Servidor offline';$('hz').textContent='0'};</script></html>'''
class Handler(BaseHTTPRequestHandler):
 def log_message(self,*a): pass
 def local_host(self):
  return self.headers.get('Host') in ('localhost:8765','127.0.0.1:8765')
 def do_GET(self):
  if not self.local_host(): self.send_error(403); return
  if self.headers.get('Origin') not in (None,'http://localhost:8765','http://127.0.0.1:8765','http://localhost:5173','http://127.0.0.1:5173'): self.send_error(403); return
  u=urlparse(self.path)
  if u.path=='/events':
   self.send_response(200); self.send_header('Content-Type','text/event-stream'); self.send_header('Cache-Control','no-cache'); 
   origin=self.headers.get('Origin')
   if origin in ('http://localhost:5173','http://127.0.0.1:5173'):
    self.send_header('Access-Control-Allow-Origin',origin)
   self.send_header('Vary','Origin'); self.end_headers()
   try:
    while not stopping:
     with lock: d=state.copy(); c=config.copy()
     d.update(model=model,device=path,bounds=' × '.join(str(b-a) for a,b in bounds)); d['hz']=d['hz'] if time.monotonic()-d.pop('last')<1.5 else 0
     x,y=d['x'],d['y']; x,y=(y,1-x) if c['mode']=='reverse' else ((1-y,x) if c['mode']=='horizontal' else (x,y))
     d.update(x=max(0,min(1,(x-.5)/c['width']+.5)),y=max(0,min(1,(y-.5)/c['height']+.5)),active=d['active'] and c['enabled'])
     self.wfile.write(('data: '+json.dumps(d)+'\n\n').encode()); self.wfile.flush(); time.sleep(1/120)
   except (BrokenPipeError,ConnectionResetError): pass
  elif u.path=='/config':
   with lock: data=json.dumps(config).encode()
   self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(data)
  elif u.path=='/':
   self.send_response(200); self.send_header('X-Frame-Options','DENY'); self.send_header('Content-Type','text/html; charset=utf-8'); self.end_headers(); self.wfile.write(HTML.encode())
  else: self.send_error(404)
 def do_POST(self):
  if not self.local_host(): self.send_error(403); return
  if self.headers.get('Origin') not in ('http://localhost:8765','http://127.0.0.1:8765'):
   self.send_error(403); return
  if self.path=='/launch':
   try: start_game()
   except (RuntimeError,OSError) as e: self.send_error(503,str(e)); return
   self.send_response(204); self.end_headers(); return
  if self.path=='/shutdown':
   global stopping
   stopping=True
   self.send_response(204); self.end_headers()
   threading.Thread(target=server.shutdown,daemon=True).start(); return
  if self.path!='/config': self.send_error(404); return
  if self.headers.get('Content-Type','').split(';')[0]!='application/json': self.send_error(415); return
  try:
   n=int(self.headers.get('Content-Length','0'))
   if not 0<n<4096: raise ValueError()
   q=json.loads(self.rfile.read(n))
   if q['mode'] not in ('reverse','horizontal','vertical'): raise ValueError()
   c=dict(mode=q['mode'],width=max(.2,min(1,float(q['width']))),height=max(.2,min(1,float(q['height']))),enabled=q['enabled'] is True)
   with lock:
    tmp=settings.with_suffix('.tmp'); tmp.write_text(json.dumps(c)); tmp.replace(settings); config.update(c)
  except (OSError,KeyError,ValueError,TypeError): self.send_error(400); return
  self.send_response(204); self.end_headers()
server=ThreadingHTTPServer(('127.0.0.1',8765),Handler)
def terminate(*args): raise SystemExit(0)
signal.signal(signal.SIGTERM,terminate)
try: server.serve_forever()
finally:
 stopping=True
 server.server_close(); stop_game()
 if capture_process is not None and capture_process.poll() is None:
  try:
   capture_process.terminate(); capture_process.wait(timeout=3)
  except subprocess.TimeoutExpired: capture_process.kill(); capture_process.wait()
  except (ProcessLookupError,PermissionError): pass
PY
python3 "$ROOT/bridge.py" "$SERIAL" "${ADB[@]}" &
BRIDGE=$!
trap 'kill "$BRIDGE" 2>/dev/null || true' EXIT
sleep 1
kill -0 "$BRIDGE"
echo 'InkLink pronto: http://localhost:8765'
echo 'Abra o painel para iniciar o jogo. Ctrl+C para encerrar.'
if command -v xdg-open >/dev/null; then xdg-open http://localhost:8765 >/dev/null 2>&1 & fi
wait "$BRIDGE"
