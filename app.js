const { createClient } = supabase;
const db = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
const $ = s => document.querySelector(s);
const esc = s => String(s ?? '').replace(/[&<>\'\"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','\"':'&quot;'}[c]));
const money = n => `Rs. ${Number(n||0).toFixed(0)}`;
async function me(){ const {data:{user}}=await db.auth.getUser(); return user; }
async function profile(){ const u=await me(); if(!u) return null; const {data}=await db.from('profiles').select('*').eq('id',u.id).maybeSingle(); return data; }
function msg(text,type='notice'){ const el=$('#msg'); if(el){el.className='notice '+type;el.textContent=text;} }
async function ensureProfile(){ const {data,error}=await db.rpc('ensure_my_profile'); if(error) return {data:null,error}; return {data,error}; }
async function guard(role){ let p=await profile(); if(!p){ await ensureProfile(); p=await profile(); } if(!p){location.href='index.html';return null;} if(role && p.role!==role){await db.auth.signOut();location.href='index.html';return null;} if(p.account_status!=='active'){msg('Your account is pending approval or suspended. Please wait for Admin approval.','error');await db.auth.signOut();return null;} return p; }
async function logout(){await db.auth.signOut();location.href='index.html';}
function header(title){document.body.insertAdjacentHTML('afterbegin',`<header><a class="logo" href="index.html">OnClick</a><strong>${esc(title)}</strong><button class="btn small secondary" onclick="logout()">Logout</button></header>`);}
async function login(role){
  const email=$('#email').value.trim(),password=$('#password').value;
  if(!email||!password)return msg('Enter email and password.','error');
  msg('Signing in...');
  const {error}=await db.auth.signInWithPassword({email,password});
  if(error)return msg(error.message,'error');

  // Admin accounts are created/approved in Supabase. Never try to create
  // an Admin profile during Admin Login.
  let p=await profile();
  if(!p && role!=='admin'){
    await ensureProfile();
    p=await profile();
  }

  if(!p){
    await db.auth.signOut();
    return msg('Profile not found for this account. Please contact Admin.','error');
  }

  if(role==='admin'){
    if(p.role!=='admin'){
      await db.auth.signOut();
      return msg('Admin access denied. This account is not an Admin.','error');
    }
    if(p.account_status!=='active'){
      await db.auth.signOut();
      return msg('This Admin account is not active.','error');
    }
    location.href='admin.html';
    return;
  }

  if(p.role!==role){
    await db.auth.signOut();
    return msg(`This account is registered as ${p.role}, not ${role}.`,'error');
  }
  if(p.account_status!=='active'){
    await db.auth.signOut();
    return msg('Your account is pending Admin approval.','error');
  }
  location.href=role==='customer'?'customer.html':'vendor.html';
}
async function signup(role){const email=$('#email').value.trim(),password=$('#password').value,name=$('#name').value.trim(),phone=$('#phone').value.trim(),area=$('#area').value.trim();if(!email||!password||!name)return msg('Name, email and password are required.','error');if(password.length<6)return msg('Password must be at least 6 characters.','error');const {data,error}=await db.auth.signUp({email,password,options:{data:{signup_role:role,full_name:name,phone,service_area:area}}});if(error)return msg(error.message,'error');msg('Account created. Admin approval is required before login. If email confirmation is enabled, confirm your email first.','success');}
async function firstAdminSetup(){const email=$('#email').value.trim(),password=$('#password').value,name=$('#name')?.value.trim()||'Master Admin',phone=$('#phone')?.value.trim()||'';if(!email||!password)return msg('Enter your existing Admin email and password.','error');msg('Checking your account...');let {error}=await db.auth.signInWithPassword({email,password});if(error)return msg(error.message,'error');const {data,error:e}=await db.rpc('bootstrap_first_admin',{master_email:MASTER_ADMIN_EMAIL,full_name:name,phone});if(e){await db.auth.signOut();return msg(e.message,'error');}msg('First Admin activated successfully. Opening Admin Dashboard...','success');setTimeout(()=>location.href='admin.html',500);}
async function requestAdminRole(){const reason=$('#reason').value.trim();if(!reason)return msg('Reason is required.','error');const {error}=await db.rpc('request_admin_role',{reason});if(error)return msg(error.message,'error');msg('Admin Team request submitted. Only the Master Admin can approve it.','success');}
async function loadCustomer(){const p=await guard('customer');if(!p)return;header('Customer Dashboard');$('#welcome').textContent=`Welcome, ${p.full_name||'Customer'}`;$('#areaText').textContent=p.service_area||'Your area';await customerShops(p)}
let customerShopsData=[];
async function customerShops(p){let q=db.from('shops').select('*,products(*)').eq('is_approved',true).eq('is_open',true);if(p.service_area)q=q.eq('service_area',p.service_area);const {data,error}=await q;if(error)return msg(error.message,'error');customerShopsData=data||[];renderShops(customerShopsData)}
function renderShops(shops){const box=$('#shops');if(!shops.length){box.innerHTML='<div class="card">No approved shops found in your area yet.</div>';return}box.innerHTML=shops.map(s=>`<div class="card shop"><h3>${esc(s.name)}</h3><span class="pill">${esc(s.category||'General')}</span><p class="muted">${esc(s.address||'')} · Delivery ${money(s.delivery_fee)}</p><div class="actions"><button class="btn small" onclick="openShop('${s.id}')">Open shop</button></div></div>`).join('')}
function openShop(id){const s=customerShopsData.find(x=>x.id===id);if(!s)return;$('#shopView').classList.remove('hidden');$('#shopTitle').textContent=s.name;$('#shopProducts').innerHTML=(s.products||[]).map(p=>{const price=p.sale_price??p.regular_price;return `<div class="product"><div><b>${esc(p.name)}</b><div class="muted">${esc(p.description||'')}</div><div>${p.sale_price!=null?`<span class="old">${money(p.regular_price)}</span>`:''}<span class="price">${money(price)}</span> <span class="pill">${p.available?'Available':'Out of stock'}</span></div></div><div>${p.available?`<input class="qty" id="qty-${p.id}" type="number" min="0" value="0">`:''}</div></div>`}).join('');window.currentShop=s}
function searchProducts(){const term=$('#search').value.toLowerCase();const shops=customerShopsData.map(s=>({...s,products:(s.products||[]).filter(p=>p.name.toLowerCase().includes(term))})).filter(s=>s.products.length);renderShops(shops)}
async function placeOrder(){const s=window.currentShop;if(!s)return;const items=(s.products||[]).map(p=>{const q=Number($(`#qty-${p.id}`)?.value||0);return q>0?{product_id:p.id,product_name:p.name,quantity:q,unit_price:p.sale_price??p.regular_price}:null}).filter(Boolean);if(!items.length)return msg('Select at least one item.','error');const subtotal=items.reduce((a,x)=>a+x.quantity*x.unit_price,0);if(subtotal<500)return msg('Minimum order is Rs. 500.','error');const p=await profile();const commission=+(subtotal*.05).toFixed(2);const {data:o,error}=await db.from('orders').insert({customer_id:p.id,shop_id:s.id,order_source:'Website',customer_name:p.full_name,customer_phone:p.phone,delivery_address:p.service_area,product_subtotal:subtotal,delivery_fee:s.delivery_fee||0,commission_rate:.05,commission_amount:commission,customer_total:subtotal+(s.delivery_fee||0),payment_method:'Pay merchant directly',status:'pending'}).select().single();if(error)return msg(error.message,'error');const {error:e2}=await db.from('order_items').insert(items.map(x=>({...x,order_id:o.id})));if(e2)return msg(e2.message,'error');msg(`Order ${o.id} submitted. Merchant will confirm it. Pay the merchant directly.`,'success')}
async function loadVendor(){const p=await guard('vendor');if(!p)return;header('Vendor Dashboard');$('#welcome').textContent=`Vendor: ${p.full_name||''}`;const {data:shops}=await db.from('shops').select('*,products(*)').eq('vendor_id',p.id);renderVendor(shops||[])}
function renderVendor(shops){const box=$('#vendorArea');if(!shops.length){box.innerHTML='<div class="card"><h3>Create your shop</h3><input id="shopName" placeholder="Shop name"><input id="shopCat" placeholder="Category"><input id="shopAddress" placeholder="Address"><input id="shopArea" placeholder="Service area (e.g. Nowshera/Pindi Gheb)"><input id="shopFee" type="number" placeholder="Delivery fee"><button class="btn topgap" onclick="createShop()">Create Shop</button></div>';return}window.vendorShop=shops[0];const s=shops[0];box.innerHTML=`<div class="card"><h2>${esc(s.name)}</h2><p>${s.is_approved?'<span class="pill">Approved</span>':'<span class="pill">Pending Admin Approval</span>'} ${s.is_open?'<span class="pill">Open</span>':'<span class="pill">Closed</span>'}</p><button class="btn small secondary" onclick="toggleShop()">${s.is_open?'Close':'Open'} shop</button><h3 class="topgap">Add Item</h3><div class="grid"><input id="pn" placeholder="Name"><input id="pc" placeholder="Category"><input id="rp" type="number" placeholder="Regular price"><input id="sp" type="number" placeholder="Sale/offer price (optional)"><select id="av"><option value="true">Available</option><option value="false">Out of stock</option></select><textarea id="pd" placeholder="Description"></textarea></div><button class="btn topgap" onclick="addProduct()">Add Item</button><h3 class="topgap">Your Items</h3>${(s.products||[]).map(x=>`<div class="listrow"><span><b>${esc(x.name)}</b> · ${money(x.sale_price??x.regular_price)} · ${x.available?'Available':'Out of stock'}</span></div>`).join('')}</div>`}
async function createShop(){const p=await profile();const {error}=await db.from('shops').insert({vendor_id:p.id,name:$('#shopName').value,category:$('#shopCat').value,address:$('#shopAddress').value,service_area:$('#shopArea').value,delivery_fee:Number($('#shopFee').value||0),is_approved:false,is_open:false});if(error)return msg(error.message,'error');location.reload()}
async function addProduct(){const s=window.vendorShop;const {error}=await db.from('products').insert({shop_id:s.id,name:$('#pn').value,category:$('#pc').value,description:$('#pd').value,regular_price:Number($('#rp').value),sale_price:$('#sp').value?Number($('#sp').value):null,available:$('#av').value==='true'});if(error)return msg(error.message,'error');location.reload()}
async function toggleShop(){const s=window.vendorShop;const {error}=await db.from('shops').update({is_open:!s.is_open}).eq('id',s.id);if(error)return msg(error.message,'error');location.reload()}
let currentAdminId='';
async function loadAdmin(){const p=await guard('admin');if(!p)return;currentAdminId=p.id;header('Admin Dashboard');$('#welcome').textContent=`Master/Admin: ${p.full_name||''}`;await adminData()}
async function adminData(){const [pr,sh,or,au,ar]=await Promise.all([db.from('profiles').select('*').order('created_at',{ascending:false}),db.from('shops').select('*,profiles:vendor_id(full_name,phone,email)').order('created_at',{ascending:false}),db.from('orders').select('*').order('created_at',{ascending:false}),db.from('audit_logs').select('*').order('created_at',{ascending:false}).limit(100),db.from('admin_requests').select('*,profiles:user_id(full_name,email,phone,role,account_status)').eq('status','pending').order('created_at',{ascending:false})]);const er=[pr,sh,or,au,ar].find(x=>x.error);if(er)return msg(er.error.message,'error');window.adminRows={profiles:pr.data||[],shops:sh.data||[],orders:or.data||[],audit:au.data||[],requests:ar.data||[]};renderAdmin()}
function renderAdmin(){const d=window.adminRows;const pending=d.profiles.filter(x=>x.account_status==='pending');$('#adminArea').innerHTML=`<div class="card"><h2>Admin Team Requests</h2>${d.requests.length?d.requests.map(x=>`<div class="listrow"><span><b>${esc(x.profiles?.full_name||'')}</b> · ${esc(x.profiles?.email||'')}<br><span class="muted">${esc(x.reason||'')}</span></span><span><button class="btn small" onclick="approveAdmin('${x.id}')">Approve Admin</button> <button class="btn small danger" onclick="rejectAdmin('${x.id}')">Reject</button></span></div>`).join(''):'<p class="muted">No pending Admin Team requests.</p>'}</div><div class="card topgap"><h2>Customers & Vendors</h2><div class="tablewrap"><table class="table"><tr><th>Name</th><th>Email</th><th>Role</th><th>Status</th><th>Action</th></tr>${d.profiles.map(x=>`<tr><td>${esc(x.full_name||x.id)}</td><td>${esc(x.email||'')}</td><td>${esc(x.role)}</td><td>${esc(x.account_status)}</td><td>${x.id!==currentAdminId?`<button class="btn small" onclick="setStatus('${x.id}','${x.account_status==='active'?'suspended':'active'}')">${x.account_status==='active'?'Suspend':'Activate'}</button>`:''}</td></tr>`).join('')}</table></div></div><div class="card topgap"><h2>Pending Customer/Vendor Accounts</h2>${pending.map(x=>`<div class="listrow"><span>${esc(x.full_name||'')} · ${esc(x.email||'')} · ${esc(x.role)}</span><button class="btn small" onclick="setStatus('${x.id}','active')">Approve</button></div>`).join('')||'<p class="muted">No pending accounts.</p>'}</div><div class="card topgap"><h2>Shops</h2><div class="tablewrap"><table class="table"><tr><th>Shop</th><th>Vendor</th><th>Approval</th><th>Open</th><th>Action</th></tr>${d.shops.map(x=>`<tr><td>${esc(x.name)}</td><td>${esc(x.profiles?.full_name||'')}</td><td>${x.is_approved?'Approved':'Pending'}</td><td>${x.is_open?'Open':'Closed'}</td><td>${!x.is_approved?`<button class="btn small" onclick="approveShop('${x.id}')">Approve</button>`:`<button class="btn small danger" onclick="suspendShop('${x.id}')">Suspend</button>`}</td></tr>`).join('')}</table></div></div><div class="card topgap"><h2>Orders</h2><div class="tablewrap"><table class="table"><tr><th>ID</th><th>Customer</th><th>Total</th><th>Status</th><th>Source</th></tr>${d.orders.map(x=>`<tr><td>${esc(x.id)}</td><td>${esc(x.customer_name)}</td><td>${money(x.customer_total)}</td><td>${esc(x.status||'pending')}</td><td>${esc(x.order_source)}</td></tr>`).join('')}</table></div></div><div class="card topgap"><h2>Audit history</h2>${d.audit.map(x=>`<div class="listrow"><span>${esc(x.action)} · ${esc(x.target_type||'')}</span><span class="muted">${esc(x.reason||'')}</span></div>`).join('')||'<p class="muted">No audit entries yet.</p>'}</div>`}
async function setStatus(id,status){const reason=prompt('Reason required');if(!reason)return;const {error}=await db.rpc('admin_set_account_status',{target_user_id:id,new_status:status,reason});if(error)return msg(error.message,'error');await adminData()}
async function approveShop(id){const {error}=await db.rpc('admin_approve_shop',{target_shop_id:id,approve:true,reason:'Approved by Admin'});if(error)return msg(error.message,'error');await adminData()}
async function suspendShop(id){const reason=prompt('Reason required');if(!reason)return;const {error}=await db.rpc('admin_suspend_shop',{target_shop_id:id,reason});if(error)return msg(error.message,'error');await adminData()}
async function approveAdmin(id){const {error}=await db.rpc('admin_decide_admin_request',{request_id:id,approve:true,reason:'Approved by Master Admin'});if(error)return msg(error.message,'error');await adminData()}
async function rejectAdmin(id){const reason=prompt('Reason required');if(!reason)return;const {error}=await db.rpc('admin_decide_admin_request',{request_id:id,approve:false,reason});if(error)return msg(error.message,'error');await adminData()}
