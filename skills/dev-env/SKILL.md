---
name: dev-env
description: Projenin sürekli ayakta duran development ortamını yönetir; ilk kurulum, merge sonrası güncelleme (build, migration, yeniden başlatma, doğrulama), durum, loglar, yeniden başlatma, yedek ve geri yükleme. Kullanıcı development ortamını kurmak, güncellemek, durumunu görmek veya yeniden başlatmak istediğinde (/dev-env) ve merge/release sonrasında kullan.
---

# /dev-env [kurulum | güncelle | durum | log | yeniden-başlat | yedek | geri-yükle]

Her projenin `development` ortamı ana repo klasöründe, `development` branch'inde sürekli ayakta durur. `main` için ortam tutulmaz. Tüm git komutlarında `git -C <mutlak yol>` kullan.

**Tanımlar**
- **Proje adı:** Ana repo dizininin adı.
- **Veri servisleri:** Veritabanı ve önbellek servisleri (PostgreSQL, MySQL, MariaDB, MongoDB, Redis vb.) projenin compose dosyasında tanımlıdır. Development ve her worktree kendi container'larını ve volume'larını kullanır; portları yayınlanmaz. Bağlantı bilgileri resmi image değişkenleriyle (`POSTGRES_*`, `MYSQL_*`, `MARIADB_*`, `MONGO_INITDB_*`) `.env.example`'da durur.
- **Standart işlem:** `~/.claude/scripts/deploy.sh`. Merge sonrası güncelleme (`apply`) ile merge öncesi prova (`rehearse`) aynı adımları aynı sırayla çalıştırır; bu skill'de adımları elle tekrarlama.
- **Proje ayarları:** Projede commit edilen `.claude/stack.toml` (`initer` skill'i oluşturur; biçimi orada). Hem prova hem güncelleme bu dosyayı okur.

## kurulum (ortam yoksa)
- İlk kurulum `initer` skill'inin parçasıdır (7. adım). Projede `.claude/stack.toml` yoksa önce `/initer` çalıştır.
- `stack.toml` var ama ana repo klasöründe development ortamı yoksa (ör. sunucu yeni kuruldu): ana klasörü `development`'a geçir ve eşitle, `.env` yoksa `.env.example`'dan oluştur (`COMPOSE_PROJECT_NAME=<proje>-dev`), sonra `~/.claude/scripts/deploy.sh apply <ana repo> --bootstrap`.

## güncelle (her merge'den sonra)
1. `development`'ı `origin/development` ile fast-forward eşitle.
2. `~/.claude/scripts/deploy.sh apply <ana repo>`. Adımlar: kontroller, ortam değişkeni eşitleme, veri servislerini başlatma, build, migration, `up`, sağlık kontrolü. `RESULT: ok` başarıdır.
3. Başarısız olursa script'in gösterdiği adımı ve son çıktıyı bildir. Geri alma yapılmaz; hemen `/tasker fix/...` ile düzeltmeye geç (`merge` skill'inin 8. adımı).

## durum / log / yeniden-başlat
- Durum: `docker compose ps`, son commit (`git log -1 --oneline`), adreslerin `curl` sonucu.
- Log: `docker compose logs --tail 100 [servis]`.
- Yeniden başlatma: `docker compose restart [servis]`.

## yedek / geri-yükle
- Yedek merge akışında otomatik alınmaz; kullanıcı istediğinde: `~/.claude/scripts/db.sh backup <ana repo> [servis]` (servis başına son 5 yedek, `~/infra/backups/<proje>/<servis>/`). Listesi: `db.sh backups <ana repo>`.
- Geri yükleme development verisinin üzerine yazar ve geri alınamaz: hangi yedeğin kullanılacağını göster, kullanıcının açık onayını al, sonra `db.sh restore <ana repo> <servis> <dosya> --yes`.
