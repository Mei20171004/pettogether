# Pro Hosting 自动登录

`promenu` 中的健康报告 URL 应设为 `https://pettogether-pro.web.app/historyreport.html`。
App 只对这个 Hosting origin 注入登录凭证；其他 URL 仍可在 WebView 中打开，但不会自动登录。

1. 已登录且有 Pro / Free Coupon 权限的用户从健康页打开该菜单。
2. Hosting 页加载后，通过 `PetTogetherBridge` 告诉 App 它已准备好。
3. App 调用 `asia-northeast1` 的 2nd gen callable `issueWebSignInToken`。Firebase callable 自动携带 App 的 Firebase Auth ID Token，Function 只使用已验证的 `request.auth.uid` 创建 Custom Token。
4. App 只在页面仍位于可信 HTTPS origin、账号和 Pro 权限未改变时，用 JavaScript 通道把 Custom Token 交给页面。令牌不进入 URL、浏览器持久存储或 Firestore。
5. 页面以 `inMemoryPersistence` 调用 `signInWithCustomToken`，验证返回的 UID，然后按现有 Firestore 规则读取这个用户所属家庭的健康资料及其 Pro / Free Coupon 状态。

Function 仅在用户打开网页时被调用；没有定时用户状态验证。`userinfo` 仍由 App 原有逻辑更新。

## 部署

在仓库根目录部署单个 Function：

```sh
firebase deploy --only functions:issueWebSignInToken --project pettogether-76452
```

在 `02_websys/02_prosys` 部署独立 Hosting site：

```sh
firebase deploy --only hosting --project pettogether-76452
```

2026-09-27 的第一次 Function 部署已创建服务，但 Firebase CLI 在设置 Cloud Run `roles/run.invoker` 的 `allUsers` 绑定时，收到 `run.services.setIamPolicy` 权限不足（HTTP 403）。目前这个 Function 对 App 仍不可用。项目管理员需给执行部署的账号 `perfact.tang@gmail.com` 授予可以设置 Cloud Run 服务 IAM 的权限（例如项目级 `roles/run.admin`），之后重跑上述 Function 部署并确认返回的调用入口可到达 Function。公开的传输入口不代表公开发放令牌：Function 内仍要求经过 Firebase Auth 验证的 ID Token。先使 Function 可用，再部署正式 Hosting。

用已登录的新版 App 从健康页点击对应 Pro 菜单作端到端验证；直接在普通浏览器打开报告页只会显示“请从 App 打开”。
