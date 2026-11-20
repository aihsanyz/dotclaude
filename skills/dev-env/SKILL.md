---
name: dev-env
description: Projenin sürekli ayakta duran development ortamını yönetir; ilk kurulum, merge sonrası güncelleme (build, yedek, migration, yeniden başlatma, doğrulama), durum, loglar, yeniden başlatma, yedek ve geri yükleme. Kullanıcı development ortamını kurmak, güncellemek, durumunu görmek veya yeniden başlatmak istediğinde (/dev-env) ve merge/release sonrasında kullan.
---

# /dev-env [kurulum | güncelle | durum | log | yeniden-başlat | yedek | geri-yükle]

Her projenin `development` ortamı ana repo klasöründe, `development` branch'inde sürekli ayakta durur. `main` için ortam tutulmaz. Tüm git komutlarında `git -C <mutlak yol>` kullan.

**Tanımlar**
- **Proje adı:** Ana repo dizininin adı (`db.sh` bunu `[a-z0-9_]`'e çevirir).
- **Ortak servisler:** Projenin `CLAUDE.md`'sinde belirtilir; yoksa `.env.example`'daki `DB_*` (postgres/mysql) ve `REDIS_*` değişkenlerinden çıkar.
- **Migration ve seed komutları:** Projenin `CLAUDE.md`'sinde tanımlıdır; tanımlı değilse kurulumda bul ve proje `CLAUDE.md`'sine ekle.

## kurulum (ortam yoksa)
1. Ana repo klasörü `development`'ta olmalı. Değilse ve çalışma alanı temizse `git switch development`; temiz değilse dur ve sor.
2. `development`'ı `origin/development` ile fast-forward eşitle.
3. `.env` yoksa `.env.example`'dan oluştur; `COMPOSE_PROJECT_NAME=<proje>-dev` yaz. Portlar `.env.example`'daki varsayılanlar olarak kalır; bu portlar development ortamına ayrılmıştır.
4. Her ortak servis için `~/.claude/scripts/db.sh init <engine> <proje> --env-file <ana repo>/.env`.
5. `docker compose build`, `docker compose up -d`, ardından migration ve varsa seed komutu (container içinde).
6. `local.md`'deki yerel ağ ve Tailscale adreslerini `curl` ile doğrula ve bildir.

## güncelle (her merge'den sonra)
1. `development`'ı `origin/development` ile fast-forward eşitle.
2. `docker compose build`. Başarısız olursa dur: eski container'lar çalışmaya devam eder; hatayı bildir.
3. Migration varsa önce yedek al: ortak SQL servisi için `db.sh backup <engine> <proje>`.
4. Migration'ı çalıştır (yeni image ile, ör. `docker compose run --rm <servis> <migration komutu>`).
   - Başarısız olursa **düzeltmeye çalışma**: hatayı, hangi migration'da durduğunu ve alınan yedeğin yolunu bildir. Düzeltme `/start-task fix/...` ile yapılır. Geri yükleme yalnızca kullanıcı isterse yapılır.
5. `docker compose up -d` (yalnızca değişen servisler yeniden başlar).
6. Adresleri `curl` ile doğrula; servis ayağa kalkmazsa son logları (`docker compose logs --tail 50`) bildir.
7. Güncelleme başarılıysa (build, migration, `up` ve `curl` hepsi geçtiyse) merge edilip temizlenmeyi bekleyen worktree'leri temizle: `merge` skill'inin 5. adımı. Bu, `/merge` dışında yapılan güncellemeler için de geçerlidir (ör. "tekrar dene").

## durum / log / yeniden-başlat
- Durum: `docker compose ps`, son commit (`git log -1 --oneline`), adreslerin `curl` sonucu.
- Log: `docker compose logs --tail 100 [servis]`.
- Yeniden başlatma: `docker compose restart [servis]`.

## yedek / geri-yükle
- Yedek: `db.sh backup <engine> <proje>` (son 5 yedek saklanır, `~/infra/shared/backups/`).
- Geri yükleme `<proje>_dev`'in üzerine yazar ve geri alınamaz: hangi yedeğin kullanılacağını göster, kullanıcının açık onayını al, sonra `db.sh restore <engine> <proje> <dosya> --yes`.
