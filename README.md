# FocusWriter Legacy (Qt5)

FocusWriter Legacy 是 [FocusWriter](https://gottcode.org/focuswriter/) 的 Qt5 經典相容版本，經調整後可與現代 Linux 發行版（如 Linux Mint 22+、Ubuntu 24.04 LTS+ 等）上由官方倉庫提供的 Qt6 新版 FocusWriter **完全並存且不衝突**。

---

## 主要特色與調整

* **獨立共存（Zero Conflicts）**：
  * 可執行檔名稱重新命名為 `focuswriter-legacy`。
  * 獨立的桌面捷徑檔 `focuswriter-legacy.desktop`（選單顯示名稱為 **FocusWriter Legacy** / **焦點作家 (舊版)**）。
  * 獨立的應用程式圖示、Man 手冊與共用資料目錄（`/usr/share/focuswriter-legacy/`）。
  * 獨立的 QtSingleApplication IPC ID（`org.gottcode.FocusWriterLegacy`）與配置路徑，避免與系統的 FocusWriter 衝突。
* **相容性修復**：
  * 支援 Qt 5.15+ 編譯環境（補齊 `<QPainterPath>` 標頭檔）。
  * 內建 Qt 訊息過濾器，自動過濾常見且無害的 `libpng warning: iCCP: known incorrect sRGB profile` 警告。
* **一鍵式打包支援**：
  * 附帶自動化 `.deb` 打包腳本 [`build_deb.sh`](build_deb.sh)。
  * 自動偵測當前作業系統版本（如 `mint22.3`、`noble` 等）並動態解析函式庫相依性。

---

## 快速打包成 .deb 檔

### 1. 編譯環境需求

在基於 Debian / Ubuntu / Linux Mint 的系統上，可透過以下指令安裝所需的編譯套件：

```bash
sudo apt update
sudo apt install -y build-essential pkg-config \
    qtbase5-dev qtbase5-dev-tools qttools5-dev-tools \
    qtmultimedia5-dev libqt5multimedia5 libhunspell-dev zlib1g-dev dpkg-dev
```

> **注意**：若未以 root/sudo 安裝上述套件，[`build_deb.sh`](build_deb.sh) 亦內建無 root 權限的備用機制，會自動透過 `apt-get download` 將缺少的開發庫提取至本機 `.build_deps` 快取進行編譯。

### 2. 執行打包

直接在專案根目錄下執行：

```bash
./build_deb.sh
```

腳本將會自動執行以下流程：
1. 偵測當前 OS 與架構（例如 `amd64`）。
2. 在獨立的工作目錄中執行 `qmake` 與 `make`。
3. 編譯多國語言翻譯檔（`.qm`）。
4. 剝除除錯符號（`strip`）並壓縮 Man 手冊（`gzip -9n`）。
5. 透過 `dpkg-shlibdeps` 自動計算當前系統精準的動態函式庫相依性（Depends）。
6. 生成符合 Debian 標準與 Lintian 規範的 `.deb` 套件檔。

打包完成後，`.deb` 檔案將產生於專案目錄中，例如：
`focuswriter-legacy_1.7.0-1~mint22.3_amd64.deb`

---

## 安裝與執行

### 安裝

```bash
sudo apt install ./focuswriter-legacy_*.deb
```

### 執行

* **終端機**：
  ```bash
  focuswriter-legacy
  ```
* **應用程式選單**：
  在「辦公」類別中點選 **FocusWriter Legacy**（或 **焦點作家 (舊版)**）。

### 移除

```bash
sudo apt remove focuswriter-legacy
```

---

## 授權

GNU General Public License v3.0 or later (GPL-3.0+)
原作者：Graeme Gott <graeme@gottcode.org>
專案網站：https://gottcode.org/focuswriter/
