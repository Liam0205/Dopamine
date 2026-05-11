# 2.x 迁移完成后反思

## 任务
将 Dopamine fork 从 1.x (dopamine 分支) 迁移到 2.x (liam-2.x 分支)。移植 14 项自定义功能，设置 CI，评估内核功能移植必要性。

## 关键发现

### 架构差异（1.x → 2.x）
1. **App 层**: Swift/SwiftUI → ObjC/UIKit (Preferences.framework for settings)
2. **IPC**: jailbreakd XPC Mach 服务 → jbctl internal 命令 + launchdhook XPC
3. **jailbreakd 被移除**: 2.x 中 privileged 操作由 jbctl internal 命令执行
4. **PPLRW**: 单页 magic page → 双模式 physrw + physrw_pte
5. **多漏洞支持**: 2.x 支持多种内核漏洞（不仅 oobPCI），用户可选
6. **iOS 范围扩大**: 15.0-15.4.1 → 15.0-16.6.1

### 移植决策
- **移植的 14 项功能**：每项一个 atomic commit，12 个 commit 总计
- **跳过的功能**：Bridge to XinA（用户要求）、反向代理（用户要求）、多环境管理器（WIP 未完成）、YouTube 彩蛋（2.x 无此功能）
- **Default Packages（ElleKit+PreferenceLoader）**：2.x 已通过 APT 源提供，无需内嵌 .deb
- **内核功能全部无需移植**：2.x 已有更好实现或问题不存在

### Path Mapping 架构适配
1.x 通过 jailbreakd XPC (message ID 101/102) 实现 → 2.x 改为 jbctl internal 命令
- `bindmount_path` / `bindunmount_path` 直接在 jbctl 内执行
- 使用 `mount_unsandboxed` / `unmount_unsandboxed` + `jbclient_root_steal_ucred` 绕过沙盒
- 持久化 plist 路径从 `page.liam.prefixers.plist` → `page.0x01.prefixers.plist`
- 启动恢复在 jbctl `startup` 命令中调用 `restore_bindmounts()`

### Bundle ID 变更
`page.liam.Dopamine` → `page.0x01.Dopamine`（2.x 使用新 ID）

## 文档影响
所有 llmdoc 稳定文档都基于 1.x 架构编写，需要大规模更新：
- `overview/project-overview.md` — 项目定位、架构、功能列表全部过时
- `must/build-system.md` — 构建管线不同（2.x 有 download_bootstraps.sh，不同的 SDK）
- `must/workflow.md` — 分支策略、CI 工作流完全不同
- `architecture/jailbreak-lifecycle.md` — 执行链完全不同（无 jailbreakd）
- `architecture/basebin-components.md` — 组件角色变化（jbctl 扩展，jailbreakd 移除）
- `reference/dopamine-branch-features.md` — 需改为 liam-2.x 功能参考

## 错误与教训
1. **应该一开始就要求 atomic commit** — 所有修改一次性做完后再拆分非常耗时
2. **2.x 的 Settings 使用 Preferences.framework (PSListController)** — 与 1.x 的 SwiftUI @AppStorage 完全不同，理解框架后移植变快
3. **DOPreferenceManager 使用 plist 直接 I/O** — 不是 NSUserDefaults，这影响 key 命名和读取方式

## 后续
- llmdoc 稳定文档需要 2.x 架构重写
- 1.x 文档可保留为历史参考但需标记为 legacy
- auto-sync CI 需要 PAT_TOKEN（用户已配置）
