from pathlib import Path
from textwrap import dedent
path = Path('wx_agent/pipeline.py')
text = path.read_text(encoding='utf-8')
marker = '\n\n__all__ = ['
if marker not in text:
    raise SystemExit('marker missing for analyze_stats insertion')
block = dedent('''
    def analyze_stats(
        self,
        *,
        start_date: Optional[str] = None,
        end_date: Optional[str] = None,
        top_n: int = 10,
        session_types: Optional[Sequence[str]] = None,
    ) -> Dict[str, object]:
        start_dt = _normalize_date(start_date) if start_date else None
        end_dt = _normalize_date(end_date) if end_date else None
        sessions = self.dataset_builder.list_sessions_metadata()

        total_msgs = 0
        hourly_distribution = [0] * 24
        allowed_types = _normalize_session_filters(session_types)
        breakdown = {
            "group": {"sessions": 0, "messages": 0},
            "single": {"sessions": 0, "messages": 0},
        }
        results: List[Dict[str, object]] = []

        for meta in sessions:
            json_path = Path(str(meta.get("file")))
            data = self.dataset_builder._load_json(json_path) or {}
            messages = data.get("messages") if isinstance(data, dict) else None
            if not isinstance(messages, list):
                continue
            session_type = str(meta.get("session_type") or "")
            category_key = _categorize_session(meta)
            if allowed_types and category_key not in allowed_types:
                continue

            cnt = 0
            sent_count = 0
            received_count = 0
            participant_counts: Optional[Counter[str]] = Counter() if category_key == "group" else None

            for msg in messages:
                dt, _ts = self.dataset_builder._extract_datetime(msg)
                if start_dt and dt and dt < start_dt:
                    continue
                if end_dt and dt and dt > end_dt + timedelta(days=1) - timedelta(seconds=1):
                    continue
                cnt += 1
                if dt:
                    hourly_distribution[dt.hour] += 1
                direction = msg.get("isSend")
                sent_flag = False
                if isinstance(direction, (int, float)):
                    sent_flag = int(direction) != 0
                elif isinstance(direction, str):
                    sent_flag = direction.strip().lower() in {"1", "true", "yes"}
                if sent_flag:
                    sent_count += 1
                else:
                    received_count += 1

                if participant_counts is not None:
                    sender = (
                        msg.get("senderDisplayName")
                        or msg.get("sender_name")
                        or msg.get("sender")
                        or msg.get("senderUsername")
                        or msg.get("sender_username")
                    )
                    sender_label = str(sender or "").strip() or "未知"
                    participant_counts[sender_label] += 1

            total_msgs += cnt
            participants_payload = None
            if participant_counts:
                total_group = sum(participant_counts.values())
                if total_group:
                    participants_payload = [
                        {
                            "name": name,
                            "messages": amount,
                            "ratio": round(amount / total_group, 4),
                        }
                        for name, amount in participant_counts.most_common(10)
                    ]

            results.append(
                {
                    "session_id": meta.get("session_id"),
                    "display_name": meta.get("display_name"),
                    "messages": cnt,
                    "session_type": session_type,
                    "category": category_key,
                    "file": meta.get("file"),
                    "sent_messages": sent_count,
                    "received_messages": received_count,
                    "participants": participants_payload,
                }
            )
            breakdown.setdefault(category_key, {"sessions": 0, "messages": 0})
            if cnt:
                breakdown[category_key]["sessions"] += 1
                breakdown[category_key]["messages"] += cnt

        results.sort(key=lambda x: int(x.get("messages", 0)), reverse=True)
        return {
            "total_messages": total_msgs,
            "session_count": len(results),
            "window": {"start": start_date, "end": end_date},
            "top": results[: max(1, top_n)],
            "all": results,
            "breakdown": breakdown,
            "hourly_distribution": hourly_distribution,
        }

''')
text = text.replace(marker, "\n" + block + marker, 1)
path.write_text(text, encoding='utf-8')
