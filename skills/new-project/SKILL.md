---
name: new-project
description: Bulunulan klasörü (boş, git'siz, uzak reposu olmayan veya mevcut bir repo) bu düzenin proje şablonuna getirir. Private GitHub reposunu, AGENTS.md'yi, compose iskeletlerini, CI'ı ve T3 proje ayarlarını kurar. Kod yazmaz, stack seçmez.
disable-model-invocation: true
argument-hint: "[projenin ne yaptığını anlatan bir cümle]"
---

# /new-project

Klasör, oturumun çalıştığı dizindir. Proje adı klasör adıdır; küçük harf ve kebab-case olur. Şablon `~/.claude/templates/project/` altındadır. Şablondaki `{{PROJECT}}` proje adıyla, `{{DESCRIPTION}}` kullanıcının verdiği cümleyle değiştirilir; cümle yoksa boş bırakılır.

**Kod yazılmaz, stack seçilmez, bağımlılık kurulmaz.** `Dockerfile`, servisler ve `## Komutlar` ilk gerçek işte doldurulur.

Genel kurallar:
- Git komutlarında `git -C <mutlak yol>` kullan.
- Repo oluşturma ve ilk push ayrı Bash çağrılarında yapılır; guard hook ilk push'u ancak repo zaten oluşmuşsa doğrulayabilir.
- Bir adım başarısız olursa dur ve bildir.

## 1. Durumu belirle
- `gh auth status` başarısızsa dur ve bildir.
- **Zaten kurulmuş mu?** `AGENTS.md`'de `## Komutlar` bölümü ve `.github/scripts/ci.sh` dosyası varsa proje kurulmuştur. Bu durumda yalnızca 5. adımı (T3 ayarları) ve 6. adımı (development ortamı) uygula, sonra bitir.
- Aksi halde klasörün durumuna göre akış seç:

| Durum | Akış |
|---|---|
| `.git` yok, ya da git var ama hiç commit yok | **A** |
| Git ve commit var, `origin` yok | **B** |
| `origin` var | **C** |

## 2. Şablonu uygula (yalnızca eksik dosyalar)
- `templates/project/` altındaki eksik dosyaları kopyala. Gizli dosyalar da dahildir: `.github/`, `.gitignore`, `.dockerignore`, `.env*.example`.
- `docs/specs/`, `docs/plans/` ve `docs/reports/` klasörlerini `.gitkeep` ile oluştur.
- `.github/scripts/ci.sh` dosyasını çalıştırılabilir yap (`chmod +x`).
- **Var olan dosyalar:**
  - `.gitignore` ve `.dockerignore`: yalnızca eksik satırları sona ekle.
  - `README.md`: Development veya Production bölümü yoksa yalnızca o bölümü sona ekle.
  - `CLAUDE.md`: İçeriği `@AGENTS.md`'den farklıysa bu içeriği `AGENTS.md`'nin `## İlkeler` bölümüne taşı (proje bilgisi kaybolmasın). Ardından `CLAUDE.md` yalnızca `@AGENTS.md` satırını içersin. Bunu kullanıcıya bildir.
  - Var olan bir compose dosyası (`compose.yaml`, `docker-compose.yml`): şablonun compose dosyalarını ekleme, var olanı bölme. Ayrımı ayrı bir iş olarak öner.

## A. Git'e alınmamış klasör
1. Klasörde dosya varsa önce gizli bilgi kontrolü yap: `.env` ve anahtar dosyaları `.gitignore`'da olmalı. `git init -b main` sonrasında `~/.claude/scripts/scan.sh fs` çalıştır. Bulgu varsa dur ve sor.
2. Sırasıyla: `git init -b main` → 2. adım (şablon) → `git add -A` → `git commit -m "chore: initial project setup"`.
3. "GitHub reposu" bölümüne, ardından 4., 5. ve 6. adımlara geç.

## B. Uzak reposu olmayan proje
1. Varsayılan branch `main` değilse (ör. `master`) yeniden adlandırmak için sor.
2. Çalışma alanı temiz değilse dur ve sor.
3. Bütün geçmişi tara: `scan.sh secrets main` ve `scan.sh fs`. Bulgu varsa dur ve sor; repo henüz hiçbir yere gönderilmedi.
4. "GitHub reposu" bölümünü uygula; mevcut geçmiş olduğu gibi gönderilir.
5. Şablonu **C** akışındaki gibi bir branch üzerinden ekle.

## C. Mevcut proje
1. `git fetch origin --prune`. `origin/main` yoksa dur ve sor (ör. varsayılan branch `master` olabilir).
2. **Eski düzen kontrolü:** `origin/development` varsa proje eski düzendedir. Kendiliğinden geçiş yapma. Önce şunları bildir:
   - `development`'ın `main`'den kaç commit önde olduğu: `git rev-list --count origin/main..origin/development`.
   - Önerilen geçiş adımları:
     1. `development` → `main` PR'ı açılır ve merge commit ile birleştirilir.
     2. Bu iskelet işi tamamlanır.
     3. Ana klasör `main`'e alınır.
     4. `development` branch'i yerelde ve uzakta silinir. Silme ayrıca onay ister.
3. Ana klasörün çalışma alanı temiz değilse dur ve sor.
4. Eksik şablon dosyası varsa şablonu bir worktree'de ekle:
   - Worktree'yi aç: `git -C <ana klasör> worktree add --no-track -b chore/adopt-workflow <ana klasör>.worktrees/chore-adopt-workflow origin/main`
   - 2. adımı orada uygula.
   - Commit'le: `chore: adopt project workflow`.
5. **Dur ve raporla; push yapma.** Raporda worktree yolu, eklenen ve taşınan dosyalar ve şu öneri bulunur: "Bu worktree'de `/ship`, ardından `/land` çalıştır."
6. Ardından 5. adımı uygula. Kural yoksa 4. adımı da uygula.

## GitHub reposu (A, B)
- **Görünürlük:** varsayılan **private**. Kullanıcı açıkça isterse public.
- **Sahip:** `gh api user --jq .login`. Kullanıcı bir organizasyon belirttiyse o.
- Aynı adda repo varsa (`gh repo view <sahip>/<ad>`) dur ve sor.
- Repoyu oluştur: `gh repo create <sahip>/<ad> --private --source <klasör> --remote origin`.
- Ardından **ayrı bir Bash çağrısında** push et: `git -C <klasör> push -u origin main`.

## 4. main için zorunlu kontroller
GitHub'da `main` branch'ine "kontroller geçmeden merge yok" kuralı ekle. Kuralı ayarlar dosyasından ver:
- Scratchpad'e şu JSON'u yaz: `{"required_status_checks":{"strict":true,"contexts":["lint","test","rehearse","scan"]},"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null}`
- `gh api -X PUT repos/<sahip>/<ad>/branches/main/protection --input <dosya>`
- Private repoda ücretli plan gerektiği için 403 hatası dönerse bunu bildir ve devam et. Bu durumda kontrolleri `/land` yapar.

## 5. T3 projesi
- `t3_project_list` ile `workspaceRoot`'u bu klasör olan projeyi bul. Yoksa `t3_project_create` ile oluştur (`title`: proje adı, `workspaceRoot`: klasör).
- `t3_project_update` ile şunları ayarla:
  - `defaultThreadEnvMode: "worktree"`
  - `scripts` (var olanlarla aynı `id`'deki girdileri değiştir, diğerlerini koru):

| id | name | command | icon | runOnWorktreeCreate |
|---|---|---|---|---|
| `devenv-up` | Ortamı kur | `"$HOME/.claude/scripts/devenv.sh" up` | configure | true |
| `devenv-ports` | Adresler | `"$HOME/.claude/scripts/devenv.sh" ports` | play | false |
| `lint` | Lint | `"$HOME/.claude/scripts/devenv.sh" run lint` | lint | false |
| `test` | Test | `"$HOME/.claude/scripts/devenv.sh" run test` | test | false |
| `devenv-stop` | Ortamı durdur | `"$HOME/.claude/scripts/devenv.sh" stop` | debug | false |

- T3, proje ayarlarını yalnızca **full-access** modundaki bir thread'den değiştirmeye izin verir. Araç `capability_denied` dönerse:
  - Yukarıdaki tabloyu kullanıcıya göster.
  - İki yol öner: projeyi T3 arayüzünden kendisi eklesin (Add project → bu klasör, script'ler tablodaki gibi, varsayılan thread modu: worktree) ya da bu adımı full-access bir thread'de tekrar çalıştırsın.
  - Diğer adımlara devam et.

## 6. Development ortamı (ana klasör)
- Ana klasör `main` branch'inde ve `origin/main` ile eşit olmalı. Değilse dur ve sor.
- Compose dosyasında servis yoksa ortam kurulmaz; ilk servisler eklendiğinde `/land` kurar.
- Servis varsa `~/.claude/scripts/devenv.sh apply <ana klasör>` çalıştır (`timeout: 600000`). İlk kurulumda seed kendiliğinden çalışır. Çıkan adresleri bildir.

## 7. Bildir
Kısa özet:
- repo adresi ve görünürlüğü
- branch'ler
- eklenen ve taşınan dosyalar
- zorunlu kontrol kuralının sonucu
- T3 ayarları
- development ortamının durumu

Sonraki adım: Projede yeni bir T3 thread'i açılır (worktree modunda). Stack ve ilk özellik `/spec` ile netleştirilir.
