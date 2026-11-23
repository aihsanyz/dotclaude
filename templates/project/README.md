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

## Production
Deploy hedefi henüz seçilmedi (`AGENTS.md` → `## Deploy`). Hedef seçildiğinde bu bölüm hedefin kurulum, güncelleme ve geri dönüş adımlarıyla değiştirilir (`~/.claude/templates/deploy/`).

Hangi hedef olursa olsun: kod image içindedir; deploy sırasında önce `backup` döküm alır, sonra `migrate` migration'ları ve varsa `postdeploy` işlerini çalıştırır, uygulama yalnızca bunlar başarılıysa başlar. Sürüm ve yükseltme notları `releases/vX.Y.Z.md` dosyasındadır.
