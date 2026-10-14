// Supabase public client. The publishable key is safe to bundle; NEVER insert secret/service_role keys here.
export const SB_URL='https://eihcsvgajcjykpwbblhz.supabase.co';
export const SB_KEY='sb_publishable_tuJ5MyHRYRd7EPpIg85GWQ_afUmF4Ue';
let session=null;
const storageKey='goride-live-session-v1';
try { session=JSON.parse(localStorage.getItem(storageKey)||'null'); } catch {}
function save(s){session=s; if(s)localStorage.setItem(storageKey,JSON.stringify(s));else localStorage.removeItem(storageKey);}
async function request(path,{method='GET',body,auth=true,headers={}}={}){
  const token=auth?await accessToken():null;
  const response=await fetch(SB_URL+path,{method,headers:{'apikey':SB_KEY,...(body!==undefined?{'Content-Type':'application/json'}:{}),...(token?{Authorization:`Bearer ${token}`}:{}),...headers},...(body!==undefined?{body:JSON.stringify(body)}:{})});
  const content=await response.text();let data;try{data=content?JSON.parse(content):null}catch{data=content}
  if(!response.ok)throw Error(data?.msg||data?.message||data?.error_description||data?.error||`Supabase request failed (${response.status})`);
  return data;
}
async function accessToken(){
  if(!session?.access_token)return null;
  if((session.expires_at||0)*1000>Date.now()+60_000)return session.access_token;
  if(!session.refresh_token){save(null);return null;}
  const r=await request('/auth/v1/token?grant_type=refresh_token',{method:'POST',auth:false,body:{refresh_token:session.refresh_token}}).catch(()=>null);
  if(!r?.access_token){save(null);return null;} save({...r,expires_at:Math.floor(Date.now()/1000)+(r.expires_in||3600)});
  return session.access_token;
}
export const authenticated=()=>!!session?.access_token;
export const currentUser=()=>session?.user||null;
export async function signIn(email,password){const s=await request('/auth/v1/token?grant_type=password',{method:'POST',auth:false,body:{email,password}});save({...s,expires_at:Math.floor(Date.now()/1000)+(s.expires_in||3600)});return s;}
export async function signUp(full_name,email,password){return request('/auth/v1/signup',{method:'POST',auth:false,body:{email,password,data:{full_name}}});}
export async function signOut(){try{await request('/auth/v1/logout',{method:'POST'});}catch{}save(null);}
export async function getProfile(){if(!authenticated())return null;const u=await request('/auth/v1/user');if(!u?.id){save(null);return null;}const rows=await select('profiles',{id:`eq.${u.id}`});return rows[0]||null;}
export async function select(table,params={}){const search=new URLSearchParams({select:'*',...params});return request(`/rest/v1/${table}?${search}`);}
export async function rpc(name,args={}){return request(`/rest/v1/rpc/${name}`,{method:'POST',body:args});}
export async function insert(table,data){return request(`/rest/v1/${table}`,{method:'POST',body:data,headers:{Prefer:'return=representation'}});}
export async function update(table,id,data,column='id'){return request(`/rest/v1/${table}?${encodeURIComponent(column)}=eq.${encodeURIComponent(id)}`,{method:'PATCH',body:data,headers:{Prefer:'return=representation'}});}
const escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export {escape};
export const money=n=>new Intl.NumberFormat('en-ZA',{style:'currency',currency:'ZAR'}).format(Number(n)||0);
export const pill=s=>`<span class="pill ${s==='requested'||s==='pending'?'wait':s==='cancelled'||s==='rejected'?'bad':''}">${escape(s)}</span>`;
export const notify=(msg,isError=false)=>{const e=document.getElementById('toast');if(e){e.textContent=msg;e.className='toast'+(isError?' error':'');setTimeout(()=>e.className='toast hidden',4500);}};
export async function protect(role){
  document.body.innerHTML=`<div class="shell"><aside><div class="brand"><span class="brand-mark">G</span>GoRide <b>SA</b></div><div class="sidebar-foot">${role.toUpperCase()} · CONNECTED TO SUPABASE</div></aside><main><header class="top"><div><div class="eyebrow">GORIDE SA / ${role}</div><h1>${role==='admin'?'Operations control room':role==='driver'?'Drive with GoRide SA':'Where to next?'}</h1></div><button class="button secondary" id="logout" hidden>Sign out</button></header><div class="notice">Secure live accounts and database. Cash only. Address verification and routing depend on configured Maps services.</div><div id="app"></div></main></div><div id="toast" class="toast hidden" role="status"></div>`;
  const root=document.getElementById('app');
  if(!authenticated()){renderLogin();return null;}
  let profile;
  try{profile=await getProfile();}catch(e){root.innerHTML=`<section class="panel"><h2>Account setup unavailable</h2><p>${escape(e.message)}</p><button id="retry" class="button">Retry</button></section>`;document.getElementById('retry').onclick=()=>location.reload();return null;}
  if(!profile){root.innerHTML='<section class="panel"><h2>Profile missing</h2><p>Sign out and check your Supabase profile trigger and database policies.</p></section>';return null;}
  if(profile.suspended){root.innerHTML='<section class="panel"><h2>Account suspended</h2><p>Contact GoRide SA support.</p></section>';}
  else if(profile.role!==role && !(role==='driver' && profile.role==='passenger')){root.innerHTML=`<section class="panel"><h2>Access restricted</h2><p>Your ${escape(profile.role)} account cannot open the ${escape(role)} app. Roles are validated by Supabase, not selected in the browser.</p></section>`;}
  document.getElementById('logout').hidden=false;document.getElementById('logout').onclick=async()=>{await signOut();location.reload();};
  return profile.suspended||profile.role!==role && !(role==='driver'&&profile.role==='passenger')?null:profile;
  function renderLogin(){root.innerHTML=`<section class="panel" style="max-width:450px"><h2>${role==='admin'?'Admin sign in':'Sign in or create an account'}</h2><form id="login" class="stack">${role!=='admin'?'<label>Full name (for sign up)<input name="name" autocomplete="name" /></label>':''}<label>Email<input name="email" type="email" autocomplete="email" required /></label><label>Password<input name="password" type="password" autocomplete="current-password" minlength="6" required /></label><div class="actions"><button class="button" name="operation" value="login">Sign in</button>${role!=='admin'?'<button class="button secondary" name="operation" value="signup">Create account</button>':''}</div><p class="foot-note">Admin roles must be assigned securely in Supabase; public admin signup is disabled. Driver applicants begin with a passenger account.</p></form></section>`;document.getElementById('login').onsubmit=async e=>{e.preventDefault();const f=new FormData(e.currentTarget);const operation=e.submitter?.value||'login';try{if(operation==='signup'){await signUp(f.get('name'),f.get('email'),f.get('password'));notify('Account requested. Confirm your email, then sign in.');}else{await signIn(f.get('email'),f.get('password'));location.reload();}}catch(err){notify(err.message,true);}};}
}
export function repeat(fn,interval=5000){fn().catch(e=>notify(e.message,true));setInterval(()=>{if(!document.hidden)fn().catch(e=>notify(e.message,true));},interval)}
