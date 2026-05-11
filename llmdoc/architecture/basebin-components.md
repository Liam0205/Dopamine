# BaseBin 组件参考

BaseBin 包含 12 个组件，编译为 arm64e，部署目标 iOS 15.0，运行时位于 `/var/jb/basebin/`。

## 共享库

### libfilecom

| 属性 | 值 |
|------|---|
| 类型 | 动态库 (.dylib) |
| 源码 | `BaseBin/libfilecom/src/FCHandler.m` |
| 依赖 | Foundation, CoreServices, Security, IOKit |
| 依赖者 | libjailbreak, boomerang, launchdhook |

**用途**: 基于文件的 IPC 机制。将 NSDictionary 序列化为 binary plist 文件，通过 `DISPATCH_SOURCE_TYPE_VNODE` 监控文件变更实现双向通信。

**使用场景**: 专用于 boomerang 与 launchd 之间的用户态重启原语交接（此时 XPC 不可用）。

**关键接口**: `FCHandler` 类 — 初始化时指定发送/接收两个文件路径，通过 vnode 通知实现异步消息。

---

### libjailbreak

| 属性 | 值 |
|------|---|
| 类型 | 动态库 (.dylib) |
| 源码 | `BaseBin/libjailbreak/src/` (多文件) |
| 依赖 | Foundation, libfilecom, libbsm |
| 依赖者 | jailbreakd, idownloadd, boomerang, jbinit, jbctl, launchdhook |

**用途**: 所有 BaseBin 组件的共享基础库。提供：

- `boot_info` 管理（plist 读写）
- jailbreakd XPC 客户端函数（`jbdGetStatus`, `jbdBindMountPath` 等）
- kcall 封装
- PPL R/W 原语（`initPPLPrimitives`, `phystouaddr`, `kvtouaddr`）
- Handoff 机制（`handoffPPLPrimitives`）
- Mach-O 解析 + 签名评估
- patchfinding 工具

**关键头文件**:
- `BaseBin/libjailbreak/src/jailbreakd.h` — `JBD_MESSAGE_ID` 枚举定义所有 XPC 消息类型
- `BaseBin/libjailbreak/src/launchd.h` — `LAUNCHD_JB_MSG` 定义 launchd hook 消息协议
- `BaseBin/libjailbreak/src/pplrw.m` — PPL 原语实现（dopamine 分支重构为完整物理映射）

---

## 守护进程

### jailbreakd

| 属性 | 值 |
|------|---|
| 类型 | 可执行文件（daemon） |
| 源码 | `BaseBin/jailbreakd/src/server.m` (主循环), `fakelib.m`, `forkfix.m` |
| 依赖 | Foundation, CoreServices, Security, libjailbreak, libarchive, libbsm |
| LaunchDaemon | `com.opa334.jailbreakd` (RunAtLoad, KeepAlive) |
| Mach 服务 | `com.opa334.jailbreakd` (特权) + `com.opa334.jailbreakd.systemwide` |

**用途**: 越狱的中央管理守护进程。持有所有内核原语，响应来自全系统的 XPC 请求。

**XPC 消息协议** (`JBD_MESSAGE_ID`):

| ID | 命令 | 访问级别 |
|----|------|---------|
| 1 | PPL init | 特权 |
| 2 | PAC init | 特权 |
| 3 | PAC finalize | 特权 |
| 4 | Handoff PPL | 特权 |
| 5 | kcall | 特权 |
| 10 | Rebuild trustcache | 特权 |
| 11 | Process binary (添加到 TC) | systemwide |
| 12 | Setuid fix | systemwide |
| 13 | Debug process | systemwide |
| 14 | Fork fix | systemwide |
| 20 | Fakelib 管理 | 特权 |
| 21 | Init environment | 特权 |
| 22 | Jailbreak update | 特权 |
| 101 | Bind mount path | 特权 |
| 102 | Bind unmount path | 特权 |
| 50 | Intercept userspace panic | systemwide |

**fakelib.m 核心功能**:
- `makeFakeLib()` — 复制 `/usr/lib` 到 `.fakelib/`，patch dyld
- `setFakeLibBindMountActive(active)` — 绑定挂载切换
- `bindMountPath(sourcePath)` — 路径映射：复制 → bindfs 挂载 → 持久化到 plist
- `bindUnmountPath(sourcePath)` — 解除路径映射

---

### idownloadd

| 属性 | 值 |
|------|---|
| 类型 | 可执行文件（daemon，可选） |
| 源码 | `BaseBin/idownloadd/src/idownloadd/main.swift` |
| 构建 | xcodebuild (唯一使用 Xcode 构建的 BaseBin 组件) |
| 依赖 | libjailbreak |
| LaunchDaemon | `com.opa334.idownloadd` (默认 Disabled/) |

**用途**: 开发调试用网络 KRW shell。初始化 PPL R/W 后启动 iDownload 网络服务。仅在用户设置中启用 `iDownloadEnabled` 时激活。

---

## 钩子（Dylib 注入）

### launchdhook

| 属性 | 值 |
|------|---|
| 类型 | 动态库 (.dylib)，注入 launchd (PID 1) |
| 源码 | `BaseBin/launchdhook/src/main.m` + 5 个 hook 文件 |
| 依赖 | libjailbreak, libfilecom, ellekit, systemhook 源码 |
| 注入方式 | opainject |

**Hook 模块**:

| 文件 | 函数 | 作用 |
|------|------|------|
| `xpc_hook.m` | `xpc_handler_hook` | 处理 jailbreakd 的原语请求（PPL R/W、sign state） |
| `daemon_hook.m` | `xpc_dictionary_get_value_hook` | 注入 `/var/jb/Library/LaunchDaemons/` 下的守护进程 |
| `spawn_hook.m` | `posix_spawn_hook` | 确保 systemhook.dylib 传播到子进程 |
| `ipc_hook.m` | `sandbox_check_by_audit_token_hook` | 放行 `cy:` / `lh:` 前缀 Mach 服务查找 |
| `dsc_hook.m` | `sysctlbyname_hook` | 抑制 `vm.shared_region_pivot` sysctl |
| `boomerang.m` | `boomerang_userspaceRebootIncoming` | 用户态重启时原语交接给 boomerang |
| `crashreporter.m` | 异常处理 | launchd 崩溃报告（dopamine 分支新增） |

---

### systemhook

| 属性 | 值 |
|------|---|
| 类型 | 动态库 (.dylib)，注入所有进程 |
| 源码 | `BaseBin/systemhook/src/main.c`, `common.c` |
| 依赖 | 无外部库（纯 C） |
| 注入方式 | 通过 fakelib patch 的 dyld DYLD_INSERT_LIBRARIES |

**constructor 执行**:
1. 消费沙盒扩展
2. 修复 setuid
3. 加载 TweakLoader 或特定 hook（forkfix/watchdoghook/rootlesshooks）

**Interpose 的系统调用**:
- `posix_spawn` / `posix_spawnp` — 传播 systemhook
- `execve` / `execl` / `execlp` / `execle` / `execv` / `execvp` / `execvP` — 正确传播环境
- `dlopen` — 信任缓存检查
- `sandbox_init` — 沙盒放行
- `ptrace` — 调试支持
- `fork` / `vfork` / `forkpty` / `daemon` — 加载 forkfix（dopamine 分支新增）

**Unject 机制** (dopamine 分支新增): 检查 `/var/mobile/zp.unject.plist`，若进程名在黑名单中则跳过 tweak 注入。

---

### watchdoghook

| 属性 | 值 |
|------|---|
| 类型 | 动态库 (.dylib)，注入 watchdogd |
| 源码 | `BaseBin/watchdoghook/src/main.m` |
| 依赖 | Foundation, ellekit, IOKit |

**用途**: 拦截 `IOConnectCallStructMethod` selector 2（watchdog 超时触发用户态 panic），重定向到 jailbreakd 的 panic 拦截处理器。防止越狱环境下的看门狗超时导致内核 panic。

---

### rootlesshooks

| 属性 | 值 |
|------|---|
| 类型 | 动态库 (.dylib, Theos tweak) |
| 源码 | `BaseBin/rootlesshooks/cfprefsd.x` |
| 构建 | Theos (`$THEOS/makefiles`)，Logos 预处理器 |
| 目标进程 | cfprefsd |

**用途**: Hook `__CFPrefsGetPathForTriplet`，将第三方偏好设置 plist 读取从 `/var/mobile/Library/Preferences/` 重定向到 `/var/jb/var/mobile/Library/Preferences/`，支持 rootless 偏好隔离。

---

### forkfix

| 属性 | 值 |
|------|---|
| 类型 | 动态库 (.dylib) |
| 源码 | `BaseBin/forkfix/src/main.c` |
| 依赖 | 直接链接 `systemhook.dylib` |
| 加载条件 | 仅当进程被标记为 debugged (wx_allowed) 时 |

**用途**: Hook `__fork`。fork() 后子进程的 PAC 签名页需要特殊权限处理。forkfix 通过 pipe 通知 jailbreakd 执行 `apply_fork_fixup()`（修复 VM map 的 wx_allowed 权限）。

---

## 工具

### jbinit

| 属性 | 值 |
|------|---|
| 类型 | 可执行文件 |
| 源码 | `BaseBin/jbinit/src/main.m` |
| 依赖 | libjailbreak |

**用途**: 越狱启动后的第一个执行的 BaseBin 二进制。通过 `launchctl_load` 加载 jailbreakd 和 trustcache_rebuild 的 LaunchDaemon plist。

---

### jbctl

| 属性 | 值 |
|------|---|
| 类型 | 可执行文件（CLI） |
| 源码 | `BaseBin/jbctl/src/main.m` |
| 依赖 | Foundation, CoreServices, Security, libjailbreak |
| LaunchDaemon | `com.opa334.trustcache_rebuild` (每日午夜运行) |

**命令**:
- `proc_set_debugged <pid>` — 标记进程为可调试
- `rebuild_trustcache` — 重建动态信任缓存
- `reboot_userspace` — 触发用户态重启
- `update tipa <path>` / `update basebin <path>` — 越狱更新
- `bindmount_path <path>` / `bindunmount_path <path>` — 路径映射

---

### boomerang

| 属性 | 值 |
|------|---|
| 类型 | 可执行文件 |
| 源码 | `BaseBin/boomerang/src/main.m` |
| 依赖 | Foundation, libjailbreak, libfilecom |

**用途**: 用户态重启的原语保持器。在重启过程中存活，接收旧 launchd 的 PPL 原语，保存并在新 launchd 启动后交还。使用 libfilecom 进行 IPC（重启期间 XPC 不可用）。

**关键函数**:
- `getPrimitives()` — 从旧 launchd 接收原语
- `sendPrimitives()` — 向新 launchd 发送原语
