const sampleShops = [
  {name:'Nowshera Grocery',category:'Grocery',address:'Nowshera',delivery_area:'Local delivery',delivery_fee:0},
  {name:'Pindi Gheb Bakers',category:'Bakery',address:'Pindi Gheb',delivery_area:'Local delivery',delivery_fee:0},
  {name:'City General Store',category:'General Store',address:'Pindi Gheb',delivery_area:'Local delivery',delivery_fee:0},
  {name:'Nowshera Fresh Mart',category:'Grocery',address:'Nowshera',delivery_area:'Local delivery',delivery_fee:0},
  {name:'Health Care Pharmacy',category:'Pharmacy',address:'Pindi Gheb',delivery_area:'Local delivery',delivery_fee:0},
  {name:'Village Dry Foods',category:'General Store',address:'Nowshera',delivery_area:'Local delivery',delivery_fee:0}
];

let shops = [];
let supabaseClient = null;
try {
  supabaseClient = window.supabase.createClient(window.SUPABASE_URL, window.SUPABASE_PUBLISHABLE_KEY);
} catch (e) { console.warn('Supabase init failed', e); }

function renderShops(list){
  const grid=document.getElementById('grid');
  if(!grid)return;
  grid.innerHTML=list.map((s,i)=>`<article class="shop"><div class="shop-icon">${['🛒','🥖','🏪','🥬','💊','🌶️'][i%6]}</div><div><span>${s.category||'Local shop'}</span><h3>${escapeHtml(s.name)}</h3><p>${escapeHtml(s.address||'Pilot area')} · ${escapeHtml(s.delivery_area||'Local delivery')}</p><button class="secondary" onclick="viewShop('${s.id||''}')">View Shop</button></div></article>`).join('');
}
function escapeHtml(v){return String(v??'').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));}
async function loadShops(){
  if(!supabaseClient){shops=sampleShops;renderShops(shops);return;}
  const {data,error}=await supabaseClient.from('shops').select('id,name,category,address,delivery_area,delivery_fee,is_approved,is_open').eq('is_approved',true).order('name');
  if(error){console.warn('Supabase shops query failed:',error);shops=sampleShops;renderShops(shops);return;}
  shops=(data&&data.length)?data:sampleShops;
  renderShops(shops);
}
async function viewShop(id){
  if(!id){alert('Sample shop preview. Live shop pages will open after merchants are added.');return;}
  const shop=shops.find(s=>s.id===id);
  if(!shop)return;
  let msg=`${shop.name}\n${shop.category||''}\n${shop.address||''}`;
  try{
    const {data,error}=await supabaseClient.from('products').select('name,price,description').eq('shop_id',id).eq('available',true).order('name');
    if(!error && data?.length){msg+='\n\nProducts:\n'+data.map(p=>`${p.name} — Rs.${p.price}`).join('\n');}
  }catch(e){}
  alert(msg);
}
function filter(){
  const q=(document.getElementById('q')?.value||'').toLowerCase();
  const cat=document.getElementById('cat')?.value||'';
  renderShops(shops.filter(s=>(!q || `${s.name} ${s.category} ${s.address}`.toLowerCase().includes(q)) && (!cat || s.category===cat)));
}

const modal=document.getElementById('modal');
document.getElementById('login')?.addEventListener('click',()=>modal?.classList.remove('hidden'));
document.getElementById('vendorLogin')?.addEventListener('click',()=>modal?.classList.remove('hidden'));
document.getElementById('close')?.addEventListener('click',()=>modal?.classList.add('hidden'));
document.getElementById('q')?.addEventListener('input',filter);
document.getElementById('cat')?.addEventListener('change',filter);
document.getElementById('lang')?.addEventListener('click',()=>alert('Urdu/English bilingual interface will be connected in the next UI pass.'));
loadShops();
