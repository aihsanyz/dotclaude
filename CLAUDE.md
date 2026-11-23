# Global Talimatlar

## İletişim
- Kullanıcıyla Türkçe konuş. Kod, kod yorumları, commit mesajları ve PR metinleri İngilizce olur.
- Kısa yaz: ne değişti, neyi doğruladın, ne kaldı.

## Kanıt
- "Geçti", "çalışıyor", "bitti" demeden önce ilgili komutu o turda çalıştır ve çıktısına dayan. Çalıştırmadıysan "çalıştırılmadı" de.
- Arayüz değişikliğini T3 tarayıcısında açıp kontrol et; `curl` yalnızca sunucunun ayakta olduğunu gösterir. T3 tarayıcısı yoksa Playwright'ı Docker'da çalıştır (`mcr.microsoft.com/playwright`, sabit etiket, `--rm`).
- Testi geçirmek için test silme, atlama veya hatayı susturma; kök nedeni bul.

## Güvenlik
- Geri alınamaz işlemlerden önce sor: `rm -rf`, `git reset --hard`, `git clean -f`, `docker compose down -v`, `docker volume rm`, `docker system prune`, veritabanı silme veya sıfırlama. Tek istisna, worktree ortamının kendi verisidir (`devenv.sh down` / `reset`). Guard hook bu komutlarda onay ister.
- Gizli bilgileri (`.env` değerleri, token, parola) çıktıya yazma, commit etme. Kullanıcıdan bir değer gerekiyorsa `request_secret` kullan.
- Sistem servislerine (docker, tailscaled vb.) sormadan dokunma.

## Çalışma
- Birden fazla dosyayı etkileyen değişiklikten önce kısa bir plan sun. Kritik belirsizlikte sor, küçük konuda makul varsayım yap ve belirt.
- Mevcut stile uy. İstenmeden refactor yapma. Yeni bağımlılıktan önce sor. Açıklayıcı olmayan yorum ekleme.
- Bir kapı başarısız olursa (CI, reviewer, security, `devenv.sh`) kendiliğinden düzeltme: sonucu, rapor yolunu ve yapılması gerekenleri kısa maddelerle ver, yönlendirmeyi bekle. Aynı sorun için en fazla 2 düzeltme turu yapılır; sonra karar kullanıcınındır.
- Uzun sürebilen komutlarda (build, bağımlılık kurulumu, `devenv.sh`, `scan.sh`) Bash'e `timeout: 600000` ver; daha uzun sürecekse arka planda çalıştır ve bitmesini bekle. Bir skill akışını kapıya, onay noktasına veya sonuç satırına gelmeden bırakma.
- Konu değiştiğinde veya oturum çok uzadığında yeni thread öner; işi `/handoff` ile aktar.

## Git ve teslim
- Kalıcı branch yalnızca `main`. Doğrudan `main`'e commit veya push yapılmaz (guard hook engeller).
- Her iş `origin/main`'den açılan kendi worktree'sinde, `<tür>/<kısa-ad>` branch'inde yapılır (`feat`, `fix`, `chore`, `docs`, `refactor`). T3'te bu, worktree modunda açılan thread'dir.
- Teslim skill'lerle yapılır ve kapılar atlanmaz:
  - `/ship`: yerel kontroller, reviewer, gerekirse security ve Codex incelemesi, push, PR.
  - `/land`: CI yeşilse squash merge, development ortamının güncellenmesi, temizlik.
  - `/release`: sürüm notu ve `vX.Y.Z` etiketi. Production'ı kullanıcı deploy hedefinde (Dokploy veya Portainer) bu etiketle günceller.
- Kullanıcının bir skill'i çağırması veya aynı işi doğal dille istemesi o adımın onayıdır. Bunun dışında PR açma ve merge etme.
- Commit ve PR metni: Conventional Commits başlığı + 1-2 maddelik açıklama. Emoji ve AI imzası yok. Squash'ta PR başlığı commit mesajı olur.
- `gh`'yi kurma, `gh auth login` çalıştırma, token okuma. `gh auth status` başarısızsa bildir. T3'te açtığın PR'ı `link_pull_request` ile bağla; CI beklenecekse `watch_pull_request` ile izle.
- **İstisna, `~/.claude` (dotclaude):** worktree ve PR kullanılmaz, doğrudan `main`'e commit edilip push edilir. Repo public olduğu için push öncesi `~/.claude/scripts/scan.sh secrets origin/main..HEAD` çalıştır; bulgu varsa push etme. `.gitignore` beyaz listedir; yeni dosyanın gizli veya makineye özel bilgi içermediğini doğrula.

## Docker ve host
- Host'a hiçbir şey kurma; host'ta yalnızca `local.md`'deki araçlar bulunur. Gerçekten gerekiyorsa kullanıcıdan iste (`gh` gibi).
- Bağımlılık kurma, test, lint, build, migration dahil tüm proje komutları container içinde çalışır (`docker compose run --rm` / `exec`). `-f` verme; compose dosyasını `.env`'deki `COMPOSE_FILE` seçer.
- Ayrıntılı Docker, migration, ağ ve CI kuralları `~/.claude/rules/` altındadır ve ilgili dosyalara dokunulunca yüklenir.

## Projeler
- Proje kuralları ve komutları projenin `AGENTS.md` dosyasındadır (Claude ve Codex ortak okur). Proje `CLAUDE.md`'si yalnızca `@AGENTS.md` içerir. `## Komutlar` anahtarları: `service`, `migrate`, `postdeploy`, `lint`, `test`, `seed`, `migrations`.
- Proje bu düzende değilse (`AGENTS.md` veya `## Komutlar` yoksa) `/new-project` öner.
- Ortamlar:
  - Ana klasör: `main`'i izleyen development ortamı, varsayılan portlarla sürekli ayakta.
  - Worktree: kendi ortamı, 4100–4999 aralığından port alır.
  - İkisi de `~/.claude/scripts/devenv.sh` ile yönetilir.
  - Production: ayrı sunucuda Dokploy (Compose türü) veya Portainer (Git stack), etiketle elle güncellenir. Hedef `AGENTS.md` → `## Deploy`'da yazar; hedefe özel adımlar `~/.claude/templates/deploy/` paketlerindedir.
- `docs/` (spec, plan, rapor) sunucuda servis edilmez. Agent raporları `docs/reports/<agent>/` altına yazılır.
- Yerel ağ ve Tailscale adresleri `local.md`'dedir; ortamı ayağa kaldırınca bu adresleri doğrula ve bildir.

## Subagent'lar
- Subagent'lar bu kurallara uyar. Push, PR açma ve merge yapmaz; dosya değiştirmeyen işler (araştırma, inceleme) worktree açmaz.
- Rapor üreten agent'lar raporu dosyaya yazar, ana oturuma yalnızca sonucu ve dosya yolunu döndürür.

## Makineye özel
@~/.claude/local.md
