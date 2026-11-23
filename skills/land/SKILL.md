---
name: land
description: Bir worktree branch'inin PR'ını CI yeşil ve inceleme güncelse squash merge eder, ana klasördeki development ortamını devenv.sh apply ile günceller, worktree ortamını ve branch'i temizler. Kullanıcı /land dediğinde veya "merge et", "main'e al" dediğinde kullan.
disable-model-invocation: true
argument-hint: "[PR numarası veya worktree yolu]"
---

# /land

Kullanıcının `/land` demesi merge onayıdır. CI ve inceleme kapıları atlanmaz. Bir adım başarısız olursa dur ve bildir.

Genel kurallar:
- Git komutlarında `git -C <mutlak yol>` kullan.
- Ana repo, `git rev-parse --path-format=absolute --git-common-dir` çıktısının üst dizinidir.
- Komutları ana repo dizininden çalıştır; worktree birazdan silinecek.

## 1. PR'ı bul
- Argüman bir PR numarasıysa onu kullan. Değilse worktree'nin branch'ine ait PR'ı bul (`gh pr view <branch>`). PR yoksa dur ve `/ship` öner.
- Al: `gh pr view <PR> --json number,title,state,headRefName,headRefOid,baseRefName,mergeStateStatus,statusCheckRollup,url`.
- `state` `MERGED` ise 5. adımdan devam et. `CLOSED` ise dur.
- `baseRefName` `main` olmalı.

## 2. Kapılar
**Branch güncel mi?**
- `git fetch origin`.
- `origin/main` PR'ın head'inin atası değilse branch geride kalmıştır:
  - `/ship`'in 2. adımındaki gibi `origin/main`'i branch'e merge et.
  - Push et. CI yeniden çalışır.
  - `watch_pull_request` ile izle ve turu bitir: "CI bitince `/land` tekrar."

**CI.** `statusCheckRollup` içinde `lint`, `test`, `rehearse` ve `scan` kontrolleri bulunmalı ve hepsi PR'ın head commit'i için `SUCCESS` olmalı.
- **Bekleyen veya eksik kontrol varsa:** `watch_pull_request` ile izle ve turu bitir.
- **Başarısız kontrol varsa:**
  - Başarısız run'ın log'unu al: `gh run view <run> --log-failed`; son satırları özetle.
  - Merge yapma ve kendiliğinden düzeltme. Yapılması gerekenleri kısa maddelerle özetle ve turu bitir.
  - Kullanıcı düzelt derse: düzelt, commit'le, `/ship`, sonra `/land`.

**İnceleme güncel mi?** Ana repoda kapı kayıtlarını oku (`git config branch.<branch>.<anahtar>`):
- Reviewer: `reviewedOk` `true` olmalı ve `reviewedHead..<head>` arasında `docs/reports/` dışında değişiklik olmamalı (`git diff --name-only`).
- Branch'te `docs/reports/security/` veya `docs/reports/codex/` raporu varsa (hassas değişiklik), aynı kural `securedHead`/`securedOk` ve `crossHead`/`crossOk` için de geçerlidir.
- Bir koşul sağlanmıyorsa veya kayıt yoksa dur ve `/ship` öner.

## 3. Merge
- Gövdeyi hazırla: PR açıklamasından 1-2 madde.
- Çalıştır: `gh pr merge <PR> --squash --match-head-commit <headRefOid> --subject "<PR başlığı> (#<PR>)" --body "<1-2 madde>"`.
  - `--admin` ve `--delete-branch` kullanma.
- Merge'ü doğrula: `gh pr view <PR> --json state` sonucu `MERGED` olmalı.

## 4. Ana klasör ve development ortamı
- `git -C <ana repo> fetch origin --prune`.
- Ana klasör `main`'de ve temizse güncelle: `git -C <ana repo> merge --ff-only origin/main`.
  - Ana klasör başka bir branch'teyse, temiz değilse veya fast-forward mümkün değilse dur ve sor. Ana klasörde kod değiştirilmez.
- Development ortamını güncelle: `~/.claude/scripts/devenv.sh apply <ana repo>` (Bash `timeout: 600000`).
  - İlk kurulumda seed kendiliğinden çalışır. Çıkan adresleri bildir.
  - Arayüz değiştiyse sayfayı T3 tarayıcısında aç ve kontrol et.
  - **`apply` başarısızsa geri alma yapılmaz.** Hata adımını ve son çıktıyı not et. 6. adımda bildir. Temizlik yine yapılır.

## 5. Temizlik
Bu adım worktree'ye ait her şeyi kaldırır.
- **Docker:** `~/.claude/scripts/devenv.sh down <worktree>`. Bu yalnızca worktree'nin container'larını, volume'larını ve image'larını siler; development ortamına dokunmaz.
- **Worktree dizini:**
  - Worktree T3'ün açtığı bir worktree'yse (`~/.t3/worktrees/` altında) dizini silme. Kullanıcıya "T3'te bu thread'i arşivle; worktree'yi T3 kaldırır" de.
  - Değilse `git -C <ana repo> worktree remove <worktree>` çalıştır. Commit edilmemiş değişiklik yüzünden reddederse dur ve sor; `--force` kullanma.
- **Branch'ler:**
  - Yerel: `git -C <ana repo> branch -D <branch>`. Worktree hâlâ duruyorsa bu adım atlanır.
  - Uzak: `git -C <ana repo> push origin --delete <branch>`. GitHub branch'i zaten sildiyse çıkan hatayı yok say.
- **Kapı durumu:** `git -C <ana repo> config --remove-section branch.<branch>`. Bölüm yoksa hatayı yok say.

## 6. Bildir
Kısa özet:
- PR, merge commit'i ve squash başlığı
- CI sonucu
- development ortamının durumu ve adresleri
- yapılan temizlik

`apply` başarısız olduysa:
- adımı, son çıktıyı ve olası sebebi bildir
- düzeltme için yeni bir worktree thread'inde `fix/<branch>` işi öner
- kendiliğinden başlama
