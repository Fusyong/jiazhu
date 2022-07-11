Moduledata = Moduledata or {}
Moduledata.jiazhu = Moduledata.jiazhu or {}

-- 本地化以提高运行效率

local glue_id = nodes.nodecodes.glue --node.id("glue")
local glyph_id = nodes.nodecodes.glyph
local hlist_id = nodes.nodecodes.hlist
local par_id = nodes.nodecodes.par
local penalty_id = nodes.nodecodes.penalty
local rule_id = nodes.nodecodes.rule
local vlist_id = nodes.nodecodes.vlist
local correctionskip_id = nodes.subtypes.glue.correctionskip
local kern_id = nodes.nodecodes.kern

local node_tail = node.tail
local node_copylist = node.copylist
local node_count = node.count
local node_dimensions = node.dimensions
local node_flushlist = node.flushlist
local node_free = node.free
local node_hasattribute = node.hasattribute
local node_hpack = node.hpack
local node_insertafter = node.insertafter
local node_insertbefore = node.insertbefore
local node_kerning = node.kerning
local node_ligaturing = node.ligaturing
local node_new = node.new
local node_remove = node.remove
local node_setattribute = node.setattribute
local node_slide = node.slide
local node_traverse = node.traverse
local node_traverseid = node.traverseid
local node_vpack = node.vpack

local tex_dimen_textwidth = tex.dimen.textwidth
local tex_linebreak = tex.linebreak
local tex_sp = tex.sp

---[[ 结点跟踪工具
local function show_detail(n, label) 
    print(">>>>>>>>>"..label.."<<<<<<<<<<")
    print(nodes.toutf(n))
    for i in node.traverse(n) do
        local char
        if i.id == glyph_id then
            char = utf8.char(i.char)
            print(i, char)
        elseif i.id == penalty_id then
            print(i, i.penalty)
        elseif i.id == glue_id then
            print(i, i.width, i.stretch,i.stretchorder, i.shrink, i.shrinkorder)
        elseif i.id == hlist_id then
            print(i, nodes.toutf(i.list))
        else
            print(i)
        end
    end
end
--]]

-- 用rule代替夹注盒子，并收集夹注盒子
local function boxes_to_rules(head)
    local n = head
    local jiazhu_boxes = {}
    local done = false
    local out_head = nil
    while n do
        if node_hasattribute(n, 2, 222) and n.id == hlist_id then
            local w = node_new(rule_id)
            w.width = tex_sp("1em")
            node_setattribute(w, 3, 333)
            head = node_insertbefore(head, n, w)
            local removed
            head, n, removed = node_remove(head, n)
            table.insert(jiazhu_boxes, removed)
            done = true
        end
        n = n.next
    end
    if done then
        out_head = head
    end
    node_flushlist(n)
    return out_head, jiazhu_boxes
end

-- 试排主段落 hsize：宽度；to_stretch：尾部拉伸（否则压缩）
local function par_break(par_head, hsize, to_stretch)

    local new_head = node_copylist(par_head)

    local is_vmode_par = (new_head.id == par_id)

    if not is_vmode_par then
        local vmodepar_node = node_new("par", "vmodepar")
        new_head, _ = node_insertbefore(new_head, new_head, vmodepar_node)
    end

    -- 删除最后的胶；添加无限罚分和parfillskip；保障pre指针正确
    local tail = node_slide(new_head) --node.tail()不检查前后指针
    if tail.id == glue_id then
        new_head, tail = node_remove(new_head, tail, true)
        node_free(tail)
    end

    -- 添加无限罚分
    local penalty = node_new("penalty")
    penalty.penalty = 10000
    new_head, tail = node_insertafter(new_head, tail, penalty)
    
    -- 添加hskip
    local hskip = node_new("glue")
    if to_stretch then
        hskip.width = 0
        hskip.stretch = hsize
    else
        hskip.width = hsize -- 能模仿系统断行
        hskip.shrink = hsize -- 能模仿系统断行
    end
    new_head, tail = node_insertafter(new_head, tail, hskip)

    -- 添加段末胶parfillskip（ TODO 似乎不起作用）
    local parfillskip = node_new("glue", "parfillskip") --一般是0pt plus 1fil
    parfillskip.stretch = 2^16 -- 可拉伸量2^16(65536)意义不明
    parfillskip.stretchorder = 2^16 --拉伸倍数2(fil)，意义不明
    new_head, tail = node_insertafter(new_head, tail, parfillskip)
  
    -- 保障prev指针正确
    node_slide(new_head)

    language.hyphenate(new_head) -- 断词，给单词加可能的连字符断点
    new_head = node_kerning(new_head) -- 加字间（出格）
    new_head = node_ligaturing(new_head) -- 西文合字
    
    -- 用hsize控制分行宽度：{hsize =  tex_sp("25em")}；
    -- 语言设置作用不详：{lang = tex.language}
    -- , lefskip = leftskip_spec 不起作用
    -- local leftskip_spec = node_new("gluespec")
    -- leftskip_spec.width = tex_sp("5em")
    -- leftskip_spec.stretch = tex_sp("5em")
    -- leftskip_spec.stretchorder = 2
    local para = {hsize=hsize}
    local info
    new_head, info = tex_linebreak(new_head, para)

    return new_head, info
end

-- 测量夹注宽度
local function jiazhu_hsize(hlist, current_n)
    -- 后面的实际宽度（包括突出）、高度、深度
    local d = node_dimensions(
        hlist.glueset,
        hlist.gluesign,
        hlist.glueorder,
        current_n
    )
    return d
end

-- 找到最后一个对视觉长度有影响的结点glyph_or_list_rule_kern
local function last_visible_node(head)
    local n = node_tail(head)
    while n do
        if n.id == glue_id
        or n.id == hlist_id
        or n.id == vlist_id
        or n.id == rule_id
        or n.id == kern_id
        then
            return n
        end
        n = n.prev
    end
end

-- 生成双行夹注
local function make_jiazhu_box(hsize, boxes)
    local b = boxes[1]
    -- local box_width = jiazhu_hsize(b, b.head)  -- 实际测量宽度，不适用width属性
    local box_width = b.width
    -- show_detail(b.head,"here")
    local b_list = b.list
    local to_remove -- 本条已经完成，需要移除
    local to_break_after = false -- 本条在行末，需要断行

    -- 夹注重排算法
    local width_tolerance = tex_sp("0.4em") -- 宽容宽度（挤进一行）
    local max_hsize = hsize + width_tolerance
    local min_hsize = hsize - width_tolerance
    local step = width_tolerance / 4 --步进控制 TODO 优化
    local vbox_width = box_width / 2
    local box_head, info
    -- 可一次（两行）安排完的短盒子
    if vbox_width <= max_hsize then
        local line_num = 3
        vbox_width = vbox_width - 2 * step --步进控制 TODO 优化
        while(line_num >= 3) do
            box_head, info = par_break(b_list, vbox_width, true)
            line_num = info.prevgraf
            vbox_width = vbox_width + step -- TODO 改进步进量或段末胶
        end
        -- 其后强制断行
        local actual_vbox_width = vbox_width - step
        if actual_vbox_width >= min_hsize and actual_vbox_width <= max_hsize then
            to_break_after = true
        end
        -- 清除rule标记
        to_remove = true
        node_flushlist(boxes[1].head)
        table.remove(boxes, 1)
    else -- 需要循环安排的长盒子
        box_head, info = par_break(b_list, hsize, false)

        -- 只取前两行所包含的节点
        local line_num = 0
        local glyph_num = 0
        for i in node_traverseid(hlist_id, box_head) do
            line_num = line_num + 1
            -- 计算字模、列表数量 TODO 计数优化，还应该增加类型，如rule等
            glyph_num = glyph_num + node_count(glyph_id, i.head)
            glyph_num = glyph_num + node_count(hlist_id, i.head)
            if line_num == 2 then
                box_head = node_copylist(box_head, i.next)
                break --计数法
            end
        end

        -- 截取未用的盒子列表  TODO 相应优化
        for i in node_traverse(b_list) do
            if i.id == glyph_id or i.id == hlist_id then
                glyph_num = glyph_num - 1
                if glyph_num == -1 then
                    local hlist = node_hpack(node_copylist(i))
                    node_flushlist(boxes[1].head)
                    boxes[1] = hlist
                end
            end
        end

        to_break_after = true
        to_remove = false
    end

    -- 打包，修改包的高度和行距
    local most_w = 0  -- 最大行宽
    for l in node_traverseid(hlist_id, box_head) do
        -- 清楚禁则导致的负值的correctionskip，确保得到视觉宽度，可探测overfull
        for g in node_traverseid(glue_id, l.head) do
            if g.subtype == correctionskip_id then
                l.head,g = node_remove(l.head, g)
            end
        end

        local last_v_n = last_visible_node(l.head)
        local actual_vbox_width = node.dimensions(
            l.glue_set,
            l.glue_sign,
            l.glue_order,
            l.head,
            last_v_n.next
        )

        l.width = nil  --清楚行宽再打包，不会有双重框
        -- l = node_hpack(l.head) -- 生成新的行宽，或node.dimensions计算
        -- if w < l.width then w = l.width end
        if most_w < actual_vbox_width then most_w = actual_vbox_width end
    end
    box_head = node_vpack(box_head)
    box_head.width = most_w

    local skip = tex_sp("0.08em") -- 夹注行间距
    local sub_glue_h = 0 -- 计算删除的胶高度
    local n = box_head.head
    local count = 0
    while n do
        if n.id == glue_id then
            count = count + 1
            if count == 1 then
                sub_glue_h = sub_glue_h + n.width
                -- 删除第一个胶
                box_head.head, n = node_remove(box_head.head, n, true)
            else
                -- 更改中间的胶
                sub_glue_h = sub_glue_h + (n.width - skip)
                n.width = skip
                n = n.next
            end
        else
            n = n.next
        end
    end

    local box_head_height = box_head.height - sub_glue_h
    local baseline_to_center =  tex_sp("0.4em") -- TODO 应根据字体数据计算
    box_head.height = baseline_to_center + box_head_height/ 2
    box_head.depth = box_head_height - box_head.height

    return box_head, boxes, to_remove, to_break_after
end

-- 根据第一个rule的位置分拆、组合、插入夹注盒子、罚点等
local function insert_jiazhu(head_with_rules, vpar_head, jiazhu_boxes)
    -- local stop = false
    -- 寻找行，寻找rule
    for h,_ in node_traverseid(hlist_id, vpar_head) do
        for r, _ in node_traverseid(rule_id,h.head) do
            if node_hasattribute(r,3,333) then
                local hsize = jiazhu_hsize(h, r) -- 夹注标记rule到行尾的长度
                local to_remove, jiazhu_box, to_break_after
                jiazhu_box, jiazhu_boxes, to_remove, to_break_after = make_jiazhu_box(hsize, jiazhu_boxes)
                for rule, _ in node_traverseid(rule_id, head_with_rules) do
                    if node_hasattribute(rule,3,333) then
                        -- 插入夹注
                        head_with_rules, jiazhu_box = node_insertbefore(head_with_rules, rule, jiazhu_box)
                        -- 插入罚点（必须断行）
                        local penalty = node_new("penalty")
                        if to_break_after then
                            penalty.penalty = -10000
                        else
                            penalty.penalty = 0
                        end
                        head_with_rules, penalty = node_insertafter(head_with_rules, jiazhu_box, penalty)
                        -- 移除标记rule
                        if to_remove then
                            head_with_rules, rule = node_remove(head_with_rules,rule,true)
                        else
                            -- 或，加胶
                            local glue = node_new("glue")
                            glue.width = 0
                            glue.stretch = tex_sp("0.5em")
                            head_with_rules, glue = node_insertafter(head_with_rules, penalty, glue)
                        end
                        node_flushlist(vpar_head)
                        return head_with_rules, jiazhu_boxes
                    end
                end
                print("jiazhu>> 没有找到插入标记。")
            end
        end
    end
end

-- TODO 递归
local function find_fist_rule(par_head_with_rule, boxes)
    local n = par_head_with_rule
    while n do
        if n.id == rule_id and  node_hasattribute(n,3,333) then
            local hsize = tex_dimen_textwidth -- tex.dimen.hsize

            -- TODO par_break改变了head_with_rules
            local vpar_head, _= par_break(par_head_with_rule, hsize, false)

            -- context(node_copylist(vpar_head))
            par_head_with_rule, boxes = insert_jiazhu(par_head_with_rule, vpar_head, boxes)

            return find_fist_rule(par_head_with_rule, boxes)
        end
        
        n = n.next
    end
    node_flushlist(n)
    return par_head_with_rule
end

function Moduledata.jiazhu.main(head)
    local out_head = head
    -- 仅处理段落
    -- if head.id == par_id then
        local par_head_with_rule, jiazhu_boxes = boxes_to_rules(head)
        if par_head_with_rule then
            out_head = find_fist_rule(par_head_with_rule, jiazhu_boxes)
        end
    -- end
    return out_head, true
end

function Moduledata.jiazhu.register()
    -- 只能使用CLD样式添加任务
    -- "processors", "before"，只加了par vmodepar和左右parfill skip
    -- "processors", "after"，还加入了字间的glue userskip、标点前后的penalty userpenalty，可用于断行
    nodes.tasks.appendaction("processors", "after", "Moduledata.jiazhu.main")
end

return Moduledata.jiazhu
