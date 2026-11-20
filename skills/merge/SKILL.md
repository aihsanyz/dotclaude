---
name: merge
description: Bir worktree branch'ini development'a alır; gerekirse push akışını çalıştırır, merge sonrası standart işlemi worktree'de provadan ve auditor güvenlik kapısından geçirir, PR açıp squash merge eder, sonra yerel development'ı eşitler ve worktree, branch ve Docker kaynaklarını temizler. Kullanıcı bir işi development'a merge etmek istediğinde (/merge) veya bir PR'ın merge edildiğini bildirdiğinde kullan. Kullanıcının bunu istemesi PR açma ve merge isteğidir.
---

# /merge

Kullanıcının `/merge` yazması veya merge istemesi PR açma ve merge isteğidir; ayrıca onay isteme. Auditor kapısı atlanmaz. Bir adım başarısız olursa dur ve bildir.

Tüm git komutlarında `git -C <mutlak yol>` kullan; shell değişkeniyle yol kurma.

## 1. Push durumu
- Branch hiç push edilmemişse, yerelde push edilmemiş commit varsa (`git log origin/<branch>..HEAD`) veya `origin/development`'ın gerisindeyse: `push` skill'inin adımlarını uygula (reviewer kapısı dahil). Bu, branch'i `origin/development` ile de günceller.

## 2. Entegrasyon provası (merge öncesi, worktree içinde)
Merge sonrası development'ta çalışacak standart işlemin birebir aynısı worktree'de denenir; hataların merge'den önce yakalanması hedeflenir.
- `~/.claude/scripts/deploy.sh rehearse <worktree yolu>`. Sırası: kontroller → ortam değişkeni eşitleme → worktree veritabanını yedekleyip güncel `<proje>_dev`'den yeniden kopyalama → build → migration → `up` → sağlık kontrolü → testler.
- Script'in kontrolleri merge sonrası hataların bilinen sebeplerini yakalar: branch'in `origin/development`'ın gerisinde olması, commit edilmemiş değişiklik, development'ta zaten bulunan bir migration'ın değiştirilmesi, development `.env`'inde değeri olmayan yeni bir değişken.
- **Başarısızsa merge yapma.** Hatayı (adım, son çıktı) bildir. Branch henüz merge edilmediği için düzeltme **aynı branch'te** yapılır; branch'in kendi migration'ları düzenlenebilir (development'ta hiç çalışmadılar). Düzeltip `/merge`'i tekrar çalıştır. Kendiliğinden düzeltmeye başlama; kullanıcıya bildir ve iste.
  - "Development .env needs values" hatası: eksik değişkenlerin değerini kullanıcıdan iste (`request_secret` ile, gizliyse) ve hem worktree'nin hem ana repo klasörünün `.env`'ine yaz; değeri çıktıya yazdırma.
  - Prova öncesi worktree veritabanının yedeği `~/infra/shared/backups/<engine>/worktrees/` altındadır; karşılaştırma için kullanılabilir.

## 3. Auditor kapısı
- `auditor` agent'ını worktree yolu ve `origin/development...HEAD` kapsamıyla çalıştır.
- Sonuç "Engellendi" ise:
  - Bulguları kullanıcıya kısaca bildir, düzelt, commit'le, `push` adımlarını uygula, provayı ve auditor'ü tekrar çalıştır.
  - İki düzeltme turundan sonra hâlâ geçmiyorsa dur ve kullanıcıya sor.
- "Geçti" ise raporu commit'le (`docs(reports): add auditor report`) ve push et. Yalnızca rapor değiştiği için reviewer ve prova tekrar çalışmaz.

## 4. Merge öncesi son kontrol
- `git fetch origin`. Prova kaydını oku: `git -C <ana repo> config branch.<branch>.rehearsedBase` ve `rehearsedHead`.
- `origin/development` provadakiyle aynı olmalı (`rehearsedBase`). Değilse başka bir iş merge edilmiştir: `push` adımlarını uygula (branch güncellenir) ve 2. adımdan tekrar başla.
- `rehearsedHead`'den bu yana yalnızca `docs/reports/` altı değişmiş olmalı (`git diff --name-only <rehearsedHead> HEAD`). Değilse 2. adımdan tekrar başla.

## 5. PR aç ve squash merge et
- **Başlık:** Squash commit mesajı olacağı için işin tamamını özetleyen Conventional Commits başlığı (ör. `feat(auth): add user login`).
- **Açıklama:** 1-2 madde; paragraf, emoji ve AI imzası yok.
- **Hedef:** `development`; **yöntem:** squash merge.
- **Araç: `gh`**
  - `command -v gh` başarısızsa dur ve kullanıcıdan kurmasını iste (`sudo apt install gh`); kendin kurma.
  - `gh auth status` başarısızsa dur ve bildir; `gh auth login` çalıştırma, token'ı kopyalama.
- **PR açma:** `gh pr create --base development --head <branch> --title "<başlık>" --body-file <geçici dosya>`. Gövdeyi scratchpad'deki geçici bir dosyadan ver, shell tırnaklama hatalarını önler.
- **T3 Code:** `link_pull_request` aracı varsa PR'ın tam URL'siyle hemen çağır; PR thread'de görünür ve durumu izlenir.
- **Merge:** `gh pr merge <PR> --squash --match-head-commit <HEAD sha> --subject "<başlık>" --body "<1-2 madde>"`. `--match-head-commit` provadan geçen commit'in merge edildiğini garanti eder. `--delete-branch` kullanma, temizliği 7. adım yapar.
- Repo'da branch koruma kuralları gereği bekleyen kontrol veya onay varsa merge'ü zorlama (`--admin` kullanma); durumu bildir ve turu bitir. Kullanıcı "merge edildi" dediğinde 4. adımın kontrollerini tekrarlamadan 6. adımdan devam et.

## 6. Merge sonrası: standart işlemin development'ta uygulanması
- Merge'ün gerçekleştiğini doğrula: `gh pr view <PR> --json state` sonucu `MERGED` olmalı; ardından `git fetch origin --prune`.
- Yerel `development`'ı eşitle (`start-task` skill'inin 3. adımındaki yöntem).
- `~/.claude/scripts/deploy.sh apply <ana repo>`: provadaki adımların aynısı (veri adımında yedek alınır, testler çalışmaz). `RESULT: ok` ise başarılıdır.
- Prova geçtiyse burada hata beklenmez; aşağıdaki akış istisnalar (ortama özgü farklar, geçici hatalar) için yedek mekanizmadır.
- **Başarısızsa temizlik yapma** (build, migration, `up` veya `curl`; hangisi olursa olsun): worktree'yi, container'larını, veritabanını ve branch'lerini olduğu gibi bırak; karşılaştırma ve teşhis için gerekir. Bu worktree artık **bekleyen** durumdadır.
  - Hatanın hangi adımda olduğunu, development ortamının o anki durumunu, worktree yolunu ve adresini bildir:
    - Build: development eski haliyle çalışıyor.
    - Migration: uygulama yeniden başlatılmadı; alınan yedeğin yolunu ver.
    - `up` veya `curl`: development ortamı kapalı veya kullanılamıyor olabilir; bunu açıkça belirt ve hızlı çözüm olarak "Geri al"ı öne çıkar.
  - Kullanıcıya şu seçenekleri sun; hangisinin uygulanacağına kullanıcı karar verir, kendiliğinden düzeltmeye başlama:
    1. **Düzelt:** `/start-task fix/...`; yeni branch bu worktree'yi çözüyor olarak işaretlenir (squash merge edilmiş branch'e devam edilmez). Ardından `/push` ve `/merge`.
    2. **Geri al:** `/start-task revert/...`; aynı şekilde işaretlenir, branch'te `git revert <squash commit>`, ardından `/push` ve `/merge`.
    3. **Tekrar dene:** Geçici hatalar için (ağ, image indirme, dolu port) `/dev-env güncelle`.
    4. **Yine de temizle:** Kullanıcının seçtiği bekleyen worktree'ler için 7. adımın temizlik işlemlerini development ortamının durumuna bakmadan uygula.
  - 8. adıma geç.

## 7. Temizlik (yalnızca development güncellemesi başarılıysa)
Geliştirmesi süren worktree'lere (PR'ı olmayan, açık olan veya merge'den sonra yeni commit almış) asla dokunma.

**Merge edilmiş sayılma koşulu** (bir worktree'nin temizlenebilmesi için ikisi birden):
- `gh pr list --head <branch> --state merged --json number,headRefOid` merge edilmiş bir PR döndürüyor.
- O PR'ın `headRefOid`'i branch'in şu anki commit'ine (`git rev-parse <branch>`) eşit. Eşit değilse branch merge'den sonra değişmiş veya aynı adla yeni bir iş açılmıştır; atla.

**Hangi worktree'ler temizlenir:**
1. Az önce merge edilen branch'in worktree'si: otomatik.
2. Bu branch'in çözdüğü olarak işaretlenmiş bekleyen worktree'ler (`git -C <ana repo> config --get-all branch.<branch>.resolves`): koşulu sağlıyorlarsa otomatik.
3. Merge edilmiş sayılan diğer bekleyen worktree'ler: **otomatik silme.** Development artık sağlıklı olduğu için kullanıcıya liste halinde sor (çoklu seçim; her biri için branch, merge edildiği PR ve neden beklediği). Yalnızca seçilenleri temizle, diğerleri beklemeye devam eder.

Her biri için:
- **Docker** (worktree'de `compose.yaml` varsa):
  - `docker compose down --rmi local`
  - Her ortak servis için worktree veritabanını sormadan sil: `~/.claude/scripts/db.sh drop <engine> <proje> <branch>`. `<proje>_dev` asla silinmez; script de bunu reddeder.
  - Worktree'nin compose projesine ait başka volume'lar varsa (`docker volume ls --filter label=com.docker.compose.project=<COMPOSE_PROJECT_NAME>`) listele ve silmeden önce sor.
- **Worktree:** `git -C <ana repo> worktree remove <worktree yolu>`. Commit edilmemiş değişiklik nedeniyle reddederse o worktree'yi atla ve sor; `--force` kullanma.
- **Branch'ler:**
  - `git -C <ana repo> branch -D <branch>`
  - `git -C <ana repo> push origin --delete <branch>`. GitHub branch'i zaten sildiyse çıkan hatayı yok say.
- **T3 Code:** Worktree T3 Code'un açtığı bir worktree'yse ve bir oturum hâlâ o dizindeyse, silmeden önce kullanıcıya bildir.

## 8. Bildir
Kısa özet: prova sonucu, auditor sonucu ve rapor yolu, PR başlığı, merge durumu, development ortamının durumu ve adresi, yapılan veya bekletilen temizlik.
