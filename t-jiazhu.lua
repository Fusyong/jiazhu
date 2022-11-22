Moduledata = Moduledata or {}
Moduledata.jiazhu = Moduledata.jiazhu or {}

-- 行宽可扩展的量
Moduledata.jiazhu.width_tolerance = "0.25em"
-- 夹注替身宽度 TODO 0.75em 太窄可能导致前面的正文太稀疏；太宽可能导致短注估算错误
Moduledata.jiazhu.anchor_rule_width = "0.75em"
-- 夹注汉字基线到中线的距离  TODO 实测
Moduledata.jiazhu.baseline_to_center = "0.34em" -- 0.4

-- 本地化以提高运行效率

local glue_id = nodes.nodecodes.glue --node.id("glue")
local glyph_id = nodes.nodecodes.glyph
local hlist_id = nodes.nodecodes.hlist
local par_id = nodes.nodecodes.par
local rule_id = nodes.nodecodes.rule
local vlist_id = nodes.nodecodes.vlist
local correctionskip_id = nodes.subtypes.glue.correctionskip
local righthangskip_id = nodes.subtypes.glue.righthangskip -- node.subtype("righthangskip")
local spaceskip_id = nodes.subtypes.glue.spaceskip
local indentskip_id = nodes.subtypes.glue.indentskip
local kern_id = nodes.nodecodes.kern

local node_tail = node.tail
local node_copylist = node.copylist
local node_count = node.count
local node_dimensions = node.dimensions
local node_flushlist = node.flushlist
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

--[[ 结点跟踪工具
local function show_detail(n, label)
    local l = label or "======="
    print(">>>>>>>>>"..l.."<<<<<<<<<<")
    print(nodes.toutf(n))
    for i in node.traverse(n) do
        local char
        if i.id == glyph_id then
            char = utf8.char(i.char)
            print(i, char)
        elseif i.id == nodes.nodecodes.penalty then
            print(i, i.penalty)
        elseif i.id == nodes.nodecodes.glue then
            print(i, i.width, i.stretch, i.shrink, i.stretchorder, i.shrinkorder)
        elseif i.id == nodes.nodecodes.hlist then
            print(i, nodes.toutf(i.list),i.width,i.height,i.depth,i.shift,i.glue_set,i.glue_sign,i.glue_order)
        elseif i.id == nodes.nodecodes.kern then
            print(i, i.kern, i.expension)
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
            w.width = tex_sp(Moduledata.jiazhu.anchor_rule_width)
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

-- 试排段落 para.hsize：宽度；para.parshape：段落形状；to_stretch：末行尾部胶拉伸（否则压缩）
local function par_break(par_head, para, to_stretch)

    -- 是否有段落形状数据
    local last_group_width
    if para.parshape then
        last_group_width = para.parshape[#para.parshape][2]
    else
        last_group_width = para.hsize
    end

    local new_head = node_copylist(par_head)

    local is_vmode_par = (new_head.id == par_id)

    local current_node
    if not is_vmode_par then
        current_node = node_new("par", "vmodepar")
        new_head, current_node = node_insertbefore(new_head, new_head, current_node)
    else
        current_node = new_head
    end


    current_node = current_node.next
    if current_node.subtype ~= indentskip_id then
        local indentskip= node_new("glue", "indentskip")
        new_head, current_node = node_insertbefore(new_head, current_node, indentskip)
    end

    -- 保障prev指针正确
    node_slide(new_head)
    
    language.hyphenate(new_head) -- 断词，给单词加可能的连字符断点
    new_head = node_kerning(new_head) -- 加字间（出格）
    new_head = node_ligaturing(new_head) -- 西文合字
    
    local t, n_parinitleftskip, n_parinitrightskip, n_parfillleftskip, n_parfillrightskip
    new_head, t, n_parinitleftskip, n_parinitrightskip, n_parfillleftskip, n_parfillrightskip = tex.preparelinebreak(new_head)
    
    if to_stretch then
        -- 默认即是一级无限拉伸胶
        -- n_parfillrightskip.width = 0
        -- n_parfillrightskip.stretch = last_group_width
    else
        n_parfillrightskip.width = last_group_width -- 能模仿系统断行
        n_parfillrightskip.shrink = last_group_width -- 能模仿系统断行
    end
    
    -- tracingparagraphs=1 输出跟踪信息
    -- emergencystretch=last_group_width*0.1
    local info
    new_head, info = tex_linebreak(new_head, para)
    -- show_detail(new_head, "new_head")
    -- print("info[d, g, l, demerites]",
    -- info.prevdepth,
    -- info.prevgraf,
    -- info.looseness,
    -- info.demerits
    -- )

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

-- 是可视结点
local function is_visible_node(n)
    local ids = {
        [hlist_id] = true,
        [vlist_id] = true,
        [rule_id ] = true,
        [glyph_id] = true,
    }
    if ids[n.id] then --  and n.width > 0且有实际宽度（必要吗？？？）
        return true
    else
        return false
    end
end

-- 找到最后一个对视觉长度有影响的结点glyph_or_list_rule_kern
local function last_visible_node(head)
    local n = node_tail(head)
    while n do
        if
        n.id == glue_id or
        n.id == hlist_id or
        n.id == vlist_id or
        n.id == rule_id or
        n.id == kern_id
        then
            return n
        end
        n = n.prev
    end
end

-- 清理系统注入的、有干扰的胶水
local function clear_glues(l,to_remove_glues)
    local n = l.head
    local width_dropdown = 0 -- 删除的元素宽度

    -- 处理头部的不可见结点
    while n and not is_visible_node(n) do
        if n.id == glue_id and to_remove_glues[n.subtype] then
            width_dropdown = width_dropdown + n.width
            l.head,n = node_remove(l.head, n, true)
        else
            n = n.next
        end
    end

    -- 处理尾部的不可见结点
    n = node_tail(n)
    while n and not is_visible_node(n) do
        if n.id == glue_id and to_remove_glues[n.subtype] then
            width_dropdown = width_dropdown + n.width
            l.head,n = node_remove(l.head, n, true)
        else
            n = n.prev
        end
    end


    -- inspect(l)
    -- show_detail(l.head, "夹注行详情，后")

    -- TODO 测量宽度/标记宽度与实际视觉宽度不一致
    -- 测量宽度与生成新的行宽node_hpack(l.head)一致，与旧行剩余宽度不同
    -- local last_v_n = last_visible_node(l.head)
    -- local actual_vbox_width = node.dimensions(
    --     l.glue_set,
    --     l.glue_sign,
    --     l.glue_order,
    --     l.head
    --     -- ,last_v_n.next
    -- )
    -- print(l.head,actual_vbox_width)
    -- 宽度取最大值：实际视觉宽度，盒子宽度
    -- if most_w < actual_vbox_width then most_w = actual_vbox_width end

    l.width = l.width - width_dropdown

    return l
end

-- 打包，修改包的高度和行距
local function clear_and_pack(box_head)
    local most_w = 0  -- 最大行宽
    local n = box_head
    while n do
        if n.id == hlist_id then
            -- 清除：
            -- 错误禁则导致的负值的correctionskip，确保得到视觉宽度，可探测overfull
            local to_remove_glues = {
                [correctionskip_id]=true,
                [righthangskip_id]=true,
                -- [spaceskip_id]=true,
                -- [indentskip_id]=true,
                -- [lefthangskip_id]=true,
                -- [leftskip_id]=true,
                -- [rightskip_id]=true,
                -- [parinitleftskip_id]=true,
                -- [parinitrightskip_id]=true,
                -- [parfillleftskip_id]=true,
                -- [parfillrightskip_id]=true,
            }
            n = clear_glues(n,to_remove_glues)
            
            -- 凸排
            n.head = Moduledata.zhpunc.protrude(n.head)
            local new_n = node_hpack( n.head, n.width, "exactly")
            box_head, new_n = node_insertbefore(box_head, n, new_n)
            box_head, n = node_remove(box_head, n) -- 不能刷洗内存
        
            if most_w < new_n.width then most_w = new_n.width end
        else
            n = n.next
        end
    end

    -- 统一为最大宽度
    for l in node_traverseid(hlist_id, box_head) do
        l.width = most_w
    end
    box_head = node_vpack(box_head)

    return box_head
end

-- 生成双行夹注
local function make_jiazhu_box(hsize, boxes)
    local b = boxes[1]

    local to_remove_glues = {
        [spaceskip_id]=true,
    }
    b = clear_glues(b,to_remove_glues)

    -- local box_width = jiazhu_hsize(b, b.head)  -- 实际测量宽度，不适用width属性
    local box_width = b.width
    -- show_detail(b.head,"here")
    local b_list = b.list
    local to_remove -- 本条已经完成，需要移除
    local to_break_after = false -- 本条在行末，需要断行

    -- 夹注重排算法
    local width_tolerance = tex_sp(Moduledata.jiazhu.width_tolerance) -- 宽容宽度（挤进一行）
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
            local para = {hsize=vbox_width}
            box_head, info = par_break(b_list, para, true)
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
        local parshape = {
            {0, hsize},{0, hsize},
            {0, tex.hsize}
        }
        -- local para = {hsize=hsize} -- 同行宽试排，对小宽度不利
        local para = {parshape=parshape} -- 据段落形状试排
        box_head, info = par_break(b_list, para, true)-- 末行压缩导致很多流溢

        -- 只取前两行所包含的节点
        local line_num = 0
        local glyph_num = 0
        for i in node_traverseid(hlist_id, box_head) do
            line_num = line_num + 1
            -- 计算字模、列表数量 TODO 计数优化，还应该增加类型
            glyph_num = glyph_num + node_count(glyph_id, i.head)
            glyph_num = glyph_num + node_count(hlist_id, i.head)
            glyph_num = glyph_num + node_count(rule_id, i.head)
            if line_num == 2 then
                box_head = node_copylist(box_head, i.next)
                break --计数法
            end
        end

        -- 截取未用的盒子列表，更新  TODO 相应优化
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

    -- 清理、包装
    box_head = clear_and_pack(box_head)

    local skip = tex_sp(Moduledata.jiazhu.interlinespace) -- 夹注行间距
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
    local baseline_to_center =  tex_sp(Moduledata.jiazhu.baseline_to_center)
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
            local para = {hsize=hsize}
            local vpar_head, _= par_break(par_head_with_rule, para, false)

            -- context(node_copylist(vpar_head))
            par_head_with_rule, boxes = insert_jiazhu(par_head_with_rule, vpar_head, boxes)

            return find_fist_rule(par_head_with_rule, boxes)
        end
        
        n = n.next
    end
    node_flushlist(n)
    return par_head_with_rule
end

-- 设置
function Moduledata.jiazhu.set(interlinespace)
    Moduledata.jiazhu.interlinespace = interlinespace
end

function Moduledata.jiazhu.main(head)
    local out_head = head
    local par_head_with_rule, jiazhu_boxes = boxes_to_rules(head)
    if par_head_with_rule then
        out_head = find_fist_rule(par_head_with_rule, jiazhu_boxes)
    end
    return out_head, true
end

function Moduledata.jiazhu.append()
    -- 确保在处理标点之后
    nodes.tasks.appendaction("processors", "after", "Moduledata.jiazhu.main")
end

return Moduledata.jiazhu
