import 'dart:convert';

// HTML转义工具函数
String _escapeHtml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

/// Generate processing card HTML
///
/// mirrors backend `get_processing_card_html` in `app/services/html_templates.py`
// Helper to process content (extract media, truncate text)
String _processForDisplay(String rawContent) {
  String mediaHtml = '';
  String textContent = rawContent;

  // Extract images
  final imgPattern = RegExp(r'!\[.*?\]\((.*?)\)');
  textContent = textContent.replaceAllMapped(imgPattern, (match) {
    final path = match.group(1) ?? '';
    mediaHtml +=
        '<div class="media-preview"><img src="$path" alt="Preview"></div>';
    return ''; // Remove from text content
  });

  // Extract audio
  final audioPattern = RegExp(r'\[(.*?(?:audio|Audio).*?)\]\((.*?)\)');
  textContent = textContent.replaceAllMapped(audioPattern, (match) {
    final path = match.group(2) ?? '';
    mediaHtml +=
        '<div class="media-preview"><audio controls src="$path"></audio></div>';
    return ''; // Remove from text content
  });

  // Process remaining text
  textContent = textContent.trim();
  if (textContent.length > 200) {
    textContent = '${textContent.substring(0, 200)}...';
  }
  final textHtml = _escapeHtml(textContent);

  return mediaHtml.isNotEmpty
      ? '$textHtml<div class="media-container">$mediaHtml</div>'
      : textHtml;
}

/// Generate processing card HTML
///
/// mirrors backend `get_processing_card_html` in `app/services/html_templates.py`
String getProcessingCardHtml(String rawContent) {
  final processedContent = _processForDisplay(rawContent);

  return '''<div class="processing-card">
            <div class="processing-content">
                <div class="processing-icon-area">
                    <div class="sparkle-icon">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                            <path d="M12 2L14.4 9.6L22 12L14.4 14.4L12 22L9.6 14.4L2 12L9.6 9.6L12 2Z"
                                fill="url(#grad1)" />
                            <defs>
                                <linearGradient id="grad1" x1="2" y1="2" x2="22" y2="22" gradientUnits="userSpaceOnUse">
                                    <stop stop-color="#8B5CF6" />
                                    <stop offset="1" stop-color="#3B82F6" />
                                </linearGradient>
                            </defs>
                        </svg>
                    </div>
                    <div class="pulse-ring"></div>
                </div>
                <div class="processing-text-area">
                    <div class="processing-title">处理中...</div>
                </div>
            </div>

            <div class="shimmer-line"></div>

            <div class="original-input">
                <div class="input-content">$processedContent</div>
            </div>
        </div>

        <style>
            .processing-card {
                background: rgba(255, 255, 255, 0.9);
                backdrop-filter: blur(10px);
                border-radius: 20px;
                padding: 16px;
                box-shadow:
                    0 4px 6px -1px rgba(0, 0, 0, 0.05),
                    0 10px 15px -3px rgba(0, 0, 0, 0.05),
                    0 0 0 1px rgba(255, 255, 255, 0.5) inset;
                border: 1px solid rgba(229, 231, 235, 0.5);
                position: relative;
                overflow: hidden;
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            }

            .processing-content {
                display: flex;
                align-items: center;
                gap: 16px;
                margin-bottom: 20px;
            }

            .processing-icon-area {
                position: relative;
                width: 28px;
                height: 28px;
                display: flex;
                align-items: center;
                justify-content: center;
                background: linear-gradient(135deg, #F3F4F6 0%, #FFFFFF 100%);
                border-radius: 14px;
                box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
            }

            .sparkle-icon {
                z-index: 2;
                animation: spin-slow 8s linear infinite;
            }

            .pulse-ring {
                position: absolute;
                top: 0;
                left: 0;
                right: 0;
                bottom: 0;
                border-radius: 14px;
                border: 2px solid #8B5CF6;
                opacity: 0;
                animation: pulse-ring 2s cubic-bezier(0.215, 0.61, 0.355, 1) infinite;
            }

            .processing-text-area {
                flex: 1;
            }

            .processing-title {
                font-size: 14px;
                font-weight: 400;
                color: #9CA3AF;
                margin-bottom: 0;
            }

            .shimmer-line {
                height: 2px;
                background: #F3F4F6;
                border-radius: 1px;
                overflow: hidden;
                position: relative;
                margin-bottom: 20px;
            }

            .shimmer-line::after {
                content: '';
                position: absolute;
                top: 0;
                left: 0;
                height: 100%;
                width: 50%;
                background: linear-gradient(90deg, transparent, #8B5CF6, transparent);
                animation: shimmer 1.5s infinite;
            }

            .original-input {
                background: #F9FAFB;
                border-radius: 12px;
                padding: 12px 16px;
                border: 1px solid #F3F4F6;
            }

            .input-content {
                font-size: 14px;
                color: #4B5563;
                line-height: 1.5;
            }

            .media-preview {
                margin-top: 8px;
                width: 100%;
                border-radius: 8px;
                overflow: hidden;
            }

            .media-preview img {
                width: 100%;
                height: auto;
                display: block;
                border-radius: 8px;
                object-fit: cover;
            }

            .media-preview audio {
                width: 100%;
                height: 40px;
                margin-top: 4px;
            }

            @keyframes spin-slow {
                0% { transform: rotate(0deg) scale(1); }
                50% { transform: rotate(180deg) scale(1.05); }
                100% { transform: rotate(360deg) scale(1); }
            }

            @keyframes pulse-ring {
                100% { transform: scale(1.25); opacity: 0; }
            }

            @keyframes shimmer {
                0% { transform: translateX(-150%); }
                100% { transform: translateX(250%); }
            }
        </style>''';
}

/// Generate chart HTML fallback
///
/// mirrors backend `get_chart_html_fallback` in `app/services/html_templates.py`
String getChartHtmlFallback(Map<String, dynamic> chart) {
  final templateId = chart['template_id'] as String? ?? '';
  final title = _escapeHtml(chart['title'] as String? ?? '');
  final insight = _escapeHtml(chart['insight'] as String? ?? '');
  final data = chart['data'] as Map<String, dynamic>? ?? {};

  final dataJson = const JsonEncoder().convert(data);
  final templateIdEscaped = _escapeHtml(templateId);

  return '''
<div class="insight-chart">
  <h3>$title</h3>
  <p class="insight-text">$insight</p>
  <div class="chart-data" data-template="$templateIdEscaped" data-chart='$dataJson'></div>
</div>''';
}

/// Generate discovery HTML fallback
///
/// mirrors backend `get_discovery_html_fallback` in `app/services/html_templates.py`
String getDiscoveryHtmlFallback(Map<String, dynamic> discovery) {
  final title = _escapeHtml(discovery['title'] as String? ?? '');
  final alertText = _escapeHtml(discovery['alert_text'] as String? ?? '');

  return '''
<div class="alert-card">
  <div class="card-header">
    <div class="icon-box theme-blue-bg">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/></svg>
    </div>
    <span class="header-title">$title</span>
    <div class="status-dot theme-blue-dot"></div>
  </div>
  <p class="alert-text">$alertText</p>
</div>
<style>
  .alert-card { padding: 24px; background: transparent; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
  .card-header { display: flex; align-items: center; gap: 12px; margin-bottom: 16px; }
  .icon-box { width: 32px; height: 32px; border-radius: 50%; display: flex; align-items: center; justify-content: center; }
  .theme-blue-bg { background: #DBEAFE; color: #2563EB; }
  .header-title { font-size: 14px; font-weight: bold; color: #1E293B; }
  .status-dot { margin-left: auto; width: 8px; height: 8px; border-radius: 50%; }
  .theme-blue-dot { background: #60A5FA; }
  .alert-text { font-size: 14px; color: #475569; line-height: 1.6; margin: 0; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
</style>''';
}

/// Generate fallback card HTML
///
/// mirrors backend `get_fallback_card_html` in `app/services/html_templates.py`
String getFallbackCardHtml(String content) {
  final processedContent = _processForDisplay(content);

  return '''
<div class="fallback-card">
    <div class="fallback-header">
        <div class="fallback-icon-area">
            <div class="warning-icon">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
                    <path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm-1-7v2h2v-2h-2zm0-8v6h2V7h-2z"
                        fill="#B45309" />
                </svg>
            </div>
        </div>
        <div class="fallback-header-text">
            <div class="fallback-title">处理失败</div>
        </div>
    </div>

    <div class="separator-line"></div>

    <div class="original-input">
        <div class="input-content">$processedContent</div>
    </div>
</div>

<style>
    .fallback-card {
        background: rgba(255, 255, 255, 0.9);
        backdrop-filter: blur(10px);
        border-radius: 20px;
        padding: 16px;
        box-shadow:
            0 4px 6px -1px rgba(0, 0, 0, 0.05),
            0 10px 15px -3px rgba(0, 0, 0, 0.05),
            0 0 0 1px rgba(255, 255, 255, 0.5) inset;
        border: 1px solid rgba(252, 211, 77, 0.3);
        position: relative;
        overflow: hidden;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }

    .fallback-header {
        display: flex;
        align-items: center;
        gap: 16px;
        margin-bottom: 20px;
    }

    .fallback-icon-area {
        position: relative;
        width: 28px;
        height: 28px;
        display: flex;
        align-items: center;
        justify-content: center;
        background: linear-gradient(135deg, #FFFBEB 0%, #FEF3C7 100%);
        border-radius: 14px;
        box-shadow: 0 2px 4px rgba(0, 0, 0, 0.05);
    }

    .warning-icon {
        display: flex;
        align-items: center;
        justify-content: center;
    }

    .fallback-header-text {
        flex: 1;
    }

    .fallback-title {
        font-size: 14px;
        font-weight: 500;
        color: #92400E;
        margin-bottom: 0;
    }

    .separator-line {
        height: 1px;
        background: #FEF3C7;
        margin-bottom: 20px;
    }

    .original-input {
        background: #FFFBEB;
        border-radius: 12px;
        padding: 12px 16px;
        border: 1px solid #FEF3C7;
    }

    .input-content {
        font-size: 14px;
        color: #92400E;
        line-height: 1.5;
    }

    .media-preview {
        margin-top: 8px;
        width: 100%;
        border-radius: 8px;
        overflow: hidden;
    }

    .media-preview img {
        width: 100%;
        height: auto;
        display: block;
        border-radius: 8px;
        object-fit: cover;
    }

    .media-preview audio {
        width: 100%;
        height: 40px;
        margin-top: 4px;
    }
</style>''';
}
