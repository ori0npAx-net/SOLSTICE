const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const base='http://127.0.0.1:8080';
const created=[];
async function json(url){const r=await fetch(base+url);assert.equal(r.status,200);return r.json()}
async function post(url,data){return fetch(base+url,{method:'POST',body:new URLSearchParams(data)})}
(async()=>{
 try {
  const panels=await json('/api/panels');assert.equal(panels.length,16);assert(panels.every(p=>/^Godot Field R0[1-4] C0[1-4]$/.test(p.model_name)));
  const id=panels[0].panel_id;
  for(const stamp of ['2026-10-24 23:59:59','2026-10-25 00:00:01']){
   const r=await post('/api/readings',{panel:id,voltage:30,current:5,simulated_at:stamp,cloud_cover:.6,rain_intensity:.2,dust_level:.4,bird_level:.1});assert.equal(r.status,201);const result=await r.json();assert(result.saved);created.push(result.reading_id);
  }
  for(let i=0;i<2;i++){
   const date=i===0?'2026-10-24':'2026-10-25';
   const rows=await json(`/api/readings?panel=${id}&date=${date}&clock=simulation`);
   const row=rows.find(r=>r.reading_id===created[i]);assert(row);assert.equal(row.cloud_cover,.6);assert.equal(row.power_output_w,150);assert(row.simulated_at.startsWith(date));assert(!rows.some(r=>r.reading_id===created[1-i]));assert.match(row.recorded_at,/^\d{4}-\d{2}-\d{2} /);assert.notEqual(row.recorded_at,row.simulated_at);
  }
  const days=await json('/api/days?clock=simulation');assert(days.some(d=>d.day==='2026-10-24'));assert(days.some(d=>d.day==='2026-10-25'));
  const summary=await json('/api/summary?date=2026-10-24&clock=simulation');assert.equal(summary.length,16);assert(summary.find(p=>p.panel_id===id).reading_count>=1);
  const all=await json(`/api/readings?panel=${id}`);assert(created.every(id=>all.some(r=>r.reading_id===id)));
  assert.equal((await fetch(base+`/api/readings?panel=${id}&date=2026-02-30`)).status,400);
  for(const extra of [{simulated_at:'2026-02-30 12:00:00'},{simulated_at:'2026-10-26 12:00:00',dust_level:'NaN'},{simulated_at:'2026-10-26 12:00:00',rain_intensity:2}]) assert.equal((await post('/api/readings',{panel:id,voltage:30,current:1,...extra})).status,400);
  assert.equal((await post('/api/simulation-state',{simulated_at:'bad',state:'{}'})).status,400);
  console.log('API PASS: 16-panel scope, midnight date separation, preserved timestamps/weather, history, summary and validation');
 } finally {
  if(created.length){
   assert(created.every(Number.isSafeInteger));
   const runtime=path.resolve(__dirname,'../../GodotSimulation/.runtime');
   const maria=fs.readdirSync(runtime).find(n=>n.startsWith('mariadb-')&&fs.existsSync(path.join(runtime,n,'bin/mariadb.exe')));
   execFileSync(path.join(runtime,maria,'bin/mariadb.exe'),['--host=127.0.0.1','--user=root',`--execute=DELETE FROM solar_tracker_db.ENERGY_READING WHERE reading_id IN (${created.join(',')})`],{env:{...process.env,MYSQL_PWD:fs.readFileSync(path.join(runtime,'db-root-password.txt'),'utf8')},stdio:'pipe'});
  }
 }
})().catch(e=>{console.error(e);process.exitCode=1});
