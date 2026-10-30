# E-mails CVxMaker — mise en place

Six modèles en français, aux couleurs de CVxMaker : mise en page compatible Gmail / Outlook / Apple Mail, lisible sur mobile, bouton + lien de secours, texte de prévisualisation, mode sombre désactivé (les couleurs restent celles de la marque).

**Aperçu :** ouvrez `preview.html` dans un navigateur (onglets, bascule mobile/ordinateur).

## 1. Coller les modèles dans Supabase
Supabase → **Authentication → Emails → Templates**. Pour chaque ligne : remplacez l'**objet** et le **corps** (mode « Source »/HTML) par le contenu du fichier.

| Onglet Supabase | Fichier | Objet |
|---|---|---|
| Confirm signup | `confirmation.html` | Confirmez votre adresse e-mail — CVxMaker |
| Reset password | `recovery.html` | Réinitialisez votre mot de passe CVxMaker |
| Magic link | `magic_link.html` | Votre lien de connexion CVxMaker |
| Change email address | `email_change.html` | Confirmez votre nouvelle adresse e-mail — CVxMaker |
| Invite user | `invite.html` | Vous êtes invité(e) sur CVxMaker |
| Reauthentication | `reauthentication.html` | Votre code de vérification CVxMaker |

Les variables entre accolades (`{{ .ConfirmationURL }}`, `{{ .SiteURL }}`, `{{ .Email }}`, `{{ .NewEmail }}`, `{{ .Token }}`) sont remplies par Supabase : ne les modifiez pas.

## 2. Réglages indispensables (sinon les liens ou le logo ne marchent pas)
- **Authentication → URL Configuration** : *Site URL* = l'adresse publique (ex. `https://cvxmaker.netlify.app`). Le logo des e-mails est lu à `{{ .SiteURL }}/icons/icon-192.png`. Ajoutez la même adresse dans *Redirect URLs*.
- **Expéditeur et envoi (SMTP personnalisé)** : l'envoi intégré de Supabase est limité à quelques e-mails par heure et arrive souvent en spam. Authentication → **SMTP Settings** : renseignez Brevo, Resend, Mailjet… avec un nom d'expéditeur « CVxMaker » et une adresse sur **votre domaine**.
- **Délivrabilité** : sur ce domaine, ajoutez les enregistrements **SPF**, **DKIM** (et DMARC) donnés par le fournisseur. Sans eux, Gmail classe vite les messages en spam.
- *Authentication → Providers → Email → Confirm email* : activé (le modèle « Confirm signup » n'est envoyé que dans ce cas).
- Durée de validité des liens : Authentication → Sessions/Emails → *OTP expiry* (3600 s = 1 h, ce que disent les modèles). Si vous changez cette valeur, adaptez le texte « 1 heure » dans `recovery.html` et `magic_link.html`.

## 3. Tester
1. Inscrivez-vous avec une adresse Gmail de test : vérifiez l'objet, le logo, le bouton, et que le lien ramène sur le site.
2. Faites « Mot de passe oublié ».
3. Regardez le message sur téléphone, et dans le dossier spam.
