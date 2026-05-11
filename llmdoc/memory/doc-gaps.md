# 文档缺口

## 已知缺口

### 高优先级

1. **KFD 漏洞变体**: `kfd_dev` 分支使用不同的漏洞路径，当前文档仅覆盖 oobPCI 路径
2. **KernelPatchfinder 包**: 外部 SPM 依赖，提供 ~34 个内核偏移量的查找逻辑，未文档化
3. **libjailbreak 完整实现**: 仅记录了头文件接口，`.m` 实现文件未详细记录

### 中优先级

4. **oobPCI 漏洞机制细节**: PCI BAR 越界的具体原理（physrw.c / tlbFail.c 内部逻辑）
5. **fastPath 证书链**: genCrt.sh 生成流程 + Apple OID 含义完整映射
6. **Codeless kext 与 WiFi 驱动交互**: IOKit 匹配优先级的具体行为
7. **BaseBin/_external/ 出处**: opainject、tar、CydiaSubstrate.framework 的构建来源

### 低优先级

8. **BuildVFS 工具**: Tools/Makefile 中引用但目录不存在，可能已废弃
9. **installHaxx 完整用途**: FAT 二进制打包的具体集成点不明确
10. **路径映射 plist 格式**: `page.liam.prefixers.plist` 的完整 schema
11. **本地化工作流指南**: localisort 工具的安装和使用
