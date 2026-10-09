# 素材来源与使用边界

素材由用户提供。父侧从已授权附件读取原始媒体后，以提交 `0ea979ec9d461a5f16626ba846d5bc0cf5c814ae` 向本仓库新增 26 个文件。消费端通过 Git 拉取后，逐张查看了 10 张位图及 16 个 SVG 图标的实际像素；没有重新下载失败的 Library 地址，也没有把父环境路径视为本机文件。

- `assets/ui/paper-background.jpeg`：2730×1536 宣纸水墨底纹。用作背景纹理，所有控件仍是真实 Control。
- `assets/ui/*.svg`：原型中的 16 个图标。使用与实际含义相符的图标；`brush.svg` 的实际图形为清除桶，用于恢复默认设置，画笔使用 `pencil.svg`。
- `assets/characters/dufu-avatar.png`：551×551 RGBA 透明头像。用于首页与画布人物保留区。
- `assets/characters/dufu-halfbody.jpg`：1980×1227 白底半身像。可在画布打开完整原像查看，未伪装为透明分层素材。
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
