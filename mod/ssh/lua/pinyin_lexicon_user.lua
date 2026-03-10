-- 用户自定义拼音词库。
--
-- 支持两种写法：
-- 1) lexicon 映射：拼音 -> 候选列表
--    例如：
--    lexicon = {
--        ["nihao"] = {
--            { text = "你好呀", freq = 15000 },
--            "你号机",
--        },
--    }
--
-- 2) entries 列表：逐条写 reading / text / freq
--    例如：
--    entries = {
--        { reading = "ssh", text = "SSH", freq = 18000 },
--        { reading = "zhongduan", text = "终端", freq = 20000 },
--    }
--
-- 说明：
-- - freq 越大，候选越靠前。
-- - 这里适合放你常用的词、短语、产品名、命令名。
-- - 后续如果导入大词库，也可以继续保留这里作为个人词库覆盖层。

return {
    lexicon = {},
    entries = {},
}
