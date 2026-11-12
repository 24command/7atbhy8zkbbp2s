# Native MOD settings tab (2026-11-13)

The previous clone assigned SettingItemsManager.content and itemsHolder to the same transform. Target4.0.3 RefreshItems/RefreshPosition independently resize content and offset itemsHolder; aliasing them breaks layout. The old cloned tab was not part of Setting's arrays, and hiding only scroll children left Misc footer content and tab selection stale.

The MOD page now clones the native frame containing the settings ScrollRect, maps viewport/content/itemsHolder to their corresponding distinct cloned transforms, removes only item children, and uses AddButton/AddToggle/AddSlider plus RefreshItems/RefreshPosition. Scroll callbacks no longer reference the original manager. Copied gameplay preview objects are hidden. No floating-panel UI redesign.

The clone's frame animator, MOD tab animator and scroll content are registered as index3 in frameAnimators/tabAnimators/tabScrollContents. Native ChangeTab(3) owns tab state/slider/transition. A recursion guard prevents the existing ChangeTab hook from destroying this page during the programmatic switch. Whole original frames are hidden while MOD is active. Leaving first restores their visibility, switches through native ChangeTab(previous), restores all three original arrays, then destroys the clone. Failed creation restores the original page and logs the error instead of leaving a deliberately hidden blank screen.

Verification: focused native binary layout/ChangeTab analysis,4.0.3 metadata and source regressions; actual Apple SDK build via Actions. No local device available: test opening MOD from each original tab, scrolling, toggles/opacity, advanced parameters, switching back, then reopening Settings. Hook count remains72. No chart reimport required.
