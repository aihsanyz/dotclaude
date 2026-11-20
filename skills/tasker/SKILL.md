---
name: tasker
description: Yeni bir iş başlatır; yerel main/development'ı eşitler, origin/development'tan worktree ve branch açar, boş port seçip Docker ortamını ayağa kaldırır ve erişim adreslerini doğrular. Kullanıcı yeni bir iş, özellik veya düzeltmeye başlamak istediğinde ya da /tasker <ad> yazdığında kullan.
---

# /tasker <ad>

Git'li bir projede yeni işi `origin/development` tabanlı bir worktree branch'inde başlatır. Bir adım başarısız olursa dur ve kullanıcıya bildir.

## 1. Branch adı
- `<tür>/<ad>` biçiminde: tür işin niteliğine göre `feat`, `fix`, `chore`, `docs`, `refactor` veya `revert` (belirsizse `feat`); ad kısa ve kebab-case (ör. `feat/user-login`).
- Ad verilmediyse kullanıcının tarif ettiği işten türet ve belirt.

## 2. Repo hazırlığı
- Repo kökünü bul (`git rev-parse --show-toplevel`; bir worktree içindeysen ana repo `git rev-parse --path-format=absolute --git-common-dir` dizininin üstü).
- `origin` yoksa dur: PR akışı uygulanamaz, kullanıcıya nasıl ilerleneceğini sor.
- `git fetch origin --prune`
- `origin/development` yoksa `main`'den oluştur ve gönder: `git push origin origin/main:refs/heads/development`, ardından tekrar fetch.

## 3. Yerel main ve development'ı eşitle
Her biri için (`main`, `development`):
- Branch bir worktree'de checkout edilmişse (`git worktree list`): `git -C <o worktree> merge --ff-only origin/<b>`.
- Edilmemişse: `git fetch origin <b>:<b>` (yerel branch yoksa oluşturur).
- Fast-forward mümkün değilse dur: yerelde uzakta olmayan commit var demektir, kullanıcıya bildir.

## 4. Worktree aç
- T3 Code bu iş için zaten bir worktree açtıysa yeni açma; tabanının `origin/development` olduğunu doğrula (`git merge-base --is-ancestor origin/development HEAD`), değilse bildir.
- Aksi halde konum: `<ana repo dizini>.worktrees/<branch adındaki / yerine ->` (ör. `~/projects/app.worktrees/feat-user-login`).
- `git -C <ana repo> worktree add --no-track -b <branch> <konum> origin/development`
  - `--no-track` zorunlu: branch'in upstream'i `origin/development` olmamalı.
- Git komutlarında yolları mutlak yaz ve shell değişkeni kullanma; guard hook değişkenli yolları doğrulayamaz.

## 5. Docker ortamı (yalnızca compose dosyası varsa)
- Proje `CLAUDE.md`'sinde `## Komutlar` bölümü yoksa dur: proje henüz hazırlanmamış, önce `/initer` çalıştırılmalı (bu skill `initer` içinden çağrıldıysa bu kontrolü atla).
- Compose dosyasında servis yoksa (`docker compose config --services` boş; `initer` iskeleti) yalnızca `.env`'i `.env.example`'dan oluştur ve `COMPOSE_PROJECT_NAME`'i aşağıdaki gibi yaz; kalan adımları atla.
- `.env` yoksa `.env.example`'dan kopyala; `.env`'in `.gitignore`'da olduğunu doğrula.
- `COMPOSE_PROJECT_NAME=<proje>-<branch adındaki / yerine ->` yaz; container ve volume'lar (veri servisleri dahil) development ortamından ayrı kalır.
- `.env.example`'daki `*_PORT` değişkenleri için boş port seç (`ss -tlnp`, `docker ps --format '{{.Ports}}'`) ve `.env`'e yaz. `.env.example`'daki varsayılan portları kullanma, onlar development ortamına ayrılmıştır; çalışan diğer worktree'lerle de çakışmamalı.
- **Bellek:** Her worktree kendi veri servislerini çalıştırır (MySQL ~450 MB, PostgreSQL ~60 MB). Açmadan önce `free -m` ile kullanılabilir belleğe bak; yetersizse kullanıcıyı uyar ve kullanılmayan bir worktree'nin durdurulmasını öner.
- Veritabanını hazırla: veri servislerini başlat (`docker compose up -d --wait <image ile tanımlı servisler>`), sonra `## Komutlar`'daki `migrate` ve `seed` komutlarını `docker compose run --rm <service> sh -c "<komut>"` ile çalıştır. Worktree temiz bir veritabanı ve seed verisiyle başlar.
- `docker compose up -d --build`, ardından servislerin ayağa kalktığını kontrol et (`docker compose ps`).
- Erişimi `local.md`'deki yerel ağ ve Tailscale adresleriyle `curl` kullanarak doğrula.
- Proje çalıştırılabilir bir uygulama ama Docker dosyaları yoksa: worktree'yi aç, ardından global kurallara göre Docker dosyalarını eklemek için plan sun.

## 6. Bildir
Kısa özet: branch, worktree yolu, taban commit'i, varsa erişim adresleri ve doğrulama sonucu.

## 7. Geliştirme sırasında: proje `CLAUDE.md`'sini güncel tut
Bu işte aşağıdakilerden biri değişirse proje `CLAUDE.md`'sinin `## Stack` ve `## Komutlar` bölümlerini **aynı commit'te** güncelle:
- Compose dosyalarında servis eklendi, silindi veya yeniden adlandırıldı; komutların çalıştığı servis değişti.
- Bir veri servisinin image'ı veya motoru değişti. **Ana sürüm yükseltmesi** (ör. postgres 17 → 18) development'ın mevcut volume'larıyla açılmaz: değişiklikten önce kullanıcıya bildir ve yükseltme planı sun.
- Migration, test veya seed komutu ya da migration dizini değişti; yeni tablolar için seed'e örnek satır eklenmeli.

Güncellemenin doğruluğu `/merge`'deki provada test edilir: `## Komutlar`'daki bir komut yanlışsa prova başarısız olur. Reviewer da compose dosyaları ile proje `CLAUDE.md`'sinin uyumunu `/push`'ta denetler.
