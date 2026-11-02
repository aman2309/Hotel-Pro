# पुराने होटल डेटा की सुरक्षित recovery — तुलना और प्रस्ताव

10 अक्टूबर 2026। यह **प्रस्ताव है, recovery/deployment नहीं किया गया**। Production
data/rules नहीं बदलीं, कोई deleted document सक्रिय नहीं किया और नया ऐप फोन पर नहीं लगाया।
Runtime Flutter source इस चरण में नहीं बदला। Read-only audit तथा offline comparison tools जोड़े हैं।

**Desktop जाँच का update:** `HotelPro-1.0.6.apk`, `HotelPro1_cPanel_Upload/hotelpro1_store.php`
और `Hotelpro1/10 store PIN.docx` मिले। तीनों की मूल files बदले बिना private copies और
SHA-256 manifest `.checkpoints/rollout-20261010/desktop-originals-1791624222884/` में
सुरक्षित हैं। APK का package `com.hotelpro1.app`, version `1.0.6+13` और certificate
नए APK से मेल खाते हैं। APK hotel records/preferences का backup नहीं है; PHP file
server code है, database export नहीं; PIN list किसी विशेष फोन की activation/trial
का प्रमाण नहीं है। Hotel Pro JSON/SQL data export Desktop scan में नहीं मिला। Desktop
के OneDrive symlink की पूरी contents नहीं खोजी गईं; वहाँ हो तो specific file path चाहिए।

## अभी क्या सुरक्षित कॉपी हुई, क्या नहीं

वास्तविक Auth UID से owner सत्यापित करके दोनों पुराने cloud business paths के
collection snapshots फिर पढ़े हैं। Firestore fields के साथ actual REST createTime/updateTime
भी रखे हैं। दो Storage photos की exact generation के bytes निजी backup में हैं;
स्थानीय backup का SHA-256 downloaded bytes से मिलाया गया।

Private evidence:
`/Users/raghuwansh/hotel_pro_1/.checkpoints/rollout-20261010/owner-1791623075133/`

`recovery-comparison-cloud-only.json` में हर record path, snapshot hash, create/update
metadata, duplicate candidates और guest/photo links हैं। Cloud Logging का अलग private
evidence `recovery-logs-1791623113568/` में है। Guest names, phone/ID numbers और photo
bytes सार्वजनिक report या Git में नहीं रखे गए। पूरे production project का managed
point-in-time backup होने का दावा नहीं है; केवल इस owner के पढ़े हुए snapshots हैं।

**फोन अभी जुड़ा नहीं मिला। इसलिए local होटल डेटा, original trial date, activation,
pending uploads और वास्तविक JSON export की copy अभी नहीं ली जा सकी।** सामान्य Mac
Downloads/Desktop/Documents में लक्षित नामों से पुराने Hotel Pro backup/export नहीं
मिले; किसी दूसरे filename/location पर होने की संभावना बाकी है। PHP/MySQL read-only
export या database access उपलब्ध नहीं है। Local/PHP अनुपलब्ध का अर्थ खाली डेटा नहीं।

## फोन से backup लेने का क्रम

1. पुराने फोन का Airplane mode चालू करें और Wi-Fi भी बंद करें। दूसरे होटल writers
   भी बंद रखें। Phone को unlocked रखकर data-capable USB cable से इसी Mac में जोड़ें।
2. Settings → About phone → Build number को 7 बार दबाएँ। Developer options → USB
   debugging चालू करें और फोन पर इस Mac का RSA authorization स्वीकार करें। USB में
   File transfer विकल्प जरूरत पड़े तो चुनें। नया APK न लगाएँ, app data clear/uninstall
   न करें। [Android USB debugging instructions](https://developer.android.com/studio/run/device)।
3. पहले installed package/version और उपलब्ध private preferences की read-only copy
   लेने की कोशिश करें। `tools/rollout/backup_connected_phone.py` app launch/install
   नहीं करता; केवल existing preferences और external files स्थानीय private checkpoint
   में copy करता है और SHA-256 manifest बनाता है। Multiple devices हों तो सही serial लें।
4. Release app में `run-as` blocked हो सकता है। USB debugging चालू होने मात्र से
   private preferences पढ़ने की अनुमति नहीं मिलती। इस स्थिति में root, bootloader
   unlock या wipe से bypass नहीं करेंगे; trial/activation की पूर्ण copy का दावा नहीं करेंगे।
   जरूरत होने पर उसी package/key की अलग **network-free, backup-only** export build का
   reviewed प्रस्ताव देना होगा; normal sync APK इस काम के लिए उपयुक्त नहीं। ऐसा build
   अभी बनाया/लगाया नहीं है। फोन की स्थिति पहले जाँचनी है।
5. मौजूदा ऐप offline खोलकर menu **BACKUP / RESTORE → BACKUP DATA** चुनें। **RESTORE
   FROM FILE**, **Fresh Hotel Start**, signout या PIN बदलना न करें। `BACKUP CREATED
   SUCCESSFULLY` के बाद file का वास्तव में बनना/आकार/JSON parse जाँचें। Source plugin
   file app के external files folder में रखता है, Downloads में होना निश्चित नहीं:
   `/sdcard/Android/data/com.hotelpro1.app/files/Hotel_Pro_1_Backup_YYYY-MM-DD.json`।
   वही copy USB/ADB से लेना प्राथमिक रास्ता है; Android access restrictions हों तो
   phone Files/share सुविधा से copy की उपलब्धता जाँचें। मूल file न हटाएँ।
6. JSON backup में केवल चार lists हैं: `hotelpro1_rooms`, `hotelpro1_bills`,
   `hotelpro1_customers`, `hotelpro1_expenses`। Room के भीतर future/extra guest data हो
   सकता है। ग्राहक photo fields में bytes हों तभी JSON से वे सुरक्षित हैं; केवल local
   file URI हो तो संबंधित image file भी चाहिए। JSON में hotel settings, trial/PIN,
   identity mapping, pending sync/photo queues नहीं हैं। उन्हें raw preferences/file
   backup से अलग सुरक्षित करना जरूरी है।
7. उपलब्ध raw `FlutterSharedPreferences.xml` और decoded copy में `hp1_trial_start`,
   `hp1_license_on`, `hp1_license_at`, `hp1_license_hash`, original device/owner/business
   markers सुरक्षित करें। वास्तविक PIN/token को chat/public report में न दिखाएँ। Old
   activation screen और entitlement receipt मदद करेंगे, लेकिन trial-days screenshot
   original exact start date का विकल्प नहीं है।

फोन जुड़ने पर तैयार script की command (अभी device अनुपलब्ध होने से नहीं चलाई):

```sh
python3 tools/rollout/backup_connected_phone.py
# multiple phones: add --serial <the-owner-phone-serial>
```

## दोनों cloud paths का ID comparison

Current: `biz_xehC63jAFQWvlgKRwabV`; पुराना: `biz_Wu3CTkZ2KAAH4mijEqND`।
Owner UID समान है। Current UID/phoneIndex mapping सही है; नया businessId नहीं बनेगा।

| रिकॉर्ड | Current path | पुराने path में | स्थिति/प्रस्ताव |
|---|---:|---:|---|
| Rooms | 12 active, सभी EMPTY | वही 12 IDs | business fields समान; config की copies सुरक्षित। Occupancy local से जाँचनी है। |
| Bills | 3, सभी deleted | 0 | unique `BILL-000001..000003`; history recovery candidates, नए बिल नहीं बनाएँ। |
| Bookings | 11, सभी deleted | 0 | 3 CHECKED_OUT bills से जुड़े, 8 पुराने BOOKED snapshots; occupancy स्वतः वापस न करें। |
| Guests | 4, सभी deleted | 0 | `CUST-0001..0004` कायम रखें; identity/history/photo review के उम्मीदवार। |
| Payments | 9, सभी deleted | 0 | 3 समान room/bill advance pairs; duplicate receipt recovery से बचाएँ। |
| Extra charges | 8, सभी deleted | 0 | room/bill projection तथा stay linkage की समीक्षा जरूरी। |
| Settings | hotel + sync | hotel + sync | hotel_mobile और sync timestamps अलग; settings अंधाधुंध merge न करें। |
| Future bookings/expenses/closed rooms | 0 | 0 | केवल cloud में अनुपस्थित; local/PHP missing स्थिति अभी अज्ञात। |
| License | absent | absent | exact trial/activation local/entitlement से चाहिए। |
| Storage ID photos | 2 objects | 0 | bytes सुरक्षित; दोनों deleted CUST-0001 से जुड़े। |

Local backup आते ही original file byte-for-byte copy और hash के बाद stable IDs से
matched/local-only/cloud-only/conflicting payloads अलग रिपोर्ट होंगे। Duplicate local
bill/customer IDs और missing expense IDs रोककर review होंगे। अभी किसी local record
को missing/safe बताने का प्रमाण नहीं है। Comparison tool कभी records नहीं लिखता:

```sh
python3 tools/rollout/compare_recovery.py --audit .checkpoints/rollout-20261010/owner-1791623075133 --local-json '<original-backup-path>'
```

यह पहले चार lists और common fields का comparison देगा; photo bytes, embedded
payments/charges, local-only fields तथा pending journals की अलग semantic review जरूरी है।
Raw preference XML comparison के लिए सीधे इस JSON argument में न दें।

## deleted:true का कारण — क्या प्रमाण मिला

Deleted documents में `deleted`, `deviceId`, schemaVersion 2, client updatedAtMs और
server updatedAt/updateTime हैं। Explicit deletedBy, deletionReason या UI-action audit
नहीं मिला। 27 सितंबर `05:46:39.862Z` पर एक ही device marker से 25 records में tombstone
timestamp है: 8 bookings + 4 guests + 3 bills + 6 payments + 4 charges। अन्य tombstones
17/19 सितंबर के अलग batches में हैं। Device marker authenticated human actor का प्रमाण नहीं।

Original checkpoint code `hotel_cloud_sync_service.dart` में missing local IDs के
हर non-settings collection पर tombstone लगाया जाता था। उसी code path तक
`Fresh Hotel Start` के बाद cleared local lists भी पहुँचती थीं। इसलिए stale/empty
snapshot और intentional local clear दोनों वर्तमान metadata से समान दिख सकते हैं।
Batch pattern उस mechanism के अनुकूल है, **लेकिन यही historical cause/intent था,
यह सिद्ध नहीं है**। Relevant Cloud Logging query पढ़ने की access मिली, मगर दोनों
business IDs और निर्धारित समय-सीमा वाली query में zero entries आए। यह deletion न
होने या किसी user के दोष का प्रमाण नहीं; logging coverage/request details सीमित हो सकते हैं।

## Financial duplicate रोकने का ठोस प्रस्ताव

तीन advance pairs में room, exact booking/payment timestamp, amount और mode समान हैं:

| Room | मूल room payment | bill projection | राशि |
|---|---|---|---:|
| 109 | `pay_adv_room_109` | `pay_adv_BILL-000001` | ₹500 |
| 101 | `pay_adv_room_101` | `pay_adv_BILL-000002` | ₹500 |
| 102 | `pay_adv_room_102` | `pay_adv_BILL-000003` | ₹1,000 |

पुराना codec उसी advance को room तथा checkout bill से अलग IDs में project कर सकता
था। सभी 9 entries जोड़ना ₹7,200 दिखाता है; तीन pairs को एक event मानने पर signature
total ₹5,200 होगा। **ये actual collected-cash totals की पुष्टि नहीं हैं।** Local receipts,
bill/payment history और PHP export से समीक्षा के बाद explicit alias map approve करना है।
Original records delete न हों; approved ledger में canonical event एक बार counted हो।
Missing part/final payments को इन totals से अनुमानित न करें।

- तीन bill IDs unique हैं; existing ID और पूरा original payload कायम रखें। Same ID
  पर अलग local/PHP payload हो तो conflict, नया duplicate bill नहीं।
- Rooms 101/102/109 के BOOKED snapshots उसी stay की CHECKED_OUT bill history से
  match करते हैं। उन्हें current room occupancy के रूप में revive नहीं करना है। बाकी
  5 पुराने booked snapshots का outcome अज्ञात है; local proof तक quarantine करें।
- Bill balance को नई received payment मानकर ledger entry न बनाएँ। Updated codec की
  derived checkout-payment projection और historical migration का खास review जरूरी
  है; receipt evidence/approved provenance के बिना नई financial entry auto-create न हो।
- Approved migration के लिए per-record before/after hashes, existing document ID,
  transaction preconditions, stable recovery event ID और alias manifest चाहिए। Dry-run
  दूसरी बार चलाने पर zero additional bill/payment events हों। पहले यह local/emulator
  में verify होगा; production execution अलग अनुमति के बाद ही।

## Guest/photo और activation recovery योजना

`CUST-0001` से तीनों bills का customerId, normalized phone और guest name मेल खाते
हैं। उसकी दो stored stay entries room/booking/checkout time से BILL-000002/000003
से match करती हैं; इनमें billNumber stored नहीं है। BILL-000001 के लिए stay entry
नहीं मिली। नया stay तभी जोड़ा जाए जब local/PHP प्रमाण और dedup signature review हो।

दो Storage objects `businesses/{currentBusiness}/guests/CUST-0001/id_front.jpg` और
`id_back.jpg` हैं। दोनों उसी guest metadata से path द्वारा जुड़े और JPEG download
सफल है। Guest document soft-deleted है। Firestore hash original pre-compression bytes
का हो सकता है जबकि Storage compressed JPEG है; पुराना source यही करता था। Actual
image/name/ID का मूल कार्ड/फोन से manual मिलान बाकी है; OCR checksum failure को इस
identity proof का विकल्प न मानें। Missing additional/other guest photos अनुमान से न जोड़ें।

Approval के बाद guest का सही original ID रखते हुए केवल प्रमाणित history restore
हो। Existing canonical photo objects रहने दें; approved restored metadata में actual
downloaded-byte hash/size/generation और original legacy hash की provenance रखें।
Content/owner match के बिना photo किसी दूसरे guest पर न लगाएँ। Upload/restore failures
के bytes queue/backup में बने रहें।

License के लिए same-owner raw preference snapshot से exact `hp1_trial_start` और
recognized activation hash निकले; दोनों cloud license records अभी absent हैं। Approved
transaction से current business के `settings/license` को create-only initialize करें,
सही पुरानी date और activation रखें। बाद में existing cloud trial को आगे बढ़ाना या
activation गिराना नहीं। Missing date/PIN entitlement पर admin evidence review करें;
UID creation/login date से trial न गढ़ें और नया trial silently शुरू न करें।

## अभी execution रोकने वाली आवश्यक चीजें

- Phone A/B के original local/JSON/photo/queue/license backups और owner markers।
- Verified owner का PHP read-only export; निजी folder में query `mysql-read-only-export.sql`
  तैयार है, चलाई नहीं। पुराने PIN-based store के लिए अलग ownership evidence चाहिए।
- Deletion intent की पुष्टि या प्रत्येक candidate के लिए user-approved recovery decision।
- Financial aliases, missing checkout receipt provenance और guest/stay/photo review।

उसके बाद final per-record recovery manifest, dry-run results और प्रभाव दिखाए जाएँगे।
आपकी confirmation से पहले production mutation, bulk revival या rules deploy नहीं होगा।
