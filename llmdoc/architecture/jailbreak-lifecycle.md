# 越狱生命周期（完整执行链）

本文档描述从 App 启动到系统进入越狱状态的完整因果链，包括漏洞利用、内核原语建立、环境部署三个阶段。

## 阶段 0：App 启动与分发

```
main.swift → Fugu15.mainHook()
  检查 CLI 子命令 (Fugu15_server / hide / unhide / uninstall / reboot)
  若无子命令 → 检查 isJailbroken() → 启动 SwiftUI (Fugu15App.main())
```

App 通过 TrollStore 侧载安装。`Info.plist` 中的 `TSRootBinaries: ["oobPCI", "tar"]` 标记需要 root 执行的辅助二进制。

## 阶段 1：进程准备

用户点击"越狱"后，`Jailbreak.swift` (`jailbreak()`) 触发：

```
1. handleWifiFixBeforeJailbreak()  // iOS < 15.4 需关闭 WiFi
2. Fugu15.launchKernelExploit(oobPCI:)
   a. posix_spawn 自身为 Fugu15_server 子进程
      - 使用 persona 属性获取 UID 0（root 权限）
      - 通过 pipe 建立 ProcessCommunication IPC
   b. Fugu15_server 进入 serverMain()
```

**IPC 协议 (ProcessCommunication)**：基于 pipe 的字符串数组协议。命令以 `0x00` 结尾，参数以 `0x01` 分隔。父进程发送命令，子进程返回结果。

关键文件：
- `Packages/Fugu15KernelExploit/Sources/Fugu15KernelExploit/Fugu15.swift` (`launchKernelExploit`)
- `Packages/ProcessCommunication/Sources/ProcessCommunication/ProcessCommunication.swift`

## 阶段 2：DriverKit 漏洞利用

### 2.1 Codeless Kext 注册

```
Fugu15_server:
  getDKCheckinData() → IOKit 注册一个 codeless kext personality
    IONameMatch: "wlan" (匹配 WiFi PCI 设备)
  获取 DriverKit check-in token + tag
```

这就是为什么 iOS < 15.4 需要先关闭 WiFi：释放 PCI 设备供漏洞利用匹配。

### 2.2 SpawnDrv 启动 oobPCI

```
SpawnDrv.launch():
  posix_spawn oobPCI 为 POSIX_SPAWN_PROC_TYPE_DRIVER
  设置 Mach exception port 用于 IPC
  使用硬件断点 patch dyld 绕过平台检查
  传递 DK check-in token 和 PCI 内存大小
```

**异常端口 IPC 协议**：oobPCI 通过跳转到魔术地址触发异常，父进程通过 exception handler 接收：
- `0x4142434400–0x41424344xx`：DK 函数调用请求
- `0x4841585800–0x484158581C`：漏洞利用函数调用（获取偏移、读写请求等）
- 线程状态寄存器携带参数和返回值

### 2.3 oobPCI 漏洞利用链

```
oobPCI main():
  1. DriverKit check-in → 获取 PCI 设备端口
  2. 通过 PCI BAR 越界读扫描物理内存 → 定位 boot-args → 推导内核基地址
  3. 构建物理 R/W 原语：
     - 损坏 IOBufferMemoryDescriptor 指向任意物理地址
     - 通过 IODMACommand 执行拷贝
  4. breakCFI() — PAC 绕过：
     - 利用线程状态竞争获取已签名的 fault handler
     - 构建 Fugu14 风格的 kcall 原语（通过异常返回 gadget）
  5. pplBypass() — PPL 绕过：
     - 创建漏洞利用 pmap → 嵌套共享区域
     - 利用 TLB 竞争写入 PPL 保护页
  6. pmap_map_in() — 映射完整物理地址空间到用户态
     - 偏移: PPLRW_USER_MAPPING_OFFSET (0x7000000000)
  7. 进入 exploit_server() 循环
     - 提供 KRW (内核读写) + kcall + PPL 写入服务
```

**不变量**: oobPCI 进程在整个越狱周期中持续运行，作为内核原语服务器。所有后续操作（trustcache、jailbreakd 等）通过 KRWHandler 请求 oobPCI 执行内核操作。

关键文件：
- `Exploits/oobPCI/Sources/main.c` (`exploit_server`)
- `Exploits/oobPCI/Sources/physrw.c` (`buildPhysPrimitive`)
- `Exploits/oobPCI/Sources/badRecovery.c` (`breakCFI`, `setupFugu14Kcall`)
- `Exploits/oobPCI/Sources/tlbFail.c` (`pplBypass`)

## 阶段 3：环境部署

父进程发送 `startEnvironment` 命令给 Fugu15_server，触发 `oobPCI.swift` 中的 `serverMain` case "startEnvironment"：

### 3.1 TrustCache 加载

```
将 basebin.tc 加载入内核 trust cache
→ BaseBin 二进制现在被系统信任，可以执行
```

### 3.2 Bootstrap 部署

```
Bootstrapper.extractBootstrap():
  1. Remount /private/preboot 为可写
  2. 创建 fake root: /private/preboot/<boot-manifest-hash>/jb-<random>/procursus/
  3. 创建符号链接: /var/jb → fake root
  4. 解压 bootstrap-iphoneos-arm64.tar.zst (Procursus 文件系统)
  5. 解压 basebin.tar 到 /var/jb/basebin/
  6. 写入 boot_info.plist (版本、偏移、分配信息)
```

### 3.3 启动 jailbreakd

```
jbinit:
  launchctl_load("com.opa334.jailbreakd.plist")
  launchctl_load("com.opa334.trustcache_rebuild.plist")
```

jailbreakd 注册两个 Mach 服务：
- `com.opa334.jailbreakd`：特权服务（仅 jbinit/launchd 可访问）
- `com.opa334.jailbreakd.systemwide`：系统级服务（所有进程通过 systemhook 访问）

### 3.4 原语转移

```
jbdTransferPPLRW()   → 将 PPL 读写原语从 oobPCI 进程转移到 jailbreakd
jbdTransferKcall()   → 将 kcall 原语转移到 jailbreakd
jbdFinalizeKcall()   → 为 launchd 和 boomerang 分配 PAC 内核页
```

转移后 jailbreakd 成为内核原语的唯一持有者，oobPCI 不再需要。

### 3.5 Fakelib 绑定挂载

```
jbdInitEnvironment():
  makeFakeLib():
    1. 复制 /usr/lib → .fakelib/
    2. Patch dyld: 添加 systemhook.dylib 到 DYLD_INSERT_LIBRARIES
    3. mount("bindfs") 将 .fakelib/ 绑定挂载到 /usr/lib
  → 所有新启动的进程都会加载 systemhook.dylib
```

**这是越狱持久性的核心机制**: 通过 patch dyld 并绑定挂载，确保每个进程启动时自动加载 systemhook。

### 3.6 注入 launchdhook 到 launchd

```
opainject launchdhook.dylib into PID 1 (launchd)
```

launchdhook constructor 执行：
1. 从 jailbreakd 获取 PPL 原语
2. 安装 hooks：
   - **XPC hook**: 处理 jailbreakd 的原语请求
   - **Daemon hook**: 将 /var/jb 下的 LaunchDaemon 注入系统启动
   - **Spawn hook**: 确保 posix_spawn 传播 systemhook.dylib
   - **IPC hook**: 允许 `cy:` / `lh:` 前缀的 Mach 服务查找
   - **DSC hook**: 抑制 shared region pivot sysctl

### 3.7 最终化

```
Bootstrapper.finalizeBootstrap():
  安装 prep_bootstrap.sh
  安装 libjbdrw.deb + ellekit.deb + preferenceloader.deb
  安装用户选择的包管理器 (Sileo / Zebra)
  [if bridgeToXinA] 安装 xinamine.deb

路径映射 (if enabled):
  读取 page.liam.prefixers.plist
  对每个 source 调用 jbdBindMountPath()

刷新图标缓存
```

## 运行时 IPC 架构

越狱完成后，系统进入稳态运行：

```
┌─────────────────────────────────────────────────────────┐
│  所有进程 (systemhook.dylib 注入)                        │
│    → XPC → jailbreakd.systemwide                        │
│      功能: process_binary / debug_me / setuid_fix /     │
│            fork_fix / intercept_userspace_panic          │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│  jailbreakd (中央守护进程)                               │
│    Mach 服务: com.opa334.jailbreakd (特权)              │
│    Mach 服务: com.opa334.jailbreakd.systemwide          │
│    职责: PPL R/W / kcall / trustcache / fakelib /       │
│         进程权限管理 / 更新 / 绑定挂载                    │
└────────────────────┬────────────────────────────────────┘
                     │ XPC (hooked handler)
┌────────────────────▼────────────────────────────────────┐
│  launchd (PID 1, launchdhook.dylib 注入)                │
│    职责: 传播 systemhook / 注入 JB daemons /            │
│         原语交接 / IPC 沙盒放行                          │
└─────────────────────────────────────────────────────────┘

特殊组件:
  boomerang: 用户态重启时保持 PPL/PAC 原语存活
    IPC: libfilecom (文件 plist + vnode 监控)
  forkfix: hook fork() 修复 PAC 签名页权限
    IPC: pipe → jailbreakd
  watchdoghook: 拦截看门狗超时，防止内核 panic
    IPC: XPC → jailbreakd.systemwide
```

## 用户态重启流程

```
jbctl reboot_userspace:
  1. boomerang_userspaceRebootIncoming() — launchdhook 通知 boomerang
  2. launchd 将 PPL 原语通过 libfilecom 传给 boomerang
  3. boomerang 在重启中存活（KeepAlive 进程）
  4. 新 launchd 启动 → launchdhook constructor:
     检测到 boomerang 存在 → getPrimitives()
     → 恢复 PPL 原语，无需重新漏洞利用
```

## 关键不变量

1. **构建顺序不可变**: libfilecom → libjailbreak → 其余组件。forkfix 必须在 systemhook 之后。
2. **原语链**: oobPCI → jailbreakd → launchd → boomerang（重启后反向）
3. **信任链**: trustcache 必须在任何 BaseBin 二进制执行前加载
4. **Fakelib 必须在 launchdhook 注入前就位**: 否则新进程不会加载 systemhook
5. **WiFi 必须在 codeless kext 注册前关闭** (iOS < 15.4): PCI 设备需要被释放
6. **jailbreakd 的 systemwide 服务必须启动后才能注入 systemhook**: 否则进程无法执行 trustcache 查询
