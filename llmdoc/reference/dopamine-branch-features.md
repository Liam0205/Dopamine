# liam-2.x 分支新功能参考

liam-2.x 分支在上游 `opa334/Dopamine` 2.x 基础上增加的定制功能。

技术栈: ObjC/UIKit, 设置页使用 Preferences.framework (PSListController/PSSpecifier), plist I/O 通过 DOPreferenceManager, 本地化覆盖 en.lproj / zh-Hans.lproj / zh-CN.lproj。

---

## 品牌与分发

### 1. 自定义 Bundle ID

**Commit**: `e34decc3`
**影响文件**: `project.pbxproj`, `DOPreferenceManager.m`

Bundle ID 改为 `page.0x01.Dopamine`（区别于上游 `com.opa334.Dopamine`），plist 存储路径同步变更。

### 2. 编译时间宏（Nightly）

**Commit**: `336adcea`
**影响文件**: `Application/Makefile`

Nightly 构建时注入 `COMPILE_TIME` 预处理宏，用于标识构建版本。

### 3. 更新检查通道

**Commit**: `e3d866c7`
**影响文件**: `DOUIManager.m`

OTA 更新检查 URL 指向 `Liam0205/Dopamine` GitHub releases（非上游 opa334）。

### 4. CI 工作流

**Commit**: `3a039c8d`
**新增文件**: `.github/workflows/liam-build.yml`, `.github/workflows/auto-sync.yml`

- `liam-build.yml` — liam-2.x 分支构建发布
- `auto-sync.yml` — 自动从上游 2.x 同步
- `permissions: contents: write` — Release 创建权限
- CI 缓存：THEOS（`theos-sdk16.5-*`）、trustcache（`trustcache-*`）使用 `actions/cache@v4`
- 版本注入：`DOPAMINE_VERSION` 传递至 `Application/Makefile`，覆盖 `MARKETING_VERSION`（`CFBundleShortVersionString`）
- Tag 构建直接用 `GITHUB_REF` 作 version（不重复追加时间戳）

### 5. 55-bit 版本编码（方案 B）

**影响文件**: `Application/Dopamine/Extensions/NSString+Version.m`

`numericalVersionRepresentation` 从 24-bit (`major<<16|minor<<8|patch`) 扩展为 55-bit (`major<<48|minor<<40|patch<<32|compact_timestamp`)。

- `compact_timestamp = YYMMDD * 1440 + HH*60 + MM`
- 触发条件：`components.count >= 5` 且 `components[3].length == 8`（YYYYMMDD 格式）
- 作用：同一上游版本的不同 release（如 `2.4.9-20260512_0044-16-g6d1f0372`）可通过数值比较区分先后
- 不满足条件时退回原始 24-bit 编码，兼容上游版本号

### 6. 更新下载 asset 选取

**影响文件**: `DOUpdateViewController.m`

Release asset 选取逻辑改为优先匹配 `.tipa` 后缀，回退到 `assets[0]`。确保设备直接下载 .tipa 而非 .ipa。

---

## 用户体验

### 7. 系统运行时间与构建信息

**Commit**: `eed106db`
**影响文件**: `DOMainViewController.m`

使用 `clock_gettime(CLOCK_MONOTONIC_RAW)` (引入 `<time.h>`) 获取系统运行时间并显示。同时在主界面 header 展示构建信息。

### 8. 确认弹窗与重启按钮

**Commit**: `935ae851`
**影响文件**: `DOMainViewController.m`

- 注销 (Respring) 和重启操作改为先弹出 `UIAlertController` 确认，防止误触
- 新增重启 (Reboot) 按钮

### 9. 越狱统计同步

**Commit**: `f748c397`
**影响文件**: `DOMainViewController.m`

跟踪并持久化 `total_jailbreaks` 累计越狱次数计数器。

---

## 设置项

### 10. 禁止更新检查

**Commit**: `7a82b8ec`
**影响文件**: `DOSettingsController.m`, `DOUIManager.m`

设置页新增 `PSSwitchCell` toggle。启用后 `DOUIManager` 中跳过更新检查逻辑。

### 11. 重建环境

**Commit**: `e24df347`
**影响文件**: `DOSettingsController.m`, `DOBootstrapper.m`

设置页新增 toggle。启用后下次越狱时强制清除并重新解压 bootstrap，完成后自动清除标记。

---

## Bootstrap 与注入

### 12. 默认 APT 源

**Commit**: `f53a4696`
**影响文件**: `DOBootstrapper.m` (`defaultSources`)

默认 sources 添加 `tweaks.0x01.page` 兼容源。

### 13. Unject 选择性注入黑名单

**Commit**: `c4726ec9`
**影响文件**: `BaseBin/systemhook/src/common.c`

读取 `/var/mobile/zp.unject.plist` 或 `/var/mobile/Library/Preferences/zp.unject.plist`。若进程可执行文件名作为 key 设置为 true，则跳过 tweak 注入。

规则:
- `/var/jb` 或 `procursus` 路径下的进程不受影响
- `.appex/` 路径（插件）始终跳过注入

### 14. Path Mapping（路径映射）

**Commit**: `f5a3d3fa`
**影响文件**: `BaseBin/jbctl/internal.m`, `DOSettingsController.m`, `BaseBin/jbctl/main.m`

使用 bindfs 挂载实现系统目录可写覆盖（字体、主题、框架等），不修改真实文件系统。

**架构** (2.x 实现):
1. UI: `DOSettingsController.m` — toggle + 路径列表管理
2. CLI: `jbctl` internal 子命令（bindmount / bindunmount）
3. 入口: `jbctl main.m` 注册 internal 命令
4. 持久化: plist 存储映射配置

与 1.x 区别: 不再使用 jailbreakd XPC 通信（`JBD_BINDMOUNT_PATH` 等），改用 jbctl 直接执行 internal 命令。

---

## 从 1.x 评估但未移植的功能

以下功能在 dopamine (1.x) 分支存在但未移植到 liam-2.x，及其原因:

| 功能 | 原因 |
|------|------|
| Bridge to XinA | 用户排除 |
| 反向代理 (Reverse Proxy) | 用户排除 |
| 多环境管理器 (Multi-env) | WIP 未完成 |
| YouTube 彩蛋禁用 | 2.x 无彩蛋 |
| PPLRW 重构 | 2.x 已有更好的 dual-mode physrw |
| Systemhook exec/fork 修复 | 2.x 有不同但可用的方案 |
| Launchd 崩溃报告器 | 2.x 上游已包含 |
| WiFi 修复 | 不适用于 2.x 架构 |
| 默认包 ElleKit+PreferenceLoader | 通过 APT 源即可获取 |
