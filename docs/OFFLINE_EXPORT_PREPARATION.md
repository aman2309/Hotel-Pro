# फोन से offline recovery backup की तैयारी

11 अक्टूबर 2026: पुराने ऐप ने BACKUP CREATED SUCCESSFULLY दिखाया, लेकिन उपलब्ध shared storage में JSON नहीं मिला। Release ऐप non-debuggable है; run-as से private preferences नहीं पढ़ी जा सकतीं। Backup अभी सत्यापित नहीं है।

## तैयार artifact

- `build/rollout/Hotel-Pro-1-Offline-Backup-v13.apk`
- Package `com.hotelpro1.app`, versionCode 13, versionName `1.0.6-backup`.
- APK SHA256 `76ecf1b96fd6d72b7f40e2ce329de00d9d975a0b14b7a775999e16ba74cf64f4`.
- Certificate SHA256 `bafcba1c4782d36bfd4d967c50a9b371b76944b87fb770a1308ea0f569b3880d`, connected phone के पुराने APK से समान।
- APK manifest में INTERNET permission और FirebaseInitProvider नहीं हैं।
- अलग temporary source workspace से build; मुख्य ऐप के runtime source को नहीं बदला। Review source `tools/offline_export/` में है।

## व्यवहार और सीमा

यह अस्थायी APK सामान्य Hotel UI की जगह केवल backup UI दिखाता है। यह मौजूदा FlutterSharedPreferences XML, सभी original keys, trial/PIN activation values (यदि मौजूद हों), pending queues और embedded photo data को JSON में पढ़ता है। Missing keys को empty defaults नहीं देता। कोई hotel import, migration, Firebase login या preferences edit नहीं करता। Downloads/HotelProRecovery में नई file लिखकर bytes और original XML hash दोबारा जाँचता है।

यह पूरे Android app sandbox का backup नहीं है। Firebase Auth credentials तथा अलग private files स्वतः शामिल नहीं हैं। Photo URI मिलने पर अलग photo extraction की उपलब्धता जाँचनी होगी। किसी value का मौजूद होना उसकी business/guest association प्रमाणित नहीं करता।

## अनुमति के बाद क्रम

1. Airplane mode चालू, Wi-Fi बंद रखें। Original installed APK की सुरक्षित copy पहले से ` .checkpoints/rollout-20261010/phone-1791692936153/installed-0.apk` में है।
2. केवल user की स्पष्ट अनुमति पर same-package/same-certificate temporary APK को `adb install -r` से update करें। Uninstall, clear-data या downgrade flag नहीं लगाएँ। Install reject हो तो रुकें।
3. Export चलाएँ; नई JSON को private checkpoint में copy करें, SHA256 और raw preference/license values जाँचें। केवल success message को प्रमाण न मानें।
4. Captured original versionCode 13 APK को `adb install -r` से वापस लगाएँ; फोन offline रखें। यह same versionCode/signature है, फिर भी device install/result सत्यापित करना बाकी है।
5. Local records को cloud IDs से read-only compare करें। Bills/payments duplicate जाँच और guest/photo संबंध की समीक्षा के बाद recovery प्रस्ताव दें। Production mutation के लिए अलग पुष्टि जरूरी है।

## जाँच

Isolated exporter के दो mocked-channel tests पास: original license/unknown keys/photo data सुरक्षित रखना तथा missing keys से trial/defaults न बनाना। Targeted Flutter analyze: no issues. Release build और APK signing verification पास। वास्तविक फोन पर native export/restore अभी नहीं चलाया गया; temporary APK install की अनुमति बाकी है।
