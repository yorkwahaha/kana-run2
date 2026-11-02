# Kana Run 2.0 — 試玩版（33 關）

Godot **4.7.2**（`I:\Projects\Godot_v4.7.2`），**Mobile** 渲染器（Web 匯出時自動改用 Compatibility）。
舊專案 `I:\Projects\Kana Run` 是凍結的 1.0 Beta，**不要修改**；本專案只從那裡複製了素材。

## 怎麼玩
- 電腦：雙擊 `play.bat`（開發者計時模式：`play-dev.bat`），或 `editor.bat` 開編輯器後按 F5。
- 手機（同一個 Wi‑Fi）：
  1. `export-web.bat` → 產生 `build/web/`
  2. `python serve_web.py` → https://<電腦IP>:8443 （例：https://192.168.50.107:8443）
  3. Godot 4.7 Web 一定要 https（secure context），所以用 1.0 的自簽憑證（已複製到 `build/certs/`；若手機沒裝過，見 `serve_web.py` 開頭說明；要重產用 `python make_certs.py`）。
- 自動測試：`selftest.bat`（單元／回歸測試 + 自動駕駛跑 1-1、1-BOSS、究極魔王，賽車與點放兩種模式）。

## 速度模式（選關畫面「設定」或暫停選單切換，存在存檔裡）
- **賽車模式**（預設）：按住加速／按住煞車／都不按自然減速。**定速鎖定**：「鎖定」鈕或 F 鍵，鎖住當下速度；鎖定時不按任何鍵會維持速度；仍可暫時按住加速或煞車，放開後沿加速／煞車曲線回到鎖定速度（不是瞬間）。再按一次解除。HUD 顯示「鎖定 xx」。
- **點放模式**：點一下加速 = 目標 +5 km/h，點一下煞車 = −5（0～60，`speed.step_kmh`）。實際速度沿加速／煞車曲線追目標；不按就維持目標，不會自然減速。HUD 顯示「目前 → 目標 km/h」。撞錯仍是速度減半；`speed.step_wrong_halves_target`（預設 true）決定目標要不要一起減半。鍵盤長按的自動重複（echo）會被忽略，一次按下只算一格。
- 跑到一半切換：賽車→點放時，目標 = 目前速度取到最近的 5 km/h；點放→賽車時解除鎖定、保留目前速度。切換時放開所有輸入。
- 兩種模式共用時限。結算畫面、計時 JSON／CSV 都會記錄模式（摘要檔現在是 `runs_v4.csv`，有 `mode`、`distance`、`target`、`points` 欄）。

## 操作
| 動作 | 手機 / 滑鼠 | 鍵盤 |
|---|---|---|
| 加速 | 右下「加速」（賽車：按住；點放：點一下 +5） | W / Space / ↑ |
| 煞車 | 左下「煞車」（賽車：按住；點放：點一下 −5） | S / ↓ |
| 定速鎖定（賽車） | 「加速」上方「鎖定」 | F |
| 換線 | 左右滑動（另一隻手指，或按著「加速」的手指直接左右滑） | A / D / ← / → |
| 重播語音 | 右上「重播」 | E |
| 暫停 | 右上「II」 | Esc / P |
| 暫停選單 | 「繼續」「重來」「模式切換」「回選關」 | Esc 繼續、R 重來、Q 回選關 |
| 開發者計時 | — | F3（或啟動參數 `-- --dev`、設定 `dev.timing_mode`） |

- 觸控按鈕大小依畫面短邊等比例縮放（加速約 28%、煞車 24%、鎖定 17%），直式和橫式都夠大。
- 多點觸控：每隻手指依 index 追蹤；從按鈕開始的手指控制那顆按鈕，其他手指負責滑動換線。
- 自動暫停：視窗失焦、App 進背景、網頁分頁切走（`visibilitychange`）時自動暫停，並放開所有按住的輸入。暫停時間不計入時間；暫停時隱藏羅馬拼音提示。

## 關卡（依 Kana Warrior 骨架）
- 33 關：平假名 21（5 區 ×〔3 關單行 + BOSS〕+ 究極魔王）、片假名 12（片1 區、片2 區各 3 關 + BOSS，片3 區 3 關 + 究極魔王）。只從 `Kana Warrior/assets/js/learning-system.js` 取 poolRows、順序、哪些是 BOSS、小知識文字、`KATA_LOOKALIKES`；名稱中性（「1-1 あ行」「1-BOSS あ・か・さ行綜合」「究極魔王 平假名全範圍」），沒有任何敵人圖、名字或美術。小知識裡提到 KW 戰鬥機制（奧義、血量）的 8 句改寫成只講假名。
- 資料在 `config/game_config.json`：`levels`（id、name、script、zone、type normal/boss/ultimate、rows、knowledge、可選 `unlock_after`／`count_override`／`limits`／`max_hp`…）、`kana_rows`、`kata_lookalikes`。`scripts/level_db.gd` 算出每關實際題庫、題數、時限。
- 小知識：開場說明與結算畫面都會顯示。
- 輕複習：`review.ratio`（0.2）的題目從同一套假名之前學過的行出（仿 `getLearnedPoolRows`）；每套的第一關（1-1、片1-1）沒有複習。
- 片假名的石碑錯誤選項優先放一個形似字（`KATA_LOOKALIKES`，例：シ → ツ／ソ／ン）。同音字（お／を）不會同排出現（`same_sound`）。
- 語音：片假名共用同 romaji 的音檔。唯一缺的是 ぢ／づ（di/du，含片假名 ヂ／ヅ）——這兩個不出題也不當選項，其他假名照常；因此沒有關卡因缺音檔而鎖住（若某關可出題假名 < 3 會自動標「缺語音」並鎖住）。
- BOSS 護盾（P1，`boss_shield`）：BOSS／究極魔王在題數的 30%、60% 升起護盾，連續答對 N 題（BOSS 2、究極 3）擊破；護盾期間答對不算進度，答錯或漏題連擊歸零。

## 距離（短程／中程／長程）
| 類型 | 短程 | 中程 | 長程 |
|---|---|---|---|
| 單行關 | 15 | 20 | 30 |
| BOSS | 25 | 35 | 50 |
| 究極魔王 | 40 | 55 | 75 |
- 時限（**暫定**，`limit_formula`）：T = 題數 × 1.6 秒（BOSS／究極 × 1.8 秒）；三星 T×1.15、二星 T×1.5、過關 T×2.0，無條件進位到整秒。例：1-1 短程 48／36／28 秒、中程 64／48／37 秒。（舊的 63／47／36 是 20 題 あ行，跟現在的 1-1 短程 15 題不能直接比。）
- 點數（`points`、`distances.points_multiplier`）：第一次在該距離過關 10、每多一顆新星 +5、重複過關 2；再乘距離倍率 短×1、中×1.5、長×2.2，**四捨五入**到整數。結算顯示「獲得點數」和總點數，總點數存在存檔。
- 星數、最佳時間按「關卡 × 距離」分開記錄；任何距離過關都會解鎖下一關。選關畫面「距離：○○（點擊切換）」記住上次選擇。

## 存檔
- `user://save.json`（version 2）：`levels[id][short|mid|long]` = cleared／best_stars／best_time，`points`，`settings`（speed_mode、distance）。原子寫入。
- 解鎖：依清單順序；片1-1 設 `unlock_after: "1-BOSS"`（過了平假名第 1 區 BOSS 就開片假名，可在 config 改）。
- 舊存檔遷移：v1 的 level_01／level_02 → 1-1／1-2 的「短程已過關」（保留解鎖），星數與時間歸零（題數不同不可比），不補點數。
- 選關畫面分「平假名／片假名」分頁、依區分組，可上下捲動。結算畫面：「重玩」「下一關」「回選關」。
- 想重置進度：刪除 `%APPDATA%\Godot\app_userdata\Kana Run 2.0\save.json`。

## 體力（HP）
- 數值血條，左上「♥ + 血條 + 65 / 100」。預設 `hp.max_hp` 100、撞錯 `wrong_damage` 35（三次就倒）、漏題 `miss_damage` 0；各關可覆寫。撞錯仍 −2 秒、速度減半。沒有自然扣血。
- 受傷時紅色殘血延遲 `delayed_bar_wait_s` 後才縮回；只有血條閃紅晃動，不晃畫面。
- 0 HP 立即結束，結算「體力耗盡」（時間用完是「時間到」），不算過關；計時紀錄 outcome = `hp_out`／`time_up`／`clear`。
- 強化接口（game.gd）：`set_max_hp_bonus(value)`、`set_damage_reduction(pct)`、`add_shield(n)`（每點擋一整下）、`heal(value)`、`take_damage(n)`；訊號 `hp_changed(hp, max_hp, shield)`、`damaged(amount, blocked)`。

## 規則
- 三條跑道，石碑每 `row_spacing_m` 公尺一排三塊。聽語音，撞對應假名。
- 答對該關該距離的題數過關。撞錯：+2 秒、速度減半，**下一排重出同一題，正確假名換到別條跑道**。三塊都沒撞到（從兩塊石碑中間穿過）：漏題 +1 秒，**這個假名排到之後新生成的一排重出**。
- 題目提示：畫面上方顯示羅馬拼音。每個假名前 `hints.romaji_first_n`（3）次出現才顯示，而且進度未達 `hints.voice_only_after_progress`（50%）；過了之後全部只播聲音（顯示「?」），切換時畫面出現「聽音模式」。
- 連擊：連續答對次數（2 以上顯示「N 連擊」並彈跳）。撞錯或漏題都歸零；不影響時間。結算顯示最佳連擊。
- 時間 = 實際時間 + 罰秒。時限見「距離」。

## 參數
全部在 `config/game_config.json`：速度（極速 60 km/h、加速 3 秒、煞車 1.2 秒、自然減速時間）、跑道寬度與換線時間、石碑間距、打擊感（光暈、擊飛距離、FOV、`screen_shake_on_normal_hit=false`）、各關時限與星數門檻。
不重新匯出也能在裝置上調：把要覆寫的欄位寫進 `user://game_config_override.json`。

## 開發者計時模式
過關或失敗時寫到 `user://timing/`（Windows：`%APPDATA%\Godot\app_userdata\Kana Run 2.0\timing\`）：
- `run_<時間>.json` / `.csv`：每題目標、結果、反應時間（語音開始→撞到）、當下速度、時間
- `runs_v4.csv`：每局一行摘要（模式、距離、題數、獲得點數、結果 clear／time_up／hp_out、通關時間、星數、對/錯/漏、平均反應、剩餘體力）
畫面右上角同時顯示即時數據。

## 美術素材與授權

- **美術：屁卡手手繪**（`/workspace/kana-run-2.0/art/` 交付包）
  - batch01：天空、跑道、石板、HUD、護盾特效
  - batch02：無字 UI、粒子（花瓣／火花／速度線）
  - batch03 + batch07/props：跑道兩側道具（房子、商店、櫻花、長椅、販賣機…）
  - batch04：暫停、選關、結算、倒數 GO、App 圖示
  - batch07：跑者 9 組 sprite sheet + JSON（錨點、回切幀）
  - 版權屬屁卡手／本專案，僅供 Kana Run 使用。
- **字型**
  - Zen Maru Gothic Bold（石板假名、選關徽章）：SIL Open Font License 1.1，`art/fonts/OFL-ZenMaruGothic.txt`
  - Noto Sans TC（HUD 子集）：SIL Open Font License 1.1
- **匯入流程**：`python3 tools/import_art.py <art 交付資料夾>` 會縮圖、產生 `.import`（有損壓縮控制 pck 大小）與 `scripts/art_manifest.gd`。執行期載入的素材全部列在 manifest。
- 基準解析度 1080×1920（canvas_items stretch, aspect expand）；3D 玩法不變，美術貼在 quad／Sprite3D 上。
- 跑者呼吸、換道側移在程式；答錯白閃是 shader，不震螢幕。
- Web 快取破壞：`export-web.bat` 會呼叫 `tools/cachebust.py` 把 js/wasm/pck 改名為 `kr2_時間戳.*` 並改寫 index.html；`serve_web.py` 送 no-store / Clear-Site-Data 標頭。

## 結構
```
config/game_config.json   所有可調參數與關卡資料
scenes/main.tscn          只有根節點；世界、HUD、音效都在 game.gd 用程式建
scripts/game.gd           主遊戲（狀態、生成、判定、打擊感、輸入、HUD）
scripts/speed_controller.gd  速度邏輯（純邏輯，可單元測試）
scripts/rules.gd          星數、碰撞車道、出題
scripts/dev_logger.gd     計時紀錄
scripts/asset_manifest.gd 所有執行期資源都要在這裡 preload，否則 Web 匯出會漏檔
tools/smoke_test.gd       無頭測試（含多種解析度的版面置中檢查）
tools/screenshot.gd       需視窗：各解析度截圖（-- --out=資料夾）
scripts/save_data.gd      存檔／解鎖
audio/ assets/fonts/      從 1.0 複製的語音、音效、音樂、字型
```

## 注意
- 1.0 的子集字型（ui/bold.ttf）缺「模」，所以提示、連擊、聽音模式用 `assets/fonts/hud_cjk.ttf`（Noto Sans TC 子集，OFL，授權在 `OFL-NotoSansTC.txt`）。HUD 加新中文字時要用 `tools/make_hud_font.py` 重產（它會自動掃 scripts/ 和 config/ 裡用到的所有中文字）。
- 只裝了 Web 匯出模板（沒有 Windows/Android 模板），所以沒有 Windows exe / APK 預設。
- 匯出時出現 `include_filter` 的 ERROR 可忽略（4.7 已移除該鍵）。

## 下一步建議
- 美術：替換佔位方塊（石碑、角色、跑道）。
- 用實際試玩校準各距離時限（目前是公式暫定值）。
- 點數的用途（商店／強化）接上 HP 強化接口。
