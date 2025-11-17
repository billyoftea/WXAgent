from pathlib import Path
from datetime import datetime
text = Path('wx_agent/pipeline.py').read_text(encoding='utf-8')
old = """        combined = \"\n\n\".join(
            section
            for section in [
                summary_text,
                qa_section,
                \"\n\".join(stats_lines),
            ]
            if section
        )
        output_path = self.config.summary_output
        legacy_save_summary(combined, output_file=str(output_path), duration_seconds=None)
        history_path = self._write_history_archive(combined, start_label, end_label)
        return output_path, history_path
"""
new = """        combined = \"\n\n\".join(
            section
            for section in [
                summary_text,
                qa_section,
                \"\n\".join(stats_lines),
            ]
            if section
        )
        base_path = Path(self.config.summary_output)
        timestamp = datetime.now().strftime(\"%Y%m%d_%H%M%S\")
        if base_path.suffix:
            output_path = base_path.with_name(f\"{base_path.stem}_{timestamp}{base_path.suffix}\")
        else:
            output_path = base_path / f\"summary_{timestamp}.md\"
        output_path.parent.mkdir(parents=True, exist_ok=True)
        legacy_save_summary(combined, output_file=str(output_path), duration_seconds=None)
        history_path = self._write_history_archive(combined, start_label, end_label)
        return output_path, history_path
"""
if old not in text:
    raise SystemExit('block not found')
text = text.replace(old, new, 1)
Path('wx_agent/pipeline.py').write_text(text, encoding='utf-8')
