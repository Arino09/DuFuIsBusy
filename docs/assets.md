# 素材来源与使用边界

素材由用户提供。父侧从已授权附件读取原始媒体后，以提交 `0ea979ec9d461a5f16626ba846d5bc0cf5c814ae` 向本仓库新增 26 个文件。消费端通过 Git 拉取后，逐张查看了 10 张位图及 16 个 SVG 图标的实际像素；没有重新下载失败的 Library 地址，也没有把父环境路径视为本机文件。

当前版本已删除全部 PPT 来源的 `assets/ui/paper-background.jpeg` 和 16 个 SVG 及其导入描述。纸色、细线、弧线由 `scripts/ink_paper.gd` 原创代码绘制；按钮、色块和文字由 Godot Control/Theme 构建。没有采用 PPT 页面截图或原图标。

- `assets/characters/dufu-avatar.png`：551×551 RGBA 透明头像。用于首页、绘画底图和提交作品合成；橡皮仅影响用户笔迹。
- `assets/characters/dufu-halfbody.jpg`：1980×1227 白底半身像。保留原始参考资源，未伪装为透明分层素材。
- `assets/backgrounds/scifi-city.jpg`、`night-market.jpg`：场景参考，可从素材目录查看，尚不能应用到画布。
- `assets/stickers/weapon-sheet.jpg`：1280×1561 五件武器白底源拼图。仅展示整图，不宣称已拆分成五张透明贴纸。
- `assets/examples/`：剑影江湖、科幻武器、夜市喝茶、厕所脑洞四张原始合成示例。可真实按武侠、科幻、市井、脑洞筛选并打开大图；不可编辑、不可作为用户已保存作品。

三个输入路径原为 `.png`，但文件签名与 Pillow 均识别为 JPEG，Godot 因扩展名不符报 `ERR_FILE_CORRUPT`。现仅无损改名，字节未变：

| 原提交路径 | 当前路径 |
|---|---|
| `assets/backgrounds/night-market.png` | `assets/backgrounds/night-market.jpg` |
| `assets/examples/night-market.png` | `assets/examples/night-market.jpg` |
| `assets/examples/restroom.png` | `assets/examples/restroom.jpg` |

未加入城堡素材、未下载额外外部美术、未公开原型 PPT、策划文档或分工表。未附素材授权清单，不为用户提供的素材作额外授权声明。

消费端只读取了 PPT 五页的文本结构；父侧看过原始五页并进行了布局对照。消费端没有独立查看 PPT 页面像素。按父侧反馈补充了画廊筛选、禁用的撤销/重做、四类强调色、可收起说明及扩大的画布。

中文字体来自环境安装的 Noto CJK，按本 Demo 字符集子集化。完整 OFL 许可及来源记录见 `assets/fonts/LICENSE.txt`，重建脚本为 `tools/subset-fonts.py`。

## 创作工具阶段

- 星星、祥云、忙字印章由 `scripts/drawing_surface.gd` 的几何绘制与文字绘制原创生成；没有使用 PPT 图片，也没有从五件武器白底拼图中伪造透明图层。
- 透明杜甫头像现在是独立可变换对象，画笔为独立透明像素层，文字/贴纸为可编辑对象层。提交图使用同一绘制逻辑在 SubViewport 中合成，排除选择框。
- `assets/fonts/CreativeSansSC.otf` 为环境安装的官方开源 Noto Sans CJK SC 完整字体，直接从 `NotoSansCJK-Regular.ttc` 的 SC face 提取，未按预置文案删字。沿用同目录 OFL 许可证；提取步骤见 `tools/copy-creative-font.py`。界面字体仍为较小子集。
- 用户输入支持完整字体覆盖的汉字、拉丁字母和常用标点；不支持字形会拒绝应用并提示替换，不静默显示方框。输入最多 24 字。
- 未新增外部图片下载、在线字体服务或收费素材。
