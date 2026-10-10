# DuFuIsBusy · 杜甫很忙

Godot **4.7.2 stable / Compatibility** 的中文轻松续画试玩版。真实 Control 与统一 Theme，原创代码纸纹与文字控件，使用用户 ZIP 人物素材。

[打开 Web 试玩](https://arino09.github.io/DuFuIsBusy/) · [验证记录](docs/validation.md) · [素材来源](docs/assets.md)

## 可以体验

- 四类命题或自由创作；鼠标、单指绘画，四种颜色和4–56 像素笔宽。
- 橡皮真正擦除笔迹，保留原人物；最多 20 步撤销/重做。
- 提交实际「人物 + 当前笔迹」图像，本地幽默点评并过关。只要求剩余笔迹非空，不识别内容、不评分、不调用 AI。
- 继续编辑、重新创作或换命题。每个命题独立保留笔迹、历史和点评，导航重建不会清空；重复提交不生成重复记录。
- 画廊示例筛选、大图和素材目录；本地设置偏好。

**画卷仅保留于本次打开期间，刷新或关闭即丢失。** 尚无作品文件保存/导出、永久画廊、贴纸放置或文字编辑。素材目录为源图参考；合成示例不能分层编辑。音频和画质设置仅保存偏好，当前没有音频或画质效果切换。

## 运行与导出

```sh
godot --editor --path .
godot --headless --editor --import --quit
godot --headless --path . --script tests/drawing_test.gd
mkdir -p build/web
godot --headless --export-release Web build/web/index.html
python3 -m http.server 8080 --directory build/web
```

Web 单线程、PWA 关闭，无 Wwise、在线 AI、后端、收费服务或新凭据。基准界面 1440×900 等比缩放，推荐桌面或横屏；竖屏可导航，但控件较小。撤销以完整笔画为单位，越界、失焦或窗口缩放会结束当前笔画。

Actions 在 PR 构建并执行像素测试，master 推送后部署 Pages，也可手动触发。保留原有最小权限，无 PAT。工具链和模板固定同版，以官方 SHA-512 校验。

![创作画布](docs/screenshots/canvas.png)
![实际作品与点评](docs/screenshots/review.png)

字体许可见 `assets/fonts/LICENSE.txt`。新增中文后运行 `python3 tools/subset-fonts.py`。
