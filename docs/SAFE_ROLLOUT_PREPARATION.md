# Hotel Pro 1 — सुरक्षित rollout की तैयारी

10 अक्टूबर 2026। **Production rules/data/migration में कोई बदलाव नहीं किया गया।**
अभी APK बनाया और production की केवल read-only जाँच की गई है। APK install/run नहीं किया गया।

**Owner audit update:** दिए गए OTP नंबर से अब account-specific जाँच पूरी हुई है।
Mapping सही है, लेकिन deleted history, missing cloud license और deleted guest से जुड़े
photos के कारण rollout अभी तैयार नहीं है। विस्तृत परिणाम [OWNER_CLOUD_AUDIT.md](OWNER_CLOUD_AUDIT.md)
में हैं; नीचे की प्रारंभिक pending-account टिप्पणियाँ पुराने preflight समय की स्थिति हैं।

## सही project और वास्तविक rules backup

Android ऐप का project **`yankees-hotel-pro`** और bucket
**`yankees-hotel-pro.firebasestorage.app`** है। Repository के CLI default में
`planning-with-ai-881ba` है; default से deploy कभी न करें। हर command में project स्पष्ट दें।

Production Rules API से दोनों वर्तमान deployed releases और पूरा source पढ़कर रखा है:

`/Users/raghuwansh/hotel_pro_1/.checkpoints/rollout-20261010/production/`

यह private, Git-ignored folder है। `rules-manifest.json` में release/ruleset IDs,
deployment time और source SHA-256 हैं। Download के बाद release को दोबारा पढ़कर
सत्यापित किया कि backup के दौरान ruleset बदला नहीं। Backup file hashes भी जाँचे गए।
यह **rules backup है**, पूरे database/Storage bytes का backup नहीं।

| सेवा | वर्तमान ruleset | deployed UTC | source SHA-256 |
|---|---|---|---|
| Firestore | `dfb990a6-8b2a-4b71-96cd-764c04230bb0` | 2026-09-17 09:46:16 | `535ea0875ca32a864ca3ce1c0f87774d250bdad5b9cdea69a0c16187e79d6d53` |
| Storage | `ec0e04b6-2800-4566-ac7e-66a78bf77e43` | 2026-09-17 06:52:01 | `ed80956f7228dbecb155465246657787d8ee3e8260761aefe0f22f9e27d7f2fd` |

## वापस लगाने की प्रक्रिया — अभी चलानी नहीं है

Private backup folder में मूल `firestore.rules`, `storage.rules` और केवल उन सेवाओं
का `firebase.rollback.json` तैयार है। कोई hosting/functions/data target इसमें नहीं है।

1. Emergency rollback की अलग पुष्टि लें। दोनों फोन और सभी नए/पुराने writers रोकें;
   unsynced local copies सुरक्षित करें। Current release/source का नया backup लें।
2. नीचे के hashes ऊपर की तालिका से मिलाएँ। Backup को संपादित न करें।
3. **केवल अनुमति मिलने पर** उसी private folder से मूल rules deploy करें:

```sh
cd '/Users/raghuwansh/hotel_pro_1/.checkpoints/rollout-20261010/production'
shasum -a 256 firestore.rules storage.rules
# MUTATING COMMAND: approval required; NOT executed during preparation.
firebase deploy --project yankees-hotel-pro --only firestore:rules,storage --config firebase.rollback.json
```

4. Rules API/console से deployed source फिर पढ़कर मिलाएँ और owner/foreign access
   जाँचें। दोनों services का deployment atomic नहीं है; एक सफल और दूसरी failed हो तो
   writers रोके रखें और बची service ठीक करें। Rule propagation के बाद ही client test करें।
5. नियम वापस लगाने से migrated documents, payments, photos या mapping वापस नहीं होते।
   Data rollback अलग reviewed reconciliation है; नई जानकारी को पुराने snapshot से
   अंधाधुंध overwrite नहीं करना है। पुरानी rules में नए versioned photo paths की अनुमति
   नहीं है, इसलिए नया ऐप photo errors दिखा सकता है। पुरानी rules से पुराने unsafe
   snapshot writers फिर अनुमत होंगे; उन्हें बिना समीक्षा चालू न करें।
6. APK build 14 से build 13 पर downgrade/uninstall data बचाने का तरीका नहीं है। जरूरत
   हो तो इसी identity/signing का अधिक versionCode वाला corrective build बनाएँ।

Rules release वापस किसी सुरक्षित retained ruleset पर point करने का API विकल्प भी
है; source से ऊपर वाला CLI तरीका retained ruleset हट जाने पर भी काम करता है।
[Firebase rule management](https://firebase.google.com/docs/rules/manage-deploy),
[release update API](https://firebase.google.com/docs/reference/rules/rest/v1/projects.releases/patch)।

## होटल के cloud/local/PHP डेटा की स्थिति

Production access मिला। Read-only mapping inventory में 9 businesses, 9 users,
8 phone-index records मिले। एक UID के दो business documents और कुछ mapping
विसंगतियाँ दिखी हैं। यह global inventory है, आपके होटल की पहचान/पूर्णता का प्रमाण नहीं।
आपका OTP नंबर/UID/businessId मिलने तक किसी business को आपका मानकर records/photos
की जाँच नहीं की जाएगी। कोई mapping बदली या नया business बनाया नहीं गया।

केवल Firestore में documents मिलना पर्याप्त नहीं है। पूर्णता तय करने के लिए:

- आपके Firebase Auth UID/phone, `users/{uid}`, `phoneIndex/{digits}` और
  `businesses/{businessId}.ownerUid` का आपस में मिलान करना है। उसी UID के दूसरे
  पुराने business में रिकॉर्ड हों तो उन्हें अलग से review करना है।
- उस होटल के rooms, bookings, futureBookings, guests, bills, payments, expenses,
  settings, closedRooms और extraCharges का owner-scoped export लेना है।
- दोनों वास्तविक फोन की local lists/journal/pending photos और trial/PIN entitlement
  export से stable IDs, bill/payment amounts तथा duplicate/conflict comparison करना है।
- उसी verified owner का PHP MySQL **read-only SELECT/export** चाहिए; store key पूरा
  नंबर/पुराने verified PIN-store ownership से तय करें। अन्य owners के PIN stores न लें।

पुराने PHP endpoint को नहीं बुलाया: उपलब्ध source में `GET` भी `ensureSchema()` और
missing store पर `INSERT` करता है। इसलिए इस शर्त में HTTP GET सुरक्षित read-only
inventory नहीं है। cPanel/MySQL read-only session/export उपलब्ध नहीं मिला। Phone भी
ADB से जुड़ा नहीं मिला; वास्तविक local data उपलब्ध नहीं है। PHP-only/local-only
migration बाकी है या नहीं, अभी प्रमाणित नहीं। **इस तुलना के बिना rollout रोकें।**

`tools/rollout/read_owner.mjs` owner पहचान मिलने पर read-only audit के लिए तैयार है:
Auth phone/UID, mappings, हर collection, license record, referenced Storage photo
object metadata और downloaded bytes के SHA-256/JPEG checks। यह app/device owner
security rules का physical-phone test नहीं है: administrator IAM से reads हैं। Audit
private checkpoint में रहेगा। Phone की pending-upload queue local export से ही दिखेगी।
किसी missing cloud license की historical activation/trial date UID से अनुमानित न करें।

CLI login जाँच में token विवरण output में आ गया था; credentials रिपोर्ट/checkpoints में
नहीं रखे गए। उस credential को revoke करके नया login करना बाकी security कदम है।

## नई rules पुराने ऐप को क्यों रोकेंगी

पुराना sync schemaVersion 2 के whole snapshots लिखता है। वह stale/empty snapshot
से दूसरे फोन के records बदल सकता है और physical deletes/photo deletes कर सकता है।
नई business record writes के लिए schemaVersion **3** चाहिए और physical record/photo
deletes denied हैं। पुरानी ownership बदलने वाली mapping flow भी सीमित है। इसलिए
पुराने client की writes permission-denied होंगी; existing data केवल rules deploy
होने से delete नहीं होता। Reads owner को उपलब्ध रहेंगी। PHP writes पर Firebase rules
का असर नहीं है, इसलिए पुराने PHP writers को अलग से बंद रखना होगा।

Schema 3 rule कोई server-side transaction enforcement नहीं है; भरोसेमंद नया ऐप
transactions/idempotency लागू करता है। गलत modified owner client रोकने के लिए केवल
version number पर्याप्त नहीं। यह owner isolation और सामान्य app-client concurrency
के लिए बनाया गया rollout है।

## दोनों फोन update करने का सुरक्षित क्रम — पुष्टि के बाद

1. सही owner पहचान, local/PHP/cloud comparison, duplicate conflicts, trial/PIN और
   photos की कमी resolve करें। Production Firestore/Storage/PHP तथा दोनों local
   copies का पूरा backup अलग सुरक्षित रखें। Production writes रोकने का समय तय करें।
2. दोनों फोन A/B पर पुराना ऐप बंद/force-stop रखें; सभी पुराने desktop/PHP writers भी
   रोकें। कोई नई booking/payment उस दौरान न लिखें। ऐप uninstall न करें।
3. Phone A (जिसमें authoritative पुरानी local जानकारी है) पर APK install-as-update
   करें, फिर B पर। दोनों पर अभी ऐप न खोलें; offline/force-stopped रखें। सही installed
   certificate और versionCode पहले मिलाएँ।
4. आपकी स्पष्ट approval के बाद reviewed migration/rules rollout करें। Storage में
   versioned paths support और Firestore schema-3/ownership rules लागू करने के दौरान
   सभी writers बंद रहें। PHP-only migration app में global importer flag से न करें।
5. A को पहले online खोलें। Mapping/restore/conflict review पूरा करें, `Synced` और
   **कोई pending photo नहीं** सत्यापित करें। अधूरा local/cloud overlap स्वयं हल मानकर
   आगे न बढ़ें; manual review/export रखें। Original trial/activation जाँचें।
6. उसके बाद B online खोलें; उसी नंबर से login करें। A के पुराने डेटा/photos/license
   लौटने और live update की जाँच करें। सफल तुलना के बाद ही रोजमर्रा की writes शुरू करें।
7. Reinstall test केवल पूरी तरह synced B पर बाद में करें; A/backups सुरक्षित रखें।

नया APK खोलना भी license/sync cloud writes कर सकता है। **अभी यह APK production
होटल में चलाने की अनुमति नहीं है**; preparation में इसे केवल बनाया/स्थानीय जाँचा है।

## APK और update identity

APK: `/Users/raghuwansh/hotel_pro_1/build/rollout/Hotel-Pro-1-1.0.7-14.apk`

- Release build सफल, versionName `1.0.7`, versionCode `14` (पुराना local APK: `1.0.6`, `13`)।
- Package दोनों में `com.hotelpro1.app`। Release certificate SHA-256 दोनों में
  `bafcba1c4782d36bfd4d967c50a9b371b76944b87fb770a1308ea0f569b3880d`।
- `apksigner verify` सफल; APK Signature Scheme v2 verified।
- APK SHA-256: `913117968ed60ec28d6aa8189077bdd3d7534ae9a88d4b7cb1c525f1b1df2c64`।
- Original signing properties, Gradle configuration, pubspec और dependency lock
  checkpoint से byte-identical हैं। Version build command में override की गई है।
- पुराना local APK भी `.checkpoints/rollout-20261010/prior-local-release.apk` में है।
  Build के लिए source checkpoint `source-for-apk-14.tar.gz` रखा है।
- जुड़ा फोन नहीं मिला, इसलिए installed certificate/version, update install और
  वास्तविक local-data retention अभी verify नहीं हैं। Google Play द्वारा अलग signing
  key से installed app हो तो यह locally signed APK सीधे update नहीं होगा; सही Play
  distribution चाहिए। Signature mismatch हो तो uninstall करके bypass न करें।

Android update उसी package/signing identity के साथ होना चाहिए।
[Android signing documentation](https://developer.android.com/studio/publish/app-signing)।
APK verification evidence `docs/validation/rollout/` में है। AGP/Kotlin के future
compatibility warnings आए; इस build को नहीं रोका। Dependency upgrade नहीं किया गया।

## पुराने OCR failure का असर

OCR parser पहले checksum जाँचता है, फिर एक digit की संभावित OCR repair करता है।
`9999 8888 7777` invalid input को वह `9999 8880 7777` बना देता है, इसलिए उसे reject
करने वाला मौजूदा test fail है। परिणाम checksum-valid हो सकता है लेकिन वास्तविक
ID नंबर गलत हो सकता है; checksum किसी व्यक्ति/सरकारी ID की authenticity सिद्ध नहीं करता।
Guest का गलत ID नंबर फॉर्म/रिकॉर्ड में जा सकता है यदि operator उसे बिना मिलान save करे।
यह OTP login/business mapping/payment sync का failure नहीं, और photo bytes को नहीं
बदलता; गलत parsed नंबर भी sync हो सकता है। Scan के बाद printed ID से नंबर/name मिलाएँ।
OCR source इस तैयारी में नहीं बदला; अलग focused fix और test validation बाकी है।

पिछली source validation: analyze साफ; संबंधित Flutter 45 पास; emulator 10 पास;
पूरे Flutter suite में 51 पास/यह 1 known failure। इस तैयारी में runtime app source
नहीं बदला, इसलिए पूरे suites अनावश्यक दोबारा नहीं चलाए। Release Android compilation,
signature/package/version comparison, backup checksums और audit scripts syntax जाँची गई।
Real OTP, device update, concurrent app actions और reinstall restore अभी बाकी हैं।
