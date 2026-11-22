/* CVxMaker — Assistant de contenu (100 % local, sans API ni envoi de données)
   Propose, selon le poste visé et le niveau d'expérience :
   • des profils (résumés) prêts à l'emploi, en 3 styles ;
   • des compétences adaptées au métier ;
   • des idées de missions et de réalisations, avec verbes d'action.
   Exposé : window.CareerKit */
(function (w) {
  'use strict';

  function norm(s) { return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\(e\)|\(ere\)|\(se\)|\(trice\)|\(ne\)/g, ' ').replace(/[^a-z0-9+#/ ]+/g, ' ').replace(/\s+/g, ' ').trim(); }
  function cap(s) { s = String(s || ''); return s.charAt(0).toUpperCase() + s.slice(1); }
  function low(s) { s = String(s || ''); return s.charAt(0).toLowerCase() + s.slice(1); }
  function uniq(a) { var seen = {}, o = []; a.forEach(function (x) { var k = norm(x); if (k && !seen[k]) { seen[k] = 1; o.push(x); } }); return o; }

  /* ---------- Bibliothèque de métiers ----------
     kw    : mots-clés (sans accents) qui rattachent un intitulé de poste à la famille
     pitch : ce que fait ce métier, en une expression (sert dans les profils)
     sk    : compétences ; tools : outils/logiciels ; q : qualités ; b : missions (verbe d'action en tête) */
  var FAMILIES = [
    { id: 'compta', label: 'comptabilité et finance', kw: ['compta', 'comptable', 'financ', 'tresor', 'paie', 'fiscal', 'audit', 'controleur de gestion', 'controle de gestion'],
      pitch: 'la tenue des comptes, la fiabilité des chiffres et le respect des échéances',
      sk: ['Comptabilité générale', 'Saisie et lettrage des écritures', 'Rapprochements bancaires', 'Déclarations fiscales et sociales', 'Clôture mensuelle et annuelle', 'Budgétisation', 'Reporting financier', 'Gestion de la trésorerie', 'Analyse des écarts'],
      tools: ['Microsoft Excel', 'Sage / Ciel Compta', 'SAGE 100', 'Power BI'], q: ['Rigueur', 'Sens de la confidentialité', 'Organisation'],
      b: ['Assurer la saisie, le contrôle et le lettrage des écritures comptables', 'Effectuer les rapprochements bancaires et le suivi de la trésorerie', 'Préparer les déclarations fiscales et sociales dans les délais légaux', 'Participer aux clôtures mensuelles et à l\'établissement des états financiers', 'Suivre les factures clients et fournisseurs et relancer les impayés', 'Produire des tableaux de bord et des analyses d\'écarts pour la direction'] },
    { id: 'admin', label: 'assistanat et administration', kw: ['assistant', 'secretaire', 'secretariat', 'administrati', 'accueil', 'receptionn', 'standard', 'office manager', 'agent administratif'],
      pitch: 'l\'organisation du travail d\'une équipe, la gestion administrative et la relation avec les interlocuteurs',
      sk: ['Gestion administrative', 'Gestion d\'agenda et de planning', 'Rédaction de courriers et comptes rendus', 'Classement et archivage', 'Accueil physique et téléphonique', 'Organisation de réunions et déplacements', 'Suivi des dossiers', 'Gestion des fournitures'],
      tools: ['Microsoft Word', 'Microsoft Excel', 'PowerPoint', 'Outlook'], q: ['Sens de l\'organisation', 'Discrétion', 'Réactivité'],
      b: ['Gérer l\'agenda, les rendez-vous et les déplacements de la direction', 'Accueillir les visiteurs et filtrer les appels avec courtoisie', 'Rédiger et mettre en forme courriers, notes et comptes rendus de réunion', 'Classer, archiver et assurer le suivi des dossiers administratifs', 'Préparer les réunions et diffuser les documents nécessaires', 'Suivre les commandes de fournitures et les relations avec les prestataires'] },
    { id: 'projet', label: 'gestion et coordination de projets', kw: ['projet', 'programme', 'coordinat', 'suivi evaluation', 'ong', 'chef de mission', 'planification'],
      pitch: 'le pilotage de projets, de la planification au suivi des résultats',
      sk: ['Gestion de projet', 'Planification et suivi des activités', 'Suivi-évaluation', 'Gestion budgétaire', 'Coordination d\'équipes', 'Rédaction de rapports', 'Mobilisation des parties prenantes', 'Gestion des risques', 'Montage de dossiers'],
      tools: ['Microsoft Excel', 'MS Project', 'Power BI', 'PowerPoint'], q: ['Leadership', 'Sens des priorités', 'Esprit d\'analyse'],
      b: ['Planifier les activités du projet et suivre l\'avancement par rapport au calendrier', 'Coordonner les équipes et les partenaires pour tenir les objectifs fixés', 'Suivre le budget et produire les rapports d\'activité et financiers', 'Mettre en place des indicateurs de suivi-évaluation et analyser les résultats', 'Animer les réunions de pilotage et rendre compte à la direction', 'Identifier les risques et proposer des actions correctives'] },
    { id: 'dev', label: 'développement informatique', kw: ['develop', 'logiciel', 'programm', 'web', 'mobile', 'fullstack', 'front', 'back', 'informatique', 'ingenieur logiciel', 'devops', 'reseau', 'systeme'],
      pitch: 'la conception et le développement de solutions numériques fiables',
      sk: ['Développement web', 'Conception d\'API', 'Tests et débogage', 'Bases de données', 'Versionnement avec Git', 'Méthodes agiles', 'Optimisation des performances', 'Sécurité applicative'],
      tools: ['JavaScript', 'Python', 'HTML / CSS', 'SQL', 'React', 'Git'], q: ['Esprit d\'analyse', 'Curiosité technique', 'Autonomie'],
      b: ['Concevoir et développer des fonctionnalités à partir des besoins métier', 'Écrire un code propre, testé et documenté', 'Corriger les anomalies et améliorer les performances des applications', 'Mettre en place des API et gérer les bases de données', 'Participer aux revues de code et aux rituels de l\'équipe agile', 'Assurer le déploiement et le suivi en production'] },
    { id: 'data', label: 'analyse de données', kw: ['data', 'donnee', 'statisti', 'business intelligence', 'bi ', 'analyste'],
      pitch: 'la transformation des données en décisions claires et exploitables',
      sk: ['Analyse de données', 'Visualisation et tableaux de bord', 'Nettoyage et préparation des données', 'Statistiques', 'Reporting automatisé', 'Requêtes SQL', 'Présentation des résultats'],
      tools: ['Microsoft Excel', 'Power BI', 'SQL', 'Python'], q: ['Rigueur', 'Esprit de synthèse', 'Curiosité'],
      b: ['Collecter, nettoyer et structurer les données de plusieurs sources', 'Construire des tableaux de bord pour le suivi des indicateurs clés', 'Analyser les tendances et formuler des recommandations chiffrées', 'Automatiser les rapports récurrents pour gagner du temps', 'Présenter les résultats aux équipes de façon claire et visuelle'] },
    { id: 'btp', label: 'bâtiment et génie civil', kw: ['civil', 'batiment', 'btp', 'architect', 'chantier', 'topograph', 'conducteur de travaux', 'maitre d oeuvre', 'urbanis'],
      pitch: 'la conception, le suivi de chantier et le respect des délais, des coûts et de la sécurité',
      sk: ['Suivi de chantier', 'Lecture et conception de plans', 'Métrés et estimation des coûts', 'Gestion de la sécurité sur site', 'Coordination des corps de métier', 'Contrôle qualité des travaux', 'Planification des travaux'],
      tools: ['Autocad', 'Excel', 'Revit', 'MS Project'], q: ['Sens des responsabilités', 'Rigueur', 'Capacité d\'adaptation'],
      b: ['Suivre l\'exécution des travaux et vérifier leur conformité aux plans', 'Coordonner les équipes et les sous-traitants sur le chantier', 'Établir les métrés, les devis et le suivi des coûts', 'Veiller au respect des règles de sécurité et de qualité', 'Produire les comptes rendus de chantier et le planning actualisé'] },
    { id: 'tech', label: 'maintenance et métiers techniques', kw: ['maintenance', 'technicien', 'electric', 'mecanic', 'plombier', 'soudeur', 'frigor', 'industriel', 'electrotechn', 'automatisme'],
      pitch: 'le bon fonctionnement des équipements et la sécurité des interventions',
      sk: ['Maintenance préventive et corrective', 'Diagnostic de pannes', 'Lecture de schémas techniques', 'Respect des normes de sécurité', 'Installation d\'équipements', 'Suivi des interventions', 'Gestion des pièces détachées'],
      tools: ['Autocad', 'Multimètre et outillage de diagnostic', 'GMAO'], q: ['Sens des responsabilités', 'Rigueur', 'Réactivité'],
      b: ['Réaliser la maintenance préventive et corrective des équipements', 'Diagnostiquer les pannes et rétablir rapidement le fonctionnement', 'Installer, régler et mettre en service de nouveaux équipements', 'Respecter les consignes de sécurité et tenir les rapports d\'intervention à jour', 'Suivre le stock de pièces détachées et proposer des améliorations'] },
    { id: 'sante', label: 'santé et soins', kw: ['infirm', 'medecin', 'sage femme', 'pharmac', 'sante', 'soins', 'aide soignant', 'laborantin', 'dentiste', 'kinesi'],
      pitch: 'la qualité des soins, l\'écoute des patients et le travail en équipe pluridisciplinaire',
      sk: ['Soins infirmiers', 'Accueil et écoute des patients', 'Suivi des dossiers médicaux', 'Respect des protocoles d\'hygiène', 'Éducation à la santé', 'Gestion des urgences', 'Travail en équipe pluridisciplinaire'],
      tools: ['Dossier patient informatisé', 'Microsoft Word'], q: ['Empathie', 'Sang-froid', 'Sens des responsabilités'],
      b: ['Assurer les soins et le suivi quotidien des patients selon les protocoles', 'Accueillir, écouter et informer les patients et leurs familles', 'Tenir à jour les dossiers médicaux avec rigueur et confidentialité', 'Appliquer les règles d\'hygiène et de sécurité', 'Participer aux actions de prévention et d\'éducation à la santé'] },
    { id: 'edu', label: 'enseignement et formation', kw: ['enseign', 'professeur', 'formateur', 'instituteur', 'educat', 'pedagog', 'tuteur', 'maitre'],
      pitch: 'la transmission des savoirs et la réussite des élèves ou des apprenants',
      sk: ['Pédagogie et conception de cours', 'Gestion de classe', 'Évaluation des apprentissages', 'Élaboration de fiches pédagogiques', 'Approche par compétences (APC)', 'Accompagnement individualisé', 'Communication avec les parents'],
      tools: ['Microsoft Word', 'PowerPoint', 'Outils numériques éducatifs'], q: ['Patience', 'Sens de l\'écoute', 'Créativité'],
      b: ['Préparer et animer des cours adaptés au niveau des élèves', 'Concevoir des fiches pédagogiques selon l\'approche par compétences', 'Évaluer les acquis et assurer le suivi individuel des élèves', 'Gérer le groupe-classe et favoriser un climat de travail positif', 'Échanger avec les familles et l\'équipe éducative sur les progrès des élèves'] },
    { id: 'droit', label: 'droit et juridique', kw: ['juriste', 'avocat', 'juridi', 'droit', 'notaire', 'huissier', 'conformite', 'contentieux'],
      pitch: 'la sécurité juridique, la rigueur des analyses et le conseil',
      sk: ['Analyse juridique', 'Rédaction de contrats et actes', 'Veille réglementaire', 'Droit du travail', 'Droit des affaires', 'Gestion du contentieux', 'Conseil et négociation'],
      tools: ['Microsoft Word', 'Bases de données juridiques'], q: ['Rigueur', 'Discrétion', 'Esprit de synthèse'],
      b: ['Analyser les situations juridiques et formuler des avis argumentés', 'Rédiger et relire contrats, actes et courriers juridiques', 'Assurer la veille réglementaire et alerter sur les évolutions', 'Suivre les dossiers contentieux jusqu\'à leur résolution', 'Conseiller les équipes sur les risques et la conformité'] },
    { id: 'rh', label: 'ressources humaines', kw: ['rh', 'ressources humaines', 'recrut', 'paie', 'talent', 'formation du personnel', 'gestionnaire du personnel'],
      pitch: 'le recrutement, l\'accompagnement des équipes et le respect du droit social',
      sk: ['Recrutement et sélection', 'Entretiens et évaluation des candidats', 'Administration du personnel', 'Droit du travail', 'Gestion des congés et absences', 'Plan de formation', 'Intégration des nouveaux salariés'],
      tools: ['Microsoft Excel', 'Outils de suivi des candidatures', 'Logiciel de paie'], q: ['Écoute', 'Discrétion', 'Diplomatie'],
      b: ['Rédiger les offres et mener les entretiens de recrutement', 'Gérer l\'administration du personnel : contrats, congés, absences', 'Organiser l\'intégration des nouveaux collaborateurs', 'Suivre le plan de formation et les évaluations annuelles', 'Veiller au respect de la réglementation du travail'] },
    { id: 'vente', label: 'vente et relation client', kw: ['commercial', 'vente', 'vendeu', 'client', 'business developer', 'prospect', 'chargé d\'affaires', 'charge d affaires', 'conseiller'],
      pitch: 'le développement du chiffre d\'affaires et la satisfaction des clients',
      sk: ['Prospection commerciale', 'Négociation', 'Relation client', 'Fidélisation de la clientèle', 'Suivi du portefeuille clients', 'Argumentaire de vente', 'Atteinte des objectifs', 'Reporting commercial'],
      tools: ['Microsoft Excel', 'CRM', 'PowerPoint'], q: ['Aisance relationnelle', 'Persévérance', 'Sens du service'],
      b: ['Prospecter de nouveaux clients et développer le portefeuille', 'Présenter les offres et négocier les conditions de vente', 'Assurer le suivi et la fidélisation des clients existants', 'Atteindre et dépasser les objectifs de vente mensuels', 'Rendre compte de l\'activité commerciale par des tableaux de bord réguliers', 'Traiter les réclamations avec réactivité et courtoisie'] },
    { id: 'marketing', label: 'marketing et communication', kw: ['marketing', 'communicat', 'community', 'reseaux sociaux', 'journalis', 'redact', 'graphi', 'designer', 'ui ux', 'photograph', 'video', 'monteur', 'publicit'],
      pitch: 'la création de contenus et d\'actions qui renforcent la visibilité d\'une marque',
      sk: ['Stratégie de communication', 'Création de contenus', 'Animation des réseaux sociaux', 'Rédaction et relecture', 'Marketing digital', 'Analyse des performances', 'Veille et tendances', 'Organisation d\'événements'],
      tools: ['Canva', 'Photoshop', 'Illustrator', 'Figma', 'Meta Business Suite'], q: ['Créativité', 'Sens de l\'écoute', 'Réactivité'],
      b: ['Concevoir et planifier les contenus sur les réseaux sociaux et le site web', 'Créer des visuels et supports de communication cohérents avec l\'identité de marque', 'Animer la communauté et répondre aux sollicitations des abonnés', 'Mesurer les résultats des campagnes et ajuster la stratégie', 'Organiser des événements et des actions de promotion'] },
    { id: 'logistique', label: 'logistique et transport', kw: ['logisti', 'stock', 'magasin', 'chauffeur', 'transport', 'approvision', 'livreur', 'transit', 'douane', 'cariste'],
      pitch: 'la maîtrise des flux, des stocks et des délais de livraison',
      sk: ['Gestion des stocks', 'Réception et expédition des marchandises', 'Inventaires', 'Planification des livraisons', 'Suivi des fournisseurs', 'Optimisation des coûts logistiques', 'Respect des règles de sécurité'],
      tools: ['Microsoft Excel', 'Logiciel de gestion de stock', 'Permis de conduire'], q: ['Organisation', 'Ponctualité', 'Fiabilité'],
      b: ['Réceptionner, contrôler et ranger les marchandises', 'Tenir les stocks à jour et réaliser les inventaires', 'Planifier les livraisons et optimiser les tournées', 'Suivre les commandes avec les fournisseurs et les clients', 'Réduire les ruptures et les écarts de stock'] },
    { id: 'banque', label: 'banque et assurance', kw: ['banque', 'bancaire', 'credit', 'assurance', 'microfinance', 'chargé de clientèle', 'charge de clientele', 'analyste credit'],
      pitch: 'l\'accompagnement financier des clients et la maîtrise des risques',
      sk: ['Analyse de dossiers de crédit', 'Conseil financier', 'Gestion de portefeuille clients', 'Maîtrise des risques', 'Conformité réglementaire', 'Vente de produits bancaires', 'Suivi des recouvrements'],
      tools: ['Microsoft Excel', 'Logiciel bancaire', 'Power BI'], q: ['Rigueur', 'Sens de la confidentialité', 'Sens du service'],
      b: ['Accueillir et conseiller les clients sur les produits et services', 'Instruire et analyser les dossiers de crédit', 'Suivre le portefeuille et anticiper les risques d\'impayés', 'Respecter les procédures de conformité et de lutte contre le blanchiment', 'Atteindre les objectifs de développement commercial'] },
    { id: 'direction', label: 'direction et management', kw: ['directeur', 'directrice', 'responsable', 'manager', 'general', 'chef d', 'gerant', 'superviseur', 'dg '],
      pitch: 'le pilotage d\'équipes et l\'atteinte des objectifs stratégiques',
      sk: ['Management d\'équipe', 'Pilotage de la performance', 'Définition d\'objectifs', 'Gestion budgétaire', 'Prise de décision', 'Conduite du changement', 'Reporting à la direction', 'Développement des collaborateurs'],
      tools: ['Microsoft Excel', 'PowerPoint', 'Power BI'], q: ['Leadership', 'Sens des responsabilités', 'Capacité de décision'],
      b: ['Encadrer et motiver une équipe pour atteindre les objectifs fixés', 'Définir les priorités et suivre la performance par des indicateurs', 'Gérer le budget et optimiser l\'utilisation des ressources', 'Mettre en place des procédures pour fiabiliser l\'organisation', 'Rendre compte à la direction et proposer des axes d\'amélioration'] },
    { id: 'agri', label: 'agriculture et agroalimentaire', kw: ['agron', 'agricul', 'agro', 'elevage', 'veterin', 'horticul', 'peche', 'environnement'],
      pitch: 'l\'amélioration des rendements et l\'accompagnement des producteurs',
      sk: ['Conseil agricole', 'Suivi des cultures', 'Gestion des intrants', 'Encadrement de producteurs', 'Collecte et analyse de données de terrain', 'Rédaction de rapports techniques', 'Appui aux coopératives'],
      tools: ['Microsoft Excel', 'GPS et outils de terrain'], q: ['Sens du terrain', 'Autonomie', 'Esprit d\'équipe'],
      b: ['Accompagner les producteurs dans l\'amélioration de leurs pratiques', 'Suivre les parcelles et collecter les données de production', 'Former les agriculteurs aux techniques adaptées', 'Rédiger les rapports de suivi pour les partenaires', 'Coordonner les activités de terrain avec les équipes'] },
    { id: 'qualite', label: 'qualité, hygiène et sécurité', kw: ['qualite', 'hse', 'securite', 'hygiene', 'agent de securite', 'gardien', 'controle'],
      pitch: 'le respect des normes, la prévention des risques et la sécurité des personnes et des biens',
      sk: ['Contrôle qualité', 'Prévention des risques', 'Rédaction de procédures', 'Audits internes', 'Respect des normes ISO', 'Surveillance et rondes', 'Gestion des incidents'],
      tools: ['Microsoft Excel', 'Microsoft Word'], q: ['Vigilance', 'Rigueur', 'Sang-froid'],
      b: ['Contrôler la conformité des produits, des postes et des procédures', 'Réaliser les rondes de surveillance et rédiger les rapports d\'incident', 'Sensibiliser le personnel aux consignes de sécurité', 'Mettre en place des actions correctives et suivre leur efficacité', 'Tenir à jour les registres et la documentation qualité'] },
    { id: 'resto', label: 'restauration et hôtellerie', kw: ['cuisin', 'serveu', 'restaura', 'hotel', 'barman', 'patiss', 'traiteur', 'chef de rang', 'commis'],
      pitch: 'la qualité du service, l\'hygiène et la satisfaction des clients',
      sk: ['Service en salle', 'Préparation des plats', 'Respect des normes d\'hygiène (HACCP)', 'Gestion des commandes', 'Accueil et conseil client', 'Travail sous pression', 'Gestion des stocks de cuisine'],
      tools: ['Caisse enregistreuse', 'Logiciel de réservation'], q: ['Sens du service', 'Réactivité', 'Esprit d\'équipe'],
      b: ['Accueillir les clients et prendre les commandes avec courtoisie', 'Préparer et dresser les plats dans le respect des temps et des recettes', 'Appliquer rigoureusement les règles d\'hygiène et de sécurité alimentaire', 'Gérer les stocks et limiter les pertes', 'Travailler en équipe pendant les périodes de forte affluence'] },
    { id: 'conseil', label: 'conseil et traduction', kw: ['consultant', 'conseil', 'traduct', 'interpret', 'expert'],
      pitch: 'l\'analyse des besoins et la livraison de recommandations claires et applicables',
      sk: ['Analyse des besoins', 'Rédaction de rapports et recommandations', 'Animation d\'ateliers', 'Présentation aux décideurs', 'Gestion de missions', 'Anglais professionnel', 'Recherche documentaire'],
      tools: ['Microsoft Word', 'PowerPoint', 'Microsoft Excel'], q: ['Esprit de synthèse', 'Autonomie', 'Aisance à l\'oral'],
      b: ['Analyser la situation du client et identifier ses besoins prioritaires', 'Rédiger des rapports et des recommandations opérationnelles', 'Animer des ateliers et présenter les résultats aux décideurs', 'Livrer les missions dans les délais et le budget convenus', 'Assurer le suivi après livraison et mesurer l\'impact'] },
    { id: 'stage', label: 'un premier poste', kw: ['stagiaire', 'stage', 'alternan', 'apprenti', 'etudiant', 'junior', 'volontaire', 'benevole'],
      pitch: 'l\'apprentissage rapide, la découverte du terrain et la contribution aux activités de l\'équipe',
      sk: ['Capacité d\'apprentissage', 'Travail en équipe', 'Communication', 'Organisation', 'Esprit d\'initiative', 'Microsoft Word', 'Microsoft Excel', 'Gestion du temps'],
      tools: ['Microsoft Word', 'Microsoft Excel', 'PowerPoint'], q: ['Motivation', 'Curiosité', 'Sérieux'],
      b: ['Participer aux activités quotidiennes du service et appuyer l\'équipe', 'Réaliser des recherches et préparer des synthèses pour le responsable', 'Mettre en pratique les connaissances acquises pendant la formation', 'Contribuer à la mise à jour des documents et des tableaux de suivi', 'Proposer des idées d\'amélioration à partir de mes observations'] }
  ];

  var GENERIC = { id: 'general', label: 'mon domaine', kw: [],
    pitch: 'un travail soigné, la fiabilité et le sens du résultat',
    sk: ['Communication', 'Travail en équipe', 'Gestion du temps', 'Résolution de problèmes', 'Sens de l\'organisation', 'Capacité d\'adaptation', 'Esprit d\'initiative', 'Relation client'],
    tools: ['Microsoft Word', 'Microsoft Excel', 'PowerPoint'], q: ['Sérieux', 'Motivation', 'Rigueur'],
    b: ['Assurer les missions confiées avec rigueur et dans les délais', 'Collaborer avec les équipes pour atteindre les objectifs communs', 'Suivre et mettre à jour les dossiers et documents de travail', 'Proposer des améliorations pour gagner en efficacité', 'Communiquer clairement avec les collègues, clients et partenaires'] };

  function match(text) {
    var t = ' ' + norm(text) + ' ', best = null, bestScore = 0;
    FAMILIES.forEach(function (f) {
      var s = 0;
      f.kw.forEach(function (k) { var kk = norm(k); if (kk && t.indexOf(kk) >= 0) s += kk.length; });
      if (s > bestScore) { bestScore = s; best = f; }
    });
    return best || GENERIC;
  }

  /* ---------- Contexte à partir du CV ---------- */
  function ctx(cv, role) {
    cv = cv || {}; var p = cv.p || {};
    var roleTxt = (role || p.role || (cv.exp && cv.exp[0] && cv.exp[0].title) || '').trim();
    var fam = match(roleTxt);
    var years = 0; try { years = typeof w.localYearsOfExperience === 'function' ? w.localYearsOfExperience() : 0; } catch (e) { }
    var ed = (cv.edu && cv.edu[0]) || {};
    var userSk = (cv.sk || []).map(function (s) { return s && s.name; }).filter(Boolean);
    return { role: roleTxt, fam: fam, years: years || 0, degree: (ed.degree || '').trim(), school: (ed.school || '').trim(), userSk: userSk,
      level: years >= 8 ? 'senior' : years >= 3 ? 'confirme' : years >= 1 ? 'junior' : 'debutant' };
  }
  function roleLabel(c) { return c.role ? low(c.role.replace(/\s*\((e|ère|se|trice|ne)\)/gi, '(e)')) : 'professionnel'; }
  function listFR(a) { a = a.filter(Boolean); if (a.length <= 1) return a[0] || ''; return a.slice(0, -1).join(', ') + ' et ' + a[a.length - 1]; }
  function yearsTxt(y) { return y + ' an' + (y > 1 ? 's' : ''); }

  /* ---------- Profils (résumés) ---------- */
  function summaries(cv, seed) {
    var c = ctx(cv), f = c.fam, r = roleLabel(c), n = (seed | 0);
    var skills = uniq(c.userSk.concat(f.sk)).slice(0, 3);
    var top = listFR(skills.map(low));
    var deg = c.degree ? c.degree + (c.school ? ' (' + c.school + ')' : '') : '';
    var out = [];
    var intro;
    if (c.level === 'debutant') intro = deg ? 'Jeune diplômé(e) — ' + deg + ' — ' : 'Candidat(e) motivé(e) ';
    else if (c.level === 'junior') intro = cap(r) + ' avec ' + yearsTxt(c.years) + ' d\'expérience ';
    else if (c.level === 'confirme') intro = cap(r) + ' confirmé(e), ' + yearsTxt(c.years) + ' d\'expérience ';
    else intro = cap(r) + ' expérimenté(e), plus de ' + yearsTxt(c.years) + ' d\'expérience ';

    // 1. Équilibré
    var a;
    if (c.level === 'debutant') a = intro + 'attiré(e) par ' + (c.role ? 'le métier de ' + r : f.label) + '. Sérieux(se) et rapide à apprendre, je maîtrise ' + top + '. Je souhaite mettre mon énergie et mes connaissances au service d\'une équipe, tout en progressant au contact de professionnels.';
    else a = intro + 'dans ' + (f.id === 'general' ? 'mon domaine' : 'le domaine de ' + f.label) + '. Reconnu(e) pour ' + f.pitch + '. Compétences clés : ' + top + '. Je cherche un poste où mettre cette expertise au service des objectifs de l\'équipe.';
    out.push({ style: 'Équilibré', text: a });
    // 2. Orienté résultats
    var b;
    if (c.level === 'debutant') b = (c.role ? cap(r) : 'Candidat(e)') + ' en début de parcours, motivé(e) et organisé(e). Mes atouts : ' + listFR(uniq(f.q.concat(skills.map(cap))).slice(0, 3).map(low)) + '. Prêt(e) à relever des défis et à contribuer rapidement aux résultats de l\'équipe.';
    else b = cap(r) + ' orienté(e) résultats : ' + (c.years ? yearsTxt(c.years) + ' passés à ' : 'engagé(e) pour ') + low(f.pitch) + '. Habitué(e) à travailler avec des objectifs clairs, des délais courts et un haut niveau d\'exigence. Points forts : ' + top + '.';
    out.push({ style: 'Orienté résultats', text: b });
    // 3. Court
    var s = c.level === 'debutant'
      ? cap(r) + ' motivé(e), ' + low(f.q[0]) + ' et ' + low(f.q[2] || f.q[1]) + '. Maîtrise de ' + top + '.'
      : cap(r) + (c.years ? ', ' + yearsTxt(c.years) + ' d\'expérience' : '') + ' : ' + top + '. ' + cap(low(f.q[0])) + ' et ' + low(f.q[1]) + ' au service de vos objectifs.';
    out.push({ style: 'Court et percutant', text: s });
    // rotation pour « Autres propositions »
    if (n) { for (var i = 0; i < (n % 3); i++) out.push(out.shift()); }
    return out;
  }

  /* ---------- Compétences ---------- */
  function skills(cv, role) {
    var c = ctx(cv, role), have = {}; (c.userSk || []).forEach(function (x) { have[norm(x)] = 1; });
    var all = c.fam.sk.concat(c.fam.tools).concat(c.fam.q);
    return uniq(all).filter(function (x) { return !have[norm(x)]; });
  }

  /* ---------- Missions ---------- */
  function bullets(titleOrRole, cv) {
    var f = match(titleOrRole || (cv && cv.p && cv.p.role) || '');
    return f.b.slice();
  }

  w.CareerKit = { match: match, summaries: summaries, skills: skills, bullets: bullets, context: ctx, families: FAMILIES };
})(window);
