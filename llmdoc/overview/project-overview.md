# Dopamine 项目概览

## 项目定位

Dopamine 是一款面向 iOS 15.0–16.6.1 的半无根（semi-untethered, rootless）越狱工具。基于 opa334/Dopamine 2.x 越狱框架（v2.4.9），由 Liam 维护的定制 fork。

- **上游**: `opa334/Dopamine` v2.4.9
- **Fork**: `Liam0205/Dopamine`，Bundle ID `page.0x01.Dopamine`
- **远端**: `git@github.com:Liam0205/Dopamine.git`
- **默认分支**: `dopamine`（1.x 遗留），活跃开发在 `liam-2.x`

## 架构变化：1.x → 2.x

| 维度 | 1.x | 2.x |
|------|-----|-----|
| App 框架 | Swift / SwiftUI | ObjC / UIKit |
| App 目录 | `Dopamine/` | `Application/` |
| 内核漏洞 | 仅 Fugu15 (oobPCI) | 多漏洞可选（用户选择） |
| PPL/PAC 绕过 | 单一方式 | 多种方式可选 |
| 特权操作 | jailbreakd 守护进程 | jbctl 内部命令 + launchdhook XPC |
| physrw | 单模式 | 双模式：physrw（完整映射）+ physrw_pte（PTE 操纵） |

## 工作原理（2.x 简化）

```
用户点击"越狱" → 选择内核漏洞 + PPL/PAC 绕过方式
  → 执行选定 exploit 获得物理 R/W
  → PPL 绕过 → kcall → 完整内核读写
  → 加载 basebin trustcache → 部署 Procursus bootstrap
  → jbctl 执行特权操作（无 jailbreakd 守护进程）
  → 注入 launchdhook 至 launchd（通过 XPC 通信）
  → 全系统 systemhook 注入 → 越狱完成
```

## 目录结构

| 目录 | 用途 | 语言 |
|------|------|------|
| `Application/` | UIKit iOS App + 本地化 | ObjC |
| `BaseBin/` | 设备端运行时组件（jbctl / launchdhook / systemhook 等） | C / ObjC / Logos |
| `Exploits/` | 多个内核漏洞利用（用户可选） | C / ASM |

## Fork 特色（liam-2.x 分支）

本 fork 在上游 2.x 基础上新增 14 项定制功能，分为四大类：

### 品牌与分发
- **自定义 Bundle ID**: `page.0x01.Dopamine`
- **编译时间宏**: Nightly 构建注入 `COMPILE_TIME`
- **更新通道**: 指向 `Liam0205/Dopamine` releases
- **CI/CD**: `liam-build.yml`（构建+缓存）+ `auto-sync.yml`（自动同步上游）
- **55-bit 版本编码**: 扩展版本数值表示，支持同一上游版本不同 release 的比较
- **更新 asset 选取**: 优先 `.tipa` 后缀

### 用户体验
- **系统运行时间与构建信息**: 主界面实时 uptime + 版本标识
- **确认弹窗与重启按钮**: 破坏性操作需确认，新增重启入口
- **越狱统计同步**: 累计越狱次数计数器

### 设置项
- **禁止更新检查**: toggle 跳过 OTA 检查
- **重建环境**: toggle 下次越狱强制重建 bootstrap

### Bootstrap 与注入
- **默认 APT 源**: `tweaks.0x01.page`
- **Unject 选择性注入黑名单**: 用户可跳过特定应用的 tweak 注入
- **Path Mapping（路径映射）**: 通过 jbctl internal 命令实现 bindfs 系统目录可写覆盖

详细实现细节见 `reference/dopamine-branch-features.md`。

## 许可证

- MIT (opa334/Dopamine)
- MIT (Pinauten GmbH/Fugu15)
- APSL 2.0 (libc 派生代码)

## 支持设备

iOS 15.0 – 16.6.1，支持所有 arm64e 设备（A12 及以上芯片）。
