# -*- coding: utf-8 -*-
"""Prévient Bing, Yandex et autres moteurs (protocole IndexNow) que des pages ont changé.
À lancer APRÈS le déploiement :  python3 tools/indexnow.py [https://votre-domaine.com]
Google n'utilise pas IndexNow : pour lui, utilisez la Search Console (envoi du sitemap)."""
import sys, re, json, urllib.request, os
KEY = "a0adcca0a6c6a3c7540af281460227ab"
BASE = (sys.argv[1] if len(sys.argv) > 1 else "https://cvxmaker.netlify.app").rstrip('/')
sm = open(os.path.join(os.path.dirname(__file__), '..', 'public', 'sitemap.xml'), encoding='utf-8').read()
urls = [u.replace('https://cvxmaker.netlify.app', BASE) for u in re.findall(r'<loc>(.*?)</loc>', sm)]
body = json.dumps({"host": BASE.split('://', 1)[1], "key": KEY, "keyLocation": f"{BASE}/{KEY}.txt", "urlList": urls}).encode()
req = urllib.request.Request("https://api.indexnow.org/indexnow", data=body, headers={"Content-Type": "application/json; charset=utf-8"})
try:
    with urllib.request.urlopen(req, timeout=20) as r:
        print("IndexNow :", r.status, len(urls), "URL envoyées")
except Exception as e:
    print("Échec IndexNow :", e)
