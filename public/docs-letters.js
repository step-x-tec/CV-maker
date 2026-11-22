
/* =========================================================================
   LETTRES & DEMANDES — lettre de motivation, demande d'emploi, demande de
   stage, candidature spontanée.
   - Texte composé à partir du CV (aucune IA externe, rien n'est envoyé).
   - 4 mises en page, mêmes couleurs que le CV, export PDF / Word / copie.
   - Enregistrement local + synchronisation du compte (table « documents »).
   ========================================================================= */
const DOC_KEY = 'scv_docs';
const DOC_TYPES = {
  lettre:    { label:'Lettre de motivation',  ic:'✉️', hint:'Pour répondre à une offre précise' },
  emploi:    { label:'Demande d\'emploi',     ic:'📝', hint:'Solliciter un emploi auprès d\'une structure' },
  stage:     { label:'Demande de stage',      ic:'🎓', hint:'Pour étudiants et jeunes diplômés' },
  spontanee: { label:'Candidature spontanée', ic:'🚀', hint:'Sans offre publiée' }
};
const DOC_TEMPLATES = [
  { id:'classic', name:'Classique' }, { id:'modern', name:'Moderne' },
  { id:'band', name:'Bandeau' },      { id:'minimal', name:'Épuré' }
];
const DOC_ACCENTS = ['#2563EB','#10B981','#F59E0B','#EF4444','#7C3AED','#16215C','#B0691E','#111827'];
const DOC_SALUTATIONS = [
  'Madame, Monsieur,', 'Monsieur le Directeur,', 'Madame la Directrice,',
  'Monsieur le Directeur des Ressources Humaines,', 'Madame la Directrice des Ressources Humaines,',
  'Monsieur le Responsable du recrutement,', 'Madame, Monsieur les membres du jury,'
];
const DOC_CLOSINGS = {
  distinguees: { label:'Salutations distinguées', f:function(b){ return 'je vous prie d\'agréer, '+b+', l\'expression de mes salutations distinguées.'; } },
  respectueuses: { label:'Salutations respectueuses', f:function(b){ return 'veuillez agréer, '+b+', l\'expression de mes salutations respectueuses.'; } },
  considerations: { label:'Considération distinguée', f:function(b){ return 'je vous prie de croire, '+b+', à l\'assurance de ma considération distinguée.'; } }
};
const DOC_FONTS = { auto:'', inter:"'Inter',system-ui,sans-serif", merriweather:"'Merriweather',Georgia,serif", poppins:"'Poppins',sans-serif", georgia:"Georgia,'Times New Roman',serif" };
const DOC_SIZES = { small:14, normal:15, large:16 };
const NB = ' ';

let DOCS = [];            // documents enregistrés (local + compte)
let DOC = null;           // document en cours d'édition
let docView = 'home';     // 'home' | 'edit'
let docTab = 'edit';      // mobile : 'edit' | 'preview'
let docSaveTimer = null, docCloudTimer = null;

/* ---------------- Utilitaires de langue ---------------- */
function dcGender(){
  const g = (cv.ec && cv.ec.gender || '').toLowerCase();
  return g.indexOf('fé')===0 || g.indexOf('fe')===0 ? 'F' : (g.indexOf('masc')===0 ? 'M' : '');
}
// accord : mot + terminaison féminine (« étudiant » + « e »), ou « (e) » si le genre est inconnu
function dcAg(word, fem){ const g=dcGender(); fem = fem==null ? 'e' : fem; return g==='F' ? word+fem : (g==='M' ? word : word+'('+fem+')'); }
function dcLowerFirst(s){ s=String(s||'').trim(); if(!s) return s; return (s.length>1 && s[1]===s[1].toLowerCase() && /[a-zà-ÿ]/i.test(s[1])) ? s.charAt(0).toLowerCase()+s.slice(1) : s; }
function dcUpperFirst(s){ s=String(s||'').trim(); return s ? s.charAt(0).toUpperCase()+s.slice(1) : s; }
function dcDe(word){ word=String(word||'').trim(); return /^[aeiouyàâäéèêëîïôöùûü]/i.test(word) ? 'd\''+word : 'de '+word; }
function dcList(arr){ arr=arr.filter(Boolean); if(arr.length<=1) return arr.join(''); return arr.slice(0,-1).join(', ')+' et '+arr[arr.length-1]; }
function dcSentence(s){ s=String(s||'').trim(); if(!s) return ''; s=dcUpperFirst(s); return /[.!?…]$/.test(s) ? s : s+'.'; }
function dcFirstLine(t){ return String(t||'').split(/\r?\n/).map(function(x){ return x.replace(/^[\s•\-–*·]+/,'').trim(); }).filter(Boolean)[0] || ''; }
function dcDateFR(iso, place){
  let d = iso ? new Date(iso+'T12:00:00') : new Date();
  if(isNaN(d)) d = new Date();
  const day = d.getDate()===1 ? '1er' : String(d.getDate());
  const txt = day+' '+d.toLocaleDateString('fr-FR',{month:'long'})+' '+d.getFullYear();
  return (place ? place.trim()+', le ' : 'Le ')+txt.replace(/^Le /,'');
}
function dcToday(){ const d=new Date(); return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0'); }
function dcNewId(){ return 'doc_'+Date.now().toString(36)+Math.random().toString(36).slice(2,7); }

/* ---------------- Modèle de document ---------------- */
function dcBlank(type){
  const p = cv.p || {};
  const d = {
    id: dcNewId(), cloudId:null, type: type||'lettre', name:'',
    template:'classic', accent: S.accent || '#2563EB', font:'auto', size:'normal',
    sender:{ name:p.name||'', role:p.role||'', address:p.address||'', phone:p.phone||'', email:p.email||'' },
    place: (p.address||'').split(',')[0].trim(), date: dcToday(),
    recipient:{ salutation:'Madame, Monsieur,', name:'', title:'', org:'', address:'' },
    job:{ title:(type==='stage' ? '' : (p.role||'')), ref:'', source:'', why:'', duration:'', start:'', availability:'' },
    tone:'formel', variant:0, closingId:'distinguees', attach:true,
    object:'', body:[], signature:p.name||'',
    auto:{ body:true, object:true }, savedAt:new Date().toISOString()
  };
  dcRegen(d, true);
  return d;
}

/* ---------------- Composition du texte à partir du CV ---------------- */
function dcContext(d){
  const e0 = (cv.exp||[])[0] || null, ed0 = (cv.edu||[])[0] || null;
  const skills = (cv.sk||[]).map(function(s){ return (s.name||'').trim(); }).filter(Boolean).slice(0,4);
  return {
    poste: (d.job.title||'').trim(), co: (d.recipient.org||'').trim(),
    years: (typeof localYearsOfExperience==='function') ? localYearsOfExperience() : 0,
    e0:e0, ed0:ed0, skills:skills, tone:d.tone, v:(d.variant||0)%3
  };
}
function dcObject(d){
  const poste = (d.job.title||'').trim(), ref = (d.job.ref||'').trim();
  if(d.type==='lettre')    return 'Candidature au poste de '+(poste||'…')+(ref?' (réf.'+NB+ref+')':'');
  if(d.type==='emploi')    return 'Demande d\'emploi'+(poste?' — '+poste:'');
  if(d.type==='stage')     return 'Demande de stage'+(poste?' — '+poste:'');
  return 'Candidature spontanée'+(poste?' — '+poste:'');
}
function dcCompose(d){
  const c = dcContext(d), co = c.co, poste = c.poste, v = c.v, dyn = c.tone==='dynamique';
  const atCo = co ? ' au sein '+dcDe(co) : '';
  const src = (d.job.source||'').trim();
  const posteL = dcLowerFirst(poste);
  const yearsTxt = c.years>=1 ? c.years+' an'+(c.years>1?'s':'')+' d\'expérience' : '';
  const degree = c.ed0 && c.ed0.degree ? '« '+c.ed0.degree.trim()+' »' : '';
  const school = c.ed0 && c.ed0.school ? c.ed0.school.trim() : '';
  const e0t = c.e0 && c.e0.title ? dcLowerFirst(c.e0.title) : '';
  const e0co = c.e0 && c.e0.company ? c.e0.company.trim() : '';
  const win = dcFirstLine(c.e0 && c.e0.desc).replace(/[.;]+$/,'');
  const skillTxt = c.skills.length ? dcList(c.skills) : '';
  const why = dcSentence(d.job.why);
  const avail = (d.job.availability||'').trim();
  const out = [];

  // Qualités mises en avant (neutres en genre, pour éviter les erreurs d'accord)
  const qualities = dyn
    ? 'Mon énergie, mon sens de l\'initiative et ma capacité à apprendre vite sont les atouts que je mettrai à votre service.'
    : 'Rigueur, sens de l\'organisation et goût du travail en équipe sont les qualités que je mettrai à votre service.';

  if(d.type==='lettre' || d.type==='spontanee'){
    // 1. Accroche
    let a;
    if(d.type==='spontanee'){
      a = 'Même si aucune offre n\'est actuellement publiée'+(co?' par '+co:'')+', je me permets de vous adresser ma candidature spontanée'+(poste?' pour un poste de '+posteL:'')+'.';
    } else if(v===1){
      a = 'C\'est avec un vif intérêt que je me porte '+dcAg('candidat')+' au poste de '+(posteL||'…')+atCo+(src?', publié '+src:'')+'.';
    } else if(v===2){
      a = 'Votre '+(src?'annonce '+src:'offre')+' pour le poste de '+(posteL||'…')+atCo+' a immédiatement retenu mon attention, et je souhaite vous proposer ma candidature.';
    } else {
      a = (src?'Suite à votre annonce '+src+', j':'J')+'e vous adresse ma candidature pour le poste de '+(posteL||'…')+atCo+'.';
    }
    if(degree) a += ' Titulaire de la formation '+degree+(school?' ('+school+')':'')+', je souhaite mettre mes compétences au service '+(co?dcDe(co):'de votre équipe')+'.';
    out.push(a);
    // 2. Parcours
    let b = '';
    if(e0t){
      b = (yearsTxt ? 'Avec '+yearsTxt+', j' : 'J')+'\'ai notamment occupé le poste de '+e0t+(e0co?' chez '+e0co:'')+'.';
      if(win) b += ' Parmi mes réalisations : '+dcLowerFirst(win)+'.';
    } else if(degree){
      b = 'Ma formation '+degree+(school?' à '+school:'')+' m\'a permis d\'acquérir des bases solides que je suis prêt'+(dcGender()==='F'?'e':dcGender()==='M'?'':'(e)')+' à mettre en pratique.';
    }
    if(skillTxt) b += (b?' ':'')+'Mes compétences ('+skillTxt+') me permettent de répondre efficacement aux exigences du poste.';
    if(b) out.push(b);
    // 3. Motivation
    let m = why ? why+' ' : (co ? 'Rejoindre '+co+' représente pour moi une réelle opportunité de contribuer à vos objectifs. ' : '');
    m += qualities;
    out.push(m);
    // 4. Conclusion
    out.push('Disponible '+(avail||'rapidement')+', je reste à votre entière disposition pour un entretien, afin de vous exposer plus en détail ma motivation et la valeur que je peux apporter à votre structure.');
  }

  else if(d.type==='emploi'){
    out.push('J\'ai l\'honneur de solliciter auprès de vous un emploi '+(poste?'en qualité de '+posteL:'correspondant à mon profil')+atCo+'.');
    let b = degree ? 'Titulaire de la formation '+degree+(school?' ('+school+')':'')+', ' : '';
    b += yearsTxt ? (b?'je justifie':'Je justifie')+' de '+yearsTxt : (b?'je dispose':'Je dispose')+' d\'une solide formation';
    b += e0t ? ', notamment en tant que '+e0t+(e0co?' chez '+e0co:'')+'.' : '.';
    if(skillTxt) b += ' Mes compétences clés : '+skillTxt+'.';
    out.push(b);
    out.push((why?why+' ':'')+qualities);
    out.push('Je suis disposé'+(dcGender()==='F'?'e':dcGender()==='M'?'':'(e)')+' à occuper ce poste '+(avail||'dans les meilleurs délais')+' et à me soumettre à tout test ou entretien que vous jugerez utile.');
  }

  else if(d.type==='stage'){
    const who = degree ? 'Actuellement en formation '+degree+(school?' ('+school+')':'')+', j' : dcAg('Étudiant')+', j';
    out.push(who+'\'ai l\'honneur de solliciter un stage'+(poste?' en lien avec « '+poste+' »':'')+(d.job.duration?' d\'une durée de '+d.job.duration:'')+(d.job.start?', à compter de '+d.job.start:'')+atCo+'.');
    let b = 'Ce stage me permettrait de mettre en pratique mes acquis théoriques, de découvrir le monde professionnel et de renforcer mes compétences'+(skillTxt?' ('+skillTxt+')':'')+'.';
    if(e0t) b += ' Mon expérience en tant que '+e0t+(e0co?' chez '+e0co:'')+' m\'a déjà permis de me familiariser avec les exigences du terrain.';
    out.push(b);
    out.push((why?why+' ':'')+(dyn ? 'Curiosité, énergie et envie d\'apprendre sont les atouts que je mettrai au service de votre équipe.' : 'Curiosité, rigueur et envie d\'apprendre sont les atouts que je mettrai au service de votre équipe.'));
    out.push('Je me tiens à votre disposition pour un entretien'+(avail?' et suis disponible '+avail:'')+'.');
  }
  return out;
}
// Régénère l'objet et le texte tant que l'utilisateur ne les a pas modifiés à la main
function dcRegen(d, force){
  if(force || d.auto.object) d.object = dcObject(d);
  if(force || d.auto.body)   d.body = dcCompose(d);
}
function dcClosingText(d){
  const base = (d.recipient.salutation||'Madame, Monsieur,').replace(/[,\s]+$/,'');
  const cl = DOC_CLOSINGS[d.closingId] || DOC_CLOSINGS.distinguees;
  const lead = d.type==='lettre' || d.type==='spontanee' ? 'Dans l\'attente de votre réponse, ' : 'Dans l\'attente d\'une suite favorable à ma demande, ';
  return dcUpperFirst(lead + cl.f(base));
}

/* ---------------- Rendu HTML (écran, impression, Word) ---------------- */
function dcFontStack(d, tpl){
  if(d.font && d.font!=='auto' && DOC_FONTS[d.font]) return DOC_FONTS[d.font];
  return tpl==='classic' ? DOC_FONTS.georgia : DOC_FONTS.inter;
}
function dcLines(arr){ return arr.filter(function(x){ return x && String(x).trim(); }).map(function(x){ return esc(String(x).trim()); }).join('<br>'); }
function dcContactLine(s, sep){ return [s.phone, s.email, s.address].filter(function(x){ return x && String(x).trim(); }).map(esc).join(sep||' &nbsp;·&nbsp; '); }

function dcRecipientBlock(d, align){
  const r = d.recipient;
  const lines = [r.name, r.title, r.org, r.address];
  const html = dcLines(lines);
  return html ? '<div style="text-align:'+align+';line-height:1.5">'+html+'</div>' : '';
}
function dcHeader(d, ac){
  const s = d.sender, tpl = d.template;
  const contact = dcContactLine(s);
  if(tpl==='band'){
    return '<table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin:-56px -64px 26px -64px;width:calc(100% + 128px)"><tr><td bgcolor="'+ac+'" style="background:'+ac+';color:#fff;padding:34px 64px 26px 64px">'
      + '<div style="font-size:26px;font-weight:700;letter-spacing:.2px;line-height:1.2;color:#fff">'+esc(s.name)+'</div>'
      + (s.role ? '<div style="font-size:12.5px;letter-spacing:1.6px;text-transform:uppercase;margin-top:5px;color:#fff;opacity:.92">'+esc(s.role)+'</div>' : '')
      + (contact ? '<div style="font-size:12.5px;margin-top:12px;color:#fff;opacity:.95">'+contact+'</div>' : '')
      + '</td></tr></table>';
  }
  if(tpl==='modern'){
    return '<table width="100%" cellpadding="0" cellspacing="0" style="border-collapse:collapse;margin-bottom:26px"><tr>'
      + '<td width="5" bgcolor="'+ac+'" style="background:'+ac+';width:5px"></td><td style="padding:2px 0 2px 16px">'
      + '<div style="font-size:25px;font-weight:700;color:'+ac+';line-height:1.2">'+esc(s.name)+'</div>'
      + (s.role ? '<div style="font-size:13px;color:#4B5563;margin-top:3px;letter-spacing:.4px">'+esc(s.role)+'</div>' : '')
      + (contact ? '<div style="font-size:12.5px;color:#4B5563;margin-top:9px">'+contact+'</div>' : '')
      + '</td></tr></table>';
  }
  if(tpl==='minimal'){
    return '<div style="margin-bottom:26px;padding-bottom:14px;border-bottom:1px solid #D1D5DB">'
      + '<div style="font-size:14px;letter-spacing:3.5px;text-transform:uppercase;font-weight:600;color:#111827">'+esc(s.name)+'</div>'
      + (s.role ? '<div style="font-size:12.5px;color:#6B7280;margin-top:4px">'+esc(s.role)+'</div>' : '')
      + (contact ? '<div style="font-size:12px;color:#6B7280;margin-top:8px">'+contact+'</div>' : '')
      + '</div>';
  }
  // classic : bloc expéditeur simple en haut à gauche
  return '<div style="margin-bottom:22px;line-height:1.5"><b style="font-size:1.05em">'+esc(s.name)+'</b>'
    + (dcLines([s.role, s.address, s.phone, s.email]) ? '<br>'+dcLines([s.role, s.address, s.phone, s.email]) : '')
    + '</div>';
}

// mode : 'screen' | 'print' | 'word'
function dcRender(d, mode){
  mode = mode || 'screen';
  const tpl = d.template || 'classic', ac = d.accent || '#2563EB';
  const fs = DOC_SIZES[d.size] || 15, ff = dcFontStack(d, tpl);
  const dateStr = esc(dcDateFR(d.date, d.place));
  const rec = dcRecipientBlock(d, tpl==='minimal' ? 'left' : 'right');
  const recipientAndDate =
      '<div style="text-align:'+(tpl==='minimal'?'left':'right')+';margin-bottom:'+(rec?'6':'22')+'px;color:#374151">'+dateStr+'</div>'
    + (rec ? '<div style="margin-bottom:22px">'+rec+'</div>' : '');
  const objectHtml = d.object ? '<div style="margin:0 0 18px 0"><b>Objet'+NB+':</b> <b>'+esc(d.object)+'</b></div>' : '';
  const salut = '<div style="margin-bottom:14px">'+esc(d.recipient.salutation||'')+'</div>';
  const paras = (d.body||[]).filter(function(x){ return x && x.trim(); }).map(function(p){
    return '<p style="margin:0 0 12px 0;text-align:justify">'+esc(p.trim()).replace(/\n/g,'<br>')+'</p>';
  }).join('');
  const closing = '<p style="margin:16px 0 0 0;text-align:justify">'+esc(dcClosingText(d))+'</p>';
  const sign = d.signature && d.signature.trim()
    ? '<div style="margin-top:30px;text-align:right"><b style="color:'+((tpl==='minimal'||tpl==='classic')?'#111827':ac)+'">'+esc(d.signature.trim())+'</b></div>' : '';
  const pj = d.attach ? '<div style="margin-top:28px;font-size:'+(fs-2)+'px;color:#4B5563"><b>P.'+NB+'J.'+NB+':</b> Curriculum vitae</div>' : '';
  const content = dcHeader(d, ac) + recipientAndDate + objectHtml + salut + paras
    + (mode==='word' ? closing + sign + pj : '<div style="break-inside:avoid;page-break-inside:avoid">' + closing + sign + pj + '</div>');
  const base = 'font-family:'+ff+';font-size:'+fs+'px;line-height:1.55;color:#1F2937;';

  if(mode==='word'){
    return '<div class="Section1" style="'+base+'">'+content.replace(/margin:-56px -64px 26px -64px;width:calc\(100% \+ 128px\)/,'margin:0 0 22px 0;width:100%')+'</div>';
  }
  // écran et impression : même structure (en-tête/pied répétés = marges propres sur chaque page)
  const spacer = '<div style="height:56px"></div>';
  return '<table style="'+base+'width:794px;border-collapse:collapse;background:#fff;'+(mode==='screen'?'min-height:1123px;height:1123px;':'')+'" cellpadding="0" cellspacing="0">'
    + '<thead><tr><td style="padding:0">'+spacer+'</td></tr></thead>'
    + '<tbody><tr><td style="padding:0 64px;vertical-align:top">'+content+'</td></tr></tbody>'
    + '<tfoot><tr><td style="padding:0">'+spacer+'</td></tr></tfoot></table>';
}
function dcPlainText(d){
  const lines = [];
  lines.push(dcDateFR(d.date, d.place));
  const r = d.recipient; [r.name, r.title, r.org, r.address].forEach(function(x){ if(x && x.trim()) lines.push(x.trim()); });
  lines.push('');
  if(d.object) lines.push('Objet : '+d.object, '');
  lines.push(d.recipient.salutation||'', '');
  (d.body||[]).forEach(function(p){ if(p && p.trim()) lines.push(p.trim(), ''); });
  lines.push(dcClosingText(d), '');
  if(d.signature) lines.push(d.signature.trim());
  const s = d.sender; const contact = [s.phone, s.email].filter(Boolean).join(' · ');
  if(contact) lines.push(contact);
  return lines.join('\n');
}
function dcWordCount(d){ return (d.body||[]).join(' ').trim().split(/\s+/).filter(Boolean).length; }

/* ---------------- Enregistrement (local + compte) ---------------- */
function dcLoadLocal(){
  try{ const a = JSON.parse(localStorage.getItem(DOC_KEY)||'[]'); DOCS = Array.isArray(a) ? a.filter(function(x){ return x && x.id && x.type && DOC_TYPES[x.type]; }) : []; }
  catch(e){ DOCS = []; }
}
function dcWriteLocal(){ try{ localStorage.setItem(DOC_KEY, JSON.stringify(DOCS)); }catch(e){} }
function dcDocTitle(d){
  if(d.name && d.name.trim()) return d.name.trim();
  const who = (d.recipient.org||'').trim() || (d.job.title||'').trim();
  return DOC_TYPES[d.type].label + (who ? ' — '+who : '');
}
function dcQueueSave(){
  if(!DOC) return;
  if(DOCS.indexOf(DOC)<0) DOCS.unshift(DOC);
  const ind = document.getElementById('dcSaved'); if(ind) ind.textContent = 'Enregistrement…';
  clearTimeout(docSaveTimer);
  docSaveTimer = setTimeout(function(){
    DOC.savedAt = new Date().toISOString(); dcWriteLocal();
    const i = document.getElementById('dcSaved'); if(i) i.textContent = '✓ Enregistré';
    clearTimeout(docCloudTimer); const snap = DOC; docCloudTimer = setTimeout(function(){ dcCloudSave(snap); }, 2500);
  }, 500);
}
async function dcCloudSave(d){
  if(typeof sb==='undefined' || !sb || !currentUser || !d) return;
  const payload = { kind:d.type, title:dcDocTitle(d).slice(0,200), data:d };
  try{
    if(d.cloudId){ await sb.from('documents').update(payload).eq('id',d.cloudId).eq('user_id',currentUser.id); }
    else {
      const r = await sb.from('documents').insert(Object.assign({ user_id:currentUser.id }, payload)).select('id').single();
      if(!r.error && r.data){ d.cloudId = r.data.id; dcWriteLocal(); }
    }
  }catch(e){}
}
async function dcCloudPull(){
  if(typeof sb==='undefined' || !sb || !currentUser) return;
  try{
    const r = await sb.from('documents').select('id,data,updated_at').eq('user_id',currentUser.id).eq('is_deleted',false).order('updated_at',{ascending:false}).limit(100);
    if(r.error || !r.data) return;
    r.data.forEach(function(row){
      if(!row.data || !row.data.type || !DOC_TYPES[row.data.type]) return;
      const remote = Object.assign({}, row.data, { cloudId:row.id, savedAt:row.updated_at });
      const local = DOCS.filter(function(x){ return x.cloudId===row.id; })[0];
      if(!local) DOCS.push(remote);
      else if(local!==DOC && new Date(row.updated_at) > new Date(local.savedAt||0)) Object.assign(local, remote);
    });
    dcWriteLocal(); if(docView==='home') dcRenderHome();
  }catch(e){}
}
function dcDelete(id){
  const d = DOCS.filter(function(x){ return x.id===id; })[0]; if(!d) return;
  DOCS = DOCS.filter(function(x){ return x.id!==id; }); dcWriteLocal();
  if(d.cloudId && typeof sb!=='undefined' && sb && currentUser){ try{ sb.from('documents').update({ is_deleted:true }).eq('id',d.cloudId).eq('user_id',currentUser.id).then(function(){}); }catch(e){} }
  dcRenderHome();
}
function dcDuplicate(id){
  const d = DOCS.filter(function(x){ return x.id===id; })[0]; if(!d) return;
  const c = JSON.parse(JSON.stringify(d)); c.id = dcNewId(); c.cloudId = null; c.name = (dcDocTitle(d)+' (copie)').slice(0,120); c.savedAt = new Date().toISOString();
  DOCS.unshift(c); dcWriteLocal(); dcRenderHome();
}

/* ---------------- Ouverture / navigation ---------------- */
function openDocs(type){
  if(!document.getElementById('docOverlay')) return;
  if(!DOCS.length) dcLoadLocal();
  document.getElementById('docOverlay').style.display = 'flex';
  document.body.style.overflow = 'hidden';
  if(type && DOC_TYPES[type]) dcOpenNew(type); else { dcShow('home'); dcRenderHome(); }
  dcCloudPull();
}
function closeDocs(){
  clearTimeout(docSaveTimer);
  if(DOC && DOCS.indexOf(DOC)>=0){ DOC.savedAt = new Date().toISOString(); dcWriteLocal(); dcCloudSave(DOC); }
  document.getElementById('docOverlay').style.display = 'none';
  document.body.style.overflow = '';
  DOC = null;
}
function dcShow(view){
  docView = view;
  document.getElementById('dcHome').style.display = view==='home' ? 'block' : 'none';
  document.getElementById('dcEdit').style.display = view==='edit' ? 'flex' : 'none';
  document.getElementById('dcBack').textContent = view==='edit' ? '←' : '✕';
  document.getElementById('dcTitle').textContent = view==='edit' ? (DOC ? DOC_TYPES[DOC.type].label : '') : 'Lettres & demandes';
  document.getElementById('dcSaved').textContent = '';
}
function dcBack(){
  if(docView==='edit'){
    clearTimeout(docSaveTimer);
    if(DOC && DOCS.indexOf(DOC)>=0){ DOC.savedAt = new Date().toISOString(); dcWriteLocal(); dcCloudSave(DOC); }
    DOC = null; dcShow('home'); dcRenderHome();
  } else closeDocs();
}
function dcOpenNew(type){
  DOC = dcBlank(type); docTab = 'edit';
  dcShow('edit'); dcBuildForm(); dcPreview();
  document.getElementById('dcForm').scrollTop = 0;
}
function dcOpenDoc(id){
  const d = DOCS.filter(function(x){ return x.id===id; })[0]; if(!d) return;
  DOC = d; docTab = 'edit';
  if(!DOC.auto) DOC.auto = { body:false, object:false };
  dcShow('edit'); dcBuildForm(); dcPreview();
}

/* ---------------- Accueil : types + documents enregistrés ---------------- */
function dcRenderHome(){
  const el = document.getElementById('dcHome');
  const hasCV = !!(cv.p.name || cv.exp.length || cv.edu.length);
  const cards = Object.keys(DOC_TYPES).map(function(k){
    const t = DOC_TYPES[k];
    return '<button class="dc-type" onclick="dcOpenNew(\''+k+'\')"><span class="dc-type-ic">'+t.ic+'</span><span><b>'+t.label+'</b><small>'+t.hint+'</small></span></button>';
  }).join('');
  const list = DOCS.slice().sort(function(a,b){ return new Date(b.savedAt||0)-new Date(a.savedAt||0); }).map(function(d){
    const when = new Date(d.savedAt||Date.now()).toLocaleDateString('fr-FR',{day:'2-digit',month:'short',year:'numeric'});
    return '<div class="dc-item"><div class="dc-item-ic">'+DOC_TYPES[d.type].ic+'</div>'
      + '<div class="dc-item-body"><b>'+esc(dcDocTitle(d))+'</b><span>'+when+'</span></div>'
      + '<div class="dc-item-act"><button class="dc-btn pri" onclick="dcOpenDoc(\''+d.id+'\')">Ouvrir</button>'
      + '<button class="dc-btn" onclick="dcDuplicate(\''+d.id+'\')">Dupliquer</button>'
      + '<button class="dc-btn del" onclick="appConfirm(\'Supprimer ce document ?\',function(){dcDelete(\''+d.id+'\')})">Suppr.</button></div></div>';
  }).join('');
  el.innerHTML = '<div class="dc-wrap">'
    + '<h2 class="display dc-h">Que souhaitez-vous rédiger ?</h2>'
    + '<p class="dc-sub">'+(hasCV ? 'Le texte est composé automatiquement à partir de votre CV ; vous gardez la main sur chaque phrase.' : 'Astuce : remplissez d\'abord votre CV, le texte sera alors pré-rempli à partir de vos informations.')+'</p>'
    + '<div class="dc-types">'+cards+'</div>'
    + '<h3 class="dc-h2">Mes documents</h3>'
    + (list || '<div class="dc-empty">Aucun document pour l\'instant.</div>')
    + '</div>';
}

/* ---------------- Formulaire ---------------- */
function dcGet(path){ return path.split('.').reduce(function(o,k){ return o==null ? '' : o[k]; }, DOC); }
function dcSetPath(path, val){
  const ks = path.split('.'); let o = DOC;
  for(let i=0;i<ks.length-1;i++) o = o[ks[i]];
  o[ks[ks.length-1]] = val;
}
function dcInp(label, path, o){
  o = o || {};
  const val = dcGet(path)||'';
  return '<div class="dc-f"><label>'+label+'</label>'
    + (o.area ? '<textarea rows="'+(o.rows||2)+'" maxlength="'+(o.max||300)+'" placeholder="'+esc(o.ph||'')+'" oninput="dcOnInput(\''+path+'\',this.value)">'+esc(val)+'</textarea>'
              : '<input type="'+(o.type||'text')+'" maxlength="'+(o.max||120)+'" value="'+esc(val)+'" placeholder="'+esc(o.ph||'')+'" oninput="dcOnInput(\''+path+'\',this.value)"'+(o.ac?' autocomplete="'+o.ac+'"':'')+'>')
    + (o.note ? '<small>'+o.note+'</small>' : '') + '</div>';
}
function dcSel(label, path, opts, o){
  const val = dcGet(path)||'';
  let items = opts.slice(); if(val && !items.some(function(x){ return (x.v||x)===val; })) items.push(val);
  return '<div class="dc-f"><label>'+label+'</label><select onchange="dcOnInput(\''+path+'\',this.value)">'
    + items.map(function(x){ const v = x.v!=null ? x.v : x, t = x.t!=null ? x.t : x; return '<option value="'+esc(v)+'"'+(v===val?' selected':'')+'>'+esc(t)+'</option>'; }).join('')
    + '</select></div>';
}
function dcSection(id, title, inner, open){
  return '<details class="dc-sec" '+(open?'open':'')+'><summary>'+title+'</summary><div class="dc-sec-body" id="'+id+'">'+inner+'</div></details>';
}
function dcBuildForm(){
  const d = DOC, t = d.type;
  const typeChips = Object.keys(DOC_TYPES).map(function(k){
    return '<button class="dc-chip'+(k===t?' on':'')+'" onclick="dcSetType(\''+k+'\')">'+DOC_TYPES[k].ic+' '+DOC_TYPES[k].label+'</button>';
  }).join('');
  const jobFields =
      dcInp(t==='stage' ? 'Domaine ou poste visé' : 'Poste visé', 'job.title', { ph:'Ex. Chargé de projet' })
    + dcInp('Entreprise / organisme', 'recipient.org', { ph:'Ex. Orange Digital Center', ac:'organization' })
    + (t==='lettre' ? dcInp('Référence de l\'offre (facultatif)', 'job.ref', { ph:'Ex. RH-2026-14' }) + dcInp('Où avez-vous vu l\'offre ? (facultatif)', 'job.source', { ph:'Ex. sur LinkedIn, sur Emploi.tg' }) : '')
    + (t==='stage' ? '<div class="dc-row">'+dcInp('Durée du stage', 'job.duration', { ph:'Ex. 3 mois' })+dcInp('À compter de', 'job.start', { ph:'Ex. janvier 2027' })+'</div>' : '')
    + dcInp('Pourquoi eux ? (1 phrase, facultatif)', 'job.why', { area:true, rows:2, max:260, ph:'Ex. Votre engagement pour l\'inclusion numérique correspond à mes valeurs.', note:'Une phrase personnelle rend la lettre bien plus convaincante.' })
    + '<div class="dc-row">'+dcInp('Disponibilité (facultatif)', 'job.availability', { ph:'Ex. immédiatement' })
    + dcSel('Ton', 'tone', [{v:'formel',t:'Formel et sobre'},{v:'dynamique',t:'Dynamique'}])+'</div>';
  const recFields =
      dcSel('Formule d\'appel', 'recipient.salutation', DOC_SALUTATIONS)
    + dcInp('Nom du destinataire (facultatif)', 'recipient.name', { ph:'Ex. Madame Kossi Ama' })
    + dcInp('Fonction (facultatif)', 'recipient.title', { ph:'Ex. Directrice des Ressources Humaines' })
    + dcInp('Adresse (facultatif)', 'recipient.address', { ph:'Ex. BP 1234, Lomé' });
  const sendFields =
      dcInp('Nom et prénom', 'sender.name', { ac:'name' }) + dcInp('Titre / fonction', 'sender.role', {})
    + '<div class="dc-row">'+dcInp('Téléphone', 'sender.phone', { type:'tel', ac:'tel' })+dcInp('Email', 'sender.email', { type:'email', ac:'email' })+'</div>'
    + dcInp('Adresse', 'sender.address', { ac:'street-address' })
    + '<div class="dc-row">'+dcInp('Lieu (en-tête de date)', 'place', { ph:'Ex. Lomé' })+dcInp('Date', 'date', { type:'date' })+'</div>'
    + '<button class="dc-link" onclick="dcResyncSender()">↻ Reprendre les infos de mon CV</button>';
  const styleBox =
      '<div class="dc-f"><label>Mise en page</label><div class="dc-chips" id="dcTplChips"></div></div>'
    + '<div class="dc-f"><label>Couleur</label><div class="dc-dots" id="dcAccents"></div></div>'
    + '<div class="dc-row">'+dcSel('Police', 'font', [{v:'auto',t:'Automatique'},{v:'inter',t:'Inter'},{v:'merriweather',t:'Merriweather'},{v:'poppins',t:'Poppins'},{v:'georgia',t:'Georgia'}])
    + dcSel('Taille', 'size', [{v:'small',t:'Petite'},{v:'normal',t:'Normale'},{v:'large',t:'Grande'}])+'</div>'
    + '<label class="dc-check"><input type="checkbox" '+(d.attach?'checked':'')+' onchange="dcOnInput(\'attach\',this.checked)"> Mentionner « P. J. : Curriculum vitae »</label>';
  document.getElementById('dcForm').innerHTML =
      '<div class="dc-chips dc-typebar" id="dcTypeChips">'+typeChips+'</div>'
    + '<div id="dcChecks" class="dc-checks"></div>'
    + dcSection('dcSecJob', '1 · '+(t==='stage'?'Le stage':'Le poste')+' visé', jobFields, true)
    + dcSection('dcSecRec', '2 · Destinataire', recFields, true)
    + dcSection('dcSecText', '3 · Texte', '<div id="dcBodyBox"></div>', true)
    + dcSection('dcSecSend', '4 · Vos coordonnées', sendFields, false)
    + dcSection('dcSecStyle', '5 · Style', styleBox, false)
    + '<div class="dc-f dc-namef">'+'<label>Nom du document (pour le retrouver)</label><input maxlength="120" value="'+esc(d.name||'')+'" placeholder="'+esc(dcDocTitle(d))+'" oninput="dcOnInput(\'name\',this.value)"></div>';
  dcRenderStyleBits(); dcRenderBody();
}
function dcRenderStyleBits(){
  const d = DOC;
  const tp = document.getElementById('dcTplChips');
  if(tp) tp.innerHTML = DOC_TEMPLATES.map(function(t){ return '<button class="dc-chip'+(d.template===t.id?' on':'')+'" onclick="dcOnInput(\'template\',\''+t.id+'\');dcRenderStyleBits()">'+t.name+'</button>'; }).join('');
  const ac = document.getElementById('dcAccents');
  if(ac) ac.innerHTML = DOC_ACCENTS.map(function(c){ return '<span class="dc-dot'+(d.accent===c?' on':'')+'" style="background:'+c+'" onclick="dcOnInput(\'accent\',\''+c+'\');dcRenderStyleBits()"></span>'; }).join('');
  const tc = document.getElementById('dcTypeChips');
  if(tc) tc.innerHTML = Object.keys(DOC_TYPES).map(function(k){ return '<button class="dc-chip'+(k===d.type?' on':'')+'" onclick="dcSetType(\''+k+'\')">'+DOC_TYPES[k].ic+' '+DOC_TYPES[k].label+'</button>'; }).join('');
}
function dcRenderBody(){
  const d = DOC, box = document.getElementById('dcBodyBox'); if(!box) return;
  const note = d.auto.body
    ? '<div class="dc-auto ok">✨ Texte composé depuis votre CV — il se met à jour quand vous changez le poste ou l\'entreprise. <button class="dc-link" onclick="dcNextVariant()">Autre formulation</button></div>'
    : '<div class="dc-auto">✏️ Texte modifié par vous. <button class="dc-link" onclick="dcRegenConfirm()">↻ Recomposer depuis mon CV</button></div>';
  const paras = d.body.map(function(p,i){
    return '<div class="dc-para"><textarea rows="'+Math.max(3, Math.ceil(p.length/54))+'" maxlength="900" oninput="dcOnPara('+i+',this)">'+esc(p)+'</textarea>'
      + '<div class="dc-para-act"><button title="Monter" onclick="dcMovePara('+i+',-1)"'+(i===0?' disabled':'')+'>▲</button><button title="Descendre" onclick="dcMovePara('+i+',1)"'+(i===d.body.length-1?' disabled':'')+'>▼</button><button title="Supprimer" class="del" onclick="dcDelPara('+i+')">✕</button></div></div>';
  }).join('');
  const objectF = '<div class="dc-f"><label>Objet</label><input maxlength="160" value="'+esc(d.object)+'" oninput="dcOnInput(\'object\',this.value)"></div>';
  const closeF = dcSel('Formule de politesse', 'closingId', Object.keys(DOC_CLOSINGS).map(function(k){ return { v:k, t:DOC_CLOSINGS[k].label }; }));
  box.innerHTML = note + objectF + paras
    + '<button class="btn-add" onclick="dcAddPara()">+ Ajouter un paragraphe</button>'
    + closeF + dcInp('Signature', 'signature', {});
}

/* ---------------- Événements du formulaire ---------------- */
function dcOnInput(path, val){
  dcSetPath(path, val);
  if(path==='object') DOC.auto.object = false;
  const genKeys = ['job.title','job.ref','job.source','job.why','job.duration','job.start','job.availability','recipient.org','tone'];
  if(genKeys.indexOf(path)>=0){
    const hadAutoBody = DOC.auto.body;
    dcRegen(DOC);
    if(hadAutoBody || DOC.auto.object) dcRenderBodyFieldsOnly();
  }
  if(path==='sender.name' && (!DOC.signature || DOC.signature===DOC._lastSenderName)) { DOC.signature = val; }
  if(path==='sender.name') DOC._lastSenderName = val;
  dcPreview(); dcQueueSave();
}
// Met à jour les champs de texte et l'objet sans reconstruire tout le formulaire (garde le focus)
function dcRenderBodyFieldsOnly(){
  const box = document.getElementById('dcBodyBox'); if(!box) return;
  const active = document.activeElement; const keep = active && box.contains(active);
  if(keep) return dcRenderBodyValuesOnly();
  dcRenderBody();
}
function dcRenderBodyValuesOnly(){
  const box = document.getElementById('dcBodyBox'); if(!box) return;
  const tas = box.querySelectorAll('.dc-para textarea');
  if(tas.length!==DOC.body.length){ dcRenderBody(); return; }
  tas.forEach(function(t,i){ t.value = DOC.body[i]; });
  const obj = box.querySelector('.dc-f input'); if(obj && DOC.auto.object) obj.value = DOC.object;
}
function dcOnPara(i, el){
  DOC.body[i] = el.value; DOC.auto.body = false;
  const note = document.querySelector('#dcBodyBox .dc-auto');
  if(note && note.classList.contains('ok')){ dcRenderNoteOnly(); }
  dcPreview(); dcQueueSave();
}
function dcRenderNoteOnly(){
  const note = document.querySelector('#dcBodyBox .dc-auto'); if(!note) return;
  note.className = 'dc-auto';
  note.innerHTML = '✏️ Texte modifié par vous. <button class="dc-link" onclick="dcRegenConfirm()">↻ Recomposer depuis mon CV</button>';
}
function dcAddPara(){ DOC.body.push(''); DOC.auto.body = false; dcRenderBody(); dcPreview(); dcQueueSave(); }
function dcDelPara(i){ DOC.body.splice(i,1); DOC.auto.body = false; dcRenderBody(); dcPreview(); dcQueueSave(); }
function dcMovePara(i, dir){
  const j = i+dir; if(j<0 || j>=DOC.body.length) return;
  const t = DOC.body[i]; DOC.body[i] = DOC.body[j]; DOC.body[j] = t; DOC.auto.body = false;
  dcRenderBody(); dcPreview(); dcQueueSave();
}
function dcRegenConfirm(){
  appConfirm('Remplacer votre texte par une nouvelle version composée depuis votre CV ?', function(){
    DOC.auto = { body:true, object:true }; dcRegen(DOC, true); dcRenderBody(); dcPreview(); dcQueueSave();
  });
}
function dcNextVariant(){ DOC.variant = ((DOC.variant||0)+1)%3; dcRegen(DOC); dcRenderBody(); dcPreview(); dcQueueSave(); }
function dcSetType(t){
  if(t===DOC.type) return;
  const apply = function(){
    const prevType = DOC.type; DOC.type = t; DOC.variant = 0;
    if(t==='stage' && DOC.job.title===(cv.p.role||'')) DOC.job.title = '';
    else if(prevType==='stage' && !DOC.job.title.trim()) DOC.job.title = cv.p.role||'';
    if(DOC.auto.body || DOC.auto.object){ /* textes automatiques : suivent le nouveau type */ }
    DOC.auto = { body:true, object:true }; dcRegen(DOC, true);
    dcBuildForm(); dcPreview(); dcQueueSave();
    document.getElementById('dcTitle').textContent = DOC_TYPES[t].label;
  };
  if(!DOC.auto.body) appConfirm('Changer le type remplace votre texte modifié par une nouvelle version. Continuer ?', apply); else apply();
}
function dcResyncSender(){
  const p = cv.p || {};
  DOC.sender = { name:p.name||'', role:p.role||'', address:p.address||'', phone:p.phone||'', email:p.email||'' };
  DOC.signature = p.name||''; DOC._lastSenderName = p.name||'';
  dcBuildForm(); dcPreview(); dcQueueSave(); toast('Coordonnées reprises depuis votre CV.');
  const sec = document.getElementById('dcSecSend'); if(sec && sec.parentElement) sec.parentElement.open = true;
}

/* ---------------- Aperçu + contrôle qualité ---------------- */
function dcPreview(){
  const page = document.getElementById('dcPage'); if(!page || !DOC) return;
  page.innerHTML = dcRender(DOC, 'screen');
  dcFitPreview(); dcRenderChecks();
}
function dcFitPreview(){
  const pane = document.getElementById('dcPrev'), wrap = document.getElementById('dcPageWrap'), page = document.getElementById('dcPage');
  if(!pane || !wrap || !page || pane.clientWidth===0) return;
  const k = Math.max(0.3, Math.min(1.15, (pane.clientWidth-28)/794));
  page.style.transformOrigin = 'top left'; page.style.transform = 'scale('+k+')';
  wrap.style.width = Math.round(794*k)+'px'; wrap.style.height = Math.round(page.offsetHeight*k)+'px';
}
window.addEventListener('resize', function(){ if(DOC) dcFitPreview(); });
function dcPages(){ const t = document.querySelector('#dcPage table'); return t ? Math.max(1, Math.ceil((t.offsetHeight-2)/1123)) : 1; }
function dcRenderChecks(){
  const el = document.getElementById('dcChecks'); if(!el) return;
  const d = DOC, words = dcWordCount(d), pages = dcPages(), items = [];
  const add = function(l, m){ items.push({ l:l, m:m }); };
  if(!d.sender.name.trim()) add('w','Indiquez votre nom (coordonnées).');
  if(!d.sender.phone.trim() && !d.sender.email.trim()) add('w','Ajoutez un téléphone ou un email pour être joignable.');
  if(!d.job.title.trim() && d.type!=='spontanee') add('w','Précisez le poste visé : le texte sera bien plus pertinent.');
  if(!d.recipient.org.trim()) add('t','Indiquez l\'entreprise : une lettre nominative marque davantage.');
  if(!d.recipient.name.trim() && d.recipient.salutation==='Madame, Monsieur,') add('t','Si possible, adressez-la à une personne nommée (« Madame Koffi, »).');
  const minW = (d.type==='lettre'||d.type==='spontanee') ? 120 : 90;
  if(words<minW) add('w','Texte court ('+words+' mots) : visez '+(minW<100?'100':'150')+' à 300 mots.');
  else if(words>330) add('w','Texte long ('+words+' mots) : visez 150 à 300 mots pour tenir sur une page.');
  if(pages>1) add('w','Le document dépasse une page ('+pages+' pages) : raccourcissez ou réduisez la taille.');
  if(!d.signature.trim()) add('w','Ajoutez votre signature (nom).');
  const warn = items.filter(function(x){ return x.l==='w'; }).length;
  const head = warn ? '<b class="warn">⚠ '+warn+' point'+(warn>1?'s':'')+' à revoir</b>' : '<b class="ok">✓ Prêt à envoyer</b>';
  el.innerHTML = '<div class="dc-checks-h">'+head+'<span>'+words+' mots · '+pages+' page'+(pages>1?'s':'')+'</span></div>'
    + (items.length ? '<ul>'+items.map(function(x){ return '<li class="'+x.l+'">'+esc(x.m)+'</li>'; }).join('')+'</ul>' : '');
  const pg = document.getElementById('dcPageInfo'); if(pg) pg.textContent = pages+' page'+(pages>1?'s':'')+' · '+words+' mots';
}
function dcTab(tab){
  docTab = tab;
  const e = document.getElementById('dcEdit'); e.setAttribute('data-tab', tab);
  document.querySelectorAll('.dc-tab').forEach(function(b){ b.classList.toggle('on', b.getAttribute('data-t')===tab); });
  if(tab==='preview') setTimeout(dcFitPreview, 30);
}

/* ---------------- Exports ---------------- */
let dcPrintRestore = null;
function dcFileBase(){ return (DOC_TYPES[DOC.type].label.split(' ')[0]+'_'+(DOC.sender.name||'CV').trim()).replace(/[^\w\-]+/g,'_'); }
function dcExportPDF(){
  if(!DOC) return;
  const area = document.getElementById('printArea'); if(!area) return;
  area.innerHTML = '<div id="cvPprint" style="width:794px">'+dcRender(DOC, 'print')+'</div>';
  window.__docPrintActive = true;
  const oldTitle = document.title; document.title = dcFileBase();
  const restore = function(){
    window.removeEventListener('afterprint', restore); document.title = oldTitle;
    if(window.__docPrintActive){ window.__docPrintActive = false; try{ renderCV(); }catch(e){} }
  };
  window.addEventListener('afterprint', restore);
  window.print();
}
function dcExportWord(){
  if(!DOC) return;
  const body = dcRender(DOC, 'word');
  const doc = '<!DOCTYPE html><html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:w="urn:schemas-microsoft-com:office:word" xmlns="http://www.w3.org/TR/REC-html40"><head><meta charset="utf-8"><title>'+esc(dcFileBase())+'</title>'
    + '<!--[if gte mso 9]><xml><w:WordDocument><w:View>Print</w:View><w:Zoom>100</w:Zoom></w:WordDocument></xml><![endif]-->'
    + '<style>@page Section1{size:595.3pt 841.9pt;margin:56pt 54pt 56pt 54pt}div.Section1{page:Section1}body{margin:0}p{margin:0 0 9pt 0}</style></head><body>'+body+'</body></html>';
  const blob = new Blob(['﻿', doc], { type:'application/msword;charset=utf-8' });
  const url = URL.createObjectURL(blob), a = document.createElement('a');
  a.href = url; a.download = dcFileBase()+'.doc';
  document.body.appendChild(a); a.click(); document.body.removeChild(a);
  setTimeout(function(){ URL.revokeObjectURL(url); }, 2000);
}
function dcCopy(){
  if(!DOC) return;
  const txt = dcPlainText(DOC);
  const done = function(){ toast('Texte copié : collez-le dans votre email.'); };
  if(navigator.clipboard && navigator.clipboard.writeText){ navigator.clipboard.writeText(txt).then(done, function(){ dcCopyFallback(txt); done(); }); }
  else { dcCopyFallback(txt); done(); }
}
function dcCopyFallback(txt){
  const ta = document.createElement('textarea'); ta.value = txt; ta.style.position='fixed'; ta.style.opacity='0';
  document.body.appendChild(ta); ta.select(); try{ document.execCommand('copy'); }catch(e){} document.body.removeChild(ta);
}

dcLoadLocal();
