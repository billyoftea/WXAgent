package wxdb

import (
	"fmt"
)

// parseMessageContent 根据消息类型解析消息内容，完全参考echotrace的Dart实现
// 关键：不做乱码判断，直接处理内容
func (e *Exporter) parseMessageContent(msgType int64, content string, isGroupChat bool, selfWxid string) string {
	// 步骤1：HTML实体解码（echotrace的_decodeHtmlEntities）
	decoded := e.decodeHTMLEntities(content)

	// 步骤2：检查是否包含XML
	hasXML := e.isXMLContent(decoded)

	// 步骤3：根据消息类型处理（完全对应echotrace的switch语句）
	switch msgType {
	case 1: // 文本消息 - 对应 echotrace case 1
		// 如果文本消息包含XML，需要解析而不是直接显示
		if hasXML {
			if title := e.extractXMLTitle(decoded, ""); title != "" {
				return fmt.Sprintf("[图文] %s", title)
			}
			if cdata := e.extractCDATA(decoded); cdata != "" {
				return cdata
			}
			return "[图文消息]"
		}
		// 普通文本消息，返回解码后的内容
		// 注意：群聊的wxid前缀会在外层的parseGroupMessage中处理
		return e.cleanTextContent(decoded)

	case 3: // 图片消息
		return "[图片]"

	case 34: // 语音消息
		return "[语音消息]"

	case 42: // 名片消息
		return "[名片消息]"

	case 43: // 视频消息
		return "[视频消息]"

	case 47: // 动画表情
		return "[动画表情]"

	case 48: // 位置消息
		return "[位置消息]"

	case 10000: // 系统消息
		// echotrace会检查是否是撤回消息，这里简化处理
		if decoded != "" {
			return decoded
		}
		return "[系统消息]"

	case 244813135921: // 引用消息
		return e.extractQuoteContent(decoded)

	case 17179869233: // 卡片式链接
		title := e.extractXMLTitle(decoded, "")
		if title != "" {
			return "[链接] " + title
		}
		return "[链接]"

	case 21474836529: // 图文消息
		title := e.extractXMLTitle(decoded, "")
		if title != "" {
			return "[图文] " + title
		}
		return "[图文消息]"

	case 154618822705: // 小程序分享
		title := e.extractXMLTitle(decoded, "")
		if title != "" {
			return "[小程序] " + title
		}
		return "[小程序]"

	case 12884901937: // 音乐卡片
		return "[音乐]"

	case 8594229559345: // 红包卡片
		return "[红包]"

	case 81604378673: // 聊天记录合并转发
		return "[聊天记录]"

	case 266287972401: // 拍一拍消息
		return "[拍一拍]"

	case 8589934592049: // 转账卡片
		return "[转账]"

	case 270582939697: // 视频号直播卡片
		return "[视频号直播]"

	case 25769803825: // 文件消息
		title := e.extractXMLTitle(decoded, "")
		if title != "" {
			return "[文件] " + title
		}
		return "[文件]"

	case 49: // 分享链接
		title := e.extractXMLTitle(decoded, "")
		if title != "" {
			return "[链接] " + title
		}
		return "[链接]"

	case 227633266737: // 接龙消息
		extracted := e.extractSolitaireContent(decoded)
		if extracted != "" {
			return extracted
		}
		return "[接龙消息]"

	default:
		// 未知类型 - echotrace的default分支
		if decoded != "" {
			cleaned := e.cleanTextContent(decoded)
			if cleaned != "" {
				return cleaned
			}
		}
		return fmt.Sprintf("[未知消息类型(%d)]", msgType)
	}
}
