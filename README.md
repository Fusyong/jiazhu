适用于ConTeXt和LuaMetaTeX(LMTX， LuaTeX的后继者，ConTeXt当前的实际引擎)的夹注模块，可以配合[竖排功能和标点压缩功能](https://blog.xiiigame.com/2022-02-15-ConTeXt-LMTX%E4%B8%AD%E6%96%87%E7%AB%96%E6%8E%92%E6%8F%92%E4%BB%B6/)使用。调整后应该可用于LuaTeX。

也是本人学习LuaMetaTeX、LuaTeX的练习项目，主要涉及：段落与行的结点列表的操控；使用tex.linebreak()函数等干预断行；使用回调函数。会保留较多学习性的注释和代码。

## 效果


![plot](https://blog.xiiigame.com/img/2022-02-15-ConTeXt-LMTX中文竖排插件/vtypesetting_callback_1.jpg)

![plot](https://blog.xiiigame.com/img/2022-02-15-ConTeXt-LMTX中文竖排插件/vtypesetting_callback_2.jpg)


## 术语

术语参考[CTeX-org](https://github.com/CTeX-org/ctex-kit/blob/master/jiazhu/jiazhu.dtx)：

> jiazhu(in Hanyu Pinyin): splitted annotation or
inline cutting note, 夹注/双行夹注 in simplified Chinese, 割注/warichū in Japanese

## 大致思路

1. 在文档中段落插入夹注hbox，并给盒子加一个属性作为标记；
1. 在"processors"类的"after"小类回调中处理：
    1. 用一个一字宽rule结点代替段落中的夹注盒子，并在一个表中收集夹注盒子，循环：
        1. 试排段落，找到分行后的rule，获取从它到行末的宽度；
        1. 根据这个宽度和盒子的自然宽度预计、试排盒子的节点列表，循环：
            1. 预估小于或等于两行时，按盒子宽度的一半试排为两行（可略宽容），删除rule；
            1. 如果预估大于两行，则按空间宽度试排，取前两行；
            1. vpack插入rule之前，其后加罚点0，（当基本填满行末空间时罚点-10000，即强制断行，放置再次插入夹注）；
1. 用新的节点列表代替原段落的节点列表（由系统断行）。

## bug & TODO

* [x] 夹注转换成标记结点和数据表
* [x] 夹注整理，分段插入
* [x] 与直排模块整合
  * [x] 长夹注（78字以上）内存溢出，死循环
    * [x] 无用结点清洗
    * [x] 计数考虑直排盒子（**问题在此**）
* [x] 在标题中无效
* [X] 夹注前空过大
* [x] 优化夹注断行算法（目前每次重新断行后取前两行，往往质量较低，宽度也不可控，常导致溢出）
  * [x] 使用parshape一次完成分组(**已废弃**，因插图时可能导致错误，且目前对参数过于敏感导致某些夹注分行时溢出而致无限循环，存档为jiazhu_parshape.lua)
* [x] 兼容新函数`tex.preparelinebreak()`
  * [x] parfillskip不起作用（用自定glue代替，但可能影响标点压缩模块，导致同样内容的两行不整齐）
    * [x] `tex.preparelinebreak()`注入的parfillskip有效
  * [ ] 与narrower重叠使用缩进（当在linebreak设置）
    * [X] 暂时用\leftskip代替
* [x] 夹注长度错误，导致与正文重叠，悬挂在版心外
  * [x] 逐行手动测量实际视觉长度
    * [x] 检查correctionskip导致的悬挂（因为是负值，无法通过手动测量感知，需清除后再测量）
  * [x] 比较视觉长度与盒子自然宽度，以大者为准
* [ ] 监控`tex.linebreak()`的质量，检查夹注行overfull
  * [ ] 检查、调整linebreak、hpack、vpack前后的info
  * [ ] 或检查正文行overfull，压缩标点
* [ ] 模块化，增加用户接口
  * [ ] 双行兼容单行

# 关于断行、分段的备用资料

## cjk排版原型

<http://wiki.luatex.org/index.php/Japanese_and_more_generally_CJK_typesetting>

## cjk断行相关的系统文件

* 语言脚本：D:\venvs\context-win64\tex\texmf-context\tex\context\base\mkiv\scrp-cjk.lua
* 行to段：D:\venvs\context-win64\tex\texmf-context\tex\context\base\mkiv\node-ltp.lua

## tex.linebreak的工作基于当前状态

<https://www.mail-archive.com/dev-luatex@ntg.nl/msg01805.html>

It is basing itself on the current TeX state at that point in time (at least, that is what it should do). You can look up tex_run_linebreak() in ltexlib.c, it should be easy to follow.

## Hans论干预断行的思路

<https://www.mail-archive.com/luatex@tug.org/msg04329.html>

> By the way, Hans, I heard you already reimplemented the TeX linebreak algorithm in pure Lua, can your code be found somewhere?

on my machine ... i'm waiting for the new hz in the backend before putting it in the context distribution because i don't want to end up with several versions (and i then need to prune some test code) ... so some patience is needed ...

btw there was an article on it some time ago, also in: <http://www.pragma-ade.com/general/manuals/hybrid.pdf>, p 101

**one thing you could play with is storing the paragraph before it gets broken, then let tex do the job, analyze afterwards, and when not ok, add some penalties and let tex do the job again**

but it might be better to rethink this special case (which is unlikely to mix with all those things that can end up in paragraphs, i.e. it's a limited tex-only case), and cook up something dedicated, at least that's the approach i'd choose as soon as context users start asking for such features

Hans

## 另一种思路：在两个回调中处理

<https://www.mail-archive.com/luatex@tug.org/msg05587.html>

I did set up pre_linebreak_filter to find out the cases where line breaking happens on the main vertical list (in contrast to being done in a box, say). Then inside pre_linebreak_filter I run

   tex.linebreak

several times with different looseness (you cann see all my reports coming together :-) ) and record the different results

Then in post_linebreak_filter I replace the generated paragraph node list with something special (basically to drop it) and to be able to find out about the para on the contribution list (which I look at in buildpage_filter). Could probably be done differently but that was the simplest way to get this working for me.

## 关于parbuilder (and related hpacking)

<http://www.pragma-ade.com/general/manuals/hybrid.pdf>, p95

in September 2008, when we were exploring solutions for Arabic par building, Taco converted the parbuilder into Lua code and **stripped away all code related to hyphenation, protrusion, expansion, last line fitting, and some more.**

## 末行长度与段落填充控制

<https://tex.stackexchange.com/questions/63762/minimum-length-of-last-line-of-a-paragraph>

## 结点操控参考实例

* <https://github.com/gucci-on-fleek/lua-widow-control>
