---
name: dev-env
description: Projenin sürekli ayakta duran development ortamını yönetir; ilk kurulum, merge sonrası güncelleme (build, yedek, migration, yeniden başlatma, doğrulama), durum, loglar, yeniden başlatma, yedek ve geri yükleme. Kullanıcı development ortamını kurmak, güncellemek, durumunu görmek veya yeniden başlatmak istediğinde (/dev-env) ve merge/release sonrasında kullan.
---

# /dev-env [kurulum | güncelle | durum | log | yeniden-başlat | yedek | geri-yükle]

Her projenin `development` ortamı ana repo klasöründe, `development` branch'inde sürekli ayakta durur. `main` için ortam tutulmaz. Tüm git komutlarında `git -C <mutlak yol>` kullan.

**Tanımlar**
- **Proje adı:** Ana repo dizininin adı.
- **Veri servisleri:** Veritabanı ve önbellek servisleri (PostgreSQL, MySQL, MariaDB, MongoDB, Redis vb.) projenin compose dosyasında tanımlıdır. Development ve her worktree kendi container'larını ve volume'larını kullanır; portları yayınlanmaz. Bağlantı bilgileri resmi image değişkenleriyle (`POSTGRES_*`, `MYSQL_*`, `MARIADB_*`, `MONGO_INITDB_*`) `.env.example`'da durur.
- **Standart işlem:** `~/.claude/scripts/deploy.sh`. Merge sonrası güncelleme (`apply`) ile merge öncesi prova (`rehearse`) aynı adımları aynı sırayla çalıştırır; bu skill'de adımları elle tekrarlama.
- **Proje ayarları:** Projede commit edilen `.claude/devenv.conf`. Hem prova hem güncelleme bu dosyayı okur:

```
DATA_SERVICES="db:postgres cache:redis"  # compose servisi:motor; kopyalanabilen: postgres, mysql, mariadb, mongodb
APP_SERVICE="app"                  # migration ve testlerin çalıştığı compose servisi
MIGRATE_CMD="..."                  # container içinde migration komutu (yoksa boş)
MIGRATIONS_DIR="migrations"        # migration dosyalarının dizini
SEED_CMD="..."                     # yalnızca ilk kurulumda çalışır (yoksa boş)
TEST_CMD="..."                     # provada çalışan testler
HEALTH_CHECKS="APP_PORT:/ API_PORT:/health"  # PORT_DEĞİŞKENİ:yol listesi; HTTP sunmayan projede boş
HEALTH_TIMEOUT=90                  # saniye
```

## kurulum (ortam yoksa)
1. Ana repo klasörü `development`'ta olmalı. Değilse ve çalışma alanı temizse `git switch development`; temiz değilse dur ve sor.
2. `development`'ı `origin/development` ile fast-forward eşitle.
3. `.claude/devenv.conf` yoksa projeyi inceleyip değerleri bul, dosyayı oluştur ve kullanıcıya göster. Bu bir proje değişikliğidir: `/start-task chore/devenv-config` ile bir worktree'de commit edilir ve normal akışla (`/push`, `/merge`) development'a girer; kurulum o merge'den sonra devam eder.
4. `.env` yoksa `.env.example`'dan oluştur; `COMPOSE_PROJECT_NAME=<proje>-dev` yaz. Portlar `.env.example`'daki varsayılanlar olarak kalır; bu portlar development ortamına ayrılmıştır.
5. `~/.claude/scripts/deploy.sh apply <ana repo>` (veri servislerini de başlatır), ardından varsa `SEED_CMD` (container içinde).
6. `local.md`'deki yerel ağ ve Tailscale adreslerini bildir.

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
- Yedek: `~/.claude/scripts/db.sh backup <ana repo> [servis]` (servis başına son 5 yedek, `~/infra/backups/<proje>/<servis>/`). Listesi: `db.sh backups <ana repo>`.
- Geri yükleme development verisinin üzerine yazar ve geri alınamaz: hangi yedeğin kullanılacağını göster, kullanıcının açık onayını al, sonra `db.sh restore <ana repo> <servis> <dosya> --yes`.
