---
name: project-init
description: Bir projeyi bu çalışma düzenine hazırlar; stack'i inceleyip .claude/stack.toml ve proje CLAUDE.md'sini oluşturur, Docker ve .env dosyalarını global kurallara uyarlar, main/development branch'lerini kurar, değişiklikleri development'a alır ve development ortamını ilk kez ayağa kaldırır. Bir projede ilk kez çalışılacağında, .claude/stack.toml yoksa veya kullanıcı /project-init dediğinde kullan.
---

# /project-init

Bir projede `/start-task`, `/merge` ve `/dev-env` kullanılmadan önce bir kez çalışır. Amaç: stack bilgisinin agent tarafından bir kez çıkarılıp `.claude/stack.toml`'a yazılması; sonraki her iş, prova ve güncellemenin bu dosyadan okuması.

Tüm git komutlarında `git -C <mutlak yol>` kullan. Bir adım başarısız olursa dur ve bildir.

## 1. Ön koşullar
- Repo kökünü bul. Git yoksa veya `origin` yoksa dur ve kullanıcıya sor.
- `gh auth status` başarısızsa dur ve bildir.
- `.claude/stack.toml` zaten varsa: init yapılmış demektir; dosyayı projeyle karşılaştır, farkları göster ve yalnızca güncelleme gerekiyorsa devam et.

## 2. Branch modeli
- `git fetch origin --prune`
- `origin/development` yoksa `main`'den oluştur: `git push origin origin/main:refs/heads/development`.
- Ana repo klasörü development ortamı olacağı için `development`'a geçmeli. Çalışma alanı temiz değilse dur ve sor; temizse `git switch development`.

## 3. Projeyi incele
Kod tabanını okuyarak çıkar; tahminleri "doğrulanmadı" diye işaretle:
- Dil, framework ve sürüm (`package.json`, `composer.json`, `pyproject.toml`, `go.mod`, `Gemfile` vb.).
- Servisler: uygulama, worker, veri servisleri (veritabanı, önbellek, kuyruk, arama) ve motorları.
- Komutlar: migration, test, seed; hangi servisin içinde çalıştıkları.
- Migration dizini.
- HTTP sunan servislerin portları ve sağlık kontrolü yolu (varsa `/health`, `/up` gibi bir uç; yoksa `/`).

## 4. Kurallarla karşılaştır
Global `CLAUDE.md`'deki Docker, Ağ Erişimi ve Development Ortamı kurallarına göre eksikleri listele:
- `Dockerfile`, `compose.yaml`, `.dockerignore` var mı? `.dockerignore`'da `docs/` ve `.env` var mı?
- Veri servisleri compose'ta tanımlı mı, resmi image değişkenlerini (`POSTGRES_*`, `MYSQL_*` vb.) kullanıyor mu, portları yayınlanmamış mı, verileri volume'da mı?
- Uygulama `0.0.0.0`'da dinliyor mu? Portlar `.env` değişkeniyle mi tanımlı (`"${APP_PORT}:<port>"`)? Servislerde `healthcheck` ve `restart: unless-stopped` var mı?
- `.env.example` uygulamanın kullandığı bütün değişkenleri varsayılan değerleriyle içeriyor mu? `.env` `.gitignore`'da mı?
- Bind mount ve hot reload kuralları.

## 5. Planı onaylat
Kullanıcıya göster ve onay al (`send_to_user` ile, uzunsa):
- Oluşturulacak `stack.toml` içeriği.
- Proje `CLAUDE.md`'sinin içeriği (aşağıdaki şablon).
- Docker, `.env.example`, `.gitignore`, `.dockerignore` değişiklikleri; her biri için hangi kurala dayandığı.
- Yeni bağımlılık eklenmesi gerekiyorsa ayrıca belirt (global kural: önce sor).

## 6. Değişiklikleri uygula
- `/start-task chore/project-init` ile worktree aç. Bu ilk init olduğundan development ortamı ve `stack.toml` henüz yok; `start-task` skill'inin 5. adımındaki development kopyalama ve `stack.toml` ön koşulunu atla, veri servisleri boş başlar.
- Dosyaları oluştur ve düzenle, Conventional Commits mesajlarıyla commit'le (ör. `chore: add stack definition and dev environment setup`).
- `/merge` akışını uygula; **prova `deploy.sh rehearse <worktree> --bootstrap` ile çalışır** (development verisi henüz olmadığı için veri boş başlar ve seed çalışır). Diğer kapılar (reviewer, auditor) normal çalışır.

## 7. Development ortamını ilk kez kur
`/merge`'ün 6. adımında, `apply` yerine:
1. Ana repo klasöründe `.env` yoksa `.env.example`'dan oluştur; `COMPOSE_PROJECT_NAME=<proje>-dev` yaz.
2. `~/.claude/scripts/deploy.sh apply <ana repo> --bootstrap` (veri servisleri boş başlar, migration ve seed çalışır).
3. `local.md`'deki yerel ağ ve Tailscale adreslerini bildir.

## Şablonlar

### `.claude/stack.toml`
```toml
# Bu dosya project-init tarafından oluşturulur; stack değişince aynı branch'te güncellenir.
[project]
language = "php"
framework = "laravel 11"
health_timeout = 90                 # saniye, isteğe bağlı

[services.app]
role = "app"                        # app | worker | data | other
health = { port_var = "APP_PORT", path = "/up" }

[services.queue]
role = "worker"

[services.db]
role = "data"
engine = "postgres"                 # postgres | mysql | mariadb | mongodb kopyalanır; redis vb. boş başlar

[services.cache]
role = "data"
engine = "redis"

[commands]
service = "app"                     # komutların çalıştığı compose servisi
migrate = "php artisan migrate --force"
test = "php artisan test"
seed = "php artisan db:seed --force"   # yalnızca ilk kurulumda

[migrations]
dir = "database/migrations"
```
Servis adları `compose.yaml`'daki adlarla aynı olmalı. Olmayan alanları yazma (ör. migration yoksa `[migrations]` ve `migrate` yok).

### Proje `CLAUDE.md`
```markdown
# <Proje adı>

<Projenin ne yaptığı, bir cümle.>

## Stack
Ayrıntılar `.claude/stack.toml`'da; stack, servisler ve komutlar için önce onu oku, kod tabanını yeniden tarama.
- <dil / framework>, veri: <servisler>

## Çalıştırma
- Development ortamı: ana repo klasörü, `development` branch'i (`/dev-env`).
- Yeni iş: `/start-task`; komutlar container içinde: `docker compose run --rm <servis> <komut>`.

## Notlar
- <Projeye özel kurallar, bilinen tuzaklar.>
```
