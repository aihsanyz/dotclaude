---
name: initer
description: Bulunulan klasörü bu çalışma düzeninin en küçük haline getirir; kod yazmaz, stack seçmez. Git, private GitHub reposu, main/development branch'leri, README.md, proje CLAUDE.md'si (boş ## Stack ve ## Komutlar), docs/reports/ ve development/production ayrımlı en küçük Docker dosyalarını (compose.dev.yaml, compose.prod.yaml, .env.example, .env.production.example, .dockerignore, .gitignore) ekler. Yeni bir projeye başlanırken, bir projede ilk kez çalışılacağında, proje CLAUDE.md'sinde ## Komutlar bölümü yoksa veya kullanıcı /initer dediğinde kullan.
---

# /initer

Bulunulan klasörde bir kez çalışır; `/tasker`, `/push`, `/merge` ve `/release` bundan sonra kullanılır. Amaç yalnızca klasörün iskeletini kurmaktır: **kod yazılmaz, stack seçilmez, bağımlılık kurulmaz, uygulama ayağa kaldırılmaz.** Projenin fikri, stack'i ve kodu sonraki işlerde şekillenir.

Mevcut dosyalara dokunma; yalnızca eksik olanları ekle. Tüm git komutlarında `git -C <mutlak yol>` kullan. Bir adım başarısız olursa dur ve bildir.

## 1. Klasörün durumunu belirle
Klasör kullanıcının oturumu açtığı dizindir (`pwd`); proje adı klasör adıdır.
- `gh auth status` başarısızsa dur ve bildir.
- Proje `CLAUDE.md`'sinde `## Komutlar` bölümü varsa init yapılmıştır. Yalnızca bu makinede development ortamı eksikse tamamla (ör. proje yeni clone edildi): ana klasörü `development`'a geçir ve `origin/development` ile eşitle, `.env` yoksa `.env.example`'dan oluştur (`COMPOSE_PROJECT_NAME=<proje>-dev`); compose dosyasında servis varsa (`docker compose config --services` boş değil) `~/.claude/scripts/deploy.sh apply <ana klasör> --bootstrap`. Sonra bildir ve bitir.
- Aksi halde:

| Durum | Akış |
|---|---|
| `.git` yok (klasör boş veya dolu) | **A. Git'e alınmamış klasör** |
| Git var, `origin` yok | **B. Uzak reposu olmayan proje** |
| Git ve `origin` var | **C. Mevcut proje** |

## 2. İskelet dosyaları
Yalnızca eksik olanları ekle; var olanı değiştirme. Var olan `CLAUDE.md`'de `## Stack` veya `## Komutlar` yoksa sadece eksik bölümü sona ekle. Var olan `.gitignore` ve `.dockerignore`'a yalnızca eksik satırları ekle.

- `README.md`: `# <proje adı>` ve kullanıcı bir cümle verdiyse o cümle.
- `CLAUDE.md`: aşağıdaki şablon.
- `docs/reports/.gitkeep`
- Development ve production ayrımı (global `CLAUDE.md`, Docker ile Geliştirme): her ortamın kendi compose dosyası vardır, `.env`'deki `COMPOSE_FILE` hangisinin kullanılacağını seçer.
  - `compose.dev.yaml` (development ortamı ve worktree'ler; servisler eklendiğinde bind mount, hot reload, Dockerfile'ın `dev` target'ı):
    ```yaml
    # Development: bind mount + hot reload, Dockerfile target "dev".
    services: {}
    ```
  - `compose.prod.yaml` (production; kod image içinde, bind mount yok, Dockerfile'ın `prod` target'ı, `restart: unless-stopped`):
    ```yaml
    # Production: code baked into the image, Dockerfile target "prod", no bind mounts.
    services: {}
    ```
  - `.env.example`:
    ```
    COMPOSE_FILE=compose.dev.yaml
    COMPOSE_PROJECT_NAME=<proje>-dev
    ```
  - `.env.production.example`:
    ```
    COMPOSE_FILE=compose.prod.yaml
    COMPOSE_PROJECT_NAME=<proje>
    ```
- `.dockerignore`: `.git`, `.env`, `.env.*`, `!.env*.example`, `docs/`
- `.gitignore`: `.env`, `.env.production`

Mevcut projede zaten bir compose dosyası (`compose.yaml`, `docker-compose.yml` vb.) varsa compose dosyalarını ve `COMPOSE_FILE`'ı ekleme, var olanı bölme veya taşıma; bunu bildir, ayrım ayrı bir işte yapılır.

`Dockerfile`, uygulama kodu, migration, test ve seed eklenmez; stack belirlendiğinde ilgili işte eklenir (Dockerfile `dev` ve `prod` target'larıyla) ve `## Stack` ile `## Komutlar` o işte doldurulur.

## A. Git'e alınmamış klasör
1. Klasör doluysa gizli bilgi kontrolü: `.env`, anahtar dosyaları ve benzerleri `.gitignore`'da mı bak; `git init -b main` sonrası `~/.claude/scripts/scan.sh fs` ile tara. Gizli bilgi bulunursa dur ve sor.
2. `git init -b main`, iskelet dosyalarını ekle, ilk commit: `chore: initial project setup`.
3. "GitHub reposu", ardından "Development ortamı".

## B. Uzak reposu olmayan proje
1. Varsayılan branch `main` değilse (ör. `master`) yeniden adlandırmak için sor.
2. Çalışma alanı temiz değilse dur ve sor. İskelet dosyalarını ekle ve commit'le: `chore: add project skeleton`.
3. "GitHub reposu", ardından "Development ortamı".

## C. Mevcut proje
1. `git fetch origin --prune`. `origin/main` yoksa dur ve sor. `origin/development` yoksa oluştur: `git push origin origin/main:refs/heads/development`.
2. Ana klasörün çalışma alanı temiz değilse dur ve sor; temizse `git switch development` ve `origin/development` ile eşitle.
3. Eksik iskelet dosyası varsa: `/tasker chore/project-setup` ile worktree aç (`## Komutlar` henüz olmadığından tasker'ın init ön koşulunu atla), eksikleri ekle, `chore: add project skeleton` ile commit'le, normal `/push` ve `/merge` akışı.
4. "Development ortamı".

## GitHub reposu (A, B)
- **Görünürlük:** varsayılan **private**; kullanıcı açıkça public isterse public.
- **Sahip:** kullanıcının kişisel hesabı (`gh api user --jq .login`); kullanıcı bir organizasyon belirttiyse o.
- Aynı adda repo varsa (`gh repo view <sahip>/<ad>`) dur ve sor.
- `gh repo create <sahip>/<ad> --private --source <klasör> --remote origin` (push etmeden), ardından `git -C <klasör> push -u origin main`.
- `development`: `git -C <klasör> push origin main:refs/heads/development`, `git fetch origin`, `git switch development`.

## Development ortamı
- Ana klasör `development` branch'inde olmalı.
- `.env` yoksa `.env.example`'dan oluştur (`COMPOSE_PROJECT_NAME=<proje>-dev`).
- Compose dosyasında servis yoksa container başlatılmaz; ilk servis eklendiğinde `/merge` ortamı ilk kez kurar. Servis varsa `~/.claude/scripts/deploy.sh apply <ana klasör> --bootstrap` ve `local.md`'deki adresleri bildir.
- Kısa özet: repo adresi, branch'ler, eklenen dosyalar.

## Şablon: proje `CLAUDE.md`
`## Komutlar` bölümünü `deploy.sh` okur; biçimi koru (`- anahtar: \`değer\``) ve yalnızca projede olan anahtarları yaz. Init'te bölüm boş kalır; stack belirlendiğinde doldurulur. Servisler ve portlar compose dosyalarından çıkarılır; burada tekrar yazılmaz.

```markdown
# <Proje adı>

<Projenin ne yaptığı, bir cümle; henüz yoksa boş bırak.>

## Stack
- Henüz belirlenmedi.
- Development ortamı: ana repo klasörü, `development` branch'i; her merge'den sonra `/merge` günceller. Yeni iş: `/tasker`.

## Komutlar
<!-- deploy.sh bu bölümü okur. Biçim: "- anahtar: `değer`". Anahtarlar: service, migrate, test, seed, migrations -->

## Notlar
```

Stack belirlendiğinde doldurulacak anahtarlar (örnek):
```markdown
- service: `app`
- migrate: `php artisan migrate --force`
- test: `php artisan test`
- seed: `php artisan db:seed --force`
- migrations: `database/migrations`
```

- `service`: komutların çalıştığı compose servisi; yazılmazsa `build:` olan ilk servis.
- `seed`: her yeni worktree'de, her provada ve development'ın ilk kurulumunda çalışır. **Gerçekçi olmalı:** her tabloda birkaç örnek satır içersin; prova temiz veritabanıyla çalıştığı için veriye bağlı migration hatalarını (ör. dolu tabloya varsayılansız `NOT NULL` kolon) ancak seed verisi yakalar. Tekrar çalıştırıldığında hata vermemeli.
- Komutlar container içinde çalışır: `docker compose run --rm <service> sh -c "<komut>"`.
