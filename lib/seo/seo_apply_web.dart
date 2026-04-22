import 'dart:html' as html;

import 'seo_metadata.dart';

const String _canonicalOrigin = 'https://fastdating1.com';

void applySeoToDocument(SeoMetadata meta, {String canonicalPath = '/'}) {
  html.document.title = meta.title;

  void setMeta(String name, String content) {
    html.MetaElement? el =
        html.document.querySelector('meta[name="$name"]') as html.MetaElement?;
    el ??= html.MetaElement()..setAttribute('name', name);
    el.content = content;
    html.document.head?.append(el);
  }

  void setPropertyMeta(String property, String content) {
    html.MetaElement? el = html.document
        .querySelector('meta[property="$property"]') as html.MetaElement?;
    el ??= html.MetaElement()..setAttribute('property', property);
    el.content = content;
    html.document.head?.append(el);
  }

  setMeta('description', meta.description);
  setPropertyMeta('og:title', meta.title);
  setPropertyMeta('og:description', meta.description);
  setPropertyMeta('og:type', 'website');
  final path = canonicalPath.startsWith('/') ? canonicalPath : '/$canonicalPath';
  final url = '$_canonicalOrigin$path';
  setPropertyMeta('og:url', url);

  html.LinkElement? link =
      html.document.querySelector('link[rel="canonical"]') as html.LinkElement?;
  link ??= html.LinkElement()..rel = 'canonical';
  link.href = url;
  html.document.head?.append(link);

  _syncHiddenSeoH1InBody(meta.h1);
}

/// Web：畫面上不再顯示 [SeoH1Banner] 主標，改寫入僅可讀的隱藏 h1（不影響首屏佈局）。
const String _seoH1ElementId = 'fd-seo-h1';

void _syncHiddenSeoH1InBody(String h1) {
  final t = h1.trim();
  if (t.isEmpty) return;
  html.HeadingElement? el =
      html.document.getElementById(_seoH1ElementId) as html.HeadingElement?;
  if (el == null) {
    el = html.HeadingElement.h1()..id = _seoH1ElementId;
    // 視覺上隱藏，仍保留在 DOM 供搜尋與讀螢幕（類 sr-only）
    el.style
      ..setProperty('position', 'absolute')
      ..setProperty('left', '-10000px')
      ..setProperty('width', '1px')
      ..setProperty('height', '1px')
      ..setProperty('padding', '0')
      ..setProperty('margin', '-1px')
      ..setProperty('overflow', 'hidden')
      ..setProperty('clip', 'rect(0, 0, 0, 0)')
      ..setProperty('clip-path', 'inset(50%)');
    html.document.body?.append(el);
  }
  el.text = t;
}
