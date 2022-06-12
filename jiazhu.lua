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
local function split_jiazhu(head)
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

-- 试排主段落
local function par_break(par_head)

    -- print("==========分行前==========")
    -- print(nodes.tosequence(par_head))

    -- 删除最后的胶；添加无限罚分和parfillskip；保障pre指针正确
    local tail = node.slide(par_head) --node.tail()不检查前后指针
    if tail.id == glue_id then
        par_head, tail = node.remove(par_head, tail, true)
    end

    -- 添加无限罚分
    local penalty = node.new("penalty")
    penalty.penalty = 10000
    -- tail.next = penalty
    par_head, _ = node.insertafter(par_head, tail, penalty)
    
    -- 添加段末胶parfillskip
    local parfillskip = node.new("glue", "parfillskip")
    -- parfillskip.spec = node.new("gluespec")
    parfillskip.stretch = 2^16 -- 拉伸量2^16、0.8 * tex.hsize
    parfillskip.stretchorder = 2 --拉伸倍数 2、0
    -- print("----------------段落填充-----------")
    -- print(parfillskip)
    -- print(parfillskip.stretch)
    -- print(parfillskip.stretchorder)
    par_head, _ = node.insertafter(par_head, tail, parfillskip)
  
    -- 保障prev指针正确
    node.slide(par_head)

    print("=========预备分行用的段落===========")
    for i in node.traverse(par_head) do
        print(i)
    end
    print(nodes.tosequence(par_head))
    print("tail",node.tail(par_head))

    language.hyphenate(par_head) -- 断词，给单词加可能的连字符断点
    par_head = node.kerning(par_head) -- 加字间（出格）
    par_head = node.ligaturing(par_head) -- 西文合字
    
    -- 用hsize控制分行宽度：{hsize =  tex.sp("25em")}；
    -- 语言设置作用不详：{lang = tex.language}
    local para = {hsize=tex.sp("20em"),tracingparagraphs=1}
    local new_head, info = tex.linebreak(par_head, para)
    
    -- print(">>>>>>>>>>>>>>>>>>>>>>")
    -- print("new_head", new_head) --分行后的列表head：glue baselineskip
    -- print("new_head_sq", nodes.tosequence(new_head))
    -- print("info", info) --如{prevgraf=4, looseness=0, prevdepth=18078, demerits=0}
    if info then
        for i, v in pairs(info) do
            print(i,v)
        end
    end

    return new_head
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

-- 根据第一个rule的位置分拆、组合、插入夹注盒子、罚点等
local function insert_jiazhu(par_head, jiazhu_boxes)
    local n = par_head
    local stop = false
    print("<<<<<<<<<<<<准备替换的行>>>>>>>>>>>>")
    for i in node.traverse(n) do
        print(i)
    end
    -- print(nodes.tosequence(n))
    -- print(nodes.tosequence(n.next.next.next.next.head))
    for h,_ in node.traverseid(hlist_id, n) do
        -- for w,_ in node.traverseid(whatsit_id,h.head) do
        for w,_ in node.traverseid(rule_id,h.head) do
            if node.hasattribute(w,3,333) then
                print(nodes.tosequence(h.head))
                print(nodes.tosequence(h.head))
                print(w)
                local hsize = jiazhu_hsize(h, w)
                print("jiazhu_hsize", hsize)
                -- print("box_width", jiazhu_boxes[1].width)
                print("9em", tex.sp("9em"))
                stop = true
            end
            if stop then break end
        end
        if stop then break end
    end
    local head_with_jiazhu = n
    return head_with_jiazhu
end

-- 分析分行结果
-- 分拆、组合夹注盒子

-- 把夹注盒子插会列表


-- 试排主段落：
local function main_trial_typeseting(head)

    print("============替换前的段落============")
    print(nodes.toutf(head))
    print(nodes.tosequence(head))
    for i in node.traverse(head) do
        print(i)
    end

    local par_head, jiazhu_boxes = split_jiazhu(head)
    print("============替换后的段落============")
    for i in node.traverse(par_head) do
        print(i)
    end
    print(nodes.toutf(par_head))
    print(nodes.tosequence(par_head))
    -- print("============收集到的夹注条目===============")
    -- for i, v in ipairs(jiazhu_boxes) do
    --     print(i, v) --hlist box
    --     print(nodes.toutf(v))
    -- end
    
    local new_head= par_break(par_head)
    -- print("============主段落重新分行===============")
    -- print(nodes.tosequence(new_head))
    -- print("1",nodes.tosequence(new_head.next.head))
    -- print(node.slide(new_head.next.head))
    -- print(node.slide(new_head.next.head).prev)
    -- print("2", nodes.tosequence(new_head.next.next.next.next.head))
    -- print(node.slide(new_head.next.next.next.next.head))
    -- print(node.slide(new_head.next.next.next.next.head).prev)
    -- print(node.slide(new_head.next.next.next.next.head).prev.prev)

    local head_with_jiazhu = insert_jiazhu(new_head, jiazhu_boxes)

    return head_with_jiazhu
end

function Jiazhu.jiazhu(head)
    -- 仅处理段落
    if head.id == par_id then
        local copy_head = node.copylist(head)
        -- print("=====================")
        -- print("copy_head", copy_head) --par vmodepar
        -- print(nodes.toutf(copy_head))
        -- print(nodes.tosequence(copy_head))
        
        local new_head = main_trial_typeseting(copy_head)
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

function Jiazhu.opt()
    -- 只能使用CLD样式添加任务
    -- "processors", "before"，只加了par vmodepar和左右parfill skip
    -- "processors", "after"，还加入了字间的glue userskip、标点前后的penalty userpenalty，可用于断行
    nodes.tasks.appendaction("processors", "after", "Jiazhu.jiazhu")
end

return Jiazhu
