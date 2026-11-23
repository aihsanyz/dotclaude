## Production (Portainer)
Production ayrı bir sunucuda Portainer stack'i olarak çalışır. Kaynak Git reposudur, ana dosya `compose.prod.yaml`.

İlk kurulum:
1. Portainer'da **Stacks → Add stack → Repository** seç. Repo bu repo, referans `refs/tags/vX.Y.Z`, compose yolu `compose.prod.yaml`.
2. Erişim yöntemini seç:
   - **Sunucuda ters vekil yoksa:** **Additional paths** alanına `compose.prod.ports.yaml` ekle. Bu dosya `{{APP_SERVICE}}` servisinin `{{APP_PORT}}` portunu `${APP_BIND}:${APP_PUBLISH_PORT}` üzerinden yayınlar. Dışarıya açılacaksa `APP_BIND=0.0.0.0` yap ve önüne TLS sağlayan bir vekil veya tünel koy.
   - **Ters vekil varsa** (Traefik, Nginx Proxy Manager, Caddy): ek dosyayı kullanma; vekili `{{APP_SERVICE}}:{{APP_PORT}}` adresine yönlendir ve gerekiyorsa servisi vekilin ağına ekle.
3. **Environment variables** bölümünde `.env.production.example`'daki anahtarları tanımla. Port eki kullanılıyorsa `APP_BIND` ve `APP_PUBLISH_PORT` değerlerini de gir. Gizli değerler repoya yazılmaz.
4. **Deploy the stack**. Sıra kendiliğinden işler: `backup` döküm alır, `migrate` migration'ları (ve varsa `postdeploy` işlerini) çalıştırır, uygulama yalnızca bunlar başarılıysa başlar.

Sürüm güncelleme:
1. `releases/vX.Y.Z.md` dosyasındaki **Upgrade Notes**'u oku. Yeni ortam değişkeni varsa önce stack'e ekle.
2. Stack ayarlarında referansı `refs/tags/vX.Y.Z` yap ve **Pull and redeploy** çalıştır. Migration'lar `migrate` servisiyle kendiliğinden çalışır.

Geri dönüş: Referansı önceki etikete çekip **Pull and redeploy** çalıştır. Migration'lar geriye uyumlu yazıldığı için eski sürüm yeni şemayla çalışır. Veriyi geri almak gerekirse `backups` volume'undaki son `pre-migrate-*.sql` dökümü kullanılır.
