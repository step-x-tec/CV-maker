/* ---------------- Import d'un CV existant (PDF, Word, texte) : lecture 100 % locale ---------------- */
/* Lecture par rubriques puis par blocs datés. Aucune donnée n'est envoyée : tout se passe dans le navigateur. */
const IMP_N=function(s){ return String(s==null?'':s).toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g,'').replace(/[^a-z0-9]+/g,' ').trim(); };
/* Rubriques : expressions d'en-tête (normalisées) ; les mots suivants doivent appartenir à IMP_TAIL (ex. « compétences clés ») */
const IMP_HEADS=[
 ['cert',['formations complementaires','formation complementaire','formations continues','formation continue','autres formations','formations et certifications','certifications','certification','certificats','certificat','attestations','attestation','training','courses','stages et formations']],
 ['edu',['parcours academique','parcours scolaire','parcours universitaire','formations','formation','etudes','etude','diplomes','diplome','education','academic background','scolarite','cursus']],
 ['exp',['experiences professionnelles','experience professionnelle','work experience','work history','professional experience','employment history','employment','experiences','experience','parcours professionnel','parcours','emplois','emploi','historique professionnel']],
 ['summary',['profil professionnel','professional summary','career objective','a propos','profil','profile','resume','objectifs','objectif','presentation','summary','about me','about']],
 ['logiciel',['competences informatiques','connaissances informatiques','logiciels','logiciel','outils informatiques','outils','informatique','software','tools','technologies']],
 ['sk',['domaines de competences','savoir faire','competences','competence','skills','aptitudes','expertise','expertises']],
 ['lang',['langues etrangeres','langues','langue','languages','language']],
 ['hobby',['centres d interet','centre d interet','loisirs','loisir','hobbies','interets','interet','interests','passions','activites extra professionnelles']],
 ['quality',['qualites personnelles','savoir etre','soft skills','qualites','qualite','atouts']],
 ['award',['distinctions','distinction','awards','award','prix','recompenses']],
 ['projects',['projets','projet','projects','project','realisations']],
 ['ref',['references','reference']],
 ['pers',['informations personnelles','infos personnelles','etat civil','coordonnees','contacts','contact','identite']]
];
const IMP_TAIL=new Set('professionnel professionnelle professionnels professionnelles cle cles techniques technique academiques academique initiale initiales complementaire complementaires supplementaires personnel personnelle personnels personnelles linguistiques linguistique informatiques informatique principales principaux de du des la le les et d l a au aux moi me mes travail carriere mene menes bien extra pro divers generales scolaire universitaire cv etrangeres continue continues en'.split(' '));
const IMP_HEAD_LIST=(function(){ const l=[]; IMP_HEADS.forEach(function(h){ h[1].forEach(function(p){ l.push([h[0],p.split(' ')]); }); }); return l.sort(function(a,b){ return b[1].length-a[1].length; }); })();
function impHeading(line){
  const raw=String(line||'').trim(); if(raw.length<3||raw.length>52||/^[•\-–—*]/.test(raw)) return null;
  const t=raw.replace(/[:：]+$/,''); if(/\d{3,}|@|https?:/.test(t)) return null;
  const toks=IMP_N(t).split(' ').filter(Boolean); if(!toks.length||toks.length>7) return null;
  for(let i=0;i<IMP_HEAD_LIST.length;i++){
    const h=IMP_HEAD_LIST[i][1], k=IMP_HEAD_LIST[i][0];
    if(toks.length<h.length) continue;
    let ok=true; for(let j=0;j<h.length;j++){ if(toks[j]!==h[j]){ ok=false; break; } }
    if(!ok) continue;
    const rest=toks.slice(h.length);
    if(rest.length<=4 && rest.every(function(w){ return IMP_TAIL.has(w); })) return k;
  }
  return null;
}

/* Dates : « 25 mars 2026 – sept. 2026 », « 03/2019 - 05/2021 », « 2018 – Présent », « depuis 2021 », « 2022 » en tête de ligne */
const IMP_MON='janv(?:ier)?|f[ée]vr?(?:ier)?|mars|avr(?:il)?|mai|juin|juil(?:let)?|ao[uû]t?|sept?(?:embre)?|oct(?:obre)?|nov(?:embre)?|d[ée]c(?:embre)?|jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?';
const IMP_PT='(?:(?:0?[1-9]|[12]\\d|3[01])\\s+)?(?:(?:'+IMP_MON+')\\.?\\s+)?(?:19|20)\\d{2}|(?:0?[1-9]|1[0-2])\\s?[\\/.]\\s?(?:19|20)\\d{2}';
const IMP_END='pr[ée]sent|aujourd.?hui|actuel(?:lement)?|en cours|now|current|present|ce jour|date';
const IMP_RANGE=new RegExp('^\\s*(?:du\\s+|from\\s+)?('+IMP_PT+')\\s*(?:[-–—]|\\bà\\b|\\bau\\b|\\bto\\b|jusqu.?[àa])\\s*(?:au\\s+|to\\s+)?('+IMP_PT+'|'+IMP_END+')\\b\\.?\\s*(.*)$','i');
const IMP_SINCE=new RegExp('^\\s*(?:depuis|since)\\s+('+IMP_PT+')\\b\\s*(.*)$','i');
const IMP_YEAR1=/^\s*((?:19|20)\d{2})\b(?!\s*[-–—\/])\s*[-–—:|]?\s+(\S.*)$/;
const IMP_YEAR_ONLY=/^\s*((?:19|20)\d{2})\s*$/;
function impNormDate(s){ return String(s).replace(/\s+/g,' ').replace(/\s*\/\s*/g,'/').replace(/^\s+|\s+$/g,'').replace(new RegExp('^('+IMP_END+')$','i'),'Présent'); }
function impDateAnchor(l){
  let m=IMP_RANGE.exec(l);
  if(m) return { dates:impNormDate(m[1])+' - '+impNormDate(m[2]), rest:(m[3]||'').replace(/^[\s|·,\-–—:]+/,'').trim() };
  m=IMP_SINCE.exec(l); if(m) return { dates:impNormDate(m[1])+' - Présent', rest:(m[2]||'').replace(/^[\s|·,\-–—:]+/,'').trim() };
  m=IMP_YEAR1.exec(l); if(m) return { dates:m[1], rest:m[2].trim() };
  m=IMP_YEAR_ONLY.exec(l); if(m) return { dates:m[1], rest:'' };
  return null;
}

function impLines(raw){
  return String(raw||'').replace(/\r/g,'').replace(/[   ]/g,' ').split('\n')
    .map(function(l){ return l.replace(/[\t ]+/g,' ').trim(); }).filter(Boolean)
    .map(function(l){ return l.replace(/(\p{Ll}) - (?=\p{Ll})/gu,'$1-'); })
    .map(function(l){ return l.replace(/^[•▪●◦·▸►■□✓✔➢➤◆❖❯›*]+\s*/,'• ').replace(/^[-–—]\s+(?=\S)/,'• ').replace(/^•\s*•\s*/,'• '); });
}
const impIsB=function(l){ return l.indexOf('• ')===0; };
const impStrip=function(l){ return String(l).replace(/^•\s*/,'').trim(); };
/* Ligne qui prolonge la précédente (retour à la ligne automatique d'un PDF) */
function impCont(prev,l){
  if(!prev||!l||impIsB(l)) return false;
  const t=impStrip(l);
  if(/^[a-zà-ÿ(,;:)\-–—&]/.test(t)) return true;
  if(/[,–—&(\-]$/.test(impStrip(prev)) ) return true;
  return false;
}
/* Fusionne les lignes qui se prolongent (non datées, non-titres) */
function impMerge(arr){
  const out=[];
  arr.forEach(function(l){
    const prev=out[out.length-1];
    if(prev!==undefined && !impHeading(l) && !impDateAnchor(l) && impCont(prev,l)) out[out.length-1]=prev+' '+impStrip(l);
    else out.push(l);
  });
  return out;
}
function impLeadsToAnchor(arr,k){
  for(let j=k+1;j<=k+2&&j<arr.length;j++){
    if(impIsB(arr[j])) return false;
    const a=impDateAnchor(arr[j]); if(a) return !a.rest;
  }
  return false;
}
const IMP_SEP1=/\s+(?:[–—|@]|chez|at)\s+/i, IMP_SEP2=/\s+-\s+/;
function impSplitHead(h){
  h=String(h||'').replace(/\s+/g,' ').replace(/[\s–—|,\-:]+$/,'').replace(/^[\s–—|,\-:]+/,'').trim();
  const m=IMP_SEP1.exec(h)||IMP_SEP2.exec(h);
  if(m && m.index>2) return [h.slice(0,m.index).trim(), h.slice(m.index+m[0].length).trim()];
  const c=h.indexOf(', ');
  if(c>2){ const L=h.slice(0,c).trim(), R=h.slice(c+2).trim();
    if(/(universit|university|school|[ée]cole|institut|coll[eè]ge|lyc[ée]e|facult|academy|campus|ltd|inc\b|sarl|corp|group|bank|banque|cabinet|\bong\b|ngo)/i.test(R) || (L.split(/\s+/).length<=4 && R.split(/\s+/).length<=6 && /^[A-ZÀ-Ý]/.test(R) && !/\d/.test(R))) return [L,R]; }
  return [h,''];
}
/* Blocs « date + intitulé + puces » (expériences, formations) ; gère les dates en tête de ligne ou sur leur propre ligne */
function impBlocks(arr){
  const blocks=[]; let cur=null, pend=[];
  const newBlock=function(dates,head){ cur={dates:dates||'',head:head,bullets:[],notes:[],refs:[],mode:'head'}; blocks.push(cur); return cur; };
  for(let k=0;k<arr.length;k++){
    const l=arr[k]; const an=impDateAnchor(l);
    if(an && !impIsB(l)){ newBlock(an.dates, pend.concat(an.rest?[an.rest]:[])); pend=[]; continue; }
    if(!impIsB(l) && impLeadsToAnchor(arr,k)){ pend.push(l); continue; }
    if(!cur){ newBlock('',[impStrip(l)]); if(impIsB(l)){ cur.head=[]; cur.bullets.push(impStrip(l)); cur.mode='bul'; } continue; }
    const t=impStrip(l);
    if(impIsB(l)){ cur.bullets.push(t); cur.mode='bul'; continue; }
    if(/^r[ée]f[ée]rences?\s*:/i.test(t)){ cur.refs.push(t.replace(/^r[ée]f[ée]rences?\s*:\s*/i,'')); cur.mode='ref'; continue; }
    if(cur.mode==='ref'){ cur.refs[cur.refs.length-1]+=' '+t; continue; }
    if(cur.mode==='bul'){ cur.bullets[cur.bullets.length-1]+=' '+t; continue; }
    if(cur.mode==='head'){
      const last=cur.head.length? cur.head[cur.head.length-1] : '';
      if(cur.head.length && cur.head.length<3 && (impCont(last,t) || (last.length>=95 && t.length<60 && !/:/.test(t)))){ cur.head[cur.head.length-1]=last+' '+t; continue; }
      if(!cur.head.length){ cur.head.push(t); continue; }
      cur.notes.push(t); cur.mode='note'; continue;
    }
    // note
    if(/^[a-zà-ÿ(,;]/.test(t)) cur.notes[cur.notes.length-1]+=' '+t; else cur.notes.push(t);
  }
  return blocks;
}

/* Langues : « Français : lu, parlé, écrit – excellent Anglais : … Ewe : parlé, lu » (souvent sur une seule ligne dans un PDF) */
const IMP_LANGNAMES=['Français','Francais','Anglais','Espagnol','Portugais','Arabe','Allemand','Italien','Chinois','Mandarin','Wolof','Éwé','Ewe','Kabiyè','Kabiye','Mina','Bambara','Dioula','Lingala','Swahili','Haoussa','Hausa','Fon','Yoruba','Peul','Mooré','Moore','Kikongo','Malgache','Berbère','Russe','Japonais','Turc','Néerlandais','French','English','Spanish','Portuguese','Arabic','German','Italian','Chinese','Russian'];
function impLevel(s){
  const n=IMP_N(s);
  if(/natif|maternelle|native|mother/.test(n)) return 'Natif';
  if(/bilingue|courant|fluent|c2|c1|excellent|tres bien|parfait/.test(n)) return 'Courant';
  if(/avance|advanced|professionnel|bien\b|bon\b|good|b2/.test(n)) return 'Avancé';
  if(/intermediaire|intermediate|moyen|b1/.test(n)) return 'Intermédiaire';
  if(/debutant|beginner|a1|elementaire/.test(n)) return 'Débutant';
  if(/notion|scolaire|basic|basique|a2/.test(n)) return 'Notions';
  return '';
}
function impLangs(text){
  const out=[]; const t=String(text||'').replace(/•/g,' ');
  const re=new RegExp('(^|[\\s,;|])('+IMP_LANGNAMES.join('|')+')\\s*(?:[:(–—\\-]|\\s)','gi');
  const hits=[]; let m;
  while((m=re.exec(t))){ hits.push({name:m[2],start:m.index+m[1].length,end:re.lastIndex}); }
  if(!hits.length) return out;
  const canon={francais:'Français',ewe:'Éwé',kabiye:'Kabiyè',moore:'Mooré',french:'Français',english:'Anglais',spanish:'Espagnol',portuguese:'Portugais',arabic:'Arabe',german:'Allemand',italian:'Italien',chinese:'Chinois',russian:'Russe'};
  hits.forEach(function(h,i){
    const seg=t.slice(h.end, i+1<hits.length?hits[i+1].start:t.length).replace(/^[\s:(–—\-]+|[\s,;)\.]+$/g,'');
    const key=IMP_N(h.name);
    const name=canon[key]||(h.name.charAt(0).toUpperCase()+h.name.slice(1).toLowerCase());
    if(out.some(function(x){ return x.lang===name; })) return;
    let lv=impLevel(seg);
    if(!lv){ lv= seg ? (/^(?:lu|parl|[ée]crit|oral|read|spoken|written)/i.test(seg) ? 'Intermédiaire' : '') : ''; }
    out.push({lang:name, level:lv||'Courant'});
  });
  return out;
}

function impItems(arr,max,rej){
  const seen=new Set(), out=[];
  (arr||[]).join(',').replace(/•/g,',').split(/[,;|\n]+/).forEach(function(x){
    x=x.replace(/^[\s\-–—:]+|[\s.]+$/g,'').trim(); if(!x) return; if(x.length>45||x.split(/\s+/).length>6){ if(rej&&x.length>=8) rej(x); return; }
    const k=x.toLowerCase(); if(seen.has(k)) return; seen.add(k); if(out.length<(max||20)) out.push(x);
  });
  return out;
}
const impCap=function(s){ s=String(s||'').trim(); return s? s.charAt(0).toUpperCase()+s.slice(1) : s; };

const IMP_MONTHS={janv:1,janvier:1,fev:2,fevr:2,fevrier:2,mars:3,avr:4,avril:4,mai:5,juin:6,juil:7,juillet:7,aout:8,sept:9,sep:9,septembre:9,oct:10,octobre:10,nov:11,novembre:11,dec:12,decembre:12};
function impBirth(s){
  let m=/(\d{1,2})\s*[\/.\-]\s*(\d{1,2})\s*[\/.\-]\s*((?:19|20)\d{2})/.exec(s);
  if(m){ const d=+m[1], mo=+m[2]; if(mo>=1&&mo<=12&&d>=1&&d<=31) return m[3]+'-'+String(mo).padStart(2,'0')+'-'+String(d).padStart(2,'0'); }
  m=/(\d{1,2})\s+([A-Za-zéûè.]+)\s+((?:19|20)\d{2})/.exec(s);
  if(m){ const mo=IMP_MONTHS[IMP_N(m[2]).replace(/ /g,'')]; if(mo) return m[3]+'-'+String(mo).padStart(2,'0')+'-'+String(+m[1]).padStart(2,'0'); }
  return '';
}


/* ---- Textes « en bloc » : tout sur une seule ligne, retours à la ligne arbitraires, pas de règles ---- */
function impIsUpperTok(w){ const L=w.replace(/[^A-Za-zÀ-ÿ]/g,''); return L.length>=2 && L===L.toUpperCase(); }
function impInlineHeadings(line){
  const w=line.split(/\s+/).filter(Boolean), out=[]; let buf=[];
  const flush=function(){ if(buf.length){ out.push(buf.join(' ')); buf=[]; } };
  for(let i=0;i<w.length;){
    let hit=0;
    for(let n=Math.min(6,w.length-i);n>=1&&!hit;n--){
      const cand=w.slice(i,i+n).join(' ').replace(/^[|•·\-–—]+\s*|\s*[|•·\-–—]+$/g,'');
      const letters=cand.replace(/[^A-Za-zÀ-ÿ]/g,'');
      if(letters.length>=3 && letters===letters.toUpperCase() && impHeading(cand)) hit=n;
    }
    if(hit){ flush(); out.push('\n'+w.slice(i,i+hit).join(' ').replace(/^[|•·\-–—]+\s*|\s*[|•·\-–—]+$/g,'')+'\n'); i+=hit; }
    else { buf.push(w[i]); i++; }
  }
  flush(); return out.join(' ').replace(/ ?\n ?/g,'\n');
}
function impPrepare(raw){
  let t=String(raw||'').replace(/\r/g,'').replace(/[   ]/g,' ');
  let lines=impLines(t);
  const nStand=function(a){ return a.filter(function(l){ return impHeading(l); }).length; };
  if(nStand(lines)>=3) return {lines:lines,blob:false,first:''};
  const nl=(t.match(/\n/g)||[]).length, pipes=(t.match(/\s\|\s/g)||[]).length;
  if(pipes>=8 && nl<=3){ const l2=impLines(t.replace(/\s+\|\s+/g,'\n')); if(nStand(l2)>=3) return {lines:l2,blob:false,first:''}; }
  const first=(t.split('\n').map(function(x){ return x.trim(); }).filter(Boolean)[0])||'';
  let f=t.replace(/\s*\n+\s*/g,' ').replace(/[\t ]+/g,' ').trim();
  f=f.replace(/\s+([•▪●◦■➢➤❖])\s*/g,'\n• ').replace(/\s+(R[ée]f[ée]rences?\s*:|M[ée]moire\s*:)/g,'\n$1');
  f=f.split('\n').map(function(x){ return x.length>40? impInlineHeadings(x) : x; }).join('\n');
  return {lines:impLines(f),blob:true,first:first};
}
/* Entrées collées sur une même ligne (expériences / formations) : on coupe avant chaque période datée */
function impSplitEntries(arr,kind){
  const out=[];
  const rg=new RegExp('(^|[\\s.;:)\\]])((?:'+IMP_PT+')\\s*(?:[-–—]|\\bà\\b|\\bau\\b|\\bto\\b)\\s*(?:'+IMP_PT+'|'+IMP_END+')\\b)','gi');
  const rgB=new RegExp('(^|[\\s.;:)\\]])((?:'+IMP_PT+')\\s*(?:[-–—]|\\bà\\b|\\bau\\b|\\bto\\b)\\s*(?:'+IMP_PT+'|'+IMP_END+')\\b)(?=\\s+[A-ZÀ-ÝŒ])','gi');
  (arr||[]).forEach(function(l){
    if(l.length<110){ out.push(l); return; }
    let s=l.replace(impIsB(l)?rgB:rg,function(m,pre,rng){ return pre+'\n'+rng; });
    if(kind==='edu') s=s.replace(/([)\].])\s+((?:19|20)\d{2})\s+(?=[A-ZÀ-Ý])/g,'$1\n$2 ');
    s.split('\n').forEach(function(x){ x=x.trim(); if(x) out.push(x); });
  });
  return out;
}
/* Nom : jamais deviné. Ligne courte « Prénom NOM », ou « Prénom(s) NOM » au tout début d'un texte en bloc. */
function impNameOk(l){
  l=String(l||'').trim(); if(!l||l.length>50) return false;
  const w=l.split(/\s+/); if(w.length<2||w.length>5) return false;
  if(/[:@\d.;()]/.test(l.replace(/\b[A-ZÀ-Ý]\./g,''))) return false;
  return w.every(function(x){ return /^[A-ZÀ-ÝŒ][\p{L}'’\-]*$/u.test(x)||/^(de|du|des|la|le|van|von|ben|ould|el|al|dit)$/i.test(x); });
}
function impNameFromStart(str){
  const w=String(str||'').trim().split(/\s+/).slice(0,6); if(w.length<2) return '';
  if(!/^[A-ZÀ-ÝŒ][\p{L}'’\-]+$/u.test(w[0])||impIsUpperTok(w[0])) return '';
  let u=-1; for(let i=1;i<Math.min(4,w.length);i++){ if(impIsUpperTok(w[i])&&/^[A-ZÀ-ÝŒ'’\-]+$/.test(w[i])){ u=i; break; } if(!/^[A-ZÀ-ÝŒ][\p{L}'’\-]+$/u.test(w[i])) return ''; }
  if(u<1) return '';
  let e=u; while(e+1<w.length&&e<3&&impIsUpperTok(w[e+1])&&/^[A-ZÀ-ÝŒ'’\-]+$/.test(w[e+1])) e++;
  return w.slice(0,e+1).join(' ');
}
const IMP_SOFT=['Microsoft Word','Word','Excel','PowerPoint','Outlook','Access','Photoshop','Illustrator','InDesign','Figma','Canva','Sage','Ciel','QuickBooks','SAP','Odoo','Power BI','Tableau','SPSS','Stata','Python','SQL','AutoCAD','Jira','Trello','Slack','Notion','WordPress','Google Forms','Kobo','Zotero','ArcGIS','QGIS','Git','Docker'];

function parseCVTextCore(raw){
  const prep=impPrepare(raw), lines=prep.lines, out=blankCV(), un=[]; if(!lines.length) return out;
  const addUn=function(t,hint){ t=String(t||'').replace(/\s+/g,' ').trim(); if(t.length>=3 && t.length<=900 && un.length<30 && !un.some(function(u){ return u.t===t; })) un.push({t:t,hint:hint||''}); };
  /* 1) découpe en rubriques */
  let first=lines.findIndex(function(l){ return impHeading(l); }); if(first<0) first=lines.length;
  const head=lines.slice(0,first); const secs={}; let cur=null;
  for(let i=first;i<lines.length;i++){ const h=impHeading(lines[i]); if(h){ cur=h; secs[cur]=(secs[cur]||[]); continue; } if(cur) secs[cur].push(lines[i]); }
  /* 2) en-tête : contacts, nom, poste */
  const headTxt=head.join('\n');
  const email=(headTxt.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/)||[])[0]||((lines.join('\n').match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/)||[])[0]); if(email) out.p.email=email;
  const li=(lines.join('\n').match(/(?:https?:\/\/)?(?:[a-z]{2,3}\.)?linkedin\.com\/[^\s,;|)]+/i)||[])[0]; if(li) out.p.linkedin=li.replace(/^https?:\/\//,'').replace(/[.\/]+$/,'');
  const phones=(headTxt.match(/\+?\d[\d ().\-]{6,}\d/g)||[]).map(function(x){ return x.trim(); }).filter(function(x){ const d=x.replace(/\D/g,''); return d.length>=8&&d.length<=15&&!/^(19|20)\d{2}\s*[-–]/.test(x); });
  if(phones.length) out.p.phone=phones[0];
  const web=(headTxt.match(/(?:https?:\/\/)?(?:www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)*\.[a-z]{2,}(?:\/[^\s,;|]*)?/gi)||[]).find(function(u){ return !/linkedin|@/.test(u)&&!out.p.email.endsWith(u)&&!/gmail|yahoo|hotmail|outlook/i.test(u); });
  if(web) out.p.website=web.replace(/^https?:\/\//,'').replace(/[.\/]+$/,'');
  const isContact=function(l){ return /@|linkedin\.com|^\+?[\d ().\-]{8,}$|(?:tel|t[ée]l|mobile|email|e-mail|adresse|www\.)/i.test(l) || (/\d{2}[ .]\d{2}[ .]\d{2}/.test(l)&&/[|,]/.test(l)); };
  const body=head.filter(function(l){ return !/^(curriculum vitae|cv)$/i.test(l.trim()); });
  if(prep.blob){
    const nm0=impNameOk(prep.first)? prep.first : impNameFromStart(prep.first||head.join(' '));
    if(nm0) out.p.name=nm0;
  } else {
    let ni=body.findIndex(function(l){ return !isContact(l) && !/\d{4,}/.test(l); });
    if(ni>=0){
      const cand=body[ni].replace(/^(cv|curriculum vitae)\s*[:\-–]?\s*/i,'').trim();
      if(impNameOk(cand)){
        out.p.name=cand;
        let role=(body[ni+1]&&!isContact(body[ni+1]))?body[ni+1]:'';
        for(let j=ni+2;j<body.length&&role;j++){ const open=(role.match(/\(/g)||[]).length>(role.match(/\)/g)||[]).length; if(isContact(body[j])||!(open||impCont(role,body[j]))) break; role+=' '+body[j]; }
        role=role.replace(/\s+/g,' ').trim();
        const sp=/^(.{3,60}?)\s+[–—|]\s+(?:candidature|poste|recherche|objectif|[àa] la recherche|en recherche|stage|stagiaire)/i.exec(role);
        if(sp) role=sp[1];
        if(role.length<=90 && !/[.!?]$/.test(role)) out.p.role=role; else if(role) addUn(role,'summary');
      } else addUn(cand,'');
    }
  }
  const contactLines=head.filter(function(l){ return /[|•·]/.test(l)||/,/.test(l); }).concat(head);
  for(let j=0;j<contactLines.length&&!out.p.address;j++){
    contactLines[j].split(/\s*[|•·]\s*/).forEach(function(part){
      part=part.trim(); if(out.p.address||!part) return;
      if(/@|linkedin|www\.|https?:|\d{6,}/.test(part)||part===out.p.name||part===out.p.role) return;
      if(/^[A-Za-zÀ-ÿ' .\-]+(?:,\s*[A-Za-zÀ-ÿ' .\-]+)+$/.test(part) && part.length<60) out.p.address=part;
    });
  }
  if(!out.p.address){ const am=/([A-ZÀ-ÝŒ][\p{L}'’-]+(?: [A-ZÀ-ÝŒ][\p{L}'’-]+)?, [A-ZÀ-ÝŒ][\p{L}'’-]+)(?=\s*[|•·]|\s+\+?\d)/u.exec(headTxt); if(am) out.p.address=am[1]; }
  /* 3) résumé */
  if(secs.summary) out.p.summary=secs.summary.map(impStrip).join(' ').replace(/\s+/g,' ').trim().slice(0,900);
  /* 4) expériences */
  const refs=[];
  impBlocks(impMerge(impSplitEntries(secs.exp||[],'exp'))).forEach(function(b){
    const sp=impSplitHead(b.head.join(' ')); let desc=b.bullets.concat(b.notes).join('\n');
    if(sp[0].length>120){ if(!desc && !b.dates){ addUn(b.head.join(' '),''); return; } desc=(sp[0]+(desc?'\n'+desc:'')).slice(0,1500); sp[0]=''; }
    if(out.exp.length<15 && (sp[0]||sp[1]||desc)) out.exp.push({title:sp[0],company:sp[1].slice(0,140),dates:b.dates,loc:'',desc:desc.slice(0,1500)});
    b.refs.forEach(function(r){
      const parts=r.split(/\s+[–—]\s+/).map(function(x){ return x.trim(); }).filter(Boolean);
      const person=(parts[0]||'').split(/,\s*/);
      const contact=parts.slice(1).join(' · ');
      refs.push({name:(person[0]||'').trim(), title:person.slice(1).join(', ').trim(), company:sp[1]||'', contact:contact});
    });
  });
  /* 5) formations */
  impBlocks(impMerge(impSplitEntries(secs.edu||[],'edu'))).forEach(function(b){
    const sp=impSplitHead(b.head.join(' '));
    const desc=b.bullets.concat(b.notes).join(' ; ').slice(0,300);
    if(sp[0].length>140){ addUn(b.head.join(' '),''); return; }
    if(out.edu.length<12 && /[A-Za-zÀ-ÿ]{3}/.test(sp[0]+sp[1])) out.edu.push({degree:sp[0],school:sp[1].slice(0,160),dates:b.dates,desc:desc});
  });
  /* 6) formations complémentaires / certifications */
  (function(){
    const arr=secs.cert||[]; const hasB=arr.some(impIsB); const items=[]; let last=null;
    arr.forEach(function(l,idx){
      const t=impStrip(l);
      if(impIsB(l)||(!hasB&&!impCont(arr[idx-1],l))){ const an=impDateAnchor(t); last={text:an?an.rest:t,date:an?an.dates:''}; items.push(last); return; }
      if(last && (impCont(arr[idx-1],l) || (arr[idx-1] && impStrip(arr[idx-1]).length>=92 && t.length<45))){ last.text+=' '+t; }
      /* sinon : intitulé de groupe (ex. « Animation, approche communautaire ») ignoré */
    });
    items.forEach(function(it){
      const sp=impSplitHead(it.text); let date=it.date;
      const ym=/\(((?:19|20)\d{2})\)/.exec(it.text); if(!date&&ym) date=ym[1];
      if(it.text.length>220){ addUn(it.text,'cert'); return; }
      if(!hasB && !IMP_SEP1.test(it.text) && !it.date){ addUn(it.text,'cert'); return; }
      if(sp[0] && out.cert.length<40) out.cert.push({title:sp[0].slice(0,140),org:sp[1].slice(0,120),date:date});
    });
  })();
  /* 7) compétences / logiciels / qualités / loisirs / langues */
  const seenSk=new Set(); const addSk=function(n){ n=n.trim(); const k=n.toLowerCase(); if(!n||seenSk.has(k)||out.sk.length>=20) return; seenSk.add(k); out.sk.push({name:n,level:3}); };
  const seenLg=new Set(); const addLg=function(n){ n=n.trim().replace(/[\s.]+$/,''); const k=n.toLowerCase(); if(!n||seenLg.has(k)||out.logiciel.length>=20) return; seenLg.add(k); out.logiciel.push({name:n,level:3}); };
  impMerge(secs.sk||[]).forEach(function(l){
    const t=impStrip(l), m=/^([^:]{2,40}?)\s*:\s*(.+)$/.exec(t);
    if(m && (impIsB(l)||m[2].length>20)){
      if(/outils?|logiciels?|informatique|software|tools|technolog|bureautique/i.test(m[1])) m[2].split(/[,;]+/).forEach(addLg);
      else if(m[2].length>60 || m[2].split(',').length<3) addSk(m[1]);
      else { addSk(m[1]); }
    } else impItems([t],20,function(x){ addUn(x,'sk'); }).forEach(addSk);
  });
  impItems(secs.logiciel||[],20,function(x){ addUn(x,'logiciel'); }).forEach(addLg);
  impItems(secs.quality||[],12,function(x){ addUn(x,'quality'); }).forEach(function(x){ out.quality.push({name:impCap(x)}); });
  impItems(secs.hobby||[],12,function(x){ addUn(x,'hobby'); }).forEach(function(x){ out.hobby.push({name:impCap(x)}); });
  out.lang=impLangs((secs.lang||[]).join(' '));
  if(!out.lang.length && secs.lang) impItems(secs.lang,8).forEach(function(x){ const m=/^([A-Za-zÀ-ÿ' ]+?)\s*[:(\-–]\s*(.+?)\)?$/.exec(x); out.lang.push(m?{lang:m[1].trim(),level:impLevel(m[2])||'Courant'}:{lang:x,level:'Courant'}); });
  /* 8) distinctions, projets, références */
  impMerge(secs.award||[]).forEach(function(l){ const t=impStrip(l); if(t.length>2) out.award.push({title:t.slice(0,140),org:'',date:(/((?:19|20)\d{2})/.exec(t)||[])[1]||'',desc:''}); });
  impMerge(secs.projects||[]).forEach(function(l){ const t=impStrip(l); const m=/^(.{3,80}?)\s*(?::|\s[–—]\s)\s*(.+)$/.exec(t); out.projects.push(m?{title:m[1].trim(),desc:m[2].trim()}:{title:t.slice(0,120),desc:''}); });
  (secs.ref||[]).forEach(function(l){ const t=impStrip(l); if(/@|\d{6,}/.test(t)){ const parts=t.split(/\s+[–—|]\s+/); out.ref.push({name:(parts[0]||'').split(/,\s*/)[0],title:(parts[0]||'').split(/,\s*/).slice(1).join(', '),company:'',contact:parts.slice(1).join(' · ')}); } });
  refs.forEach(function(r){ if(r.name && out.ref.length<5) out.ref.push(r); });
  /* 9) état civil : uniquement dans l'en-tête, la rubrique « informations personnelles » ou une ligne qui l'annonce */
  const all=lines.join('\n');
  const pers=head.join('\n')+'\n'+(secs.pers||[]).join('\n')+'\n'+lines.filter(function(l){ return /situation|[ée]tat civil|nationalit|permis|n[ée]e? le/i.test(l); }).join('\n');
  const bm=/N[ée]e?(?:\(e\))?\s+le\s+([^\n|,;]+?)(?:\s+[àa]\s+([A-ZÀ-Ý][\p{L}' \-]+))?(?=\s*[|,;\n]|$)/iu.exec(all);
  if(bm){ const bd=impBirth(bm[1]); if(bd){ out.ec.birthDate=bd; if(bm[2]) out.ec.birthPlace=bm[2].trim(); } }
  const nm=/Nationalit[ée]\s*[:\-]\s*([A-Za-zÀ-ÿ\-]+(?:\s*\([^)]*\))?)/i.exec(pers); if(nm) out.ec.nationality=impCap(nm[1].trim());
  const ms=/\b(c[ée]libataire|mari[ée](?:\(e\))?|divorc[ée](?:\(e\))?|veu[fv]e?)\b/i.exec(pers);
  if(ms){ const v=IMP_N(ms[1]); out.ec.marital=/^celib/.test(v)?'Célibataire':/^mari/.test(v)?'Marié(e)':/^divorc/.test(v)?'Divorcé(e)':'Veuf(ve)'; }
  const pm=/Permis(?:\s+de\s+conduire)?\s*(?::|cat[ée]gorie|cat\.)?\s*([A-D](?:\s*(?:,|et|\/)\s*[A-D])*)\b/i.exec(pers);
  if(pm){ const c=pm[1].toUpperCase().replace(/\s*(,|\/)\s*/g,',').replace(/\s*ET\s*/g,','); const cand={ 'A':'Permis A','B':'Permis B','C':'Permis C','D':'Permis D','A,B':'Permis A et B' }[c]; if(cand) out.ec.license=cand; }
  (secs.pers||[]).forEach(function(l){ const t=impStrip(l); if(!/@|linkedin|nationalit|n[ée]e? le|c[ée]libataire|mari[ée]|divorc|veu[fv]|permis|^\+?[\d ().\-]{8,}$|t[ée]l|adresse/i.test(t)) addUn(t,''); });
  /* 10) secours pour un texte sans rubriques : langues avec niveau explicite, logiciels cités en liste */
  if(!out.lang.length){
    const lm=new RegExp('('+IMP_LANGNAMES.join('|')+')\\s*(?::|\\()\\s*([^,;|•\\n)]{2,40})','gi'); let m2; const seenL=new Set();
    while((m2=lm.exec(all))){ const lv=impLevel(m2[2]); const nm2=impLangs(m2[1]+' : '+m2[2])[0]; if(lv && nm2 && !seenL.has(nm2.lang)){ seenL.add(nm2.lang); out.lang.push({lang:nm2.lang,level:lv}); } }
  }
  if(!out.logiciel.length){
    const found=IMP_SOFT.filter(function(w){ return new RegExp('(^|[^\\p{L}])'+w.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+'(?![\\p{L}])','u').test(all); });
    const uniq=found.filter(function(w){ return !(w==='Word'&&found.indexOf('Microsoft Word')>=0); });
    if(uniq.length>=3) uniq.slice(0,12).forEach(function(w){ out.logiciel.push({name:w,level:3}); });
  }
  /* 11) texte sans aucune rubrique reconnue : rien n'est deviné, on propose le texte à classer */
  if(!out.p.summary && !out.exp.length && !out.edu.length && !out.cert.length && !out.sk.length && lines.length){
    const rest=lines.map(impStrip).join(' ').replace(/\s+/g,' ').trim(); if(rest.length>=40) addUn(rest.slice(0,900),'summary');
  }
  out.__un=un;
  return out;
}

/* Ne casse jamais l'import : en cas d'erreur inattendue, on rend au moins les coordonnées sûres. */
function parseCVText(raw){
  try{ return parseCVTextCore(raw); }
  catch(e){
    try{ console.warn('[CVxMaker] import', e); }catch(_){}
    const o=blankCV(), t=String(raw||'');
    const em=t.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/); if(em) o.p.email=em[0];
    o.__un=[{t:t.replace(/\s+/g,' ').trim().slice(0,900),hint:'summary'}];
    return o;
  }
}

async function impReadFile(file){
  if(file && file.size>8*1024*1024) throw new Error('FICHIER_TROP_GROS');   // 8 Mo max : évite de figer le navigateur
  const n=(file.name||'').toLowerCase();
  if(n.endsWith('.txt')||file.type==='text/plain') return await file.text();
  const load=(src)=>new Promise((res,rej)=>{ const s=document.createElement('script'); s.src=src; s.onload=res; s.onerror=()=>rej(new Error('network')); document.head.appendChild(s); });
  if(n.endsWith('.pdf')){
    if(!window.pdfjsLib){ await load('/vendor/pdf.min.js'); window.pdfjsLib.GlobalWorkerOptions.workerSrc='/vendor/pdf.worker.min.js'; }
    const pdf=await window.pdfjsLib.getDocument({data:await file.arrayBuffer()}).promise; let txt='';
    for(let p=1;p<=Math.min(pdf.numPages,4);p++){ const c=await (await pdf.getPage(p)).getTextContent(); let y=null,line='';
      c.items.forEach(it=>{ const yy=Math.round(it.transform[5]); if(y!==null && Math.abs(yy-y)>3){ txt+=line.trim()+'\n'; line=''; } y=yy; line+=it.str+' '; }); txt+=line.trim()+'\n'; }
    return txt;
  }
  if(n.endsWith('.docx')){
    if(!window.mammoth) await load('/vendor/mammoth.browser.min.js');
    return (await window.mammoth.extractRawText({arrayBuffer:await file.arrayBuffer()})).value;
  }
  throw new Error('format');
}
function openCvImport(){
  let o=document.getElementById('impOverlay'); if(o) o.remove();
  o=document.createElement('div'); o.id='impOverlay';
  o.style.cssText='position:fixed;inset:0;z-index:9000;background:rgba(15,23,42,.55);display:flex;align-items:flex-end;justify-content:center';
  o.innerHTML='<div role="dialog" aria-label="Importer un CV" style="background:#fff;width:min(560px,100%);max-height:92vh;overflow:auto;border-radius:18px 18px 0 0;padding:18px 18px 24px;box-sizing:border-box">'
   +'<div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px"><b style="font-size:16px">Importer mon CV existant</b><button onclick="document.getElementById(\'impOverlay\').remove()" style="border:0;background:#F1F5F9;border-radius:99px;width:32px;height:32px;font-size:16px" aria-label="Fermer">✕</button></div>'
   +'<div style="font-size:12px;color:#64748B;margin-bottom:10px">Choisissez un fichier PDF, Word ou texte, ou collez le contenu. La lecture se fait sur votre appareil : votre fichier n\'est envoyé nulle part. Vous pourrez tout corriger ensuite.</div>'
   +'<label style="display:block;border:2px dashed #CBD5E1;border-radius:12px;padding:16px;text-align:center;font-weight:700;font-size:14px;cursor:pointer">📄 Choisir un fichier<input id="impFile" type="file" accept=".pdf,.docx,.txt,text/plain,application/pdf" style="display:none" onchange="impFromFile(this.files[0])"></label>'
   +'<div style="text-align:center;font-size:12px;color:#94A3B8;margin:8px 0">ou</div>'
   +'<textarea id="impText" rows="6" placeholder="Collez ici le texte de votre CV…" style="width:100%;box-sizing:border-box;border:1.5px solid #CBD5E1;border-radius:12px;padding:10px;font:14px/1.4 inherit;resize:vertical"></textarea>'
   +'<button onclick="impAnalyze(document.getElementById(\'impText\').value)" style="margin-top:10px;width:100%;background:var(--accent);color:#fff;border:0;border-radius:12px;padding:13px;font-weight:700;font-size:15px">Lire ce texte</button>'
   +'<div id="impOut" style="margin-top:14px"></div></div>';
  o.addEventListener('click',e=>{ if(e.target===o) o.remove(); });
  document.body.appendChild(o);
}
async function impFromFile(f){
  if(!f) return; const out=document.getElementById('impOut');
  if(f.size>8*1024*1024){ out.innerHTML='<div style="color:#B45309;font-size:13px">Ce fichier est trop volumineux (8 Mo maximum).</div>'; return; }
  out.innerHTML='<div style="font-size:13px;color:#64748B">Lecture du fichier…</div>';
  try{ const t=await impReadFile(f); if(!t||t.trim().length<40) throw new Error('empty'); document.getElementById('impText').value=t; impAnalyze(t); }
  catch(e){ const m=String(e&&e.message); out.innerHTML='<div style="color:#B45309;font-size:13px">'+(m==='network'?'Impossible de charger le lecteur de fichiers (connexion). Collez plutôt le texte de votre CV ci-dessus.':m==='format'?'Format non pris en charge. Utilisez un PDF, un fichier Word (.docx) ou du texte.':'Aucun texte lisible dans ce fichier (PDF scanné ?). Collez plutôt le texte de votre CV ci-dessus.')+'</div>'; }
}
function impAnalyze(t){
  const out=document.getElementById('impOut'); if(!t||t.trim().length<40){ out.innerHTML='<div style="color:#B45309;font-size:13px">Collez le contenu de votre CV (quelques lignes au minimum).</div>'; return; }
  const r=parseCVText(t); window.__impCV=r;
  const row=(a,b)=>'<div style="display:flex;gap:8px;font-size:13px;padding:4px 0;border-bottom:1px solid #F1F5F9"><span style="width:96px;color:#64748B;flex-shrink:0">'+a+'</span><b style="word-break:break-word">'+(b?esc(b):'<span style="color:#B45309;font-weight:600">non trouvé</span>')+'</b></div>';
  out.innerHTML='<div style="font-weight:800;font-size:14px;margin-bottom:6px">Ce que nous avons reconnu</div>'
   +row('Nom',r.p.name)+row('Poste visé',r.p.role)+row('Email',r.p.email)+row('Téléphone',r.p.phone)+row('Résumé',r.p.summary?r.p.summary.slice(0,90)+'…':'')
   +row('Expériences',r.exp.length?r.exp.length+' ('+r.exp.map(e=>e.title).filter(Boolean).slice(0,2).join(', ')+')':'')+row('Formations',r.edu.length?r.edu.length+' ('+r.edu.map(e=>e.degree).filter(Boolean).slice(0,2).join(', ')+')':'')+row('Certifications',r.cert.length?String(r.cert.length):'')+row('Compétences',r.sk.length?r.sk.length+' ('+r.sk.slice(0,3).map(s=>s.name).join(', ')+'…)':'')+row('Logiciels',r.logiciel.length?r.logiciel.length+' ('+r.logiciel.slice(0,3).map(s=>s.name).join(', ')+'…)':'')+row('Langues',r.lang.length?r.lang.map(l=>l.lang).join(', '):'')+row('Loisirs',r.hobby.length?r.hobby.map(h=>h.name).join(', '):'')+row('Références',r.ref.length?String(r.ref.length):'')
   +impUnHTML(r)
   +'<div style="font-size:11.5px;color:#64748B;margin:8px 0">Nous ne devinons rien : ce qui n\'est pas sûr reste vide ou « à classer ». Relisez chaque étape après l\'import.</div>'
   +'<button onclick="impApply()" style="width:100%;background:#059669;color:#fff;border:0;border-radius:12px;padding:13px;font-weight:700;font-size:15px">Utiliser ces informations</button>';
}
const IMP_UN_OPTS=[['','Ne pas utiliser'],['summary','Résumé du profil'],['sk','Compétence'],['logiciel','Logiciel'],['hobby','Loisir'],['quality','Qualité'],['cert','Certification / formation']];
function impUnHTML(r){
  const un=(r&&r.__un)||[]; if(!un.length) return '';
  return '<div style="margin:12px 0 4px;padding:10px;border:1.5px dashed #F59E0B;border-radius:12px;background:#FFFBEB"><div style="font-weight:800;font-size:13px;margin-bottom:2px">À classer ('+un.length+')</div><div style="font-size:11.5px;color:#92400E;margin-bottom:8px">Ces passages n\'ont pas pu être rangés avec certitude. Choisissez où les mettre, ou laissez « Ne pas utiliser ».</div>'
   +un.map(function(u,i){ return '<div style="margin-bottom:8px"><div style="font-size:12px;word-break:break-word;margin-bottom:3px">'+esc(u.t.length>160?u.t.slice(0,160)+'…':u.t)+'</div><select data-imp-un="'+i+'" style="width:100%;padding:7px;border:1px solid #CBD5E1;border-radius:8px;font-size:12.5px">'+IMP_UN_OPTS.map(function(o){ return '<option value="'+o[0]+'">'+o[1]+'</option>'; }).join('')+'</select></div>'; }).join('')+'</div>';
}
function impPlaceUnassigned(r){
  const un=(r&&r.__un)||[]; const sels=document.querySelectorAll('select[data-imp-un]');
  sels.forEach(function(sel){
    const u=un[+sel.getAttribute('data-imp-un')]; const k=sel.value; if(!u||!k) return;
    const t=u.t.trim();
    if(k==='summary') r.p.summary=((r.p.summary?r.p.summary+' ':'')+t).slice(0,1200);
    else if(k==='sk') r.sk.push({name:t.slice(0,60),level:3});
    else if(k==='logiciel') r.logiciel.push({name:t.slice(0,60),level:3});
    else if(k==='hobby') r.hobby.push({name:t.slice(0,60)});
    else if(k==='quality') r.quality.push({name:t.slice(0,60)});
    else if(k==='cert') r.cert.push({title:t.slice(0,140),org:'',date:''});
  });
  delete r.__un;
}
function impApply(){
  const r=window.__impCV; if(!r) return;
  impPlaceUnassigned(r);
  const go=function(){ cv=r; onChange(); renderForm(); renderCV(); const o=document.getElementById('impOverlay'); if(o) o.remove(); toast('CV importé. Relisez chaque étape.'); cvxTrack('cv_import',{}); };
  const has=cv.p.name||cv.exp.length||cv.edu.length;
  if(has) appConfirm('Remplacer le CV en cours par le CV importé ?',go); else go();
}

