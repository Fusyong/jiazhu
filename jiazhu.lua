Moduledata = Moduledata or {}
Moduledata.jiazhu = Moduledata.jiazhu or {}
Jiazhu = Moduledata.jiazhu

local glyph_id = nodes.nodecodes.glyph --node.id("glyph")
local hlist_id = nodes.nodecodes.hlist
local vlist_id = nodes.nodecodes.vlist
local glue_id = nodes.nodecodes.glue
local rule_id = nodes.nodecodes.rule
local par_id = nodes.nodecodes.par
local penalty_id = nodes.nodecodes.penalty
local whatsit_id = nodes.nodecodes.whatsit

local function show_detail(n, label) 
    print(">>>>>>>>>"..label.."<<<<<<<<<<")
    for i in node.traverse(n) do
        local char
        if i.id == glyph_id then
            char = utf8.char(i.char)
            print(i, char)
        elseif i.id == penalty_id then
            print(i, i.penalty)
        elseif i.id == glue_id then
            print(i, i.width, i.stretch, i.shrink)
        elseif i.id == hlist_id then
            print(i, nodes.toutf(i))
        else
            print(i)
        end
    end
end

-- 用rule代替夹注盒子，并收集夹注盒子
local function boxes_to_rules(head)
    local n = head
    local jiazhu_boxes = {}
    while n do
        if node.hasattribute(n, 2, 222) and n.id == hlist_id then
            local w = node.new(rule_id)
            w.width = tex.sp("1em")
            node.setattribute(w, 3, 333)
            head = node.insertbefore(head, n, w)
            local removed = nil
            head, n, removed = node.remove(head, n)
            table.insert(jiazhu_boxes, removed)
        end
        n = n.next
    end

    return head, jiazhu_boxes
end

-- 试排主段落 hsize：宽度；to_stretch：尾部拉伸（否则压缩）
local function par_break(par_head, hsize, to_stretch)

    local new_head = par_head
    local is_vmode_par = (new_head.id == par_id)

    if not is_vmode_par then
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
local function make_jiazhu_box(hsize, boxes)
    local b = boxes[1]
    local box_width =b.width -- 对应的夹注盒子宽度
    local b_list = b.list
    local to_remove -- 本条已经完成，需要移除

    -- 夹注重排算法
    local width_tolerance = tex.sp("0.5em") -- 宽容宽度（挤进一行）；兼步进控制
    local vbox_width = box_width / 2
    local box_head, info
    -- 可一次（两行）安排完的短盒子
    if vbox_width <= (hsize + width_tolerance) then
        local line_num = 3
        while(line_num >= 3) do
            box_head, info = par_break(node.copylist(b_list), vbox_width, true)
            line_num = info.prevgraf
            vbox_width = vbox_width + width_tolerance / 2 -- TODO 改进步进量或段末胶
        end
        -- TODO 盒子打包
        box_head = node.vpack(box_head)
        to_remove = true
        table.remove(boxes, 1)
    else -- 需要循环安排的长盒子
        box_head, info = par_break(node.copylist(b_list), hsize, false)
        -- TODO 盒子打包，剪裁box
        to_remove = false
    end

    return box_head, boxes, to_remove
end

-- 根据第一个rule的位置分拆、组合、插入夹注盒子、罚点等
local function insert_jiazhu(head_with_rules, vpar_head, jiazhu_boxes)
    local stop = false
    -- 寻找行，寻找rule
    local jiazhu_box
    for h,_ in node.traverseid(hlist_id, vpar_head) do
        for r, _ in node.traverseid(rule_id,h.head) do
            if node.hasattribute(r,3,333) then
                local hsize = jiazhu_hsize(h, r) -- 夹注标记rule到行尾的长度
                local to_remove
                jiazhu_box, jiazhu_boxes, to_remove = make_jiazhu_box(hsize, jiazhu_boxes)
                -- TODO 插入
                head_with_rules, jiazhu_box = node.insertbefore(head_with_rules, r, jiazhu_box)
                local penalty = node.new("penalty")
                penalty.penalty = -100000
                head_with_rules, penalty = node.insertafter(head_with_rules, jiazhu_box, penalty)

                if to_remove then
                    head_with_rules, _ = node.remove(head_with_rules,r,true)
                end
                stop = true
            end
            if stop then break end
        end
        if stop then break end
    end
    return head_with_rules, jiazhu_boxes
end

-- 分析分行结果
-- 分拆、组合夹注盒子

-- 把夹注盒子插会列表


-- 试排主段落：
local function main_trial_typeseting(head)

    local par_head_with_rule, jiazhu_boxes = boxes_to_rules(head)

    -- TODO 递归
    local vpar_head
    local function find_fist_rule(head_with_rules, boxes)
        for r in node.traverseid(rule_id, head_with_rules) do
            if node.hasattribute(r,3,333) then
                local hsize = tex.dimen.textwidth -- tex.dimen.hsize
                vpar_head, _= par_break(head_with_rules, hsize)
                head_with_rules, boxes = insert_jiazhu(head_with_rules, vpar_head, boxes)
                head_with_rules = find_fist_rule(head_with_rules, boxes)
            end
        end
        return head_with_rules
    end
    par_head_with_rule = find_fist_rule(par_head_with_rule, jiazhu_boxes)

    return par_head_with_rule
end

function Jiazhu.main(head)
    -- 仅处理段落
    if head.id == par_id then
        local copy_head = node.copylist(head)
        local par_head_with_rule = main_trial_typeseting(copy_head)
        return par_head_with_rule, true
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
