# Global Talimatlar

## İletişim
- Kullanıcıyla her zaman Türkçe konuş; kod, kod yorumları, commit mesajları ve PR metinleri İngilizce olsun.
- Kısa ve net yanıt ver; ne değiştiğini ve neyin doğrulandığını söyle.

## Güvenlik
- **ÖNEMLİ:** Geri alınamaz işlemlerden önce mutlaka sor: `rm -rf`, `git reset --hard`, `git push --force`, `git clean -fd`, `docker compose down -v`, `docker volume rm`, `docker system prune`, veritabanı silme/sıfırlama (merge sonrası worktree veritabanları ve volume'ları hariç).
- Gizli bilgileri (`.env`, token, parola) çıktıya yazdırma ve commit etme.

## Çalışma Akışı
- Birden fazla dosyayı etkileyen değişikliklerden önce kısa bir plan sun.
- Kritik belirsizliklerde sor; küçük konularda makul varsayımı yap ve bunu belirt.
- Değişiklikten sonra projenin test/lint komutlarını çalıştır; başarısızsa çıktıyı göster.
- Testi geçirmek için testi silme, atlama veya hatayı susturma; sorunun asıl nedenini bul.

## Kod
- Mevcut koddaki stil ve kalıplara uy; istenmeden refactor yapma.
- Yeni bağımlılık eklemeden önce sor.
- Açıklayıcı olmayan yorumlar ekleme.
- Çalıştırma, test ve port bilgisi değişirse projenin README veya `CLAUDE.md` dosyasını güncelle; yeni projede bunları içeren bir proje `CLAUDE.md`'si oluştur.

## Git, Commit ve PR
- **ÖNEMLİ:** `main` ve `development`'a doğrudan commit/push yapma (guard hook ile zorlanır); PR'ları kullanıcı istemeden açma veya merge etme.
- Git'li projelerde `main` ve `development` ile çalışılır; `development` yoksa `main`'den oluştur ve uzağa gönder.
- Her iş `origin/development`'tan açılan bir worktree branch'inde yapılır (T3 Code'da da taban `origin/development`, `main` değil). Yerel `main` ve `development` uzaktakiyle her zaman fast-forward eşit tutulur.
- Geliştirme ilerledikçe commit at. Akışları skill'lerle yürüt, adımları elle tekrarlama; kapılar atlanmaz:
  - `/initer`: bulunulan klasörü bu düzene bir kez hazırlar; klasör boşsa seçilen stack'le yeni proje oluşturur, doluysa mevcut projeyi uyarlar (git, private GitHub reposu, `main`/`development`, stack ve komutları içeren proje `CLAUDE.md`'si, Docker ve `.env` uyumu, development ortamı). Diğer skill'lerden önce çalışır.
  - `/tasker`: yeni iş için worktree, branch, development verisinin kopyası ve Docker ortamı.
  - `/push`: reviewer kapısı, ardından push.
  - `/merge`: entegrasyon provası ve auditor kapısı, PR, `development`'a squash merge, development ortamının güncellenmesi ve temizlik.
  - `/release`: auditor + releaser, kullanıcı onayı, `main`'e merge commit, `vX.Y.Z` etiketi. Yalnızca kullanıcı sürüm çıkarmak istediğinde.
- Kullanıcının bir skill'i çağırması veya aynı işi doğal dille istemesi o adımın onayıdır.
- **İstisna:** `~/.claude` (dotclaude) reposu bu akıştan muaftır: worktree, `development`, PR ve skill'ler kullanılmaz; değişiklikler doğrudan `main`'e commit edilip push edilir. Repo public olduğu için push öncesi `~/.claude/scripts/scan.sh secrets origin/main..HEAD` çalıştır; bulgu varsa push yapma. `.gitignore` beyaz listedir; yeni bir dosyayı eklemeden önce gizli veya makineye özel bilgi içermediğini doğrula.
- Uzak repo yoksa PR akışı uygulanamaz; nasıl ilerleneceğini kullanıcıya sor.
- PR işlemleri `gh` ile yapılır. `gh` kurulu değilse kendin kurma; kullanıcıdan kurmasını iste (host kurulum yasağının tek istisnası). `gh` ve `git push` kullanıcının `gh auth login` ile tanımladığı oturumu kullanır; `gh auth login` çalıştırma, token'ı okuma veya kopyalama, `gh auth status` başarısızsa bildir. T3 Code içindeysen açtığın PR'ları `link_pull_request` ile thread'e bağla.
- Commit ve PR metinlerini kullanıcı yazmış gibi sade yaz: Conventional Commits başlığı + 1-2 maddelik kısa açıklama. Squash merge'de PR başlığı commit mesajı olacağı için PR başlığı da Conventional Commits formatında olmalı. Uzun paragraf, emoji ve Claude/AI imzası (`Co-Authored-By`, "Generated with" vb.) ekleme.

## Subagent ve Paralel Çalışma
- Subagent'lar da bu dosyadaki tüm kurallara uyar; push, PR açma ve merge yapmaz. Bunları yalnızca ana oturum kullanıcı onayıyla yapar.
- Subagent'lar birbirini çağıramaz; agent'ları sırayla ana oturum çalıştırır ve birinin raporunu diğerine dosya yoluyla iletir.
- Tüm agent raporları projenin `docs/reports/<agent adı>/` klasörüne yazılır ve ilgili işle birlikte commit edilir.
- Kullanıcı "incele" derse `reviewer`'ı, "güvenlik incelemesi" derse `auditor`'ü tek başına çalıştır.
- Dosya değiştiren her paralel iş, `origin/development`'tan açılan kendi worktree'sinde yapılır; sadece okuma yapan işler (arama, inceleme) için worktree açma.
- Her paralel iş kendi compose ortamını farklı portla ayağa kaldırır ve iş bitince kapatır.

## Docker ile Geliştirme
- Host'a hiçbir şey kurma: proje bağımlılıkları, runtime'lar, araçlar ve sistem paketleri dahil. Host'ta kesinlikle gerekiyorsa önce sor.
- Çalıştırılabilir uygulama projelerinde `Dockerfile`, `compose.yaml` ve `.dockerignore` bulunmalı. Yoksa plan sunarak ekle, varsa ona göre güncelle. Doküman, dotfiles, config gibi repolarda gerekmez.
- Bağımlılık kurma, test, lint, build, migration dahil tüm proje komutlarını container içinde çalıştır (`docker compose run --rm` / `docker compose exec`).
- Geliştirmede kaynak kodu bind mount ile bağla, hot reload kullan; `node_modules`, `.venv` gibi dizinler container içinde veya named volume'da kalsın.
- Yapılandırmayı `.env` ile yönet, `.env.example` tut.
- **ÖNEMLİ:** `docs/` çalıştığı sunucuda servis edilmemeli: `.dockerignore`'a ekle, image'a, build çıktısına veya statik sunuma dahil etme. GitHub'da bulunması sorun değil. Denetimi `auditor` yapar.

## Development Ortamı ve Veri Servisleri
- Her projenin `development` ortamı ana repo klasöründe (`development` branch'i) sürekli ayakta durur: `.env.example`'daki varsayılan portlar ve `COMPOSE_PROJECT_NAME=<proje>-dev`. Her merge'den sonra güncellenir. `main` için ortam tutulmaz.
- **ÖNEMLİ:** Merge sonrası development'ta tek bir standart işlem çalışır (`~/.claude/scripts/deploy.sh apply`: ortam değişkeni eşitleme, build, migration, `up`, sağlık kontrolü). Merge'den önce aynısı worktree'de, development verisinin güncel kopyasıyla provadan geçer (`deploy.sh rehearse`); prova geçmeden merge yapılmaz. Hatalar merge öncesinde yakalanır ve aynı branch'te düzeltilir.
- Merge sonrası development güncellemesi yine de başarısız olursa geri alma yapılmaz: hatayı bildir ve hemen `/tasker fix/...` ile düzeltmeye geç; düzeltme önceliklidir.
- Development ortamının durumu, logları ve yeniden başlatılması için ana klasörde `docker compose ps/logs/restart`. Veri yedeği ve geri yükleme yapılmaz.
- Migration'lar: development'ta uygulanmış bir migration asla düzenlenmez, düzeltme yeni bir migration'la yapılır. Henüz merge edilmemiş branch'in kendi migration'ları düzenlenebilir. MySQL'de yarım kalmış bir migration için nasıl ilerleneceğini kullanıcıya sor.
- Veri servisleri (PostgreSQL, MySQL, MariaDB, MongoDB, Redis vb.) projenin compose dosyasında tanımlanır. Development ve her worktree kendi container'larını ve volume'larını kullanır; portları yayınlanmaz. Bağlantı bilgileri resmi image değişkenleriyle (`POSTGRES_*`, `MYSQL_*`, `MARIADB_*`, `MONGO_INITDB_*`) `.env.example`'da durur.
- Worktree'ler development verisinin kopyasıyla başlar (`~/.claude/scripts/deploy.sh copy-data`); Redis gibi önbellekler ve kopyalanamayan motorlar boş başlar.
- Her worktree kendi veri servislerini çalıştırdığı için bellek sınırlıdır (MySQL ~450 MB); yeni worktree açmadan önce kullanılabilir belleğe bak, yetersizse kullanıcıyı uyar.
- Merge sonrası worktree'nin bütün compose volume'ları (veri dahil) sormadan silinir; development'ın volume'ları ve verisi asla otomatik silinmez veya sıfırlanmaz.
- Projenin stack bilgisi ve komutları proje `CLAUDE.md`'sindedir: `## Stack` (dil, framework, servisler) ve `## Komutlar` (`service`, `migrate`, `test`, `seed`, `migrations`; biçim `- anahtar: \`değer\``). `/initer` oluşturur, stack değişince aynı branch'te güncellenir; prova ve güncelleme `## Komutlar`'ı okur. Veri servisleri, motorları ve portlar `compose.yaml`'dan çıkarılır, ayrıca yazılmaz.

## Ağ Erişimi
- Uygulama ve arayüz servisleri yerel ağdan ve Tailscale'den erişilebilir olmalı:
  - Container içindeki uygulama `0.0.0.0` üzerinde dinlemeli (ör. `vite --host 0.0.0.0`).
  - Portları `.env` değişkeniyle tanımla (`"${APP_PORT}:<port>"`); aynı anda çalışan worktree'ler farklı port kullanmalı.
  - Dev server host kontrolüne (ör. Vite `allowedHosts`) makinenin Tailscale DNS adını ekle.
- Veritabanı, cache, kuyruk gibi iç servislerin portlarını yayınlama; Docker iç ağında kalsınlar.
- Port seçmeden önce kullanımda olup olmadığını kontrol et (`ss -tlnp`, `docker ps`).
- Ayağa kaldırdıktan sonra yerel ağ ve Tailscale adreslerini (`local.md`) `curl` ile doğrula ve bildir.

## Tarayıcı
- Tarayıcı gereken işlerde T3 Code tarayıcısını kullan.
- Kullanılamıyorsa Playwright'ı Docker container içinde çalıştır (`mcr.microsoft.com/playwright`, sabit sürüm etiketi, `--rm`).

## Sunucu Ortamı
- Host'ta yalnızca temel araçlar bulunur (`local.md`); runtime'lar ve geliştirme araçları (node, uv, go, make, gcc vb.) host'a kurulmaz. `gh` PR akışı için gereklidir; kurulu değilse kullanıcıdan kurmasını iste.
- Sistem servislerine (docker, tailscaled vb.) sormadan dokunma veya yeniden başlatma.

## Makineye Özel Ayarlar
@~/.claude/local.md
