---
name: merge
description: Bir worktree branch'ini development'a alır; gerekirse push akışını çalıştırır, auditor güvenlik kapısından geçirir, PR açıp squash merge eder, sonra yerel development'ı eşitler ve worktree, branch ve Docker kaynaklarını temizler. Kullanıcı bir işi development'a merge etmek istediğinde (/merge) veya bir PR'ın merge edildiğini bildirdiğinde kullan. Kullanıcının bunu istemesi PR açma ve merge isteğidir.
---

# /merge

Kullanıcının `/merge` yazması veya merge istemesi PR açma ve merge isteğidir; ayrıca onay isteme. Auditor kapısı atlanmaz. Bir adım başarısız olursa dur ve bildir.

Tüm git komutlarında `git -C <mutlak yol>` kullan; shell değişkeniyle yol kurma.

## 1. Push durumu
- Branch hiç push edilmemişse, yerelde push edilmemiş commit varsa (`git log origin/<branch>..HEAD`) veya `origin/development`'ın gerisindeyse: `push` skill'inin adımlarını uygula (reviewer kapısı dahil).

## 2. Auditor kapısı
- `auditor` agent'ını worktree yolu ve `origin/development...HEAD` kapsamıyla çalıştır.
- Sonuç "Engellendi" ise:
  - Bulguları kullanıcıya kısaca bildir, düzelt, commit'le, `push` adımlarını uygula ve auditor'ü tekrar çalıştır.
  - İki düzeltme turundan sonra hâlâ geçmiyorsa dur ve kullanıcıya sor.
- "Geçti" ise raporu commit'le (`docs(reports): add auditor report`) ve push et. Yalnızca rapor değiştiği için reviewer tekrar çalışmaz.

## 3. PR aç ve squash merge et
- **Başlık:** Squash commit mesajı olacağı için işin tamamını özetleyen Conventional Commits başlığı (ör. `feat(auth): add user login`).
- **Açıklama:** 1-2 madde; paragraf, emoji ve AI imzası yok.
- **Hedef:** `development`; **yöntem:** squash merge.
- **Araç: `gh`**
  - `command -v gh` başarısızsa dur ve kullanıcıdan kurmasını iste (`sudo apt install gh`); kendin kurma.
  - `gh auth status` başarısızsa dur ve bildir; `gh auth login` çalıştırma, token'ı kopyalama.
- **PR açma:** `gh pr create --base development --head <branch> --title "<başlık>" --body-file <geçici dosya>`. Gövdeyi scratchpad'deki geçici bir dosyadan ver, shell tırnaklama hatalarını önler.
- **T3 Code:** `link_pull_request` aracı varsa PR'ın tam URL'siyle hemen çağır; PR thread'de görünür ve durumu izlenir.
- **Merge:** `gh pr merge <PR> --squash --subject "<başlık>" --body "<1-2 madde>"`. `--delete-branch` kullanma, temizliği 5. adım yapar.
- Repo'da branch koruma kuralları gereği bekleyen kontrol veya onay varsa merge'ü zorlama (`--admin` kullanma); durumu bildir ve turu bitir. Kullanıcı "merge edildi" dediğinde 4. adımdan devam et.

## 4. Merge sonrası: önce development ortamı
- Merge'ün gerçekleştiğini doğrula: `gh pr view <PR> --json state` sonucu `MERGED` olmalı; ardından `git fetch origin --prune`.
- Yerel `development`'ı eşitle (`start-task` skill'inin 3. adımındaki yöntem).
- **Development ortamını güncelle:** `dev-env` skill'inin güncelleme adımları. Build, migration, `up` ve `curl` doğrulamasının hepsi geçerse güncelleme başarılıdır.
- **Başarısızsa temizlik yapma:** worktree'yi, container'larını, veritabanını ve branch'lerini olduğu gibi bırak; karşılaştırma ve teşhis için gerekir. Hatayı, worktree yolunu ve adresini bildir; düzeltmenin `/start-task fix/...` ile yeni bir branch'te yapılacağını söyle (squash merge edilmiş branch'e devam edilmez). 6. adıma geç.

## 5. Temizlik (yalnızca development ortamı sağlıklıysa)
Bu worktree'yi ve daha önce merge edilip temizlenmeyi bekleyen worktree'leri temizle. Bekleyenleri bul: `git worktree list` içindeki her branch için `gh pr list --head <branch> --state merged --json number` sonuç döndürüyorsa merge edilmiştir. Her biri için:
- **Docker** (worktree'de `compose.yaml` varsa):
  - `docker compose down --rmi local`
  - Her ortak servis için worktree veritabanını sormadan sil: `~/.claude/scripts/db.sh drop <engine> <proje> <branch>`. `<proje>_dev` asla silinmez; script de bunu reddeder.
  - Worktree'nin compose projesine ait başka volume'lar varsa (`docker volume ls --filter label=com.docker.compose.project=<COMPOSE_PROJECT_NAME>`) listele ve silmeden önce sor.
- **Worktree:** `git -C <ana repo> worktree remove <worktree yolu>`. Commit edilmemiş değişiklik nedeniyle reddederse o worktree'yi atla ve sor; `--force` kullanma.
- **Branch'ler:**
  - `git -C <ana repo> branch -D <branch>`
  - `git -C <ana repo> push origin --delete <branch>`. GitHub branch'i zaten sildiyse çıkan hatayı yok say.
- **T3 Code:** Worktree T3 Code'un açtığı bir worktree'yse ve bir oturum hâlâ o dizindeyse, silmeden önce kullanıcıya bildir.

## 6. Bildir
Kısa özet: auditor sonucu ve rapor yolu, PR başlığı, merge durumu, development ortamının durumu ve adresi, yapılan veya bekletilen temizlik.
