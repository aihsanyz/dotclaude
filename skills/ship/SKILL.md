---
name: ship
description: Worktree branch'ini teslime hazırlar. Branch'i origin/main ile günceller, yerel lint ve testi çalıştırır, reviewer'ı (artımlı veya kısa modda) ve hassas değişiklikte security agent'ını ve Codex çapraz incelemesini çalıştırır, raporları commit'ler, push eder, PR açar, PR'ı T3'te bağlar ve CI'ı izler. Kullanıcı /ship dediğinde veya "push et", "PR aç" dediğinde kullan.
disable-model-invocation: true
argument-hint: "[--cross] [worktree yolu]"
---

# /ship

Kullanıcının `/ship` demesi push ve PR onayıdır. Kapılar atlanmaz. Bir adım başarısız olursa dur ve bildir.

Genel kurallar:
- Git komutlarında `git -C <worktree mutlak yolu>` kullan; yolu shell değişkeniyle kurma.
- Ana repo: `git -C <worktree> rev-parse --path-format=absolute --git-common-dir` çıktısının üst dizini.
- **Kapı durumu** ana repoda `git config` ile tutulur:
  - `branch.<branch>.reviewedHead`
  - `branch.<branch>.securedHead`
  - `branch.<branch>.crossHead`
  - `branch.<branch>.fixRounds`

## 1. Ön kontroller
- Worktree olarak argümandaki yolu kullan; yoksa bulunulan dizini.
- Branch `main` veya `master` ise ya da bulunulan yer ana klasörse dur: iş bir worktree branch'inde olmalı.
- `gh auth status` başarısızsa dur ve bildir.
- `docs/reports/` dışında commit edilmemiş değişiklik varsa listele ve sor:
  - İşin parçasıysa Conventional Commits mesajıyla commit'le.
  - Değilse dur.

## 2. origin/main ile güncelle
- `git fetch origin`.
- `git merge-base --is-ancestor origin/main HEAD` başarısızsa: `git merge --no-edit origin/main`.
  - Rebase kullanma; push edilmiş branch'te force push gerekir.
  - Çakışma çıkarsa yalnızca emin olduğun çakışmaları çöz. Emin değilsen `git merge --abort` yap ve bildir.

## 3. Yerel kontroller
- Çalıştır (Bash `timeout: 600000`):
  - `~/.claude/scripts/devenv.sh run lint <worktree>`
  - `~/.claude/scripts/devenv.sh run test <worktree>`
- `.env` yoksa önce `devenv.sh up <worktree>` çalıştır.
- Komut tanımlı değilse bunu not et ve devam et.
- Başarısızsa dur: hatayı ve son çıktıyı bildir, yapılması gerekenleri kısa maddelerle özetle ve turu bitir.

## 4. Hassas değişiklik ve diff boyutu
- `git diff --name-only origin/main...HEAD` ile değişen dosyaları al.
- Şu yollardan biri değiştiyse **hassas** say:
  - kimlik doğrulama veya yetki kodu (`auth`, `login`, `session`, `permission`, `policy`, `middleware`, `token`)
  - migration dizini
  - bağımlılık ve lock dosyaları
  - `Dockerfile*`, `compose*.y*ml`, `.env*.example`, `.dockerignore`
  - `.github/`
  - web sunucusu veya proxy ayarları
  - statik dosya sunumu
- Reviewer'ın önceki raporu "Hassas değişiklik: evet" dediyse de hassas say.
- **Kısa mod:** Hassas değilse ve `git diff --shortstat origin/main...HEAD` toplamda 60 satırın altındaysa reviewer kısa modda çalışır.

## 5. İncelemeler
**Mod seçimi.** Her kapının kendi kaydı vardır: reviewer için `reviewedHead`, security için `securedHead`, Codex için `crossHead`. Her kapı için:
- Kayıt HEAD'e eşitse **veya** kayıt ile HEAD arasında yalnızca `docs/reports/` değiştiyse kapı atlanır.
- Kayıt HEAD'in atasıysa mod `incremental since=<kayıt>` olur. Önceki raporun yolu da verilir.
- Diğer durumlarda mod `full` olur. Reviewer için, 4. adım kısa mod dediyse `short`.

**Çalıştırılacaklar.** Aşağıdakileri **paralel** başlat ve hepsinin sonucunu bekle:
- **`reviewer` agent'ı:** worktree yolu, branch, mod ve varsa spec yolu (`docs/specs/` altında bu işe ait dosya) ile. 3. adımdaki lint ve test çıktısını da ver.
- **`security` agent'ı (yalnızca hassas değişiklikte):** worktree yolu, `origin/main...HEAD` kapsamı ve mod ile.
- **Codex çapraz incelemesi** (hassas değişiklikte kendiliğinden, `--cross` verildiyse her durumda):
  - `orchestrator_capabilities` ile Codex'in modelini seç ve `delegate_task` çağır. Ayarlar: `role: "review"`, `isolation: "shared"`, `target.providerInstanceId: "codex"`, `target.options: {reasoningEffort: "high"}`.
  - Görev metni şunları söyler:
    - `<worktree>` içindeki `origin/main...HEAD` diff'ini incele ve hiçbir dosyayı değiştirme. Artımlı modda asıl inceleme `<since>..HEAD` diff'idir; önceki Codex raporundaki bulguların kapanıp kapanmadığını da kontrol et.
    - Doğruluk, güvenlik ve veri kaybı riskine odaklan, yalnızca en az %80 emin olduğun bulguları yaz.
    - Raporu Türkçe olarak `docs/reports/codex/<YYYYMMDD-HHMM>-<branch>.md` dosyasına yaz.
    - İlk satır `# Codex İncelemesi: Hazır | Düzeltme gerekli` olsun; bulgular Kritik, Önemli ve Öneri başlıkları altında `dosya:satır` ile yazılsın.
    - Son satırda yalnızca sonucu ve rapor yolunu döndür.
  - Delegate'in sonucunu `next` yönlendirmesine göre bekle.

**Sonuç.**
- **Geçen her kapı** kendi kaydını hemen alır, diğer kapılar başarısız olsa bile: `git -C <ana repo> config branch.<branch>.reviewedHead|securedHead|crossHead <incelenen HEAD>`. Böylece sonraki turda yalnızca başarısız kapı tam çalışır, diğerleri yalnızca düzeltme diff'ine bakar.
- **Bir kapı başarısız olursa** (reviewer veya Codex "Düzeltme gerekli", security "Engellendi"):
  - Push yapma ve kendiliğinden düzeltme. Raporlar commit'lenmeden worktree'de kalır ve bir sonraki başarılı `/ship`'te diğer raporlarla birlikte commit'lenir.
  - `fixRounds` değerini 1 artır.
  - Rapor yollarını, engelleyen bulguları ve yapılması gerekenleri kısa maddelerle özetle ve turu bitir.
  - `fixRounds` 2'ye ulaştıysa bunu belirt: "Aynı iş için 2 düzeltme turu oldu; nasıl ilerleneceğine sen karar ver."
- **Kullanıcı düzelt derse:** düzelt, commit'le ve `/ship`'i yeniden çalıştır. Bu sefer incelemeler artımlı modda çalışır.
- **Önceden var olan bulgular** push'u durdurmaz. 8. adımdaki özette listelenir ve ayrı bir `fix/...` işi önerilir.

## 6. Raporları commit'le ve kapı durumunu kaydet
- Yeni raporları commit'le: `git add docs/reports/` ve `git commit -m "docs(reports): add review reports"`.
- Rapor commit'i yalnızca `docs/reports/` değiştirdiği için kapı kayıtları geçerli kalır. `fixRounds` değerini sıfırla.

## 7. Push ve PR
- `git push -u origin <branch>`. Guard hook engellerse kuralı aşmaya çalışma, nedenini bildir.
- PR zaten açıksa (`gh pr view <branch> --json number,url,state`) yeni PR açma.
- PR yoksa aç: `gh pr create --base main --head <branch> --title "<başlık>" --body-file <scratchpad dosyası>`.
  - **Başlık:** işin tamamını özetleyen Conventional Commits başlığı. Squash commit mesajı bu olur.
  - **Gövde:** 1-2 madde; emoji ve AI imzası yok.
- T3'te PR'ı `link_pull_request` ile bağla ve CI'ı `watch_pull_request` ile izle.

## 8. Bildir
Kısa özet:
- lint ve test sonucu
- reviewer, security ve Codex sonuçları, rapor yolları ve mod (atlandıysa nedeni)
- varsa önceden var olan bulgular
- push edilen commit'ler
- PR adresi
- "CI izleniyor; yeşil olunca `/land`" notu
