const {chromium}=require('playwright');
(async()=>{const b=await chromium.launch();const p=await b.newPage({viewport:{width:1000,height:900}});const errs=[];p.on('pageerror',e=>errs.push(e.message));
p.on('dialog',d=>{window.__dlg=1;d.dismiss()});
await p.goto('http://localhost:8812/app.html');await p.waitForTimeout(1500);
const r=await p.evaluate(()=>{
 const PAY=['"><img src=x onerror="window.__x=(window.__x||0)+1">','<script>window.__x=(window.__x||0)+1</script>',"'\"><svg onload=window.__x=(window.__x||0)+1>",'javascript:window.__x=1','</style><img src=x onerror=window.__x=1>','{{constructor.constructor("window.__x=1")()}}'];
 let n=0; const pay=()=>PAY[n++%PAY.length];
 function fill(o){ for(const k in o){ if(typeof o[k]==='string') o[k]=pay(); else if(Array.isArray(o[k])&&o[k].length===0){} else if(o[k]&&typeof o[k]==='object') fill(o[k]); } }
 const tmpl=()=>({title:'',company:'',dates:'',loc:'',desc:'',degree:'',school:'',name:'',level:3,handle:'',platform:'linkedin',url:'',role:'',contact:'',phone:'',email:'',issuer:'',year:'',link:'',tools:''});
 ['exp','edu','sk','lang','cert','hobby','ref','award','logiciel','quality','projects'].forEach(k=>{cv[k]=[tmpl(),tmpl()];});
 cv.p.social=[{platform:'linkedin',handle:''},{platform:'x',handle:''}];
 fill(cv); S.photoData=''; S.accent='#2563EB';
 const res={tplFail:[],hit:0};
 TEMPLATES.forEach(t=>{ try{ const h=renderTpl(t,cv); const d=document.createElement('div'); d.style.display='none'; d.innerHTML=h; document.body.appendChild(d);
   if(d.querySelector('script,img[onerror],svg[onload],[onerror],[onload]')) res.tplFail.push(t.id); d.remove(); }catch(e){ res.tplFail.push(t.id+':'+e.message); } });
 for(let s=1;s<=7;s++){ step=s; try{ renderForm(); const f=document.getElementById('stepBody'); if(f&&f.querySelector('script,[onerror],[onload]')) res.tplFail.push('form'+s);}catch(e){res.tplFail.push('form'+s+e.message)} }
 try{ renderCV(); }catch(e){res.tplFail.push('renderCV '+e.message)}
 res.cvDom=!!document.querySelector('#cvPreview [onerror], #cvPreview script, #cvZoom [onerror]');
 return res;});
await p.waitForTimeout(800);
console.log(JSON.stringify(r),'x=',await p.evaluate(()=>window.__x),'dlg',await p.evaluate(()=>window.__dlg),errs.slice(0,5));
await b.close();})();
