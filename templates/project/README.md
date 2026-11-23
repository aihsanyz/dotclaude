# {{PROJECT}}

{{DESCRIPTION}}

## Development
Ortamı `.env`'deki `COMPOSE_FILE=compose.dev.yaml` seçer: bind mount ve hot reload.

```bash
cp .env.example .env
docker compose up -d --build --wait
docker compose logs -f
```

Migration ve seed (komutlar `AGENTS.md` → `## Komutlar`):

```bash
docker compose run --rm <service> sh -c "<migrate>"
docker compose run --rm <service> sh -c "<seed>"
```

## Production (Dokploy)
- Proje türü **Compose**, dosya `compose.prod.yaml`. Kod image içindedir, bind mount yoktur.
- Ortam değişkenleri Dokploy'da `.env.production.example`'daki anahtarlarla tanımlanır.
- Deploy sırasında `migrate` servisi önce veritabanı yedeğini alır, sonra migration'ları ve varsa `postdeploy` işlerini çalıştırır. Uygulama yalnızca bunlar başarılıysa başlar.

Güncelleme: Dokploy'da kaynak referansını yeni etikete (`vX.Y.Z`) çekip deploy et. Sürüm notları ve yükseltme notları `releases/vX.Y.Z.md` dosyasındadır.

Dokploy dışında elle kurulum:

```bash
git clone <repo> && cd {{PROJECT}} && git checkout vX.Y.Z
cp .env.production.example .env   # gizli değerleri doldur
docker compose up -d --build --wait
```
