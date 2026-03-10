local PinyinIme = {}

PinyinIme.PAGE_SIZE = 8

local LEXICON = {
    ["ni"] = { { text = "你", freq = 1000 }, { text = "呢", freq = 940 }, { text = "尼", freq = 880 }, { text = "泥", freq = 820 }, { text = "拟", freq = 760 } },
    ["hao"] = { { text = "好", freq = 1000 }, { text = "号", freq = 940 }, { text = "浩", freq = 880 }, { text = "毫", freq = 820 }, { text = "豪", freq = 760 } },
    ["ma"] = { { text = "吗", freq = 1000 }, { text = "妈", freq = 940 }, { text = "马", freq = 880 }, { text = "麻", freq = 820 }, { text = "码", freq = 760 } },
    ["wo"] = { { text = "我", freq = 1000 }, { text = "握", freq = 940 }, { text = "窝", freq = 880 }, { text = "卧", freq = 820 } },
    ["men"] = { { text = "们", freq = 1000 }, { text = "门", freq = 940 }, { text = "闷", freq = 880 } },
    ["shi"] = { { text = "是", freq = 1000 }, { text = "时", freq = 940 }, { text = "事", freq = 880 }, { text = "使", freq = 820 }, { text = "十", freq = 760 } },
    ["jie"] = { { text = "界", freq = 1000 }, { text = "接", freq = 940 }, { text = "节", freq = 880 }, { text = "解", freq = 820 }, { text = "结", freq = 760 } },
    ["zhong"] = { { text = "中", freq = 1000 }, { text = "种", freq = 940 }, { text = "重", freq = 880 }, { text = "终", freq = 820 }, { text = "钟", freq = 760 } },
    ["wen"] = { { text = "文", freq = 1000 }, { text = "问", freq = 940 }, { text = "闻", freq = 880 }, { text = "稳", freq = 820 }, { text = "温", freq = 760 } },
    ["ying"] = { { text = "英", freq = 1000 }, { text = "应", freq = 940 }, { text = "影", freq = 880 }, { text = "营", freq = 820 }, { text = "迎", freq = 760 } },
    ["jian"] = { { text = "键", freq = 1000 }, { text = "见", freq = 940 }, { text = "件", freq = 880 }, { text = "间", freq = 820 }, { text = "建", freq = 760 } },
    ["pan"] = { { text = "盘", freq = 1000 }, { text = "判", freq = 940 }, { text = "盼", freq = 880 }, { text = "攀", freq = 820 } },
    ["zhongwen"] = { { text = "中文", freq = 1000 } },
    ["yingwen"] = { { text = "英文", freq = 1000 } },
    ["zhongying"] = { { text = "中英", freq = 1000 } },
    ["pinyin"] = { { text = "拼音", freq = 1000 } },
    ["shurufa"] = { { text = "输入法", freq = 1000 } },
    ["jianpan"] = { { text = "键盘", freq = 1000 } },
    ["xuni"] = { { text = "虚拟", freq = 1000 } },
    ["xunijianpan"] = { { text = "虚拟键盘", freq = 1000 } },
    ["xitong"] = { { text = "系统", freq = 1000 } },
    ["xitongjianpan"] = { { text = "系统键盘", freq = 1000 } },
    ["zhongduan"] = { { text = "终端", freq = 1000 } },
    ["mingling"] = { { text = "命令", freq = 1000 } },
    ["minglinghang"] = { { text = "命令行", freq = 1000 } },
    ["lianjie"] = { { text = "连接", freq = 1000 } },
    ["duankai"] = { { text = "断开", freq = 1000 } },
    ["chonglian"] = { { text = "重连", freq = 1000 } },
    ["wangluo"] = { { text = "网络", freq = 1000 } },
    ["fuwuqi"] = { { text = "服务器", freq = 1000 } },
    ["yonghu"] = { { text = "用户", freq = 1000 } },
    ["yonghuming"] = { { text = "用户名", freq = 1000 } },
    ["mima"] = { { text = "密码", freq = 1000 } },
    ["denglu"] = { { text = "登录", freq = 1000 } },
    ["zhuxiao"] = { { text = "注销", freq = 1000 } },
    ["kaishi"] = { { text = "开始", freq = 1000 } },
    ["tingzhi"] = { { text = "停止", freq = 1000 } },
    ["baocun"] = { { text = "保存", freq = 1000 } },
    ["quxiao"] = { { text = "取消", freq = 1000 } },
    ["queding"] = { { text = "确定", freq = 1000 } },
    ["guanbi"] = { { text = "关闭", freq = 1000 } },
    ["dakai"] = { { text = "打开", freq = 1000 } },
    ["fanhui"] = { { text = "返回", freq = 1000 } },
    ["shezhi"] = { { text = "设置", freq = 1000 } },
    ["xuyao"] = { { text = "需要", freq = 1000 } },
    ["buneng"] = { { text = "不能", freq = 1000 } },
    ["keyi"] = { { text = "可以", freq = 1000 } },
    ["bukeyi"] = { { text = "不可以", freq = 1000 } },
    ["women"] = { { text = "我们", freq = 1000 } },
    ["nimen"] = { { text = "你们", freq = 1000 } },
    ["tamen"] = { { text = "他们", freq = 1000 }, { text = "她们", freq = 940 } },
    ["zheli"] = { { text = "这里", freq = 1000 } },
    ["nali"] = { { text = "哪里", freq = 1000 } },
    ["shenme"] = { { text = "什么", freq = 1000 } },
    ["zenme"] = { { text = "怎么", freq = 1000 } },
    ["weishenme"] = { { text = "为什么", freq = 1000 } },
    ["yinwei"] = { { text = "因为", freq = 1000 } },
    ["suoyi"] = { { text = "所以", freq = 1000 } },
    ["ruguo"] = { { text = "如果", freq = 1000 } },
    ["danshi"] = { { text = "但是", freq = 1000 } },
    ["erqie"] = { { text = "而且", freq = 1000 } },
    ["qishi"] = { { text = "其实", freq = 1000 } },
    ["xianzai"] = { { text = "现在", freq = 1000 } },
    ["jintian"] = { { text = "今天", freq = 1000 } },
    ["mingtian"] = { { text = "明天", freq = 1000 } },
    ["zuotian"] = { { text = "昨天", freq = 1000 } },
    ["shijian"] = { { text = "时间", freq = 1000 } },
    ["difang"] = { { text = "地方", freq = 1000 } },
    ["dongxi"] = { { text = "东西", freq = 1000 } },
    ["shiqing"] = { { text = "事情", freq = 1000 } },
    ["gongzuo"] = { { text = "工作", freq = 1000 } },
    ["xuexi"] = { { text = "学习", freq = 1000 } },
    ["shenghuo"] = { { text = "生活", freq = 1000 } },
    ["pengyou"] = { { text = "朋友", freq = 1000 } },
    ["jiating"] = { { text = "家庭", freq = 1000 } },
    ["haode"] = { { text = "好的", freq = 1000 } },
    ["buhao"] = { { text = "不好", freq = 1000 } },
    ["zhenhao"] = { { text = "真好", freq = 1000 } },
    ["bangzhu"] = { { text = "帮助", freq = 1000 } },
    ["zhichi"] = { { text = "支持", freq = 1000 } },
    ["chenggong"] = { { text = "成功", freq = 1000 } },
    ["shibai"] = { { text = "失败", freq = 1000 } },
    ["cuowu"] = { { text = "错误", freq = 1000 } },
    ["zhengque"] = { { text = "正确", freq = 1000 } },
    ["wenjian"] = { { text = "文件", freq = 1000 } },
    ["mulu"] = { { text = "目录", freq = 1000 } },
    ["lujing"] = { { text = "路径", freq = 1000 } },
    ["shuru"] = { { text = "输入", freq = 1000 } },
    ["shuchu"] = { { text = "输出", freq = 1000 } },
    ["bianji"] = { { text = "编辑", freq = 1000 } },
    ["fuzhi"] = { { text = "复制", freq = 1000 } },
    ["zhantie"] = { { text = "粘贴", freq = 1000 } },
    ["shanchu"] = { { text = "删除", freq = 1000 } },
    ["qiehuan"] = { { text = "切换", freq = 1000 } },
    ["zhuti"] = { { text = "主题", freq = 1000 } },
    ["yanse"] = { { text = "颜色", freq = 1000 } },
    ["gaoliang"] = { { text = "高亮", freq = 1000 } },
    ["gundong"] = { { text = "滚动", freq = 1000 } },
    ["lishi"] = { { text = "历史", freq = 1000 } },
    ["houxuan"] = { { text = "候选", freq = 1000 } },
    ["dianji"] = { { text = "点击", freq = 1000 } },
    ["chumo"] = { { text = "触摸", freq = 1000 } },
    ["shubiao"] = { { text = "鼠标", freq = 1000 } },
    ["anjian"] = { { text = "按键", freq = 1000 } },
    ["zhendong"] = { { text = "震动", freq = 1000 } },
    ["fangxiangjian"] = { { text = "方向键", freq = 1000 } },
    ["kongge"] = { { text = "空格", freq = 1000 } },
    ["huiche"] = { { text = "回车", freq = 1000 } },
    ["fanye"] = { { text = "翻页", freq = 1000 } },
    ["shangyiye"] = { { text = "上一页", freq = 1000 } },
    ["xiayiye"] = { { text = "下一页", freq = 1000 } },
    ["nihao"] = { { text = "你好", freq = 1000 } },
    ["zaijian"] = { { text = "再见", freq = 1000 } },
    ["xiexie"] = { { text = "谢谢", freq = 1000 } },
    ["qingwen"] = { { text = "请问", freq = 1000 } },
    ["duibuqi"] = { { text = "对不起", freq = 1000 } },
    ["meiguanxi"] = { { text = "没关系", freq = 1000 } },
    ["zhongguo"] = { { text = "中国", freq = 1000 } },
    ["hanyu"] = { { text = "汉语", freq = 1000 } },
    ["shijie"] = { { text = "世界", freq = 1000 } },
    ["womenhao"] = { { text = "我们好", freq = 1000 } },
    ["womende"] = { { text = "我们的", freq = 1000 } },
    ["nide"] = { { text = "你的", freq = 1000 } },
    ["wode"] = { { text = "我的", freq = 1000 } },
    ["fuwu"] = { { text = "服务", freq = 1000 } },
    ["wangye"] = { { text = "网页", freq = 1000 } },
    ["ruanjian"] = { { text = "软件", freq = 1000 } },
    ["yingjian"] = { { text = "硬件", freq = 1000 } },
    ["zhanghao"] = { { text = "账号", freq = 1000 } },
    ["mimacuo"] = { { text = "密码错", freq = 1000 } },
    ["lianjiechenggong"] = { { text = "连接成功", freq = 1000 } },
    ["lianjieshibai"] = { { text = "连接失败", freq = 1000 } },
}

local RECENT_READING = {}
local RECENT_TEXT = {}
local RECENT_BIGRAM = {}

local EXTERNAL_LEXICON_MODULES = {
    "pinyin_lexicon_extra",
    "pinyin_lexicon_user",
}

local LOAD_STATS = {
    base_keys = 0,
    base_entries = 0,
    merged_keys = 0,
    merged_entries = 0,
    total_keys = 0,
    total_entries = 0,
    merged_modules = 0,
    modules = {},
}

local function normalizeReadingKey(raw)
    return tostring(raw or ""):lower():gsub("[^a-zv]", "")
end

local function countLexiconEntries(lexicon)
    local keys, entries = 0, 0
    for _, bucket in pairs(lexicon or {}) do
        if type(bucket) == "table" then
            keys = keys + 1
            for _, entry in ipairs(bucket) do
                if type(entry) == "table" and entry.text and entry.text ~= "" then
                    entries = entries + 1
                end
            end
        end
    end
    return keys, entries
end

local function ensureBucket(reading)
    LEXICON[reading] = LEXICON[reading] or {}
    return LEXICON[reading]
end

local function appendEntry(reading, entry, source)
    reading = normalizeReadingKey(reading)
    if reading == "" then return false end
    local text = nil
    local freq = 1000
    if type(entry) == "string" then
        text = entry
    elseif type(entry) == "table" then
        text = entry.text or entry[1]
        freq = tonumber(entry.freq or entry.score or entry.weight or entry[2]) or 1000
    end
    if not text or text == "" then return false end
    local bucket = ensureBucket(reading)
    for _, existing in ipairs(bucket) do
        if existing.text == text then
            if freq > (existing.freq or 0) then
                existing.freq = freq
            end
            return false
        end
    end
    table.insert(bucket, { text = text, freq = freq, source = source })
    return true
end

local function mergeLexiconMap(map, source)
    local mergedKeys = {}
    local mergedEntries = 0
    for reading, bucket in pairs(map or {}) do
        local normalized = normalizeReadingKey(reading)
        if normalized ~= "" then
            if type(bucket) == "table" and bucket.text then
                if appendEntry(normalized, bucket, source) then
                    mergedEntries = mergedEntries + 1
                    mergedKeys[normalized] = true
                end
            elseif type(bucket) == "table" then
                for _, entry in ipairs(bucket) do
                    if appendEntry(normalized, entry, source) then
                        mergedEntries = mergedEntries + 1
                        mergedKeys[normalized] = true
                    end
                end
            elseif type(bucket) == "string" then
                if appendEntry(normalized, bucket, source) then
                    mergedEntries = mergedEntries + 1
                    mergedKeys[normalized] = true
                end
            end
        end
    end
    local mergedKeyCount = 0
    for _ in pairs(mergedKeys) do mergedKeyCount = mergedKeyCount + 1 end
    return mergedKeyCount, mergedEntries
end

local function mergeLexiconEntries(entries, source)
    local mergedKeys = {}
    local mergedEntries = 0
    for _, item in ipairs(entries or {}) do
        if type(item) == "table" then
            local reading = normalizeReadingKey(item.reading or item.pinyin or item.key)
            if reading ~= "" and appendEntry(reading, item, source) then
                mergedEntries = mergedEntries + 1
                mergedKeys[reading] = true
            end
        end
    end
    local mergedKeyCount = 0
    for _ in pairs(mergedKeys) do mergedKeyCount = mergedKeyCount + 1 end
    return mergedKeyCount, mergedEntries
end

local function mergeLexiconChunk(name, chunk)
    if type(chunk) ~= "table" then return 0, 0 end
    local source = chunk.name or name
    local keysA, entriesA = 0, 0
    local keysB, entriesB = 0, 0
    if chunk.lexicon or chunk.dict then
        keysA, entriesA = mergeLexiconMap(chunk.lexicon or chunk.dict, source)
    else
        keysA, entriesA = mergeLexiconMap(chunk, source)
    end
    if chunk.entries then
        keysB, entriesB = mergeLexiconEntries(chunk.entries, source)
    end
    return keysA + keysB, entriesA + entriesB
end

local function isModuleMissing(name, err)
    err = tostring(err or "")
    return err:find("module '" .. name .. "' not found", 1, true) ~= nil
end

local ALL_KEYS = {}
local INITIALS_INDEX = {}
local buildSegmentations

local function rebuildAllKeys()
    ALL_KEYS = {}
    for key in pairs(LEXICON) do table.insert(ALL_KEYS, key) end
    table.sort(ALL_KEYS, function(a, b)
        if #a == #b then return a < b end
        return #a > #b
    end)
end

local function pickInitialsSegments(reading)
    local segmentations = buildSegmentations(reading)
    local best = nil
    for _, segments in ipairs(segmentations) do
        if #segments > 1 then
            if not best or #segments > #best then
                best = segments
            end
        end
    end
    if not best then
        return (#reading > 0) and string.sub(reading, 1, 1) or nil
    end
    local parts = {}
    for _, segment in ipairs(best) do
        parts[#parts + 1] = string.sub(segment, 1, 1)
    end
    return table.concat(parts)
end

local function rebuildInitialsIndex()
    INITIALS_INDEX = {}
    for reading, bucket in pairs(LEXICON) do
        local initials = pickInitialsSegments(reading)
        if initials and initials ~= "" then
            local out = INITIALS_INDEX[initials]
            if not out then
                out = {}
                INITIALS_INDEX[initials] = out
            end
            local seen = {}
            for _, existing in ipairs(out) do
                seen[existing.text .. "|" .. existing.reading] = true
            end
            for idx = 1, math.min(#bucket, 3) do
                local entry = bucket[idx]
                local dedupeKey = tostring(entry.text or "") .. "|" .. tostring(reading)
                if entry.text and not seen[dedupeKey] then
                    seen[dedupeKey] = true
                    table.insert(out, { text = entry.text, reading = reading, freq = entry.freq or 1000 })
                end
            end
        end
    end
end

local function loadExternalLexicons()
    LOAD_STATS.base_keys, LOAD_STATS.base_entries = countLexiconEntries(LEXICON)
    for _, moduleName in ipairs(EXTERNAL_LEXICON_MODULES) do
        local ok, chunk = pcall(require, moduleName)
        if ok then
            local mergedKeys, mergedEntries = mergeLexiconChunk(moduleName, chunk)
            if mergedEntries > 0 then
                LOAD_STATS.merged_modules = LOAD_STATS.merged_modules + 1
                LOAD_STATS.merged_keys = LOAD_STATS.merged_keys + mergedKeys
                LOAD_STATS.merged_entries = LOAD_STATS.merged_entries + mergedEntries
                table.insert(LOAD_STATS.modules, string.format("%s(+%d/%d)", moduleName, mergedKeys, mergedEntries))
            else
                table.insert(LOAD_STATS.modules, string.format("%s(+0/0)", moduleName))
            end
        elseif not isModuleMissing(moduleName, chunk) then
            print(string.format("[PinyinIme] Failed to load %s: %s", moduleName, tostring(chunk)))
        end
    end
    rebuildAllKeys()
    rebuildInitialsIndex()
    LOAD_STATS.total_keys, LOAD_STATS.total_entries = countLexiconEntries(LEXICON)
    print(string.format(
        "[PinyinIme] Lexicon ready: base=%d/%d merged=%d/%d modules=%d total=%d/%d",
        LOAD_STATS.base_keys,
        LOAD_STATS.base_entries,
        LOAD_STATS.merged_keys,
        LOAD_STATS.merged_entries,
        LOAD_STATS.merged_modules,
        LOAD_STATS.total_keys,
        LOAD_STATS.total_entries
    ))
    if #LOAD_STATS.modules > 0 then
        print("[PinyinIme] Modules: " .. table.concat(LOAD_STATS.modules, ", "))
    end
end

local FUZZY_RULES = {
    { "zh", "z", 18 }, { "z", "zh", 20 },
    { "ch", "c", 18 }, { "c", "ch", 20 },
    { "sh", "s", 18 }, { "s", "sh", 20 },
    { "ing", "in", 14 }, { "in", "ing", 16 },
    { "eng", "en", 14 }, { "en", "eng", 16 },
}

local function normalize(raw)
    return (raw or ""):lower():gsub("[^a-zv]", "")
end

local function getReadingRecent(reading, text)
    local bucket = RECENT_READING[reading]
    return bucket and (bucket[text] or 0) or 0
end

local function getBigramRecent(prevText, text)
    local bucket = prevText and RECENT_BIGRAM[prevText] or nil
    return bucket and (bucket[text] or 0) or 0
end

local function makeCandidate(text, reading, score, extras)
    local candidate = { text = text, reading = reading, score = score }
    if extras then
        for key, value in pairs(extras) do candidate[key] = value end
    end
    return candidate
end

local function addCandidate(acc, seen, candidate)
    if not candidate or not candidate.text or candidate.text == "" then return end
    local key = table.concat({ candidate.text, candidate.remaining or "", candidate.reading or "" }, "|")
    local existing = seen[key]
    if existing then
        if candidate.score > existing.score then
            existing.score = candidate.score
            existing.reading = candidate.reading
            existing.remaining = candidate.remaining
            existing.source = candidate.source
        end
        return
    end
    seen[key] = candidate
    table.insert(acc, candidate)
end

local function collectFuzzyVariants(raw)
    local variants = { [raw] = 0 }
    local frontier = { { text = raw, penalty = 0, depth = 0 } }
    local index = 1
    while index <= #frontier do
        local current = frontier[index]
        index = index + 1
        if current.depth < 2 then
            for _, rule in ipairs(FUZZY_RULES) do
                local from, to, penalty = rule[1], rule[2], rule[3]
                local searchStart = 1
                while true do
                    local i, j = string.find(current.text, from, searchStart, true)
                    if not i then break end
                    local nextText = string.sub(current.text, 1, i - 1) .. to .. string.sub(current.text, j + 1)
                    local nextPenalty = current.penalty + penalty
                    if not variants[nextText] or nextPenalty < variants[nextText] then
                        variants[nextText] = nextPenalty
                        table.insert(frontier, { text = nextText, penalty = nextPenalty, depth = current.depth + 1 })
                    end
                    searchStart = i + 1
                end
            end
        end
    end
    local out = {}
    for text, penalty in pairs(variants) do table.insert(out, { text = text, penalty = penalty }) end
    table.sort(out, function(a, b)
        if a.penalty == b.penalty then return #a.text < #b.text end
        return a.penalty < b.penalty
    end)
    return out
end

local function matchingKeys(raw, pos)
    local out = {}
    for _, key in ipairs(ALL_KEYS) do
        if string.sub(raw, pos, pos + #key - 1) == key then
            table.insert(out, key)
        end
    end
    return out
end

buildSegmentations = function(raw)
    local results = {}
    local function dfs(pos, segments)
        if #results >= 18 then return end
        if pos > #raw then
            local copy = {}
            for i = 1, #segments do copy[i] = segments[i] end
            table.insert(results, copy)
            return
        end
        if #segments >= 6 then return end
        for _, key in ipairs(matchingKeys(raw, pos)) do
            table.insert(segments, key)
            dfs(pos + #key, segments)
            table.remove(segments)
        end
    end
    dfs(1, {})
    return results
end

local function scoreLexiconEntry(reading, entry, opts, fuzzyPenalty)
    local score = entry.freq or 0
    score = score + getReadingRecent(reading, entry.text) * 180
    score = score + (RECENT_TEXT[entry.text] or 0) * 35
    score = score + getBigramRecent(opts.prev_text, entry.text) * 120
    score = score - (fuzzyPenalty or 0)
    return score
end

local function collectExactCandidates(raw, opts, acc, seen)
    for _, variant in ipairs(collectFuzzyVariants(raw)) do
        local entries = LEXICON[variant.text]
        if entries then
            for _, entry in ipairs(entries) do
                addCandidate(acc, seen, makeCandidate(entry.text, raw, scoreLexiconEntry(raw, entry, opts, variant.penalty) + 1200, { source = "exact", remaining = "" }))
            end
        end
    end
end

local function collectPrefixCandidates(raw, opts, acc, seen)
    for _, variant in ipairs(collectFuzzyVariants(raw)) do
        for _, key in ipairs(ALL_KEYS) do
            if key ~= variant.text and string.sub(key, 1, #variant.text) == variant.text then
                local entries = LEXICON[key]
                for idx = 1, math.min(#entries, 2) do
                    local entry = entries[idx]
                    local score = scoreLexiconEntry(key, entry, opts, variant.penalty) + 540 - math.max(0, #key - #variant.text) * 22
                    addCandidate(acc, seen, makeCandidate(entry.text, raw, score, { source = "prefix", remaining = string.sub(raw, #variant.text + 1) }))
                end
            end
        end
    end
end

local function collectInitialsCandidates(raw, opts, acc, seen)
    if #raw < 2 then return end
    local function addFromBucket(initials, entries, exact)
        if not entries then return end
        for idx = 1, math.min(#entries, exact and 4 or 2) do
            local entry = entries[idx]
            local score = (entry.freq or 1000)
                + getReadingRecent(entry.reading, entry.text) * 180
                + (RECENT_TEXT[entry.text] or 0) * 35
                + getBigramRecent(opts.prev_text, entry.text) * 120
                + (exact and 760 or 540)
                - math.max(0, #initials - #raw) * 42
            addCandidate(acc, seen, makeCandidate(entry.text, raw, score, {
                source = exact and "initials" or "initials-prefix",
                remaining = "",
                reading = entry.reading,
            }))
        end
    end

    addFromBucket(raw, INITIALS_INDEX[raw], true)
    for initials, entries in pairs(INITIALS_INDEX) do
        if initials ~= raw and string.sub(initials, 1, #raw) == raw then
            addFromBucket(initials, entries, false)
        end
    end
end

local function collectSegmentationCandidates(raw, opts, acc, seen)
    local segmentations = buildSegmentations(raw)
    for _, segments in ipairs(segmentations) do
        local words = {}
        local score = 900 - (#segments - 1) * 80
        for _, key in ipairs(segments) do
            local entry = LEXICON[key] and LEXICON[key][1] or nil
            if not entry then words = nil break end
            table.insert(words, entry.text)
            score = score + scoreLexiconEntry(key, entry, opts, 0)
        end
        if words then
            addCandidate(acc, seen, makeCandidate(table.concat(words), raw, score, { source = "segment", remaining = "" }))
        end
    end
    for _, key in ipairs(ALL_KEYS) do
        if #key < #raw and string.sub(raw, 1, #key) == key then
            local entry = LEXICON[key] and LEXICON[key][1] or nil
            if entry then
                local remain = string.sub(raw, #key + 1)
                local score = scoreLexiconEntry(key, entry, opts, 0) + 420 - #remain * 18
                addCandidate(acc, seen, makeCandidate(entry.text, raw, score, { source = "partial", remaining = remain }))
            end
        end
    end
end

function PinyinIme.getCandidates(raw, opts)
    raw = normalize(raw)
    opts = opts or {}
    local limit = opts.limit or 48
    if raw == "" then return {} end

    local acc, seen = {}, {}
    collectExactCandidates(raw, opts, acc, seen)
    collectSegmentationCandidates(raw, opts, acc, seen)
    collectInitialsCandidates(raw, opts, acc, seen)
    collectPrefixCandidates(raw, opts, acc, seen)

    table.sort(acc, function(a, b)
        if a.score == b.score then
            if #a.text == #b.text then return a.text < b.text end
            return #a.text > #b.text
        end
        return a.score > b.score
    end)

    local out = {}
    for i = 1, math.min(#acc, limit) do
        out[i] = acc[i]
    end
    return out
end

function PinyinIme.stats()
    return {
        page_size = PinyinIme.PAGE_SIZE,
        base_keys = LOAD_STATS.base_keys,
        base_entries = LOAD_STATS.base_entries,
        merged_keys = LOAD_STATS.merged_keys,
        merged_entries = LOAD_STATS.merged_entries,
        total_keys = LOAD_STATS.total_keys,
        total_entries = LOAD_STATS.total_entries,
        merged_modules = LOAD_STATS.merged_modules,
        modules = LOAD_STATS.modules,
    }
end

function PinyinIme.rememberSelection(reading, text, prevText)
    reading = normalize(reading)
    if reading == "" or not text or text == "" then return end
    RECENT_READING[reading] = RECENT_READING[reading] or {}
    RECENT_READING[reading][text] = (RECENT_READING[reading][text] or 0) + 1
    RECENT_TEXT[text] = (RECENT_TEXT[text] or 0) + 1
    if prevText and prevText ~= "" then
        RECENT_BIGRAM[prevText] = RECENT_BIGRAM[prevText] or {}
        RECENT_BIGRAM[prevText][text] = (RECENT_BIGRAM[prevText][text] or 0) + 1
    end
end

loadExternalLexicons()

return PinyinIme
