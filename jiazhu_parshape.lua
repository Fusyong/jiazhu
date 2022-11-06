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
local righthangskip_id = nodes.subtypes.glue.righthangskip -- node.subtype("righthangskip")
local lefthangskip_id = nodes.subtypes.glue.lefthangskip
local leftskip_id = nodes.subtypes.glue.leftskip
local rightskip_id = nodes.subtypes.glue.rightskip
local leftfill_id = nodes.subtypes.glue.leftfill
local rightfill_id = nodes.subtypes.glue.rightfill
local correctionskip_id = nodes.subtypes.glue.correctionskip
local parinitleftskip_id = nodes.subtypes.glue.parinitleftskip
local parinitrightskip_id = nodes.subtypes.glue.parinitrightskip
local parfillleftskip_id = nodes.subtypes.glue.parfillleftskip
local parfillrightskip_id = nodes.subtypes.glue.parfillrightskip
local indentskip_id = nodes.subtypes.glue.indentskip
local kern_id = nodes.nodecodes.kern

local node_tail = node.tail
local node_copylist = node.copylist
local node_count = node.count
local node_dimensions = node.dimensions
local node_flushlist = node.flushlist
local node_free = node.free
local node_hasattribute = node.hasattribute
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
local node_hpack = node.hpack

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
            -- 预设最短夹注，太小会导致循环流溢错误（尤其是受禁则影响时）！！！！ TODO 监控错误
            -- 1:3: [package: overfull \hbox (5012.06207pt too wide) in paragraph at lines 225--230]
            w.width = tex_sp("2em")
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
        new_head, current_node = node_insertafter(new_head, current_node, indentskip)
    end

    -- -- 添加hskip(表示parfillskip)
    -- local hskip = node_new("glue")
    -- if to_stretch then
    --     hskip.width = 0
    --     hskip.stretch = last_group_width
    -- else
    --     hskip.width = last_group_width -- 能模仿系统断行
    --     hskip.shrink = last_group_width -- 能模仿系统断行
    -- end
    -- new_head, tail = node_insertafter(new_head, tail, hskip)

    -- 保障prev指针正确
    node_slide(new_head)

    language.hyphenate(new_head) -- 断词，给单词加可能的连字符断点
    new_head = node_kerning(new_head) -- 加字间（出格）
    new_head = node_ligaturing(new_head) -- 西文合字
    -- show_detail(new_head, "par_before")
    local h, t, n_parinitleftskip, n_parinitrightskip, n_parfillleftskip, n_parfillrightskip = tex.preparelinebreak(new_head)
    n_parfillrightskip.stretchorder = 0
    n_parfillrightskip.stretch = 0
    -- show_detail(new_head, "par_after")
    local info
    new_head, info = tex_linebreak(new_head, para) -- 引擎会自动多次测试，直到demerits符合要求
    -- tex.show(new_head)

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
-- TODO 使用parshap

local function make_jiazhu_box(tail_hsize, boxes)

    local b = boxes[1]
    local box_width = jiazhu_hsize(b, b.head)  -- 实际测量宽度，不适用width属性
    local b_list = b.list

    -- 夹注重排算法
    -- local breaking_extend_factor = 1.01 -- 估算断行导致的长度扩展，超过1.05会造成循环。没有实际效果
    local length_sum = box_width / 2 -- * breaking_extend_factor  -- 估算的总长度
    local tex_hsize = tex.hsize -- TODO 这里是值引用吗？？？
    
    -- 生成段落形状表
    local step = tex_sp("0.25em") --步进控制，对速度有影响 TODO 优化
    local start_w = tex_sp("1.5em") -- 新行起始长度，控制过短的情况，否则可能导致错误或堆叠，对速度有影响 TODO 无效
    local parshape
    local left_except_first = length_sum - tail_hsize -- 除首组外的长度
    if left_except_first >0 then --预计安排组：1+lines_group+1
        local lines_group, f= math.modf(left_except_first / tex_hsize) -- 整行组数，尾组比率
        -- 头两行
        parshape = {
            {0,tail_hsize},{0,tail_hsize},
        }
        -- 肚子行
        for i=1, lines_group, 1 do
            table.insert( parshape, {0, tex_hsize})
            table.insert( parshape, {0, tex_hsize})
        end
        -- 尾行（只用一个数据控制）
        local last_hsize = f * tex_hsize
        if last_hsize < start_w then
            last_hsize = start_w
        end
        table.insert( parshape, {0, last_hsize})
        -- table.insert( parshape, {0, last_hsize})
    else -- 预计一组安排
        local first_hsize = length_sum
        -- 只用一个数据控制
        parshape = {
            {0,first_hsize}
        }
    end
    
    local box_head, info
    local line_num
    while true do
        -- emergencystretch=tex_sp("0.1em") -- 导致过稀疏
        -- looseness=1 -- 可能导致缺点过大而不断循环测试
        box_head, info = par_break(b_list, {parshape=parshape}, true)
        line_num = info.prevgraf
        local tail_and_on_num = line_num - (#parshape - 1) --预设最后一组之下的行数
        if tail_and_on_num == 2 then
            break -- 成功；目前假设不存在末行不满这种可能
        elseif tail_and_on_num > 2 then  -- 溢出，则拉伸最后一行
            local new_hsize = parshape[#parshape][2] + step
            if #parshape > 2 then -- 两组以上
                if parshape[#parshape][2] >= tex_hsize then --本已到头，则增加行数据
                    parshape[#parshape][2] = tex_hsize
                    table.insert(parshape, {0, tex_hsize})
                    table.insert(parshape, {0, start_w})
                elseif new_hsize >= tex_hsize then --本次到头
                    parshape[#parshape][2] = tex_hsize
                else -- 本次仍未到头
                    parshape[#parshape][2] = new_hsize
                end
            else --仅仅一组本行安排
                if parshape[#parshape][2] >= tail_hsize then --本已到头，则增加行数据
                    parshape[#parshape][2] = tail_hsize
                    table.insert(parshape, {0, tail_hsize})
                    table.insert(parshape, {0, start_w})
                elseif new_hsize >= tail_hsize then
                    parshape[#parshape][2] = tail_hsize
                else
                    parshape[#parshape][2] = new_hsize
                end
            end
        else -- 少于预估（以及第一个条中末行不满），目前假设不存在这种可能
            -- 因禁则的原因，可能会导致始终无法挤成两行 TODO
            parshape[#parshape][2] = parshape[#parshape][2] - step
        end
    end


    -- 打包，修改包的高度和行距
    local function pack_group(head)
        local most_w = 0 -- 最大行宽
        for l in node_traverseid(hlist_id, head) do
            -- show_detail(l.head, "夹注行详情，前")
            local n = l.head
            while n do
                if n.id == glue_id then
                    -- 没有影响
                    -- if n.subtype == parfillleftskip_id  then
                    --     l.head,n = node_remove(l.head,n.prev,true)
                    --     l.head,n = node_remove(l.head,n,true)
                    -- else
                    if n.subtype == righthangskip_id-- 删除每行的righthangskip
                        -- 清楚禁则导致的负值的correctionskip，确保得到视觉宽度，可探测overfull
                        or n.subtype == correctionskip_id
                        -- 没有影响
                        -- or n.subtype == lefthangskip_id
                        -- or n.subtype == leftskip_id
                        -- or n.subtype == rightskip_id
                        -- or n.subtype == righthangskip_id
                        then
                        l.head,n = node_remove(l.head,n,true)
                    else
                        n = n.next
                    end
                -- 没有影响
                -- elseif n.id == par_id then
                --     l.head,n = node_remove(l.head,n,true)
                else
                    n = n.next
                end
            end
            -- show_detail(l.head, "夹注行详情，后")

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
        
        head = node_vpack(head)
        head.width = most_w

        local skip = tex_sp("0.08em") -- 夹注行间距
        local sub_glue_h = 0 -- 计算删除的胶高度
        local n = head.head
        while n do
            if n.id == glue_id then
                sub_glue_h = sub_glue_h + (n.width - skip)
                n.width = skip
            end
            n = n.next
        end
        
        local box_head_height = head.height - sub_glue_h
        local baseline_to_center =  tex_sp("0.4em") -- TODO 应根据字体数据计算
        head.height = baseline_to_center + box_head_height/ 2
        head.depth = box_head_height - head.height
        return head
    end

    -- 只取前两行所包含的节点
    local jiazhu_groups = {}
    local l_num = 0
    local first
    local second
    for i in node_traverseid(hlist_id, box_head) do
        l_num = l_num + 1
        local _, f = math.modf(l_num/2)
        if f == 0 then
            second = i
            local group = node_copylist(first, second.next)
            group = pack_group(group)
            table.insert(jiazhu_groups, group)
            first = nil
            second = nil
        else
            first = i
        end
    end
    -- 收集落单行
    if first then
        local group = node_copylist(first, first.next)
        group = pack_group(group)
        table.insert(jiazhu_groups, group)
    end

    node_flushlist(boxes[1].head)
    node_flushlist(box_head)
    table.remove(boxes, 1)

    return jiazhu_groups, boxes
end

-- 根据第一个rule的位置分拆、组合、插入夹注盒子、罚点等
local function insert_jiazhu(head_with_rules, vpar_head, jiazhu_boxes)
    -- local stop = false
    -- 寻找行，寻找rule
    for h,_ in node_traverseid(hlist_id, vpar_head) do
        for r, _ in node_traverseid(rule_id,h.head) do
            if node_hasattribute(r,3,333) then
                local hsize = jiazhu_hsize(h, r) -- 夹注标记rule到行尾的长度
                local jiazhu_groups
                jiazhu_groups, jiazhu_boxes = make_jiazhu_box(hsize, jiazhu_boxes)
                for rule, _ in node_traverseid(rule_id, head_with_rules) do
                    if node_hasattribute(rule,3,333) then
                        for i=1, #jiazhu_groups, 1 do
                            local group = jiazhu_groups[i]
                            -- 插入夹注
                            head_with_rules, group = node_insertbefore(head_with_rules, rule, group)
                            
                            -- 插入罚点
                            if i < #jiazhu_groups then -- 非末行后，强制断行
                                local penalty = node_new("penalty")
                                penalty.penalty = -10000
                                head_with_rules, penalty = node_insertafter(head_with_rules, group, penalty)
                                local glue = node_new("glue")
                                glue.width = 0
                                glue.stretch = tex_sp("0.5em")
                                head_with_rules, glue = node_insertafter(head_with_rules, penalty, glue)
                            end
                        end
                        
                        head_with_rules, rule = node_remove(head_with_rules,rule,true)-- 移除标记rule
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
            
            local vpar_head, _= par_break(par_head_with_rule, {hsize=hsize}, false)
            
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
    local par_head_with_rule, jiazhu_boxes = boxes_to_rules(head)
    if par_head_with_rule then
        out_head = find_fist_rule(par_head_with_rule, jiazhu_boxes)
    end

    return out_head, true
end

function Moduledata.jiazhu.append()
    -- 只能使用CLD样式添加任务
    -- "processors", "before"，只加了par vmodepar和左右parfill skip
    -- "processors", "after"，还加入了字间的glue userskip、标点前后的penalty userpenalty，可用于断行
    nodes.tasks.appendaction("processors", "after", "Moduledata.jiazhu.main")
end

return Moduledata.jiazhu
