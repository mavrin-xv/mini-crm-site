// Admin pages as plain strings: no build step, no framework.
// The board renders every user-typed value with textContent, never innerHTML.

const STYLE = `
:root{--bg:#f6f6f4;--card:#fff;--ink:#1d1d1b;--muted:#6b6b66;--line:#e2e1dc;--accent:#1f6feb;--late:#c62828;--ok:#2e7d32}
@media (prefers-color-scheme:dark){:root{--bg:#141413;--card:#1f1f1d;--ink:#ecebe6;--muted:#9a9993;--line:#33322f;--accent:#6ea8ff;--late:#ff6b6b;--ok:#7bd88f}}
*{box-sizing:border-box}body{margin:0;font:14px/1.45 system-ui,-apple-system,Segoe UI,sans-serif;background:var(--bg);color:var(--ink)}
header{display:flex;gap:12px;align-items:center;flex-wrap:wrap;padding:12px 16px;border-bottom:1px solid var(--line);position:sticky;top:0;background:var(--bg);z-index:2}
header h1{font-size:16px;margin:0 8px 0 0}header input{flex:1;min-width:160px;padding:8px 10px;border:1px solid var(--line);border-radius:8px;background:var(--card);color:var(--ink)}
button{font:inherit;padding:7px 12px;border-radius:8px;border:1px solid var(--line);background:var(--card);color:var(--ink);cursor:pointer}
button.primary{background:var(--accent);border-color:var(--accent);color:#fff}
.pill{font-size:12px;padding:3px 8px;border-radius:99px;border:1px solid var(--line);color:var(--muted)}.pill.late{color:var(--late);border-color:var(--late)}
.board{display:grid;grid-auto-flow:column;grid-auto-columns:minmax(240px,1fr);gap:12px;padding:16px;overflow-x:auto}
.col h2{font-size:13px;text-transform:uppercase;letter-spacing:.04em;color:var(--muted);margin:0 0 8px;display:flex;justify-content:space-between}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:10px 12px;margin-bottom:8px;cursor:pointer}
.card.late{border-left:4px solid var(--late)}.card .t{font-weight:600}.card .s{color:var(--muted);font-size:12px}
dialog{border:1px solid var(--line);border-radius:12px;background:var(--card);color:var(--ink);width:min(560px,96vw);padding:0}
dialog .in{padding:16px}dialog label{display:block;font-size:12px;color:var(--muted);margin:10px 0 4px}
dialog input,dialog select,dialog textarea{width:100%;padding:8px;border:1px solid var(--line);border-radius:8px;background:var(--bg);color:var(--ink);font:inherit}
.row{display:flex;gap:8px}.row>*{flex:1}.ev{font-size:12px;color:var(--muted);border-top:1px solid var(--line);padding:6px 0}
.err{color:var(--late);min-height:1.2em}a{color:var(--accent)}
`;

export function loginPage(configured) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Sign in</title><style>${STYLE}
main{max-width:340px;margin:12vh auto;padding:0 16px}input{width:100%;padding:10px;border:1px solid var(--line);border-radius:8px;margin:8px 0;background:var(--card);color:var(--ink)}</style></head>
<body><main><h1 style="font-size:18px">Lead board</h1>
${configured
    ? `<form id="f"><input id="p" type="password" placeholder="Password" autocomplete="current-password" required autofocus>
<button class="primary" style="width:100%">Sign in</button><p class="err" id="e"></p></form>
<script>
document.getElementById('f').onsubmit=async(ev)=>{ev.preventDefault();
const r=await fetch('/api/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({password:document.getElementById('p').value})});
if(r.ok)location.href='/admin';else document.getElementById('e').textContent=(await r.json().catch(()=>({}))).error||'Sign-in failed';};
</script>`
    : `<p>The admin is closed because <code>ADMIN_PASSWORD</code> or <code>SESSION_SECRET</code> is not set.
Run <code>npx wrangler secret put ADMIN_PASSWORD</code> and <code>npx wrangler secret put SESSION_SECRET</code> (16+ characters), then reload.</p>`}
</main></body></html>`;
}

export function adminPage() {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>Lead board</title><style>${STYLE}</style></head>
<body>
<header><h1>Leads</h1><span class="pill" id="late"></span><span class="pill" id="due"></span>
<input id="q" type="search" placeholder="Search name, phone, area"><button id="refresh">Refresh</button><button id="out">Sign out</button></header>
<div class="board" id="board"></div>
<dialog id="dlg"><div class="in">
  <div class="row"><div><div class="t" id="d-name" style="font-weight:600;font-size:16px"></div><div class="s" id="d-sub"></div></div>
  <div style="flex:0"><button id="d-close">Close</button></div></div>
  <p id="d-msg" style="white-space:pre-wrap"></p>
  <div class="row"><div><label>Status</label><select id="d-status"></select></div><div><label>Value</label><input id="d-value" type="number" min="0" step="1"></div></div>
  <div class="row"><div><label>Next follow-up (YYYY-MM-DD)</label><input id="d-next" placeholder="2026-12-01"></div><div><label>Lost reason</label><input id="d-lost" maxlength="200"></div></div>
  <label>Add a note</label><textarea id="d-note" rows="2" placeholder="Called, left voicemail"></textarea>
  <p class="err" id="d-err"></p>
  <div class="row"><button class="primary" id="d-save">Save</button></div>
  <div id="d-events" style="margin-top:12px"></div>
</div></dialog>
<script>
const $=(id)=>document.getElementById(id);let DATA=null,CUR=null;
const el=(tag,cls,text)=>{const e=document.createElement(tag);if(cls)e.className=cls;if(text!=null)e.textContent=text;return e;};
const ago=(ts)=>{const m=Math.round((Date.now()-Date.parse(ts.replace(' ','T')+'Z'))/60000);return m<60?m+' min':m<1440?Math.round(m/60)+' h':Math.round(m/1440)+' d';};
async function api(path,opt){const r=await fetch(path,Object.assign({headers:{'content-type':'application/json'}},opt||{}));
 if(r.status===401){location.href='/admin/login';throw new Error('auth');}const j=await r.json();if(!j.ok)throw new Error(j.error||'Error');return j.data;}
async function load(){const q=$('q').value.trim();DATA=await api('/api/leads'+(q?'?q='+encodeURIComponent(q):''));render();
 const s=await api('/api/stats');$('late').textContent='Not called back: '+s.late_new;$('late').className='pill'+(s.late_new?' late':'');$('due').textContent='Follow-ups due: '+s.followups_due;}
function isLate(l){return l.status==='new'&&(Date.now()-Date.parse(l.created_at.replace(' ','T')+'Z'))>DATA.sla_min*60000;}
function render(){const b=$('board');b.replaceChildren();
 for(const [key,label] of Object.entries(DATA.statuses)){const items=DATA.leads.filter(l=>l.status===key);const col=el('div','col');
  const h=el('h2');h.append(el('span',null,label),el('span',null,String(items.length)));col.append(h);
  for(const l of items){const c=el('div','card'+(isLate(l)?' late':''));c.id='lead-'+l.id;
   c.append(el('div','t',l.name),el('div','s',(DATA.services[l.service]||l.service)+(l.preferred_date?' · '+l.preferred_date:'')),
     el('div','s',l.phone+' · '+ago(l.created_at)+' ago'+(l.contact_leads>1?' · repeat':'')+(l.value?' · '+l.value+' '+DATA.currency:'')));
   if(l.next_action_at)c.append(el('div','s','Follow up: '+l.next_action_at));
   c.onclick=()=>openLead(l.id);col.append(c);}
  b.append(col);}
 const h=location.hash.match(/lead-(\\d+)/);if(h&&!$('dlg').open)openLead(Number(h[1]));}
async function openLead(id){const d=await api('/api/leads/'+id);CUR=d.lead;
 $('d-name').textContent=CUR.name;$('d-sub').replaceChildren();const tel=el('a',null,CUR.phone);tel.href='tel:'+CUR.phone;
 $('d-sub').append(tel,document.createTextNode(' · '+(DATA.services[CUR.service]||CUR.service)+(CUR.area?' · '+CUR.area:'')+(CUR.email?' · '+CUR.email:'')+(CUR.utm_source?' · via '+CUR.utm_source:'')));
 $('d-msg').textContent=CUR.message||'';const sel=$('d-status');sel.replaceChildren();
 for(const [k,v] of Object.entries(DATA.statuses)){const o=el('option',null,v);o.value=k;if(k===CUR.status)o.selected=true;sel.append(o);}
 $('d-value').value=CUR.value??'';$('d-next').value=CUR.next_action_at||'';$('d-lost').value=CUR.lost_reason||'';$('d-note').value='';$('d-err').textContent='';
 const ev=$('d-events');ev.replaceChildren();for(const e of d.events.slice().reverse()){
  ev.append(el('div','ev',e.at+' UTC · '+e.kind+(e.to_status?' → '+e.to_status:'')+(e.note?' · '+e.note:'')));}
 $('dlg').showModal();}
$('d-save').onclick=async()=>{try{const body={status:$('d-status').value,value:$('d-value').value,next_action_at:$('d-next').value.trim()||null,lost_reason:$('d-lost').value};
 await api('/api/leads/'+CUR.id,{method:'PATCH',body:JSON.stringify(body)});
 const n=$('d-note').value.trim();if(n)await api('/api/leads/'+CUR.id+'/notes',{method:'POST',body:JSON.stringify({note:n})});
 $('dlg').close();history.replaceState(null,'',location.pathname);await load();}catch(e){$('d-err').textContent=e.message;}};
$('d-close').onclick=()=>{$('dlg').close();history.replaceState(null,'',location.pathname);};
$('refresh').onclick=load;let t;$('q').oninput=()=>{clearTimeout(t);t=setTimeout(load,250);};
$('out').onclick=async()=>{await fetch('/api/logout',{method:'POST'});location.href='/admin/login';};
load();setInterval(()=>{if(!$('dlg').open)load();},60000);
</script></body></html>`;
}
