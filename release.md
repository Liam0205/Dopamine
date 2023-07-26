## 关于本次更新

这本质上是一个自用版本，发布的意思是「分享」。

### 1.1.2 - 20230726_165300

1. 在 App 刚启动的尚未载入系统启动时间之时，显示有意义的占位符而非显示为空白。
2. 更新上游至 `opa334/Dopamine:05e5d77`。这个提交将我之前的代码并入了上游，因此对于使用我的版本的用户实际上没有任何变化。
3. 更新上游至 `opa334/Dopamine:08a00c0`。这个提交以不会被探测到的方式重新实现了 `launchd` 崩溃报告。
4. 对 commit 重新排序，以适应将来可能的变更。
5. 新功能开发中。

## 修改版的主要功能

1. 提供汉化（包括中国大陆、中国香港、中国台湾）。对，汉化作者是我（自豪）。
2. 可与官方版本共存。
3. 支持应用内更新越狱包。
4. 支持目录映射，并支持越狱后新增目录映射（而无需重启越狱；位于越狱后的设置中）。
5. 允许用户在越狱成功后点按「用户空间重启以完成越狱」，而不是自动重启。
6. 额外提供「软重启」、「重启」功能按钮。
7. 提供重建越狱引导环境的功能（位于设置中）。
8. 提供「屏蔽更新」的功能，以屏蔽 Dopamine 在启动时检查更新。当然，你可能因此错过最新更新；虽然这通常不是什么大问题。
9. 提供「桥接心浪」的功能，以便以 XinA 的模式安装有根插件。
10. 在首次越狱和重建越狱时，自动安装正确版本的 ElleKit 和 PreferenceLoader。
11. 首页加入编译时间及系统启动时间，关于页加入编译版本。

------

## About This Update

This modification is disigned to be used only by me myself.

### 1.1.2 - 20230726_165300

1. Display meaningful placeholders instead of showing blank when the app is launched before the system startup time has elapsed.
2. Update upstream to `opa334/Dopamine:05e5d77`. This commit incorporates my previous code into the upstream repository, so there are no actual changes for users who are using my mod.
3. Update upstream to `opa334/Dopamine:08a00c0`. This commit re-implements `launchd` crash reporter in a way that will not be detected.
4. Reordering commits to accommodate potential future changes.
5. New Feature: WIP...

## About this Mod

1. Offers Chinese translation (Mainland China, Hongkong of China, Taiwan of China).
2. Be able to stay with the official version.
3. Offers the ability to OTA update.
4. Support path bind & mount. Also support hot bind & mount (do not need to reboot and re-jailbreak; find it at settings page after jailbroken).
5. Allow users to reboot userspace by tap button, rather than slightly reboot.
6. Offers ldrestart and reboot buttons.
7. In settings, users could enable "rebuild environment".
8. Provide a "block updates" feature to block Dopamine from checking for updates on startup. However, you may miss out on the latest updates as a result, although this is generally not a significant issue.
9. Provide the "Bridge to XinA" feature to facilitate the installation of rooted plugins using the XinA mode.
10. Installing the correct ElleKit and PreferenceLoader when Jailbreak for the first time.
11. Add compile time and system uptime on the first page, and add compile version in about page.

------
