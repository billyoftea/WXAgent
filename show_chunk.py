from pathlib import Path
text = Path('wx_agent/pipeline.py').read_text(encoding='utf-8')
idx = text.index('output_path = self.config.summary_output')
chunk = text[idx-200:idx+200]
print(repr(chunk))
