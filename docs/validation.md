# UI Demo 验证记录

日期：2026-10-09。工程位于独立目录 `/workspace/DuFuIsBusy`，未修改 GameJam2026 或其部署。

## 实际运行环境

Godot `4.7.2.stable.official.ed1daf0bf`，同版官方 Web 模板。Compatibility、单线程、PWA 关闭。

原生验证使用独立 Xorg dummy 显示器、Mesa llvmpipe、XTest 鼠标输入。Web 验证使用 Chromium 151 + Playwright，在本机 `/DuFuIsBusy/` 子路径运行真正的导出版本。用户明确授权仅本次隔离测试进程临时关闭 Chromium 沙箱；只访问 localhost、拒绝页面外部请求，测试后关闭浏览器和 HTTP 服务。未更改持久安全设置。

## 已验证的行为

| 项目 | 结果 |
|---|---|
| 五页 UI、中文字体、原始图片与 SVG | 实际 WebGL 渲染并查看截图；真实控件，不是页面截图 |
| 四类命题与返回 | 逐一点击进入画布，命题正确，返回正常 |
| 命题栏 | 独立于画布，未重叠；说明可收起，画布宽度增加 |
| 撤销 / 重做 | 真实禁用，点击不会伪造操作 |
| 原像 / 武器 / 场景大图 | 打开和返回正常；明确标注只读、整图、未开放放置 |
| 画廊筛选 | 全部 4 张；武侠、科幻、市井、脑洞各 1 张；筛选后大图对应正确 |
| 我的作品 | 空态，不伪造存档 |
| 重复点击与键盘 | 无弹窗堆叠；Tab 不进入背景控件；Escape 可返回 |
| 设置持久化 | 连续更改后立即刷新，音量 49% 和音效关闭均保留；再次切换与恢复默认正常 |
| 不同尺寸 | 1440×900、1024×768、844×390、390×844 可导航，无裁切；竖屏文字较小，尚非手机专用布局 |
| Web 资源 | 子路径资源返回成功；无脚本异常、失败请求或外部页面请求 |
| 浏览器控制台 | 无 error；软件渲染截图时有 `GPU stall due to ReadPixels` 性能警告 |

发现并修复了 Web 设置写入时序问题：原先连续 ConfigFile 写入后立即刷新可能丢失最后一次修改，Web 改为同步 localStorage；原生继续使用 ConfigFile。刷新后再次点击开关验证读取的实际状态，而不只检查存储内容。

## 素材核验

消费端通过父侧提交 `0ea979e` 获取并逐图查看 26 份实际媒体。三份名为 PNG 的文件实际为 JPEG；仅改扩展名及引用，原始字节不变。详情见 [素材记录](assets.md)。

消费端未独立查看 PPT 五页像素。父侧已看过原型并提出四项布局修正，现已实现；最终原型对照由父侧完成。

## 发布验证的分工

父侧已确认启用 Pages，并成功发布旧骨架 `6da2cac`。本次素材版将通过同一工作流部署，以最新提交的 Actions 结果为准。当前环境访问公开 Pages 域名曾被代理 CONNECT 403 拒绝，因此本地截图不冒充线上截图；最终线上视觉复核由父侧受支持浏览器完成。

## 最新截图

- [首页](screenshots/home.png)
- [命题画卷](screenshots/levels.png)
- [创作画布](screenshots/canvas.png)
- [画廊](screenshots/gallery.png)
- [设置](screenshots/settings.png)
- [贴纸目录](screenshots/stickers.png)
- [我的作品空态](screenshots/gallery-mine.png)
- [刷新后的设置](screenshots/settings-reloaded.png)
