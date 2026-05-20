import { Injectable } from '@nestjs/common';

@Injectable()
export class AppService {
  getDashboardHtml(): string {
    return `<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Eon Horizon OC Dashboard</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body class="h-screen overflow-hidden bg-slate-950 text-slate-100">
  <div class="h-screen overflow-hidden p-4 grid grid-cols-12 grid-rows-12 gap-4">
    <aside class="col-span-3 row-span-12 min-h-0 overflow-hidden rounded-2xl border border-slate-800 bg-slate-900/90 flex flex-col">
      <div class="p-4 border-b border-slate-800 flex items-center justify-between">
        <div><h1 class="text-lg font-semibold">Players</h1><p id="status" class="text-xs text-slate-400">loading</p></div>
        <button id="settingsBtn" class="px-3 py-2 rounded-lg bg-sky-600 hover:bg-sky-500 text-sm">Settings</button>
      </div>
      <div id="players" class="min-h-0 overflow-y-auto max-h-full p-3 space-y-2"></div>
    </aside>

    <main class="col-span-6 row-span-12 min-h-0 overflow-hidden grid grid-rows-12 gap-4">
      <section class="row-span-2 min-h-0 overflow-hidden grid grid-cols-3 gap-4">
        <div class="rounded-2xl bg-slate-900 border border-slate-800 p-4 overflow-hidden"><div class="text-xs text-slate-400">Online</div><div id="onlineCard" class="text-3xl font-bold">0</div></div>
        <div class="rounded-2xl bg-slate-900 border border-slate-800 p-4 overflow-hidden"><div class="text-xs text-slate-400">ME Items</div><div id="meCard" class="text-3xl font-bold">-</div></div>
        <div class="rounded-2xl bg-slate-900 border border-slate-800 p-4 overflow-hidden"><div class="text-xs text-slate-400">Flux</div><div id="fluxCard" class="text-3xl font-bold">-</div></div>
      </section>
      <section class="row-span-4 min-h-0 overflow-hidden rounded-2xl border border-slate-800 bg-slate-900 p-4">
        <div class="flex items-center justify-between mb-3"><h2 class="font-semibold">Flux Network</h2><div id="fluxMeta" class="text-xs text-slate-400"></div></div>
        <div class="h-3 rounded-full bg-slate-800 overflow-hidden mb-3"><div id="fluxBar" class="h-full bg-emerald-500" style="width:0%"></div></div>
        <div class="h-[calc(100%-56px)] min-h-0"><canvas id="fluxChart"></canvas></div>
      </section>
      <section class="row-span-6 min-h-0 overflow-hidden rounded-2xl border border-slate-800 bg-slate-900 flex flex-col">
        <div class="p-4 border-b border-slate-800 flex justify-between"><h2 class="font-semibold">ME Items</h2><span id="itemsCount" class="text-xs text-slate-400">0</span></div>
        <div id="items" class="min-h-0 overflow-y-auto max-h-full p-3 space-y-2"></div>
      </section>
    </main>

    <section class="col-span-3 row-span-12 min-h-0 overflow-hidden rounded-2xl border border-slate-800 bg-slate-900 flex flex-col">
      <div class="p-4 border-b border-slate-800 flex items-center justify-between"><h2 class="font-semibold">Chat</h2><button id="debugBtn" class="px-3 py-2 rounded-lg bg-slate-800 hover:bg-slate-700 text-sm">Debug</button></div>
      <div id="chat" class="min-h-0 overflow-y-auto max-h-full p-3 space-y-2"></div>
    </section>
  </div>

  <div id="settingsModal" class="hidden fixed inset-0 bg-black/70 p-6">
    <div class="mx-auto max-w-3xl max-h-full overflow-hidden rounded-2xl bg-slate-900 border border-slate-700 flex flex-col">
      <div class="p-4 border-b border-slate-800 flex justify-between"><h2 class="font-semibold">Node Settings</h2><button data-close="settingsModal">Close</button></div>
      <form id="configForm" class="min-h-0 overflow-y-auto p-4 grid grid-cols-2 gap-3"></form>
    </div>
  </div>

  <div id="debugModal" class="hidden fixed inset-0 bg-black/70 p-6">
    <div class="mx-auto max-w-5xl h-full overflow-hidden rounded-2xl bg-slate-900 border border-slate-700 flex flex-col">
      <div class="p-4 border-b border-slate-800 flex justify-between"><h2 class="font-semibold">Debug</h2><button data-close="debugModal">Close</button></div>
      <pre id="debug" class="min-h-0 overflow-auto p-4 text-xs break-all"></pre>
    </div>
  </div>

  <script>
    const $ = (id) => document.getElementById(id);
    const fields = ['nodeLabel','nodeTags','telemetryEvery','configEvery','onlineEvery','meEvery','fluxEvery','scanRange','maxItems','topItems','members'];
    let selectedNode = 'main-base';
    let latestState = null;
    let latestNode = null;
    let fluxChart = new Chart($('fluxChart'), {
      type: 'line',
      data: { labels: [], datasets: [
        { label: 'stored', data: [], borderColor: '#34d399', tension: .25, pointRadius: 0 },
        { label: 'input', data: [], borderColor: '#38bdf8', tension: .25, pointRadius: 0 },
        { label: 'output', data: [], borderColor: '#f59e0b', tension: .25, pointRadius: 0 }
      ]},
      options: { responsive: true, maintainAspectRatio: false, animation: false, plugins: { legend: { labels: { color: '#cbd5e1' } } }, scales: { x: { ticks: { color: '#94a3b8' } }, y: { ticks: { color: '#94a3b8' } } } }
    });
    function formatCompactRu(n){n=Number(n||0);if(n>=1e9)return trim(n/1e9)+'ккк';if(n>=1e6)return trim(n/1e6)+'кк';if(n>=1e3)return trim(n/1e3)+'к';return String(Math.floor(n))}
    function trim(n){return Number.isInteger(n)?String(n):n.toFixed(1).replace('.0','')}
    function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
    function pct(a,b){return b?Math.max(0,Math.min(100,a/b*100)):0}
    function renderPlayers(players){$('players').innerHTML=players.map(p=>'<button class="w-full text-left rounded-xl bg-slate-800/70 p-3 hover:bg-slate-800 overflow-hidden"><div class="flex justify-between gap-2"><b class="truncate">'+esc(p.name)+'</b><span class="'+(p.online?'text-emerald-400':'text-amber-400')+' text-xs">'+(p.online?'online':'seen')+'</span></div><div class="text-xs text-slate-400 truncate" title="'+esc(p.uuid||'')+'">'+esc(p.uuid||'no uuid')+'</div><div class="text-xs text-slate-500">'+p.nodes.map(n=>esc(n.nodeLabel)).join(', ')+'</div></button>').join('')||'<div class="text-slate-500">No players</div>'}
    function renderChat(chat){$('chat').innerHTML=chat.slice(-200).reverse().map(c=>'<div class="rounded-xl bg-slate-800/70 p-3 overflow-hidden" title="'+esc(c.uuid||'')+'"><div><b class="text-sky-300">'+esc(c.player||'system')+'</b>: <span class="break-words">'+esc(c.message)+'</span></div><div class="text-xs text-slate-500">'+esc(c.nodeLabel)+' · '+new Date(c.receivedAt).toLocaleTimeString()+'</div></div>').join('')||'<div class="text-slate-500">No chat</div>'}
    function renderItems(items){$('itemsCount').textContent=String(items.length);$('items').innerHTML=items.map(i=>'<div class="rounded-xl bg-slate-800/70 p-3 grid grid-cols-[1fr_auto] gap-3 overflow-hidden"><div class="min-w-0"><div class="font-medium truncate">'+esc(i.label||i.id)+'</div><div class="text-xs text-slate-500 break-all">'+esc(i.id)+'</div></div><div class="font-bold text-lg">'+formatCompactRu(i.count)+'</div></div>').join('')||'<div class="text-slate-500">No items</div>'}
    function renderSummary(state){const node=state.nodes[0];$('onlineCard').textContent=state.players.filter(p=>p.online).length;$('meCard').textContent=formatCompactRu(node?.meTotalItems);$('fluxCard').textContent=formatCompactRu(node?.fluxStored);$('fluxMeta').textContent=node?formatCompactRu(node.fluxStored)+' / '+formatCompactRu(node.fluxMax)+' RF · in '+formatCompactRu(node.fluxInput)+' · out '+formatCompactRu(node.fluxOutput):'-';$('fluxBar').style.width=pct(node?.fluxStored,node?.fluxMax)+'%';$('status').textContent='updated '+new Date().toLocaleTimeString()}
    function updateChart(history){const points=history.filter(p=>p.node===selectedNode).slice(-120);fluxChart.data.labels=points.map(p=>new Date(p.receivedAt).toLocaleTimeString());fluxChart.data.datasets[0].data=points.map(p=>p.stored);fluxChart.data.datasets[1].data=points.map(p=>p.input);fluxChart.data.datasets[2].data=points.map(p=>p.output);fluxChart.update()}
    async function loadConfig(){const cfg=await fetch('/api/oc/config?node='+encodeURIComponent(selectedNode)).then(r=>r.json());$('configForm').innerHTML='<label class="text-sm text-slate-400">node<select name="node" class="mt-1 w-full rounded-lg bg-slate-950 border border-slate-700 p-2 text-slate-100">'+latestState.nodes.map(n=>'<option '+(n.node===selectedNode?'selected':'')+'>'+esc(n.node)+'</option>').join('')+'</select></label>'+fields.map(f=>'<label class="text-sm text-slate-400">'+f+'<input name="'+f+'" class="mt-1 w-full rounded-lg bg-slate-950 border border-slate-700 p-2 text-slate-100" value="'+esc(Array.isArray(cfg[f])?cfg[f].join(', '):cfg[f]??'')+'"></label>').join('')+'<div class="col-span-2 flex gap-2"><button class="px-4 py-2 rounded-lg bg-sky-600">Save</button><button id="resetBtn" type="button" class="px-4 py-2 rounded-lg bg-amber-700">Reset</button></div>';$('resetBtn').onclick=async()=>{await fetch('/api/oc/config/'+encodeURIComponent(selectedNode)+'/reset',{method:'POST'});await loadConfig()}}
    $('configForm').onsubmit=async(e)=>{e.preventDefault();const fd=new FormData(e.target);selectedNode=String(fd.get('node'));const patch={};for(const f of fields){const v=String(fd.get(f)||'').trim();patch[f]=['nodeLabel'].includes(f)?v:['nodeTags','members'].includes(f)?v.split(',').map(x=>x.trim()).filter(Boolean):Number(v)}await fetch('/api/oc/config/'+encodeURIComponent(selectedNode),{method:'PATCH',headers:{'Content-Type':'application/json'},body:JSON.stringify(patch)});await loadConfig()}
    async function load(){latestState=await fetch('/api/oc/state').then(r=>r.json());selectedNode=latestState.nodes[0]?.node||selectedNode;latestNode=selectedNode?await fetch('/api/oc/nodes/'+encodeURIComponent(selectedNode)).then(r=>r.json()):null;renderSummary(latestState);renderPlayers(latestState.players);renderChat(latestState.chat);renderItems(latestState.items);updateChart(latestState.fluxHistory);$('debug').textContent=JSON.stringify({state:latestState,node:latestNode},null,2)}
    $('settingsBtn').onclick=async()=>{$('settingsModal').classList.remove('hidden');await loadConfig()};$('debugBtn').onclick=()=>$('debugModal').classList.remove('hidden');document.querySelectorAll('[data-close]').forEach(b=>b.onclick=() => $(b.dataset.close).classList.add('hidden'));
    load();setInterval(load,1000);
  </script>
</body>
</html>`;
  }
}
