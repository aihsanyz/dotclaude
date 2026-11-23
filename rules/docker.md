---
paths:
  - "**/Dockerfile*"
  - "**/compose*.yaml"
  - "**/compose*.yml"
  - "**/docker-compose*.y*ml"
  - "**/.env*.example"
  - "**/.dockerignore"
---

# Docker ve compose kuralları

- **İki ortam, iki dosya:**
  - `compose.dev.yaml`: development ortamı ve worktree'ler. Bind mount, hot reload ve Dockerfile'ın `dev` target'ı kullanılır. `node_modules` ve `.venv` gibi dizinler named volume'da durur.
  - `compose.prod.yaml`: production. Kod image'ın içindedir, bind mount yoktur. Dockerfile'ın `prod` target'ı ve `restart: unless-stopped` kullanılır.
  - Hangi dosyanın kullanılacağını `.env`'deki `COMPOSE_FILE` seçer: `.env.example` → `compose.dev.yaml`, `.env.production.example` → `compose.prod.yaml`.
- **Birlikte güncelle:** Servis, veri servisi veya değişken eklerken iki compose dosyasını ve iki örnek `.env`'i aynı commit'te güncelle. Servis adları iki dosyada aynı kalır.
- **Migration servisi:** `compose.prod.yaml`'da tek seferlik bir `migrate` servisi bulunur.
  - Uygulamayla aynı image'ı kullanır ve `AGENTS.md`'deki `migrate` komutunu, varsa ardından `postdeploy` komutunu çalıştırır.
  - Uygulama servisi buna `depends_on: { migrate: { condition: service_completed_successfully } }` ile bağlanır. Migration başarısızsa yeni sürüm başlamaz.
  - Production'da migration'dan önce veritabanı dökümü alınır (`pg_dump` / `mysqldump`) ve ayrı bir yedek volume'una yazılır.
- **Portlar:**
  - Uygulama portları `.env` değişkeniyle tanımlanır (`"${APP_PORT}:3000"`).
  - Veritabanı, cache ve kuyruk gibi iç servislerin portları yayınlanmaz.
  - Bağlantı bilgileri resmi image değişkenleriyle (`POSTGRES_*`, `MYSQL_*`, `MARIADB_*`, `MONGO_INITDB_*`) `.env.example`'da durur.
- **Image'lar:**
  - Base image'lar sabit sürümlüdür; `latest` kullanılmaz.
  - Production image'ı root olmayan bir kullanıcıyla çalışır.
  - `privileged` ve Docker socket mount'u kullanılmaz.
  - Veri servisinin ana sürümünü yükseltmeden önce (ör. postgres 17 → 18) kullanıcıya bildir ve yükseltme planı sun. Mevcut volume'lar yeni ana sürümle açılmaz.
- **Gizli bilgi ve `docs/`:**
  - `.dockerignore` en az `.git`, `.env`, `.env.*`, `!.env*.example` ve `docs/` satırlarını içerir.
  - `docs/` image'a, build çıktısına veya statik sunuma girmez.
- **Healthcheck:** Her servisin bir healthcheck'i olur; `docker compose up --wait` buna dayanır.
