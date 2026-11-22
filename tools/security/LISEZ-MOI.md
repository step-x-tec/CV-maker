# Tests d'attaque (reproductibles)
- `attaques-sql-*.sql` : à lancer sur une base de TEST (jamais la production) après les migrations, avec 2 utilisateurs
  `aaaaaaaa-0000-0000-0000-000000000001` et `bbbbbbbb-0000-0000-0000-000000000002` dans auth.users. Attendu : tout « BLOQUÉ ».
- `test-xss-navigateur.js` : Playwright, remplit tous les champs d'un CV avec des charges XSS et rend les 50 modèles. Attendu : `tplFail: []`.
