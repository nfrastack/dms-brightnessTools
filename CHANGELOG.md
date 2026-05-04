## 1.0.0 2026-05-03 <code at nfrastack dot com>

   ### Added
      - Initial release
      - Variant-aware bar pill: one slider per configured device
      - Control Center entry that aggregates all variants flagged for CC into a single detail panel
      - Auto device discovery via `dms brightness list` with sysfs scan fallback
      - Per-variant `Show OSD when adjusting` toggle
      - Reactive sysfs updates so external brightness changes (Fn keys, `brightnessctl`) reflect in the pill immediately
      - Configurable minimum-percent floor and wheel/keyboard step per variant
