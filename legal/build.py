#!/usr/bin/env python3
"""Builds the public legal/support pages from the markdown sources in backend/.
Run: python3 legal/build.py   (output: legal/privacy|terms|support/index.html, legal/index.html)"""
import markdown, pathlib, html

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT.parent / "backend"
MD = lambda t: markdown.markdown(t, extensions=["sane_lists"])

SUPPORT_EN = """# Nomad Support

Need help with Nomad? Email **illyakovaliuk@gmail.com** and we'll reply as soon as we can.

## Common questions

**How do I delete my account?** Settings → Delete account. This permanently removes your profile, routes, photos, comments and points, and the files you uploaded.

**How do I block or report someone?** Open their profile (or press and hold their comment) and choose *Block user*. To report a route, photo or comment, use its menu. Blocked users are managed in Settings → Blocked users.

**How do I cancel Nomad Pro?** Subscriptions are managed by Apple: Settings → your name → Subscriptions → Nomad. You can also restore purchases on the Nomad Pro screen.

**Route recording stopped or looks wrong.** Make sure location access is set to *While Using* or *Always* in iOS Settings → Nomad → Location, and that Precise Location is on.

**SOS.** SOS opens a pre-filled message to your own emergency contacts. It does not call emergency services: in an emergency call your local emergency number.

Legal: [Privacy Policy](/privacy/) · [Terms of Service](/terms/)
"""
SUPPORT_UK = """# Підтримка Nomad

Потрібна допомога з Nomad? Напишіть на **illyakovaliuk@gmail.com**, і ми відповімо щойно зможемо.

## Часті запитання

**Як видалити акаунт?** Налаштування → Видалити акаунт. Це остаточно видаляє ваш профіль, маршрути, фото, коментарі та бали, а також файли, які ви завантажили.

**Як заблокувати чи поскаржитися на користувача?** Відкрийте його профіль (або затисніть коментар) і оберіть *Заблокувати користувача*. Щоб поскаржитися на маршрут, фото чи коментар, скористайтеся його меню. Заблокованими керуйте в Налаштування → Заблоковані користувачі.

**Як скасувати Nomad Pro?** Підписками керує Apple: Налаштування → ваше імʼя → Підписки → Nomad. Також можна відновити покупки на екрані Nomad Pro.

**Запис маршруту зупинився або виглядає неправильно.** Переконайтеся, що доступ до геолокації встановлено на *Під час використання* або *Завжди* в iOS Налаштування → Nomad → Геолокація, а «Точна геолокація» ввімкнена.

**SOS.** SOS відкриває готове повідомлення вашим екстреним контактам. Він не телефонує екстреним службам: у разі небезпеки зателефонуйте за місцевим екстреним номером.

Правове: [Політика конфіденційності](/privacy/) · [Умови використання](/terms/)
"""

PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · Nomad</title>
<meta name="description" content="{desc}">
<style>
:root {{ --bg:#fafaf8; --fg:#161616; --muted:#5d5d5a; --line:#e3e2dc; --accent:#c2551f; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#0f0f0e; --fg:#ecebe6; --muted:#a09f98; --line:#2a2a27; --accent:#e8743b; }} }}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--bg); color:var(--fg); font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }}
main {{ max-width:720px; margin:0 auto; padding:24px 20px 80px; }}
nav {{ display:flex; gap:16px; align-items:center; flex-wrap:wrap; padding-bottom:16px; border-bottom:1px solid var(--line); margin-bottom:8px; }}
nav .brand {{ font-weight:700; letter-spacing:.04em; margin-right:auto; }}
nav a {{ color:var(--muted); text-decoration:none; font-size:14px; }}
nav a:hover, nav a.on {{ color:var(--accent); }}
.lang {{ display:flex; border:1px solid var(--line); border-radius:999px; overflow:hidden; }}
.lang button {{ background:none; border:0; color:var(--muted); padding:5px 12px; font:inherit; font-size:13px; cursor:pointer; }}
.lang button.on {{ background:var(--accent); color:#fff; }}
h1 {{ font-size:30px; line-height:1.2; margin:28px 0 6px; }}
h2 {{ font-size:20px; margin:32px 0 6px; }}
p, li {{ color:var(--fg); }} li {{ margin:4px 0; }}
a {{ color:var(--accent); }}
.doc[hidden] {{ display:none; }}
</style>
</head>
<body>
<main>
<nav>
  <span class="brand">NOMAD</span>
  <a href="/privacy/" {p}>Privacy</a><a href="/terms/" {t}>Terms</a><a href="/support/" {s}>Support</a>
  <span class="lang"><button data-l="en">EN</button><button data-l="uk">УК</button></span>
</nav>
<section class="doc" data-l="en">{en}</section>
<section class="doc" data-l="uk" hidden>{uk}</section>
</main>
<script>
(function () {{
  var l = 'en';
  try {{ l = localStorage.getItem('lang') || ((navigator.language || '').toLowerCase().indexOf('uk') === 0 ? 'uk' : 'en'); }} catch (e) {{}}
  function set(x) {{
    document.documentElement.lang = x;
    document.querySelectorAll('.doc').forEach(function (d) {{ d.hidden = d.dataset.l !== x; }});
    document.querySelectorAll('.lang button').forEach(function (b) {{ b.classList.toggle('on', b.dataset.l === x); }});
    try {{ localStorage.setItem('lang', x); }} catch (e) {{}}
  }}
  document.querySelectorAll('.lang button').forEach(function (b) {{ b.onclick = function () {{ set(b.dataset.l); }}; }});
  set(l);
}})();
</script>
</body>
</html>
"""

def write(path, title, desc, en, uk, on):
    d = ROOT / path
    d.mkdir(parents=True, exist_ok=True)
    flags = {k: ('class="on"' if k == on else "") for k in "pts"}
    (d / "index.html").write_text(PAGE.format(title=html.escape(title), desc=html.escape(desc), en=MD(en), uk=MD(uk), **flags), encoding="utf-8")

rd = lambda n: (SRC / n).read_text(encoding="utf-8")
write("privacy", "Privacy Policy", "How Nomad handles your data.", rd("PRIVACY_POLICY.md"), rd("PRIVACY_POLICY.uk.md"), "p")
write("terms", "Terms of Service", "Terms for using Nomad.", rd("TERMS_OF_SERVICE.md"), rd("TERMS_OF_SERVICE.uk.md"), "t")
write("support", "Support", "Help and contact for Nomad.", SUPPORT_EN, SUPPORT_UK, "s")
(ROOT / "index.html").write_text('<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=/support/"><link rel="canonical" href="/support/"><title>Nomad</title>', encoding="utf-8")
print("built")
