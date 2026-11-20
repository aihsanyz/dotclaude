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
- `~/.claude/scripts/deploy.sh rehearse <worktree yolu>`. Sırası: kontroller → ortam değişkeni eşitleme → worktree verisini yedekleyip development'ın güncel verisiyle değiştirme → build → migration → `up` → sağlık kontrolü → testler.
- `initer` branch'i için (development ortamı henüz yok) `--bootstrap` ile çalıştır; 6. adımda da `initer` skill'inin D akışındaki 7. adımı uygula.
- Script'in kontrolleri merge sonrası hataların bilinen sebeplerini yakalar: branch'in `origin/development`'ın gerisinde olması, commit edilmemiş değişiklik, development'ta zaten bulunan bir migration'ın değiştirilmesi, development `.env`'inde değeri olmayan yeni bir değişken.
- **Başarısızsa merge yapma.** Hatayı (adım, son çıktı) bildir. Branch henüz merge edilmediği için düzeltme **aynı branch'te** yapılır; branch'in kendi migration'ları düzenlenebilir (development'ta hiç çalışmadılar). Düzeltip `/merge`'i tekrar çalıştır. Kendiliğinden düzeltmeye başlama; kullanıcıya bildir ve iste.
  - "Development .env needs values" hatası: eksik değişkenlerin değerini kullanıcıdan iste (`request_secret` ile, gizliyse) ve hem worktree'nin hem ana repo klasörünün `.env`'ine yaz; değeri çıktıya yazdırma.
  - Prova öncesi worktree verisinin yedeği `~/infra/backups/<proje>/<servis>/wt-<branch>.gz` dosyasındadır (`db.sh backups <worktree>`); karşılaştırma için kullanılabilir.

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
- Yerel `development`'ı eşitle (`tasker` skill'inin 3. adımındaki yöntem).
- `~/.claude/scripts/deploy.sh apply <ana repo>`: provadaki adımların aynısı (veri kopyalanmaz ve yedeklenmez, testler çalışmaz). `RESULT: ok` ise başarılıdır.
- Prova geçtiyse burada hata beklenmez. Yine de başarısız olursa geri alma yapılmaz; 7. adımdan sonra doğrudan düzeltmeye geçilir (8. adım).

## 7. Temizlik (her durumda)
Merge edilen branch'in işi bitmiştir; development güncellemesi başarısız olsa bile temizlenir, düzeltme yeni bir branch'te yapılır.
- **Docker** (worktree'de `compose.yaml` varsa):
  - Worktree'nin `.env`'indeki `COMPOSE_PROJECT_NAME`'in development'ınkinden (`<proje>-dev`) farklı olduğunu doğrula; aynıysa dur ve sor.
  - `docker compose down -v --rmi local`: worktree'nin container'ları, image'ları ve veri servisleri dahil bütün volume'ları sormadan silinir. Bunlar yalnızca o worktree'ye aittir. Development'ın volume'ları asla otomatik silinmez.
  - Worktree yedeklerini sil: `~/.claude/scripts/db.sh forget <worktree yolu>`.
- **Worktree:** `git -C <ana repo> worktree remove <worktree yolu>`. Commit edilmemiş değişiklik nedeniyle reddederse dur ve sor; `--force` kullanma.
- **Branch'ler:**
  - `git -C <ana repo> branch -D <branch>`
  - `git -C <ana repo> push origin --delete <branch>`. GitHub branch'i zaten sildiyse çıkan hatayı yok say.
- **T3 Code:** Worktree T3 Code'un açtığı bir worktree'yse ve bir oturum hâlâ o dizindeyse, silmeden önce kullanıcıya bildir.

## 8. Bildir; development güncellemesi başarısızsa düzeltmeye geç
- Kısa özet: prova ve auditor sonucu, rapor yolu, PR başlığı, merge durumu, development ortamının durumu ve adresi, yapılan temizlik.
- `apply` başarısızsa: hatanın adımını ve son çıktısını bildir, ardından **hemen** `/tasker fix/<merge edilen branch'in adı>` ile düzeltme işini aç. Worktree development'ın güncel kodu ve verisiyle açıldığı için hata orada tekrarlanır; sebebi bul, düzelt ve değişikliği kullanıcıya göster. Push ve merge yine kullanıcının isteğiyle yapılır. Düzeltme merge edilene kadar diğer işlerin provaları da aynı hatayla durabilir; düzeltme önceliklidir.
