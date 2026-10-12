# hsuanice_Fix Overlap Items Partial or Complete.lua — Changelog

hsuanice_Fix Overlap Items Partial or Complete

## 26.1012.0736

- Released as part of the 26.1012.0736 package update.

History before 26.1012.0736 (moved out of the script header; last header version: `0.1.3`).

```text
v0.1.3 (2025-09-13)
  - 移除 TSV 相關功能與檔案輸出
  - 一開始先強制打開 Console，再清空，避免某些環境下視窗不彈出
  - Summary 改為掃描結束後再印（避免顯示 0 計數）
v0.1.2 (2025-09-13)
  - 掃描結束印出 summary（partial / complete / total）
v0.1.1 (2025-09-13)
  - 忽略「純交叉淡變」造成的重疊（手動/自動淡入淡出都納入）
v0.1.0 (2025-09-13)
  - 掃描所有軌（不依選取），每軌找 item 重疊，分類 partial/complete
  - 在相關 items 上加 take marker：Review: Item overlap — partial/complete
```
