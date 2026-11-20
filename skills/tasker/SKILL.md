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

## 5. Docker ortamı (yalnızca `compose.yaml` varsa)
- Projede `.claude/stack.toml` yoksa dur: proje henüz hazırlanmamış, önce `/initer` çalıştırılmalı (bu skill `initer` içinden çağrıldıysa bu kontrolü ve development kopyalamasını atla).
- Projenin development ortamı yoksa (ana klasörde `.env` yok veya container'lar çalışmıyor) önce `/initer` ile kur; worktree verisi development'tan kopyalanır.
- `.env` yoksa `.env.example`'dan kopyala; `.env`'in `.gitignore`'da olduğunu doğrula.
- `COMPOSE_PROJECT_NAME=<proje>-<branch adındaki / yerine ->` yaz; container ve volume'lar (veri servisleri dahil) development ortamından ayrı kalır.
- `.env.example`'daki `*_PORT` değişkenleri için boş port seç (`ss -tlnp`, `docker ps --format '{{.Ports}}'`) ve `.env`'e yaz. `.env.example`'daki varsayılan portları kullanma, onlar development ortamına ayrılmıştır; çalışan diğer worktree'lerle de çakışmamalı.
- **Bellek:** Her worktree kendi veri servislerini çalıştırır (MySQL ~450 MB, PostgreSQL ~60 MB). Açmadan önce `free -m` ile kullanılabilir belleğe bak; yetersizse kullanıcıyı uyar ve kullanılmayan bir worktree'nin durdurulmasını öner.
- Veri servislerini başlat ve development verisini kopyala: `docker compose up -d --wait <stack.toml'da role = "data" olan servisler>`, ardından `~/.claude/scripts/db.sh copy-from-dev <worktree>`. Redis gibi önbellekler boş başlar.
- `docker compose up -d --build`, ardından servislerin ayağa kalktığını kontrol et (`docker compose ps`).
- Erişimi `local.md`'deki yerel ağ ve Tailscale adresleriyle `curl` kullanarak doğrula.
- Proje çalıştırılabilir bir uygulama ama Docker dosyaları yoksa: worktree'yi aç, ardından global kurallara göre Docker dosyalarını eklemek için plan sun.

## 6. Bildir
Kısa özet: branch, worktree yolu, taban commit'i, varsa erişim adresleri ve doğrulama sonucu.

## 7. Geliştirme sırasında: `stack.toml`'u güncel tut
Bu işte aşağıdakilerden biri değişirse `.claude/stack.toml`'u **aynı commit'te** güncelle; stack özeti değiştiyse proje `CLAUDE.md`'sini de:
- `compose.yaml`'da servis eklendi, silindi veya yeniden adlandırıldı; bir servisin rolü değişti (app, worker, data).
- Bir veri servisinin image'ı veya motoru değişti. **Ana sürüm yükseltmesi** (ör. postgres 17 → 18) mevcut volume'larla açılmaz: değişiklikten önce kullanıcıya bildir ve yükseltme planı sun.
- Migration, test veya seed komutu, migration dizini ya da komutların çalıştığı servis değişti.
- HTTP servislerinin portu (`.env` değişkeni) veya sağlık kontrolü yolu değişti.

Güncelleme doğruluğu `/merge`'deki provada test edilir: `stack.toml`'daki bir komut veya servis yanlışsa prova başarısız olur. Reviewer da `compose.yaml` ile `stack.toml`'un uyumunu `/push`'ta denetler.
