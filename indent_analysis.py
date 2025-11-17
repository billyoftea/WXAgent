from pathlib import Path
path = Path('wx_agent/pipeline.py')
text = path.read_text(encoding='utf-8')
old_start = '\ndef analyze_stats('
old_end = '\n    return {\n        "total_messages": total_msgs,\n        "session_count": len(results),\n        "window": {"start": start_date, "end": end_date},\n        "top": results[: max(1, top_n)],\n        "all": results,\n        "breakdown": breakdown,\n        "hourly_distribution": hourly_distribution,\n    }\n'
start_idx = text.find(old_start)
end_idx = text.find(old_end, start_idx)
if start_idx == -1 or end_idx == -1:
    raise SystemExit('analyze_stats block not found')
end_idx += len(old_end)
block = text[start_idx:end_idx]
indent_block = '\n    ' + block.strip('\n').replace('\n', '\n    ')
text = text[:start_idx] + indent_block + text[end_idx:]
path.write_text(text, encoding='utf-8')
