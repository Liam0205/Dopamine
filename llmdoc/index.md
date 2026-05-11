# llmdoc 全局文档索引

## /must/ — 每次会话必读

| 文档 | 说明 |
|------|------|
| `must/build-system.md` | 2.x 构建管线：BaseBin Makefile → download_bootstraps → xcodebuild → tipa |
| `must/workflow.md` | 分支策略（2.x / liam-2.x）、CI 工作流（liam-build / auto-sync）、本地开发 |

## /overview/ — 项目身份与边界

| 文档 | 说明 |
|------|------|
| `overview/project-overview.md` | Dopamine 2.x fork 概览：iOS 15–16.6.1、ObjC/UIKit、14 项定制功能 |

## /architecture/ — 架构与不变量

| 文档 | 说明 |
|------|------|
| `architecture/jailbreak-lifecycle.md` | ⚠️ 基于 1.x 架构，待更新为 2.x（无 jailbreakd，改用 jbctl + launchdhook XPC） |
| `architecture/basebin-components.md` | ⚠️ 基于 1.x 架构，待更新（2.x 移除 jailbreakd/libfilecom/jbinit，新增 ChOma/XPF 等） |

## /reference/ — 稳定事实查询

| 文档 | 说明 |
|------|------|
| `reference/dopamine-branch-features.md` | liam-2.x 分支相对上游 2.x 的 14 项定制功能，含 commit 与实现细节 |

## /guides/ — 工作流指南

（待补充）

## /memory/ — 历史记忆

| 文档 | 说明 |
|------|------|
| `memory/decisions/` | 架构决策记录 |
| `memory/reflections/2026-05-11-init.md` | llmdoc:init 反思：关键发现与覆盖空白 |
| `memory/reflections/2026-05-11-2x-migration.md` | 2.x 迁移反思：架构差异、移植决策、文档影响 |
| `memory/doc-gaps.md` | 已知文档缺口 |
