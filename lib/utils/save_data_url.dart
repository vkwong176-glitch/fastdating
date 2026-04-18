import 'save_data_url_io.dart' if (dart.library.html) 'save_data_url_web.dart' as impl;

Future<void> saveDataUrlToDevice(String dataUrl, String fileName) =>
    impl.saveDataUrlToDevice(dataUrl, fileName);
