from pathlib import Path
path = Path('wx_agent/pipeline.py')
text = path.read_text(encoding='utf-8')
text = text.replace('\r\n', '\n')
text = text.replace('\n\n', '\n')
path.write_text(text, encoding='utf-8')
