---
name: dev-env
description: Projenin sürekli ayakta duran development ortamını yönetir; ilk kurulum, merge sonrası güncelleme (build, yedek, migration, yeniden başlatma, doğrulama), durum, loglar, yeniden başlatma, yedek ve geri yükleme. Kullanıcı development ortamını kurmak, güncellemek, durumunu görmek veya yeniden başlatmak istediğinde (/dev-env) ve merge/release sonrasında kullan.
---

# /dev-env [kurulum | güncelle | durum | log | yeniden-başlat | yedek | geri-yükle]

Her projenin `development` ortamı ana repo klasöründe, `development` branch'inde sürekli ayakta durur. `main` için ortam tutulmaz. Tüm git komutlarında `git -C <mutlak yol>` kullan.

**Tanımlar**
- **Proje adı:** Ana repo dizininin adı (`db.sh` bunu `[a-z0-9_]`'e çevirir).
- **Standart işlem:** `~/.claude/scripts/deploy.sh`. Merge sonrası güncelleme (`apply`) ile merge öncesi prova (`rehearse`) aynı adımları aynı sırayla çalıştırır; bu skill'de adımları elle tekrarlama.
- **Proje ayarları:** Projede commit edilen `.claude/devenv.conf`. Hem prova hem güncelleme bu dosyayı okur:

```
SHARED_SERVICES="postgres redis"   # ortak servisler: postgres, mysql, redis
APP_SERVICE="app"                  # migration ve testlerin çalıştığı compose servisi
MIGRATE_CMD="..."                  # container içinde migration komutu (yoksa boş)
MIGRATIONS_DIR="migrations"        # migration dosyalarının dizini
SEED_CMD="..."                     # yalnızca ilk kurulumda çalışır (yoksa boş)
TEST_CMD="..."                     # provada çalışan testler
HEALTH_PORT_VAR="APP_PORT"         # sağlık kontrolünün portunu tutan .env değişkeni
HEALTH_PATH="/"                    # sağlık kontrolü yolu
HEALTH_TIMEOUT=90                  # saniye
```

## kurulum (ortam yoksa)
1. Ana repo klasörü `development`'ta olmalı. Değilse ve çalışma alanı temizse `git switch development`; temiz değilse dur ve sor.
2. `development`'ı `origin/development` ile fast-forward eşitle.
3. `.claude/devenv.conf` yoksa projeyi inceleyip değerleri bul, dosyayı oluştur ve kullanıcıya göster. Bu bir proje değişikliğidir: `/start-task chore/devenv-config` ile bir worktree'de commit edilir ve normal akışla (`/push`, `/merge`) development'a girer; kurulum o merge'den sonra devam eder.
4. `.env` yoksa `.env.example`'dan oluştur; `COMPOSE_PROJECT_NAME=<proje>-dev` yaz. Portlar `.env.example`'daki varsayılanlar olarak kalır; bu portlar development ortamına ayrılmıştır.
5. Her ortak servis için `~/.claude/scripts/db.sh init <engine> <proje> --env-file <ana repo>/.env`.
6. `~/.claude/scripts/deploy.sh apply <ana repo>`, ardından varsa `SEED_CMD` (container içinde).
7. `local.md`'deki yerel ağ ve Tailscale adreslerini bildir.

## güncelle (her merge'den sonra)
1. `development`'ı `origin/development` ile fast-forward eşitle.
2. `~/.claude/scripts/deploy.sh apply <ana repo>`. Adımlar: kontroller, ortam değişkeni eşitleme, yedek, build, migration, `up`, sağlık kontrolü. `RESULT: ok` başarıdır.
3. Başarısız olursa script'in gösterdiği adımı ve son çıktıyı bildir; migration hatasında **düzeltmeye çalışma**, alınan yedeğin yolunu ver. Build hatasında eski container'lar çalışmaya devam eder. Seçenekler için `merge` skill'inin 6. adımına bak.
4. Güncelleme `/merge` dışında çalıştırıldıysa (ör. "tekrar dene") ve başarılıysa: hangi sorunun çözüldüğü belli olmadığından bekleyen worktree'lerin hiçbirini otomatik silme. `merge` skill'inin 7. adımındaki koşulu sağlayanları kullanıcıya liste halinde sor ve yalnızca seçilenleri temizle. `/merge` içinden çağrıldıysa temizliği `merge` skill'i yapar.

## durum / log / yeniden-başlat
- Durum: `docker compose ps`, son commit (`git log -1 --oneline`), adreslerin `curl` sonucu.
- Log: `docker compose logs --tail 100 [servis]`.
- Yeniden başlatma: `docker compose restart [servis]`.

## yedek / geri-yükle
- Yedek: `db.sh backup <engine> <proje>` (son 5 yedek saklanır, `~/infra/shared/backups/`).
- Geri yükleme `<proje>_dev`'in üzerine yazar ve geri alınamaz: hangi yedeğin kullanılacağını göster, kullanıcının açık onayını al, sonra `db.sh restore <engine> <proje> <dosya> --yes`.
