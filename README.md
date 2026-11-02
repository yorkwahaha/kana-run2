# Kana Run 2.0 — 第一關試玩版

Godot **4.7.2**（`I:\Projects\Godot_v4.7.2`），**Mobile** 渲染器（Web 匯出時自動改用 Compatibility）。
舊專案 `I:\Projects\Kana Run` 是凍結的 1.0 Beta，**不要修改**；本專案只從那裡複製了素材。

## 怎麼玩
- 電腦：雙擊 `play.bat`（開發者計時模式：`play-dev.bat`），或 `editor.bat` 開編輯器後按 F5。
- 手機（同一個 Wi‑Fi）：
  1. `export-web.bat` → 產生 `build/web/`
  2. `python serve_web.py` → https://<電腦IP>:8443 （例：https://192.168.50.107:8443）
  3. Godot 4.7 Web 一定要 https（secure context），所以用 1.0 的自簽憑證（已複製到 `build/certs/`；若手機沒裝過，見 `serve_web.py` 開頭說明；要重產用 `python make_certs.py`）。
- 自動測試：`selftest.bat`（單元測試 + 自動駕駛跑完第一關）。

## 操作
| 動作 | 手機 / 滑鼠 | 鍵盤 |
|---|---|---|
| 加速 | 按住 | 按住 Space / W / ↑ |
| 減速 | 放開 | 放開 |
| 煞車 | 雙擊並按住 | S / ↓ |
| 換線 | 按住時左右滑 | A / D / ← / →（設定可改成需按住） |
| 重播語音 | — | R |
| 開發者計時 | — | F3（或啟動參數 `-- --dev`、設定 `dev.timing_mode`） |

## 規則（第一關）
- 三條跑道，石碑每 `row_spacing_m` 公尺一排三塊。聽語音（あいうえお），撞對應假名。
- 答對 20 題過關。撞錯：+2 秒、速度減半。三塊都沒撞到（從兩塊石碑中間穿過）：漏題 +1 秒。
- 時間 = 實際時間 + 罰秒。時限 63 秒；≤47 秒二星；≤36 秒三星。
- 校準依據：Hayato 最佳 31.3 秒 × 企劃書公式（三星 ×1.15、二星 ×1.5、過關 ×2.0）。理論最快約 30.7 秒。

## 參數
全部在 `config/game_config.json`：速度（極速 60 km/h、加速 3 秒、煞車 1.2 秒、滑行、雙擊判定窗）、跑道寬度與換線時間、石碑間距、打擊感（光暈、擊飛距離、FOV、`screen_shake_on_normal_hit=false`）、各關時限與星數門檻。
不重新匯出也能在裝置上調：把要覆寫的欄位寫進 `user://game_config_override.json`。

## 開發者計時模式
過關或失敗時寫到 `user://timing/`（Windows：`%APPDATA%\Godot\app_userdata\Kana Run 2.0\timing\`）：
- `run_<時間>.json` / `.csv`：每題目標、結果、反應時間（語音開始→撞到）、當下速度、時間
- `runs.csv`：每局一行摘要（通關時間、星數、對/錯/漏、平均反應）
畫面右上角同時顯示即時數據。

## 結構
```
config/game_config.json   所有可調參數與關卡資料
scenes/main.tscn          只有根節點；世界、HUD、音效都在 game.gd 用程式建
scripts/game.gd           主遊戲（狀態、生成、判定、打擊感、輸入、HUD）
scripts/speed_controller.gd  速度邏輯（純邏輯，可單元測試）
scripts/rules.gd          星數、碰撞車道、出題
scripts/dev_logger.gd     計時紀錄
scripts/asset_manifest.gd 所有執行期資源都要在這裡 preload，否則 Web 匯出會漏檔
tools/smoke_test.gd       無頭測試
audio/ assets/fonts/      從 1.0 複製的語音、音效、音樂、字型
```

## 注意
- 字型是 1.0 的子集字型，HUD 目前用英文/數字避免缺字。
- 只裝了 Web 匯出模板（沒有 Windows/Android 模板），所以沒有 Windows exe / APK 預設。
- 匯出時出現 `include_filter` 的 ERROR 可忽略（4.7 已移除該鍵）。

## 下一步建議
- 美術：替換佔位方塊（石碑、角色、跑道）。
- 第二關起：更多行（か行…）、關卡選單、存檔與星數紀錄。
