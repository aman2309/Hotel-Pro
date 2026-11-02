# आपके होटल की read-only cloud जाँच

10 अक्टूबर 2026। दिए गए OTP नंबर (अंतिम अंक `1818`) के Firebase Auth account से
पहचान तय करके जाँच की गई। **कोई production data/rules/mapping बदली नहीं गई।**
यह रिपोर्ट SAFE_ROLLOUT_PREPARATION.md में पहले दर्ज pending owner-audit स्थिति को अद्यतन करती है।

## पहचान और स्थायी path

- Project: `yankees-hotel-pro`
- वास्तविक Auth UID: `P0HqzHUpMUdwUJMjnWOPirunAvV2`
- वर्तमान businessId: `biz_xehC63jAFQWvlgKRwabV`
- Cloud root: `businesses/biz_xehC63jAFQWvlgKRwabV`
- Auth phone, `users/{UID}`, phoneIndex और business owner एक-दूसरे से मेल खाते हैं।
  Auth account disabled नहीं है। **इस owner के लिए नया businessId नहीं बनाना है।**
- उसी phone value के दो पुराने Firestore user documents हैं, लेकिन वास्तविक phone
  Auth account एक मिला। केवल phone-field lookup पर्याप्त नहीं है; Auth UID निर्णायक है।
- उसी UID का दूसरा business `biz_Wu3CTkZ2KAAH4mijEqND` भी है। उसमें 12 rooms,
  hotel/sync settings हैं; bookings/guests/bills/payments/license/photo objects नहीं मिले।
  उसे delete या current path से replace नहीं किया गया। पुराने user/business records
  की lineage review बाकी है।

## वर्तमान cloud documents

| प्रकार | मौजूद documents | `deleted: true` | restore के लिए active |
|---|---:|---:|---:|
| Rooms | 12 | 0 | 12 |
| Bookings | 11 | 11 | 0 |
| Guests | 4 | 4 | 0 |
| Bills | 3 | 3 | 0 |
| Payments | 9 | 9 | 0 |
| Extra charges | 8 | 8 | 0 |
| Future bookings | 0 | 0 | 0 |
| Expenses | 0 | 0 | 0 |
| Closed rooms | 0 | 0 | 0 |
| Settings (`hotel`, `sync`) | 2 | 0 | 2 |

`deleted: true` soft-deletion marker है; document अभी मौजूद है। नए ऐप का सामान्य restore
उसे active record नहीं मानेगा। बिना intent/local/PHP comparison marker हटाना भी सुरक्षित
नहीं है: संभव है कुछ deletions operator ने जानबूझकर किए हों। उनका कारण/कर्ता इस audit
से सिद्ध नहीं है। कई deleted records के updatedAt 27 सितंबर 2026 हैं, इस task से पहले।
`settings/sync` schemaVersion 2 और lastSyncAt `2026-10-01T05:12:43.304Z` दिखाता है।
यह live read snapshot है; पूर्ण database history या point-in-time export नहीं।

**Firestore को पूरा, recoverable hotel backup मानना अभी गलत होगा।** Local/PHP-only
records हैं या नहीं, दोनों फोन के exports और PHP database export से comparison के
बिना तय नहीं हो सकता। Soft-deleted records की सुरक्षित reviewed recovery भी जरूरी हो सकती है।

## ID photos

- वर्तमान business में Storage के 2 photo objects मिले: एक guest के front/back।
- दोनों generation-specific downloads सफल और JPEG bytes सत्यापित हुए। Private copies
  audit folder के `photos/` में उनके actual SHA-256 filenames से सुरक्षित हैं।
- उनके guest document पर `deleted: true` है। किसी active guest से reference नहीं है;
  नए reinstall के सामान्य active-guest restore से वे अभी नहीं लौटेंगे।
- Firestore stored SHA-256 और downloaded JPEG hashes दोनों photos के लिए अलग हैं।
  पुराना checkpoint upload code पहले original bytes का hash निकालता था, फिर JPEG
  compress करता था, और उसी original hash को compressed upload के metadata में लिखता
  था। इसलिए mismatch अकेले corruption/गलत guest photo सिद्ध नहीं करता। Original
  phone bytes/फोटो देखकर मिलान आवश्यक है; existing metadata को अब नहीं बदला।
- Phone की pending upload queue उपलब्ध नहीं है। केवल ये दो objects मिलने से बाकी
  guests/additional photos का upload पूरा होना सिद्ध नहीं होता।

## Trial/PIN activation

दोनों owned business paths में `settings/license` नहीं मिला। इसलिए पुरानी trial start
date और PIN activation का cloud acknowledgement **सत्यापित नहीं हो सकता**। यह user
की activation न होने का प्रमाण नहीं; पुराना ऐप इसे केवल local preferences में रखता था।
Originating phone के `hp1_trial_start`, `hp1_license_on`, `hp1_license_hash` तथा पुराने
activation/entitlement प्रमाण का owner-scoped review जरूरी है। Missing historical
trial date को नया trial मानकर शुरू न करें। इस audit में license create नहीं किया गया।

## अगले कदम और rollout रोकने के कारण

1. दोनों फोन पर वर्तमान ऐप uninstall/clear-data न करें। पुराने writers बंद रखकर
   local records, photos, license और pending edits की सुरक्षित प्रतियाँ निकालें।
2. cPanel/MySQL से verified owner के PHP store की **read-only SELECT/export** लें।
   उपलब्ध PHP endpoint GET भी INSERT/schema creation कर सकता है, इसलिए वह नहीं बुलाया।
3. दोनों पुराने cloud paths, soft-deleted records, local/PHP lists और ID photos को
   stable IDs व financial totals से reconcile करें। Records revive/import करने का
   concrete migration plan और conflicts दिखाएँ; आपकी अलग confirmation से पहले चलाएँ नहीं।
4. Original trial/PIN entitlement पहले सुरक्षित करें। तभी license migration/restore
   पूर्ण होने का दावा करें।
5. नया APK अभी live account में न खोलें: bootstrap license/sync writes कर सकता है।
   `Use cloud` conflict resolution भी अभी न चुनें; cloud active lists से local history
   गायब दिख सकती है। पहले दोनों प्रतियाँ export और review करें।
6. Rules/data backup + approved migration के बाद ही coordinated A-then-B rollout और
   real-device OTP, realtime, offline/concurrency तथा reinstall test करें।

Private audit evidence (guest data और photos Git/public report में शामिल नहीं):

`/Users/raghuwansh/hotel_pro_1/.checkpoints/rollout-20261010/owner-1791616802415/`

इसमें identity, Auth owner metadata, पूरा वर्तमान/पुराना collection snapshot, Storage
object inventory, generation-specific photo copies और read-only audit summary हैं।
Administrator IAM reads सफल हुए; actual Android owner-security-rule access और phone
pending uploads इस जाँच से सत्यापित नहीं हुए। APK/runtime source नहीं बदला गया।
