# UI Demo 验证记录

日期：2026-10-09。初始远程提交：`d398d5df37ef32e716fca4906351b1ed53740ad7`，默认分支 master。

## 环境与隔离

项目在 `/workspace/DuFuIsBusy`；工具、缓存和证据在独立的 `/workspace/dufu-tools` 与 `/workspace/dufu-evidence`。未编辑 GameJam2026 或其部署。

Godot `4.7.2.stable.official.ed1daf0bf` 与 `4.7.2.stable` Web 模板。原生实测由 Xorg dummy 显示器 + Mesa llvmpipe 渲染；脚本用 XTest 注入真实鼠标事件，截取实际窗口。

## 已实测

| 范围 | 结果 |
|---|---|
| 首页、命题、画布、双页签画廊、设置 | 实际渲染，已视觉查看五类页面截图 |
| 开始闯关、自由创作、返回首页 | 真实点击可到达；日志记录页面变化 |
| 交通 / 科幻主题切换 | 命题文本变化；画布命题栏不覆盖画布 |
| 贴纸分类目录、文字构图示例弹窗 | 可打开、关闭；明确标示未实现功能 |
| 重复点击工具 / 暂歇按钮 | 无多层弹窗堆叠或脚本错误 |
| 音量与音效偏好 | 调到 49%、关闭音效；文件写入并在重新进入页面显示 |
| 恢复默认确认 | 有确认与取消；取消保留当前偏好 |
| 1440×900、1024×768 | 页面完整，较窄比例有留边，未见控件重叠 |
| 中文字体 | 本地打包字体，截图可读，未依赖浏览器系统字体 |

初次原生运行因环境无声卡出现 ALSA 错误并回退 dummy；不是 UI 脚本错误。正式检查用 `--audio-driver Dummy`。

## Web 导出与静态子路径检查

本机 release 导出成功。`/DuFuIsBusy/` 子路径下 HTML、JS、PCK、WASM、PNG 均返回 HTTP 200，WASM MIME 为 `application/wasm`，未配置 service worker。最终导入、headless 场景运行和导出日志没有脚本或资源错误。此项是静态传输检查，不等同于浏览器 WebGL 运行验收。

## 尚未通过的完整验收项

1. Library 原始附件本地传输失败：初次及一次支持流程重试均报 `download failed`。没有素材字节，未独立视觉核对 PPT 五页及 ZIP 像素。占位不是最终素材。
2. Chromium 151 的 SUID sandbox helper 不归 root 所有，正常沙箱启动被 Chromium 拒绝。未关闭沙箱，因此没有 WebGL 浏览器操作、浏览器控制台、线上截图验收。
3. `gh api` 返回 Forbidden；当前工具没有 Pages 设置写入接口。首次 Pages 启用可能需仓库管理员在 Settings → Pages 选择 GitHub Actions。
4. 竖屏仅等比缩放，不是专门的手机布局。

## 截图

- [首页](screenshots/home.png)
- [命题画卷](screenshots/levels.png)
- [创作画布](screenshots/canvas.png)
- [贴纸目录](screenshots/stickers.png)
- [灵感画廊](screenshots/gallery-inspiration.png)
- [我的作品空态](screenshots/gallery-mine.png)
- [设置](screenshots/settings.png)
- [1024×768](screenshots/home-1024.png)
