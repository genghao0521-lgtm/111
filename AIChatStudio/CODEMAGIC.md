# Codemagic 打包说明

这个目录已经包含 `codemagic.yaml`。如果你把 `AIChatStudio` 作为一个 GitHub/GitLab/Bitbucket 仓库根目录上传，Codemagic 可以直接读取这个配置。

## 你需要准备

- Apple Developer Program 账号。
- App Store Connect API Key，建议权限为 App Manager。
- 一个唯一 Bundle ID，例如 `com.yourname.aichatstudio`。

## 推荐流程：TestFlight / App Store

1. 在 Apple Developer / App Store Connect 中创建 App ID 和 App 记录，Bundle ID 要和项目一致。
2. 修改 `codemagic.yaml` 里的：

```yaml
BUNDLE_ID: "com.codex.aichatstudio"
```

改成你的 Bundle ID。

3. 如果你想收到构建邮件，把：

```yaml
- your-email@example.com
```

改成你的邮箱。

4. 把整个 `AIChatStudio` 文件夹提交到 GitHub/GitLab/Bitbucket。
5. 打开 Codemagic，点 `Add application`，连接这个仓库。
6. 选择 `codemagic.yaml` 工作流。
7. 在 Codemagic Team settings 里连接 `Developer Portal`，上传 App Store Connect API Key。
8. 在 Codemagic 的 iOS code signing identities 中生成或上传 Apple Distribution certificate，并获取 App Store provisioning profile。
9. 运行 `AI Chat Studio - iOS App Store` 工作流。
10. 构建成功后，在 Artifacts 下载 `.ipa`，或继续配置 publishing 到 App Store Connect/TestFlight。

## Ad Hoc 安装到自己手机

如果你暂时不走 TestFlight，而是想装到指定 iPhone：

1. 在 Apple Developer 里添加你的 iPhone UDID。
2. 创建 Ad Hoc provisioning profile。
3. 在 Codemagic 上传/获取这个 profile。
4. 运行 `AI Chat Studio - iOS Ad Hoc` 工作流。
5. 下载构建产物里的 `.ipa`。

## 常见坑

- `Bundle identifier` 必须和 Apple Developer、Codemagic 签名配置、`codemagic.yaml` 三处一致。
- App Store/TestFlight 必须用 `app_store` 类型签名。
- 第三方分发或指定设备安装通常用 `ad_hoc`。
- 如果 Codemagic 提示找不到 profile，不要混用手动证书字段和 `distribution_type + bundle_identifier` 自动匹配方式。
- SwiftUI 工程没有 `.xcworkspace`，所以配置里使用的是 `--project AIChatStudio.xcodeproj`。
