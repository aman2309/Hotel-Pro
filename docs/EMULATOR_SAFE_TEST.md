# Android emulator: अलग account से सुरक्षित परीक्षण

11 अक्टूबर 2026। Production deploy या असली फोन में कोई install/data change नहीं किया गया।

## मशीन और अलग environment

Mac: 8 GiB RAM; शुरुआत में internal disk लगभग 10 GiB खाली। मौजूदा Pixel_8 AVD external AndroidAVD volume पर है, जहाँ लगभग 60 GiB खाली था। उसे इस्तेमाल या wipe नहीं किया। अलग `HotelProSyncTest` AVD उसी external volume पर बनाया। Installed image Android 37.2 arm64 Play Store/16KB है; emulator 4 GiB RAM तक बढ़ाता है और 16 GiB host RAM की recommendation warning देता है। इसलिए एक Android emulator पर्याप्त है; दूसरे client के automated tests JavaScript Firebase SDK से चलते हैं।

अलग source copy `/private/tmp/hotel-pro-emulator-test` से test APK बनता है। Main project का runtime source नहीं बदला। Review/reproduce के लिए `tools/emulator_test/local-only.patch` है; इसे production source पर सीधे न लगाएँ।

- अलग package `com.hotelpro1.app.synctest`, label `Hotel Pro LOCAL TEST`.
- Firebase project `demo-hotel-pro-sync`; native FirebaseInitProvider हटाया, production google-services plugin test build में हटाया।
- Android emulator endpoints: Auth `10.0.2.2:19099`, Firestore `10.0.2.2:18080`, Storage `10.0.2.2:19199`.
- Mac servers localhost पर bind हैं। Demo project में non-emulated services fail होती हैं। कोई production rules/data deployment नहीं।
- PHP live writer disabled; reviewed legacy PHP import flag false है। Test में production PHP import चालू न करें।
- Test workspace में Gradle heap 2 GiB और workers 2 किए; main project setting नहीं बदली।

## परीक्षण का परिणाम और सीमा

36 Flutter sync tests पास: empty local/cloud safety, UID mapping, stable IDs, conflict handling, financial history preservation आदि। Local Firebase के 10 tests पास: two-client mapping/listener, different-owner isolation, atomic concurrent booking/payment, idempotent retry, offline/reconnect, license restore/reset prevention, photo restore/access तथा old writer rejection। Targeted test-build analyze clean।

ये SDK/model/rules tests हैं। Android screen से booking/payment, reinstall, native photo loading और दो physical phones का पूरा end-to-end flow अभी इन results से सिद्ध नहीं होता। OTP user स्वयं भरेगा। इस local Auth emulator में SMS नहीं भेजा जाता; local generated OTP console/API में मिलता है। काल्पनिक test नंबर `+919999999995` इस्तेमाल करें, असली होटल नंबर नहीं।

## असली नंबर पर रोक का कारण

10 अक्टूबर की पिछली read-only audit में current business `biz_xehC63jAFQWvlgKRwabV` और old business `biz_Wu3CTkZ2KAAH4mijEqND` मिले। 11 bookings, 4 guests, 3 bills, 9 payments और 8 charges soft-deleted हैं। Intentional delete या old snapshot sync का कारण साबित नहीं हुआ। तीन payment alias pairs की financial समीक्षा बाकी है। Local backup verified नहीं; PHP export नहीं मिला। दो saved ID photos deleted CUST-0001 से जुड़े हैं; manual association/pending uploads की पुष्टि बाकी है।

दोनों business paths में cloud license नहीं मिला। `LicenseService.bindBusiness` missing license पर local trial/current date से नया cloud record बना सकता है। Fresh emulator में पुरानी local activation नहीं होती, इसलिए production APK से real login अभी सुरक्षित नहीं है। पहले original license/trial proof सुरक्षित करना और returning-owner missing-license behavior को रोकना/approved recovery करना जरूरी है। पुराने phone का backup helper अभी install नहीं हुआ; latest instruction के अनुसार phone को नहीं छुआ जाएगा।

Empty first local state के sync safeguards tests पास हैं और bootstrap में allowPush restore से पहले false रहता है। फिर भी identity/license bootstrap metadata लिख सकता है; इसलिए इसे production में zero-write guarantee न मानें। असली नंबर के लिए अलग reviewed recovery और approval बाकी हैं।

## आगे manual test का क्रम

1. केवल LOCAL TEST ऐप में काल्पनिक नंबर से OTP request करें; local generated code लेकर user भरें।
2. एक room/guest/booking बनाकर Firestore में IDs देखें। दूसरे local SDK client से बदलाव करें और Android UI listener देखें।
3. Emulator network offline करें, pending edit बनाकर reconnect/retry देखें। Concurrent booking/payment में winner/conflict और receipt IDs जाँचें।
4. केवल disposable test package का data/reinstall प्रयोग करें; उसी test नंबर से UID/business, trial, history और photos लौटें।
5. दूसरे काल्पनिक owner से isolation देखें। असली फोन और असली owner को इस test workflow में शामिल न करें।

Local emulator state अभी persistent exported backup नहीं है। Firebase emulators बंद करने से test fixtures खो सकते हैं; production को इसका कोई प्रभाव नहीं।

## Install/स्क्रीन की पुष्टि

LOCAL TEST APK SHA256 `256d1be165e22a467c1bad408e3bc441871ca2332182c1ed955b08fa8933eb43`.
`emulator-5554` पर install Success, boot completed और सही package की foreground activity सत्यापित हैं। Login screen का evidence `docs/validation/emulator-20261011/login-screen.png` में है। अभी user ने test OTP नहीं भरा; native manual flows pending हैं। पुराने login text में cPanel शब्द है, लेकिन इस build का live writer Firestore ही है। Debug kernel में पुराने bucket का एक diagnostic expected-value log रह गया है; वास्तविक FirebaseOptions/demo bucket और तीन local emulator routes जाँचे हैं।

स्थानीय servers दोबारा शुरू करने की command (production default project का उपयोग न करें):

```sh
firebase emulators:start --project demo-hotel-pro-sync --config tools/emulator_test/firebase.local.json --only auth,firestore,storage
```

HTTP routing fix: स्थानीय OTP request Android cleartext policy से रुकी। केवल test APK में base cleartext denied और domain 10.0.2.2 allow वाला network security config जोड़ा। Auth emulator reachable; नई APK update के बाद user को SEND OTP फिर दबाना है।

11 अक्टूबर 10:29: user ने local OTP से login किया। नए test owner में rooms नहीं थे। केवल localhost demo project में create-only room_101/102/103 नमूने जोड़े; बिना restart/refresh Android dashboard में TOTAL 3, EMPTY 3 और तीन cards आए। Native realtime room listener सत्यापित; booking/payment/offline/reinstall/photo manual tests बाकी हैं।
