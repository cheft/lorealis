#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Convert Google Pinyin dictionary (Rime format) to Lua lexicon format.
"""

import math
import re

def normalize_freq(freq, max_freq=20000000):
    """Normalize frequency to 0-20000 range using logarithmic scaling."""
    if freq <= 0:
        return 1
    # Use log scale: log(freq) / log(max_freq) * 20000
    # This ensures high freq items get high scores, low freq get low scores
    log_freq = math.log(freq + 1)  # +1 to avoid log(0)
    log_max = math.log(max_freq + 1)
    normalized = int((log_freq / log_max) * 20000)
    return max(1, min(20000, normalized))

def parse_dict_file(input_file):
    """Parse the Rime dictionary file."""
    entries = []
    
    with open(input_file, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            # Skip comments and empty lines
            if not line or line.startswith('#') or line.startswith('---'):
                continue
            # Skip metadata lines
            if line.startswith('name:') or line.startswith('version:') or line.startswith('sort:') or line.startswith('...'):
                continue
            
            # Split by tab
            parts = line.split('\t')
            if len(parts) >= 3:
                text = parts[0].strip()
                reading = parts[1].strip()
                try:
                    freq = int(parts[2].strip())
                except ValueError:
                    continue
                
                # Skip entries with freq = 0 (they are disabled)
                if freq <= 0:
                    continue
                
                # Normalize frequency
                norm_freq = normalize_freq(freq)
                
                entries.append({
                    'reading': reading,
                    'text': text,
                    'freq': norm_freq
                })
    
    return entries

def generate_lua_file(entries, output_file):
    """Generate Lua lexicon file."""
    # Group entries by reading (pinyin)
    lexicon = {}
    for entry in entries:
        reading = entry['reading']
        if reading not in lexicon:
            lexicon[reading] = []
        lexicon[reading].append(entry)
    
    # Sort each group by frequency (descending)
    for reading in lexicon:
        lexicon[reading].sort(key=lambda x: x['freq'], reverse=True)
    
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write('-- 用户自定义拼音词库。\n')
        f.write('--\n')
        f.write('-- 基于 Google Pinyin Dictionary (Rime ice 8105) 转换而来。\n')
        f.write('-- 包含《通用规范汉字表》8105 个汉字及扩展字符。\n')
        f.write('--\n')
        f.write('-- 格式说明：\n')
        f.write('-- - lexicon: 按拼音分组的中文字符列表\n')
        f.write('-- - entries: 备用格式（此文件主要使用 lexicon）\n')
        f.write('-- - freq: 词频（越大越靠前，范围 1-20000）\n')
        f.write('\n')
        f.write('return {\n')
        f.write('    lexicon = {\n')
        
        # Write lexicon entries grouped by first letter for better organization
        sorted_readings = sorted(lexicon.keys())
        
        current_prefix = None
        for reading in sorted_readings:
            prefix = reading[0] if reading else ''
            
            # Add comment for each letter section
            if prefix != current_prefix:
                current_prefix = prefix
                f.write(f'\n        -- [{prefix.upper()}] 拼音首字母\n')
            
            # Write entry for this reading
            f.write(f'        ["{reading}"] = {{\n')
            for entry in lexicon[reading]:
                f.write(f'            {{ text = "{entry["text"]}", freq = {entry["freq"]} }},\n')
            f.write('        },\n')
        
        f.write('    },\n')
        f.write('    entries = {\n')
        f.write('        -- 保留原有的用户自定义词汇（可在此添加更多）\n')
        f.write('        { reading = "nihao", text = "你好", freq = 20000 },\n')
        f.write('        { reading = "xiexie", text = "谢谢", freq = 20000 },\n')
        f.write('    }\n')
        f.write('}\n')

def main():
    input_file = 'res/pinyin_dict.ts'
    output_file = 'mod/ssh/lua/pinyin_lexicon_user.lua'
    
    print(f"Parsing dictionary file: {input_file}")
    entries = parse_dict_file(input_file)
    print(f"Found {len(entries)} entries")
    
    print(f"Generating Lua file: {output_file}")
    generate_lua_file(entries, output_file)
    print("Done!")

if __name__ == '__main__':
    main()
