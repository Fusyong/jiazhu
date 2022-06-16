Moduledata = Moduledata or {}
Moduledata.jiazhu = Moduledata.jiazhu or {}
Jiazhu = Moduledata.jiazhu

local glyph_id = nodes.nodecodes.glyph --node.id("glyph")
local hlist_id = nodes.nodecodes.hlist
local vlist_id = nodes.nodecodes.vlist
local glue_id = nodes.nodecodes.glue
local rule_id = nodes.nodecodes.rule
local par_id = nodes.nodecodes.par
local whatsit_id = nodes.nodecodes.whatsit

-- 用rule代替夹注盒子，并收集夹注盒子
local function boxes_to_rules(head)
    local n = head
    local jiazhu_boxes = {}
    while n do
        if node.hasattribute(n, 2, 222) and n.id == hlist_id then
            -- print("======找到夹注====")
            -- print(box)
            -- print(nodes.tosequence(box.list))
            -- print(nodes.toutf(box.list))
        
            -- local w = node.new(whatsit_id, "user_defined") --8
            local w = node.new(rule_id)
            w.width = tex.sp("1em")
            node.setattribute(w, 3, 333)
            -- local v = node.hasattribute(w, 3, 333)
            -- w.type = 108
            -- w.value = "hello world"
            -- w.user_id = 5
            -- print(w.subtype, w.user_id,w.type, w.value,w.attr, v)
            head = node.insertbefore(head, n, w)
            print("----------------glue---------------")
            print(n.prev)
            print("----------------glue1---------------")
            print(n.prev.prev.width)
            print(n.prev.prev.stretch)
            print(n.prev.prev.stretchorder)
            print(n.prev.prev.shrink)
            print(n.prev.prev.shrinkorder)
            print("----------------glue2---------------")
            print(n.prev.prev.prev.prev.width)
            print(n.prev.prev.prev.prev.prev.prev.stretch)
            print(n.prev.prev.prev.prev.stretchorder)
            print(n.prev.prev.prev.prev.shrink)
            print(n.prev.prev.prev.prev.shrinkorder)
            local removed = nil
            head, n, removed = node.remove(head, n)
            table.insert(jiazhu_boxes, removed)
            -- print("===========================")
            -- print(nodes.tosequence(new_head))
            -- print(nodes.toutf(new_head))
        end
        n = n.next
    end

    return head, jiazhu_boxes
end

-- 试排主段落 hsize：宽度；to_stretch：尾部拉伸（否则压缩）
local function par_break(par_head, hsize, to_stretch)

    local new_head = par_head
    local is_vmode_par = (new_head.id == par_id)

    -- print("==========分行前==========")
    -- print(nodes.tosequence(par_head))
    
    if not is_vmode_par then
        print("==========插入par==========")
        local vmodepar_node = node.new("par", "vmodepar")
        new_head, _ = node.insertbefore(new_head, new_head, vmodepar_node)
    end

    -- 删除最后的胶；添加无限罚分和parfillskip；保障pre指针正确
    local tail = node.slide(new_head) --node.tail()不检查前后指针
    if tail.id == glue_id then
        new_head, tail = node.remove(new_head, tail, true)
    end

    -- 添加无限罚分
    local penalty = node.new("penalty")
    penalty.penalty = 10000
    new_head, tail = node.insertafter(new_head, tail, penalty)
    
    -- 添加hskip
    local hskip = node.new("glue")
    if to_stretch then
        hskip.width = 0
        hskip.stretch = hsize
    else
        hskip.width = hsize -- 能模仿系统断行
        hskip.shrink = hsize -- 能模仿系统断行
    end
    new_head, tail = node.insertafter(new_head, tail, hskip)

    -- 添加段末胶parfillskip（ TODO 似乎不起作用）
    local parfillskip = node.new("glue", "parfillskip") --一般是0pt plus 1fil
    parfillskip.stretch = 2^16 -- 可拉伸量2^16(65536)意义不明
    parfillskip.stretchorder = 2^16 --拉伸倍数2(fil)，意义不明
    new_head, tail = node.insertafter(new_head, tail, parfillskip)
  
    -- 保障prev指针正确
    node.slide(new_head)

    print("=========预备分行用的段落===========")
    for i in node.traverse(par_head) do
        print(i)
    end
    print(nodes.tosequence(par_head))
    print("tail",node.tail(par_head))

    language.hyphenate(new_head) -- 断词，给单词加可能的连字符断点
    new_head = node.kerning(new_head) -- 加字间（出格）
    new_head = node.ligaturing(new_head) -- 西文合字
    
    -- 用hsize控制分行宽度：{hsize =  tex.sp("25em")}；
    -- 语言设置作用不详：{lang = tex.language}
    local para = {hsize=hsize,tracingparagraphs=1}
    local info
    new_head, info = tex.linebreak(new_head, para)

    return new_head, info
end

-- 测量夹注宽度
local function jiazhu_hsize(hlist, current_n)
    -- 后面的实际宽度（包括突出）、高度、深度
    local d = node.dimensions(
        hlist.glue_set,
        hlist.glue_sign,
        hlist.glue_order,
        current_n
    )
    return d
end

-- 生成双行夹注
local function make_jiazhu(par_head_with_rule, vpar_head,hsize, boxes)
    local b = boxes[1]
    local box_width =b.width -- 对应的夹注盒子宽度
    -- print("========夹注===========")
    -- print("hsize", hsize)
    -- print("box_width", box_width)
    -- print("<<<<<<<<<<<< 盒子 1 >>>>>>>>>>>>")
    -- for i in node.traverse(b.list) do
    --     print(i)
    -- end

    -- 夹注重排算法
    local width_tolerance = tex.sp("0.5em") -- 宽容宽度（挤进一行）；兼步进控制
    local vbox_width = box_width / 2
    local par_head, info
    -- 可一次（两行）安排完的短盒子
    if vbox_width <= (hsize + width_tolerance) then
        local line_num = 3
        while(line_num >= 3) do
            par_head, info = par_break(node.copylist(b.list), vbox_width, true)
            line_num = info.prevgraf
            vbox_width = vbox_width + width_tolerance / 2 -- TODO 改进步进量或段末胶
        end
        -- TODO 插入vbox，删除box，删除rule
        -- 需要循环安排的长盒子
    else
        par_head, info = par_break(node.copylist(b.list), hsize, false)
        -- TODO 插入vbox，剪裁box
    end
    
    context(par_head)

    return par_head_with_rule, vpar_head, boxes
end

-- 根据第一个rule的位置分拆、组合、插入夹注盒子、罚点等
local function insert_jiazhu(par_head_with_rule, vpar_head, jiazhu_boxes)
    local v_n = vpar_head
    local stop = false
    -- print("<<<<<<<<<<<<准备替换的行>>>>>>>>>>>>")
    -- for i in node.traverse(n) do
    --     print(i)
    -- end
    -- print(nodes.tosequence(n))
    -- print(nodes.tosequence(n.next.next.next.next.head))

    -- 寻找行，寻找rule
    for h,_ in node.traverseid(hlist_id, v_n) do
        for r, _ in node.traverseid(rule_id,h.head) do
            if node.hasattribute(r,3,333) then
                local hsize = jiazhu_hsize(h, r) -- 夹注标记rule到行尾的长度
                par_head_with_rule, vpar_head, jiazhu_boxes = make_jiazhu(par_head_with_rule, vpar_head, hsize, jiazhu_boxes)
                -- TODO 递归
                stop = true
            end
            if stop then break end
        end
        if stop then break end
    end
    return v_n
end

-- 分析分行结果
-- 分拆、组合夹注盒子

-- 把夹注盒子插会列表


-- 试排主段落：
local function main_trial_typeseting(head)

    -- print("============替换前的段落============")
    -- print(nodes.toutf(head))
    -- print(nodes.tosequence(head))
    -- for i in node.traverse(head) do
    --     print(i)
    -- end

    local par_head_with_rule, jiazhu_boxes = boxes_to_rules(head)
    -- print("============替换后的段落============")
    -- for i in node.traverse(par_head) do
    --     print(i)
    -- end
    -- print(nodes.toutf(par_head))
    -- print(nodes.tosequence(par_head))
    -- print("============收集到的夹注条目===============")
    -- for i, v in ipairs(jiazhu_boxes) do
    --     print(i, v) --hlist box
    --     print(nodes.toutf(v))
    -- end

    -- local hsize = tex.dimen.hsize --tex.sp("20em")
    local hsize = tex.dimen.textwidth --tex.sp("20em")
    local vpar_head, info= par_break(par_head_with_rule, hsize)
    -- print("============主段落重新分行===============")
    -- print(nodes.tosequence(new_head))
    -- print("1",nodes.tosequence(new_head.next.head))
    -- print(node.slide(new_head.next.head))
    -- print(node.slide(new_head.next.head).prev)
    -- print("2", nodes.tosequence(new_head.next.next.next.next.head))
    -- print(node.slide(new_head.next.next.next.next.head))
    -- print(node.slide(new_head.next.next.next.next.head).prev)
    -- print(node.slide(new_head.next.next.next.next.head).prev.prev)

    local head_with_jiazhu = insert_jiazhu(par_head_with_rule, vpar_head, jiazhu_boxes)

    return head_with_jiazhu
end

function Jiazhu.main(head)
    -- 仅处理段落
    local new_head
    if head.id == par_id then
        local copy_head = node.copylist(head)
        -- print("=====================")
        -- print("copy_head", copy_head) --par vmodepar
        -- print(nodes.toutf(copy_head))
        -- print(nodes.tosequence(copy_head))
        
        new_head = main_trial_typeseting(copy_head)
        -- node.write(new_head) --写到当前列表后，没有vbox壳，写入会导致混乱
        context(new_head) --cld，在原输入后输入

        -- head = new_head
        -- 把head后节点包装到vlist
        -- local v_node = node.vpack(new_head)
        -- print(">>>>>>>>>>>>>>>>>>>>>>")
        -- print("v_node", v_node) --vlist unknown
        -- print("v_node_head_sq", nodes.tosequence(v_node.head))
        -- node.write(v_node) --写到当前列表后
        -- context(v_node) --cld，在原输入后输入
    end
    return head, true
end

function Jiazhu.register()
    -- 只能使用CLD样式添加任务
    -- "processors", "before"，只加了par vmodepar和左右parfill skip
    -- "processors", "after"，还加入了字间的glue userskip、标点前后的penalty userpenalty，可用于断行
    nodes.tasks.appendaction("processors", "after", "Jiazhu.main")
end

return Jiazhu
