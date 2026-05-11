# 开发工作流 (2.x)

## 分支策略

| 分支 | 用途 | CI 行为 |
|------|------|---------|
| `2.x` | 上游镜像 (opa334/Dopamine 2.x) | auto-sync 每小时同步，**禁止直接修改** |
| `liam-2.x` | 活跃开发分支，12 个定制 commit 基于 2.x | push/PR 触发构建，tag push 触发 Release |
| `dopamine` | 1.x 正式发布 (legacy) | Dopamine.yml，不再活跃开发 |
| `dev` | 1.x 开发预发布 (legacy) | Dopamine_prerelease.yml，不再活跃开发 |

## CI 工作流

### liam-build.yml — 构建与发布

触发条件：push/PR 到 `liam-2.x`，或 tag push (`v*`)，或手动 dispatch。

流程：
1. macos-latest，setup Xcode latest-stable
2. 安装 Procursus (ldid, findutils, sed, coreutils, make) + GNU Make (brew)
3. 安装 THEOS + iPhoneOS16.5 SDK
4. 编译 trustcache (OPENSSL=1)
5. 设置环境变量：`COMPILE_TIME` = UTC+2 时间戳 `YYYYMMDD_HHMMSS`
6. 下载 Bootstraps (`Application/Dopamine/Resources/download_bootstraps.sh`)
7. `gmake -j NIGHTLY=1` 构建
8. 上传 Artifact：`Dopamine.ipa` + `Dopamine.tipa`
9. 若为 tag push (`v*`)：创建 GitHub Release（自动生成 release notes）

### auto-sync.yml — 上游自动同步

触发条件：每小时 cron + 手动 dispatch。需要 `PAT_TOKEN` secret。

流程：
1. ubuntu-latest，fetch-depth=0
2. fetch upstream (opa334/Dopamine) 2.x 分支 + tags
3. fast-forward `origin/2.x` 到 `upstream/2.x`，push tags
4. rebase `liam-2.x` onto `2.x`，force-with-lease push
5. rebase 失败 → 创建 issue (label: `auto-sync-conflict`)
6. rebase 成功 + 上游有新 tag → 打 `{tag}-liam` 标签并 push（触发 liam-build Release）

冲突手动解决：
```bash
git fetch origin
git checkout liam-2.x
git rebase origin/2.x
# 解决冲突
git push origin liam-2.x --force-with-lease
```

### Legacy 工作流

- `Dopamine.yml` — dopamine 分支，1.x 正式发布
- `Dopamine_prerelease.yml` — dev 分支，1.x 预发布
- `main.yml` — 已禁用

## 日常开发循环

### 完整构建 + 推送设备

```bash
make update
```

等价于：
1. `make all` — 编译所有组件 + 打包 .tipa
2. `./jbupdate.sh` — scp 到设备 + `jbctl update tipa`

设备别名定义在 `jbupdate.sh`: `DEVICE=iPhone13Pro.Remote`（SSH config）。

### 仅构建不推送

```bash
make          # 产出 Application/Dopamine.tipa
```

### 单组件热替换

无需完整构建即可测试单个 dylib：

```bash
# forkfix (端口 2222)
cd BaseBin/forkfix && ./upload.sh

# systemhook (端口 2223，自动 rebuild trustcache)
cd BaseBin/systemhook && ./upload.sh
```

upload.sh 内部逻辑：编译 → scp 到设备 `/var/jb/` 对应路径 → 可能触发 trustcache 重建。

### 清理构建

```bash
make clean    # 调用 BaseBin/clean.sh（各组件 make clean）
```

## 本地构建环境配置

```bash
# 1. 安装 Procursus 工具
brew install ldid coreutils make

# 2. 编译安装 trustcache
git clone https://github.com/CRKatri/trustcache
cd trustcache && make OPENSSL=1 && sudo cp trustcache /usr/local/bin/

# 3. 安装 Theos
export THEOS=~/theos
git clone --recursive https://github.com/theos/theos.git $THEOS

# 4. 确保 Xcode + iOS SDK 已安装
xcode-select --install
```

## 版本与标签

- Release tag 格式: `v*`（如 `v2.0.1`）
- 上游同步自动打标签: `{upstream_tag}-liam`（如 `v2.0.1-liam`）
- Artifact 命名: `Dopamine-Liam`
- COMPILE_TIME: UTC+2 格式 `YYYYMMDD_HHMMSS`

## 设备调试

越狱后设备上可用工具：
- `/var/jb/basebin/jbctl` — 管理命令
- `/var/jb/basebin/idownloadd` — KRW 网络 shell（需设置中启用）

常用 jbctl 命令：
```bash
jbctl rebuild_trustcache         # 重建信任缓存
jbctl reboot_userspace           # 用户态重启
jbctl update tipa <path>         # 从 .tipa 更新
jbctl proc_set_debugged <pid>    # 标记进程可调试
jbctl bindmount_path <path>      # 添加路径映射
```
