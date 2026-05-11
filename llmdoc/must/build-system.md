# 构建系统

## 管线总览（2.x）

```
make all
  ├── make -C BaseBin          # 编译子项目 → basebin.tar + basebin.tc
  ├── make -C Packages         # 编译 libkrw-provider / libroot / basebin-link
  └── make -C Application      # xcodebuild → ldid 签名 → Dopamine.tipa
```

**关键不变量**: 根 Makefile 按 BaseBin → Packages → Application 顺序执行。Xcode 项目本身不调用 BaseBin 或 Packages 构建——根 Makefile 保证产物在 xcodebuild 之前就绪。

**与 1.x 区别**:
- App 目录为 `Application/`（非 `Dopamine/`），使用 ObjC 编写
- 不再有独立的 `Exploits/` 顶级目录，漏洞利用代码内嵌于 `Application/Dopamine/Exploits/`
- 新增 `Packages/` 构建步骤（libkrw-provider、libroot、basebin-link）
- Bootstrap 不再内嵌于仓库，构建时由脚本下载

## BaseBin 构建

### 构建顺序与依赖

BaseBin 使用 Makefile 驱动（非 pack.sh），构建流程：

```
ChOma (无依赖) → libchoma.dylib
  └─→ XPF (依赖 ChOma) → libxpf.dylib
MachOMerger (无依赖)
opainject (无依赖，Theos 构建)
libjailbreak (依赖 ChOma)
  ├─→ systemhook
  │     └─→ forkfix (依赖 systemhook + libjailbreak)
  ├─→ launchdhook
  ├─→ boomerang
  ├─→ jbctl
  ├─→ idownloadd
  ├─→ watchdoghook
  └─→ rootlesshooks (Theos 构建)
```

构建完成后:
1. `trustcache create .build/basebin.tc .build` → 生成 TrustCache
2. `dyldhook` 编译（不需加入 trustcache）
3. `.build/` 目录打包为 `basebin.tar`

### 与 1.x 区别

- 无 `jailbreakd`（其职能由 `jbctl` 承担）
- 无 `libfilecom`（移除）
- 无 `jbinit`（移除）
- 新增 `ChOma`、`XPF`、`MachOMerger`、`opainject`、`dyldhook`
- 共享头文件存放于 `.include/`，来自 `_external/include/` 和各子项目
- 预置文件（fallback、LaunchDaemons）来自 `_external/basebin/`

### 共享机制

- `.build/` 目录：所有编译产物的暂存区，初始化时从 `_external/basebin/` 复制基础文件
- `.include/` 目录：所有共享头文件，从 `_external/include/` 初始化，各子项目构建后追加各自头文件
- SDK 中若已有 XPC 头（iOS 17.4+），会移除本地 `.include/xpc/`

### 编译约定

所有组件统一使用 `arm64e` 架构、`iphoneos` SDK。Theos 组件（opainject、rootlesshooks）需 `$THEOS` 环境变量。

## 漏洞利用

2.x 的漏洞利用代码位于 `Application/Dopamine/Exploits/`，包含多个利用：

| 目录 | 描述 |
|------|------|
| `badRecovery` | — |
| `dmaFail` | — |
| `kfd` | — |
| `multicast_bytecopy` | — |
| `weightBufs` | — |

漏洞利用不再作为独立二进制构建并打包到 Resources，而是直接编译进 App 中。

## Packages 构建

`Packages/Makefile` 依次编译三个 Theos 包：

- `libkrw-provider` — KRW 接口提供者
- `libroot` — rootless 路径映射库
- `basebin-link` — basebin 符号链接包

## Application 构建

```
Application/Makefile:
  xcodebuild -scheme Dopamine (无代码签名)
  → NIGHTLY=1 时注入 GCC_PREPROCESSOR_DEFINITIONS:
      NIGHTLY=1
      COMMIT_HASH = git rev-parse HEAD
      COMPILE_TIME = 环境变量 $COMPILE_TIME
  → DOPAMINE_VERSION 非空时注入: MARKETING_VERSION = $DOPAMINE_VERSION
      (覆盖 CFBundleShortVersionString，使 app 内更新检查可正确比较版本)
  → xattr -rc (清除隔离属性)
  → ldid -SDopamine.entitlements (ad-hoc 签名)
  → Payload/ 打包为 Dopamine.ipa + Dopamine.tipa
```

### Bootstrap 下载

`Application/Dopamine/Resources/download_bootstraps.sh` 在构建前执行，下载 Procursus bootstrap 归档：

```bash
curl -L https://apt.procurs.us/bootstraps/1800/bootstrap-iphoneos-arm64.tar.zst
curl -L https://apt.procurs.us/bootstraps/1900/bootstrap-iphoneos-arm64.tar.zst
```

Bootstrap 不提交到仓库，CI 和本地构建均需运行此脚本。

## 本地构建前置条件

| 工具 | 用途 | 安装方式 |
|------|------|---------|
| Xcode + iOS SDK | App 编译 | Mac App Store |
| GNU Make | 并行构建 | `brew install make` |
| `ldid` | 伪代码签名 | Procursus (`brew install ldid`) |
| `trustcache` | TrustCache 生成 | 从 `CRKatri/trustcache` 源码编译（需 OpenSSL） |
| `$THEOS` | opainject / rootlesshooks / Packages 编译 | `git clone theos` + iPhoneOS16.5 SDK |
| Procursus 工具链 | coreutils / findutils / sed / make | CI 使用 `dhinakg/procursus-action` |
| `libarchive` | bootstrap 处理 | `brew install libarchive` |

## CI 工作流

| 工作流文件 | 触发分支 | 产出 |
|-----------|---------|------|
| `liam-build.yml` | `liam-2.x` (push/PR/手动) | Artifact: `Dopamine-Liam`（.ipa + .tipa）；tag `v*` 时创建 Release |
| `main.yml` | 所有分支 (push/PR/定时/手动) | Artifact: `Dopamine`（仅 .ipa） |

### CI 缓存策略

| 对象 | Cache action | Key | 路径 |
|------|-------------|-----|------|
| THEOS + SDK | `actions/cache@v4` | `theos-sdk16.5-${{ runner.os }}` | `theos` |
| trustcache binary | `actions/cache@v4` | `trustcache-${{ runner.os }}-${{ runner.arch }}` | `trustcache/trustcache` |

trustcache 安装分两步：Build（仅 cache miss 时编译）+ Install binary（每次都拷贝到 PATH）。

### CI 特点（与 1.x 区别）

- 运行于 `macos-latest`（非 macos-13）
- 无 `arm.pfx` 证书导入
- 无 sed 注入 `SECRETS_*` 到源码
- 新增 `Download Bootstraps` 步骤
- 使用 `gmake -j$(sysctl -n hw.logicalcpu) NIGHTLY=1` 并行构建
- 环境变量 `COMPILE_TIME` 使用 UTC+2 时间戳（格式 `YYYYMMDD_HHMMSS`）
- Artifact 名称: `Dopamine-Liam`（liam-build）/ `Dopamine`（main）

## 开发辅助 target

根 Makefile 提供 `update` 和 `update-basebin` target，用于 SSH 推送到测试设备：

```makefile
update:        # scp Dopamine.tipa → jbctl update tipa
update-basebin: # scp basebin.tar → jbctl update basebin
```

需设置 `DEVICE` 变量（如 `make update DEVICE=root@192.168.1.x`）。
