---
name: initer
description: Bulunulan klasörü bu çalışma düzenine göre kurar; klasör boşsa kullanıcının seçtiği stack'le yeni projeyi oluşturur, kod varsa mevcut projeyi düzenler. Git, private GitHub reposu, main/development branch'leri, stack ve komutları içeren proje CLAUDE.md'si, Docker ve .env uyumu ve development ortamını hazırlar. Yeni bir projeye başlanırken, bir projede ilk kez çalışılacağında, proje CLAUDE.md'sinde ## Komutlar bölümü yoksa veya kullanıcı /initer dediğinde kullan.
---

# /initer

Bulunulan klasörde bir kez çalışır; `/tasker`, `/push`, `/merge` ve `/release` bundan sonra kullanılır. Amaç: stack bilgisinin ve komutların bir kez çıkarılıp proje `CLAUDE.md`'sine yazılması, projenin global `CLAUDE.md` kurallarına uyması ve development ortamının ayakta olması.

Tüm git komutlarında `git -C <mutlak yol>` kullan. Bir adım başarısız olursa dur ve bildir.

## 1. Klasörün durumunu belirle
Klasör kullanıcının oturumu açtığı dizindir (`pwd`).
- `gh auth status` başarısızsa dur ve bildir.
- Proje `CLAUDE.md`'sinde `## Komutlar` bölümü varsa init yapılmıştır:
  - Development ortamı bu makinede kurulu değilse (ana klasörde `.env` yok veya container'lar çalışmıyor; ör. sunucu yenilendi, proje yeni clone edildi): ana klasörü `development`'a geçir ve `origin/development` ile eşitle, `.env` yoksa `.env.example`'dan oluştur (`COMPOSE_PROJECT_NAME=<proje>-dev`), sonra `~/.claude/scripts/deploy.sh apply <ana klasör> --bootstrap`. Veri boş başlar, seed çalışır.
  - `CLAUDE.md`'deki stack ve komutları projeyle karşılaştır, farkları göster; yalnızca güncelleme gerekiyorsa D akışına geç.
- Aksi halde duruma göre akış seç:

| Durum | Akış |
|---|---|
| Klasör boş (`ls -A` çıktısı yok) | **A. Yeni proje** |
| Dosya var, `.git` yok | **B. Git'e alınmamış proje** |
| Git var, `origin` yok | **C. Uzak reposu olmayan proje** |
| Git ve `origin` var | **D. Mevcut proje** |

## Ortak: GitHub reposu (A, B, C)
- **Görünürlük:** varsayılan **private**; kullanıcı açıkça public isterse public.
- **Ad:** klasör adı; **sahip:** kullanıcının kişisel hesabı (`gh api user --jq .login`). Kullanıcı bir organizasyon belirttiyse o.
- Aynı adda repo varsa (`gh repo view <sahip>/<ad>`) dur ve sor.
- `gh repo create <sahip>/<ad> --private --source <klasör> --remote origin` (push etmeden), ardından `git -C <klasör> push -u origin main`.
- `development`'ı oluştur: `git -C <klasör> push origin main:refs/heads/development`, `git fetch origin`, `git switch development`.

## A. Yeni proje (boş klasör)
1. **Sor** (tek soruda, `AskUserQuestion`): ne yapılacağı (bir cümle), dil ve framework, veri servisleri (PostgreSQL, MySQL, MongoDB, Redis vb. veya yok), varsa özel istekler. Bilinen bir tercih yoksa yaygın ve güncel bir seçenek öner.
2. **Planı onaylat** (`send_to_user`): oluşturulacak dosyalar, framework ve bağımlılıklar (sürümleriyle), servisler, portlar, migration ve test aracı.
3. **İskeleti oluştur**, global kurallara göre:
   - Çalışan en küçük uygulama: `0.0.0.0`'da dinler, bir sağlık uç noktası vardır (`/health` veya framework'ün karşılığı).
   - `Dockerfile`, `compose.yaml` (uygulama + veri servisleri; `healthcheck`, `restart: unless-stopped`, portlar `.env` değişkeniyle, iç servislerin portları yayınlanmaz, veri volume'da), `.dockerignore` (`docs/`, `.env`), `.gitignore` (`.env`), `.env.example` (bütün değişkenler varsayılanlarıyla).
   - Migration aracı ve ilk migration (veritabanı varsa), test aracı ve bir duman testi, seed (gerekiyorsa).
   - Proje `CLAUDE.md`'si (stack ve `## Komutlar` bölümüyle) ve kısa bir `README.md` (aşağıdaki şablon).
   - Bağımlılıkları host'a değil, container içinde kur (ör. lock dosyasını `docker run --rm` ile üret).
4. **Yerinde doğrula** (henüz git yok, düzeltmeler doğrudan yapılır): `.env.example`'dan `.env` oluştur, `COMPOSE_PROJECT_NAME=<ad>-dev`; `docker compose up -d --build --wait`, migration, seed ve testleri container içinde çalıştır, sağlık uç noktasını `curl` ile kontrol et. Geçene kadar düzelt. Bu ortam development ortamı olarak kalır.
5. **Git:** `git init -b main`, ilk commit (`feat: initial project setup`), ardından "Ortak: GitHub reposu".
6. **Standart işlem:** `~/.claude/scripts/deploy.sh apply <klasör>` (veri zaten var; migration ve sağlık kontrolü standart sırayla). `local.md`'deki adresleri bildir.

## B. Git'e alınmamış proje
1. Gizli bilgi kontrolü: commit'ten önce `.env`, anahtar dosyaları ve benzerleri için `.gitignore`'u kontrol et; `git init -b main` sonrası `~/.claude/scripts/scan.sh fs` ile tara. Gizli bilgi bulunursa dur ve kullanıcıya sor.
2. Mevcut kodu **değiştirmeden** ilk commit: `chore: import existing code`.
3. "Ortak: GitHub reposu", ardından **D**.

## C. Uzak reposu olmayan proje
1. Varsayılan branch `main` değilse (ör. `master`) yeniden adlandırmak için kullanıcıya sor.
2. "Ortak: GitHub reposu" (`main` push'u ve `development`), ardından **D**.

## D. Mevcut proje
1. **Branch modeli:** `git fetch origin --prune`. `origin/main` yoksa (ör. `master` kullanılıyor) dur ve sor. `origin/development` yoksa `main`'den oluştur: `git push origin origin/main:refs/heads/development`. Ana klasör development ortamı olacak: çalışma alanı temiz değilse dur ve sor; temizse `git switch development`.
2. **İncele:** dil, framework ve sürüm; servisler (uygulama, worker, veri servisleri ve motorları); migration, test ve seed komutları ve çalıştıkları servis; migration dizini; HTTP servislerinin portları ve sağlık yolu. Tahminleri "doğrulanmadı" diye işaretle.
3. **Kurallarla karşılaştır** (global `CLAUDE.md`: Docker, Ağ Erişimi, Development Ortamı):
   - `Dockerfile`, `compose.yaml`, `.dockerignore` (`docs/`, `.env`) var mı?
   - Veri servisleri compose'ta mı, resmi image değişkenlerini kullanıyor mu, portları yayınlanmamış mı, veri volume'da mı?
   - Uygulama `0.0.0.0`'da mı, portlar `.env` değişkeniyle mi, `healthcheck` ve `restart: unless-stopped` var mı?
   - `.env.example` eksiksiz mi, `.env` `.gitignore`'da mı? Bind mount ve hot reload.
4. **Planı onaylat** (`send_to_user`): proje `CLAUDE.md`'si (stack ve komutlar), dosya değişiklikleri ve dayandıkları kurallar, varsa yeni bağımlılıklar.
5. **Uygula:** `/tasker chore/project-setup`. Development ortamı ve `## Komutlar` bölümü henüz olmadığından `tasker`'ın 5. adımındaki init ön koşulunu ve development kopyalamasını atla; veri servisleri boş başlar. Değişiklikleri Conventional Commits ile commit'le.
6. **Merge:** `/merge` akışı; prova `deploy.sh rehearse <worktree> --bootstrap` ile çalışır. Reviewer ve auditor normal çalışır.
7. **Development ortamını ilk kez kur** (`/merge`'ün 6. adımında `apply` yerine): ana klasörde `.env` yoksa `.env.example`'dan oluştur (`COMPOSE_PROJECT_NAME=<proje>-dev`), sonra `~/.claude/scripts/deploy.sh apply <ana klasör> --bootstrap`. `local.md`'deki adresleri bildir.

## Şablon: proje `CLAUDE.md`
`## Komutlar` bölümünü `deploy.sh` okur; biçimi koru (`- anahtar: \`değer\``) ve yalnızca projede olan anahtarları yaz. Veri servisleri, motorları ve portlar `compose.yaml`'dan çıkarılır; burada tekrar yazılmaz.

```markdown
# <Proje adı>

<Projenin ne yaptığı, bir cümle.>

## Stack
- <dil / framework ve sürüm>
- Servisler: <app: ..., worker: ..., db: postgres, cache: redis>
- Development ortamı: ana repo klasörü, `development` branch'i; her merge'den sonra `/merge` günceller. Yeni iş: `/tasker`.

## Komutlar
<!-- deploy.sh bu bölümü okur. Biçim: "- anahtar: `değer`". Anahtarlar: service, migrate, test, seed, migrations, engines -->
- service: `app`
- migrate: `php artisan migrate --force`
- test: `php artisan test`
- seed: `php artisan db:seed --force`
- migrations: `database/migrations`

## Notlar
- <Projeye özel kurallar, bilinen tuzaklar.>
```

- `service`: komutların çalıştığı compose servisi; yazılmazsa `build:` olan ilk servis.
- `seed`: yalnızca ilk kurulumda çalışır.
- `engines`: yalnızca image adından anlaşılmayan veri servisleri için (ör. `db=postgres mq=redis`).
- Komutlar container içinde çalışır: `docker compose run --rm <service> sh -c "<komut>"`.
