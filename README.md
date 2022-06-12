
# jiazhu

适用于LuaMetaTeX(LMTX)的夹注模块。调整后应该可用于LuaTeX。

也是本人学习LuaMetaTeX、LuaTeX的练习项目，主要涉及：段落与行的结点列表的操控；使用tex.linebreak()函数等干预断行；使用回调函数。会保留较多学习性的注释和代码。

术语参考[CTeX-org](https://github.com/CTeX-org/ctex-kit/blob/master/jiazhu/jiazhu.dtx)：

> `jiazhu`: splitted annotation or
inline cutting note, 夹注/双行夹注 in simplified Chinese, 割注/warichū in Japanese.

## 大致思路

1. 在文档中段落插入夹注hbox，并给盒子加一个属性作为标记；
1. 在"processors"类的"after"小类回调中处理：
   1. 用一个一字宽rule结点代替段落中的夹注盒子，并在一个表中收集夹注盒子，循环：
      1. 重新试排段落，找到分行后的rule，获取从它到行末的宽度；
      1. 根据这个宽度试排对应夹注盒子的节点列表，循环：
         1. 如果试排所得大于或等于两行，则取前两行vpack插入rule之前，其后加罚点10000（强制断行点）；
            1. 如果正好两行（允许有第二行有一二字不满），删除rule标记；
         1. 如果不足两行，则缩小试排宽度，直到正好为两行为止（根据盒子原宽度优化算法）；
1. 用新的节点列表代替原段落的节点列表（由系统断行）。

## 当前状态

未完成。当前障碍是：使用tex.linebreak()试排段落时，末行行尾填充（parfillskip）无效。望方家不吝赐教。

# 关于断行、分段的备用资料

## cjk排版原型

http://wiki.luatex.org/index.php/Japanese_and_more_generally_CJK_typesetting

## cjk断行相关的系统文件：

* 语言脚本：D:\venvs\context-win64\tex\texmf-context\tex\context\base\mkiv\scrp-cjk.lua
* 行to段：D:\venvs\context-win64\tex\texmf-context\tex\context\base\mkiv\node-ltp.lua


## tex.linebreak的工作基于当前状态

https://www.mail-archive.com/dev-luatex@ntg.nl/msg01805.html

It is basing itself on the current TeX state at that point in time (at least, that is what it should do). You can look up tex_run_linebreak() in ltexlib.c, it should be easy to follow.

## Hans论干预断行的思路

https://www.mail-archive.com/luatex@tug.org/msg04329.html

> By the way, Hans, I heard you already reimplemented the TeX linebreak algorithm in pure Lua, can your code be found somewhere?

on my machine ... i'm waiting for the new hz in the backend before putting it in the context distribution because i don't want to end up with several versions (and i then need to prune some test code) ... so some patience is needed ...

btw there was an article on it some time ago, also in: http://www.pragma-ade.com/general/manuals/hybrid.pdf, p 101

**one thing you could play with is storing the paragraph before it gets broken, then let tex do the job, analyze afterwards, and when not ok, add some penalties and let tex do the job again**

but it might be better to rethink this special case (which is unlikely to mix with all those things that can end up in paragraphs, i.e. it's a limited tex-only case), and cook up something dedicated, at least that's the approach i'd choose as soon as context users start asking for such features

Hans

## 另一种思路：在两个回调中处理

https://www.mail-archive.com/luatex@tug.org/msg05587.html

I did set up pre_linebreak_filter to find out the cases where line breaking happens on the main vertical list (in contrast to being done in a box, say). Then inside pre_linebreak_filter I run

   tex.linebreak

several times with different looseness (you cann see all my reports coming together :-) ) and record the different results

Then in post_linebreak_filter I replace the generated paragraph node list with something special (basically to drop it) and to be able to find out about the para on the contribution list (which I look at in buildpage_filter). Could probably be done differently but that was the simplest way to get this working for me.

## 关于parbuilder (and related hpacking)

http://www.pragma-ade.com/general/manuals/hybrid.pdf, p95

in September 2008, when we were exploring solutions for Arabic par building, Taco converted the parbuilder into Lua code and **stripped away all code related to hyphenation, protrusion, expansion, last line fitting, and some more.**

