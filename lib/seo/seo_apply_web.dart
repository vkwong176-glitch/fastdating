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
}
