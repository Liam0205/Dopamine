int setFakeLibVisible(bool visible);
int makeFakeLib(void);
bool isFakeLibBindMountActive(void);
int setFakeLibBindMountActive(bool active);
int64_t registerJbPrefixedPath(NSString *sourcePath, int retry);
int64_t bindMountPath(NSString *sourcePath, bool check_existances);
int64_t bindUnmountPath(NSString *sourcePath);
